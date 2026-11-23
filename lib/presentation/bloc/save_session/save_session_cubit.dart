import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/core/core.dart';
import '../../../domain/engine/engine.dart';
import 'save_session_ui_state.dart';

/// Wraps the pure [SaveSessionController] in presentation state.
///
/// The cubit owns no save offsets and never touches the filesystem directly.
/// Layout detection arrives through [resolveLayout]; file I/O arrives through
/// the injected [SaveRepository].
final class SaveSessionCubit extends Cubit<SaveSessionUiState> {
  /// Creates a live session cubit.
  factory SaveSessionCubit({
    required SaveEngine engine,
    required SaveRepository repository,
    required LayoutResolver resolveLayout,
  }) {
    final recorder = _RecordingSaveRepository(repository);
    final controller = SaveSessionController(
      engine: engine,
      repository: recorder,
    );
    final cubit = SaveSessionCubit._(recorder, controller, resolveLayout);
    controller.addListener(cubit._handleControllerState);
    return cubit;
  }

  SaveSessionCubit._(this._recorder, this._controller, this._resolveLayout)
    : super(const SaveSessionClosed());

  /// A cubit that cannot open or save anything.
  ///
  /// Used by the UI and tests until the real layout is wired. Every action
  /// reports a typed error instead of throwing.
  SaveSessionCubit.disabled()
    : _recorder = null,
      _controller = null,
      _resolveLayout = null,
      super(const SaveSessionClosed());

  final LayoutResolver? _resolveLayout;
  final _RecordingSaveRepository? _recorder;
  SaveSessionController? _controller;

  String? _pendingStatusMessage;
  String _statusMessage = 'No save folder is open';
  String? _openingPath;
  String? _pendingDestination;
  ExportMode? _pendingMode;
  bool _deferSaved = false;
  _SavedDraft? _pendingSaved;
  bool _busy = false;
  SaveSlotId? _activeSlot;

  /// Whether this cubit can reach the engine.
  bool get isEnabled => _controller != null;

  /// The open domain project, read-only, or `null` when nothing is open.
  ///
  /// Presentation may inspect fields through this; every mutation must still go
  /// through this cubit so validation, history and logging stay authoritative.
  SaveProject? get openProject => _controller?.state.project;

  /// The engine's parse result for the most recent open attempt.
  ///
  /// `null` when the last attempt was refused before it reached the engine
  /// (empty path, dirty project, disabled session) or when the session is
  /// disabled. Read-only: the cubit still owns the attempt itself.
  ParseResult? get lastOpenResult => _recorder?.lastOpenResult;

  /// Opens [path] read-only.
  ///
  /// [discardUnsavedChanges] exists for exactly one caller: the new-save flow,
  /// after the user answered the unsaved-changes dialog with Discard, because
  /// the create has already written real files and the user agreed to lose the
  /// current edits. Every other caller keeps the refusal below; there is no
  /// default and no silent bypass.
  Future<void> openPath(
    String path, {
    bool discardUnsavedChanges = false,
  }) async {
    final controller = _controller;
    if (controller == null) {
      _emitDisabled();
      return;
    }
    if (_busy) {
      return;
    }
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      _emitFailure(
        message: 'Enter a save folder path.',
        kind: SaveSessionErrorKind.ioFailure,
        details: 'The path was empty after trimming whitespace.',
      );
      return;
    }
    final current = controller.state.project;
    if (!discardUnsavedChanges &&
        current != null &&
        current.dirty.hasUnsavedChanges) {
      _emitFailure(
        message: 'Save or close the current project before opening another.',
        kind: SaveSessionErrorKind.refused,
        details:
            'The open project has ${current.dirty.changedFieldCount} '
            'changed field(s). Opening another folder would discard them.',
        recoverable: true,
      );
      return;
    }

    _busy = true;
    _activeSlot = null;
    _openingPath = trimmed;
    _recorder?.resetRecording();
    try {
      final resolution = await _resolveLayout!.call(trimmed);
      switch (resolution) {
        case LayoutResolved():
          _pendingStatusMessage = 'Opened $trimmed';
          await controller.open(trimmed);
        case LayoutRejected():
          _emitRejectedLayout(
            resolution,
            recoverable: controller.state.project != null,
          );
          return;
      }
    } catch (error) {
      _emitFailure(
        message: 'The save folder could not be opened.',
        kind: SaveSessionErrorKind.ioFailure,
        details: '$error',
        recoverable: controller.state.project != null,
      );
    } finally {
      _busy = false;
      _openingPath = null;
      _pendingStatusMessage = null;
    }
  }

  /// Closes the session and disposes this cubit.
  ///
  /// A dirty project is never discarded here: without [force] the cubit emits
  /// [SaveSessionPendingDiscard] and stays alive for `confirmDiscard()`.
  @override
  Future<void> close({bool force = false}) async {
    final controller = _controller;
    if (controller == null) {
      return super.close();
    }
    final project = controller.state.project;
    final alreadyPending = state is SaveSessionPendingDiscard;
    if (!force &&
        project != null &&
        project.dirty.hasUnsavedChanges &&
        !alreadyPending) {
      emit(SaveSessionPendingDiscard(_buildProject(controller.state)));
      return;
    }
    if (alreadyPending && !force) {
      return;
    }
    controller.removeListener(_handleControllerState);
    controller.dispose();
    _controller = null;
    _activeSlot = null;
    _statusMessage = 'No save folder is open';
    emit(const SaveSessionClosed());
    return super.close();
  }

  /// Discards unsaved edits after the user explicitly confirmed.
  void confirmDiscard() {
    if (state is! SaveSessionPendingDiscard) {
      return;
    }
    unawaited(close(force: true));
  }

  /// Keeps the project open after the user cancelled the discard prompt.
  void cancelDiscard() {
    if (state is! SaveSessionPendingDiscard) {
      return;
    }
    final controller = _controller;
    if (controller == null || controller.state.project == null) {
      emit(const SaveSessionClosed());
      return;
    }
    emit(SaveSessionReady(_buildProject(controller.state)));
  }

  /// Saves in place.
  Future<void> save() => _runExport(
    destinationPath: _controller?.state.project?.rootPath,
    mode: ExportMode.saveInPlace,
    action: (controller) => controller.save(),
  );

  /// Saves to [destinationPath].
  ///
  /// [overwrite] must only be true after the user checked the overwrite box in
  /// the Save As dialog. The recording repository is the only place it is
  /// applied, and only for this one call.
  Future<void> saveAs(String destinationPath, {bool overwrite = false}) async {
    final root = _controller?.state.project?.rootPath;
    final trimmed = destinationPath.trim();
    if (root != null && _normalizePath(trimmed) == _normalizePath(root)) {
      _emitFailure(
        message: 'Save As needs a different destination.',
        kind: SaveSessionErrorKind.refused,
        details: 'The destination is the open save folder "$root".',
        recoverable: true,
      );
      return;
    }
    await _runExport(
      destinationPath: trimmed,
      mode: ExportMode.saveAs,
      overwrite: overwrite,
      action: (controller) => controller.saveAs(trimmed),
    );
  }

  /// Copies one slot's open-time original bytes to [destinationPath].
  Future<void> duplicate(String destinationPath, {SaveSlotId? slot}) {
    final target = slot ?? _activeSlot;
    return _runExport(
      destinationPath: destinationPath.trim(),
      mode: ExportMode.duplicate,
      action: (controller) =>
          controller.duplicate(destinationPath.trim(), slot: target),
    );
  }

  /// Resets one slot, or every open slot when [slot] is null.
  ///
  /// [confirm] must be true; the reset dialog is the explicit confirmation and
  /// no files change otherwise.
  Future<void> reset({SaveSlotId? slot, bool confirm = false}) async {
    final controller = _controller;
    if (controller == null) {
      _emitDisabled();
      return;
    }
    if (controller.state.project == null) {
      _emitNotOpen();
      return;
    }
    if (!confirm) {
      _emitFailure(
        message: 'Restoring a slot needs confirmation.',
        kind: SaveSessionErrorKind.refused,
        details:
            'No files were changed. Confirm the reset dialog to restore the '
            'slot from the retained original backup.',
        recoverable: true,
      );
      return;
    }
    final target =
        slot ??
        _activeSlot ??
        _firstOpenProgressSlot(controller.state.project!);
    _pendingStatusMessage = target == null
        ? 'Restored the open slots from the original backup'
        : 'Restored ${target.value} from the original backup';
    try {
      await controller.reset(slot: slot);
      _pendingStatusMessage = null;
    } catch (error) {
      _emitFailure(
        message: 'The slot could not be restored from its backup.',
        kind: SaveSessionErrorKind.refused,
        details: '$error',
        recoverable: true,
      );
    }
  }

  /// Undoes the newest edit.
  void undo() {
    final controller = _controller;
    if (controller == null) {
      _emitDisabled();
      return;
    }
    if (!controller.state.canUndo) {
      return;
    }
    _pendingStatusMessage = 'Undid the most recent edit';
    controller.undo();
    _pendingStatusMessage = null;
  }

  /// Redoes the newest undone edit.
  void redo() {
    final controller = _controller;
    if (controller == null) {
      _emitDisabled();
      return;
    }
    if (!controller.state.canRedo) {
      return;
    }
    _pendingStatusMessage = 'Redid the most recent edit';
    controller.redo();
    _pendingStatusMessage = null;
  }

  /// Applies [command] through the engine.
  void edit(EditCommand command) {
    final controller = _controller;
    if (controller == null) {
      _emitDisabled();
      return;
    }
    final project = controller.state.project;
    if (project == null) {
      _emitNotOpen();
      return;
    }
    final descriptor = project.layout.descriptor(command.field);
    if (descriptor != null && isProgressSlotId(descriptor.slot)) {
      _activeSlot = descriptor.slot;
    }
    _pendingStatusMessage = null;
    controller.edit(command);
  }

  /// Re-runs validation.
  void validate() {
    final controller = _controller;
    if (controller == null) {
      _emitDisabled();
      return;
    }
    if (controller.state.project == null) {
      _emitNotOpen();
      return;
    }
    _pendingStatusMessage = 'Validation refreshed';
    controller.validate();
    _pendingStatusMessage = null;
  }

  /// Alias for [validate] used by panels that refresh after an external change.
  void refreshValidation() {
    final controller = _controller;
    if (controller == null) {
      _emitDisabled();
      return;
    }
    if (controller.state.project == null) {
      _emitNotOpen();
      return;
    }
    _pendingStatusMessage = 'Validation refreshed';
    controller.validate();
    _pendingStatusMessage = null;
  }

  /// Selects which progress slot the warnings and timestamps refer to.
  void selectSlot(SaveSlotId slot) {
    final controller = _controller;
    final project = controller?.state.project;
    if (controller == null || project == null) {
      _emitNotOpen();
      return;
    }
    if (!project.documents.containsKey(slot)) {
      _emitFailure(
        message: 'That slot is not open in this folder.',
        kind: SaveSessionErrorKind.refused,
        details: '${slot.value} is not part of the detected layout.',
        recoverable: true,
      );
      return;
    }
    _activeSlot = slot;
    if (controller.state.status == SessionStatus.ready) {
      emit(SaveSessionReady(_buildProject(controller.state)));
    }
  }

  Future<void> _runExport({
    required String? destinationPath,
    required ExportMode mode,
    required Future<void> Function(SaveSessionController controller) action,
    bool overwrite = false,
  }) async {
    final controller = _controller;
    if (controller == null) {
      _emitDisabled();
      return;
    }
    if (_busy) {
      return;
    }
    final project = controller.state.project;
    if (project == null) {
      _emitNotOpen();
      return;
    }
    final destination = destinationPath?.trim();
    if (destination == null || destination.isEmpty) {
      _emitFailure(
        message: 'Choose a destination folder first.',
        kind: SaveSessionErrorKind.refused,
        details: 'The destination path was empty.',
        recoverable: true,
      );
      return;
    }

    _busy = true;
    _deferSaved = true;
    _pendingSaved = null;
    _pendingDestination = destination;
    _pendingMode = mode;
    _pendingStatusMessage = null;
    final recorder = _recorder!..resetRecording();
    recorder.allowOverwrite = overwrite;
    try {
      await action(controller);
      final draft = _pendingSaved;
      if (draft != null) {
        _emitSaved(draft);
      }
    } catch (error) {
      _emitFailure(
        message: switch (mode) {
          ExportMode.saveInPlace => 'The save was not written.',
          ExportMode.saveAs => 'Save As was not written.',
          ExportMode.duplicate => 'The duplicate was not written.',
        },
        kind: SaveSessionErrorKind.ioFailure,
        details: '$error',
        recoverable: true,
      );
    } finally {
      _busy = false;
      _deferSaved = false;
      _pendingSaved = null;
      _pendingDestination = null;
      _pendingMode = null;
    }
  }

  void _emitSaved(_SavedDraft draft) {
    if (isClosed) {
      return;
    }
    _statusMessage = 'Saved to ${draft.path}';
    emit(
      SaveSessionSaved(
        path: draft.path,
        mode: draft.mode,
        project: draft.project,
        written: draft.written,
        statusMessage: _statusMessage,
      ),
    );
  }

  void _handleControllerState(SaveSessionState state) {
    if (isClosed) {
      return;
    }
    switch (state.status) {
      case SessionStatus.closed:
        _activeSlot = null;
        _statusMessage = 'No save folder is open';
        emit(const SaveSessionClosed());
      case SessionStatus.opening:
        emit(SaveSessionOpening(_openingPath ?? state.project?.rootPath ?? ''));
      case SessionStatus.ready:
        if (state.error != null) {
          _emitControllerFailure(state);
        } else {
          emit(SaveSessionReady(_buildProject(state)));
        }
      case SessionStatus.saving:
        final project = state.project;
        if (project == null) {
          return;
        }
        emit(
          SaveSessionSaving(
            project: _buildProject(state, statusMessage: 'Saving…'),
            destinationPath: _pendingDestination ?? project.rootPath,
            mode: _pendingMode ?? ExportMode.saveInPlace,
          ),
        );
      case SessionStatus.saved:
        final project = state.project;
        if (project == null) {
          return;
        }
        final draft = _draftFromController(state);
        if (_deferSaved) {
          _pendingSaved = draft;
          return;
        }
        _emitSaved(draft);
      case SessionStatus.error:
        _emitOpenFailure(state);
    }
  }

  /// Reports why layout detection refused the folder being opened.
  ///
  /// [LayoutRejected.reason] is the detector's or codec's own text, so a
  /// corrupt container, an unreadable revision and a non-save folder each get
  /// their own message and detail instead of one generic "unsupported" claim.
  void _emitRejectedLayout(
    LayoutRejected rejection, {
    required bool recoverable,
  }) {
    final file = rejection.path;
    final details = file == null
        ? rejection.reason
        : '${rejection.reason}\nFile: $file';
    _emitFailure(
      message: switch (rejection.kind) {
        LayoutRejectionKind.notASave => 'This folder does not contain a save.',
        LayoutRejectionKind.unsupportedRevision =>
          'This save uses a game version this build does not support.',
        LayoutRejectionKind.corrupt =>
          'This save folder is damaged or incomplete.',
      },
      kind: switch (rejection.kind) {
        LayoutRejectionKind.corrupt => SaveSessionErrorKind.corruptSave,
        LayoutRejectionKind.notASave ||
        LayoutRejectionKind.unsupportedRevision =>
          SaveSessionErrorKind.unsupportedLayout,
      },
      details: _withPath(details),
      recoverable: recoverable,
    );
  }

  void _emitOpenFailure(SaveSessionState state) {
    final result = _recorder?.lastOpenResult;
    final fallback = state.error ?? 'The save folder could not be opened.';
    switch (result) {
      case ParseUnsupported(:final reason, :final detectedVersion):
        _emitFailure(
          message: 'This save folder is not supported by this version.',
          kind: SaveSessionErrorKind.unsupportedLayout,
          details: _withPath(
            detectedVersion == null
                ? reason
                : '$reason (detected layout version $detectedVersion)',
          ),
          recoverable: state.project != null,
        );
      case ParseCorrupt(:final reason, :final at):
        _emitFailure(
          message: 'This save folder is damaged or incomplete.',
          kind: SaveSessionErrorKind.corruptSave,
          details: _withPath(at == null ? reason : '$reason (at $at)'),
          recoverable: state.project != null,
        );
      case ParseOk():
      case ParseUnverified():
      case null:
        _emitFailure(
          message: 'The save folder could not be opened.',
          kind: SaveSessionErrorKind.ioFailure,
          details: _withPath(fallback),
          recoverable: state.project != null,
        );
    }
  }

  void _emitControllerFailure(SaveSessionState state) {
    final export = _recorder?.lastExport;
    final issues = export?.issues ?? const <ValidationIssue>[];
    final details = <String>[
      if (state.error != null) state.error!,
      ...issues.map(_formatIssue),
    ].join('\n');
    final isExport = export != null;
    _emitFailure(
      message: isExport
          ? 'The save was not written.'
          : 'That change was not applied.',
      kind: isExport
          ? SaveSessionErrorKind.refused
          : SaveSessionErrorKind.editRefused,
      details: details.isEmpty ? state.error : details,
      recoverable: true,
    );
  }

  void _emitNotOpen() {
    _emitFailure(
      message: 'No save folder is open.',
      kind: SaveSessionErrorKind.notOpen,
      details: 'Open a save folder before using this action.',
      recoverable: false,
    );
  }

  void _emitDisabled() {
    _emitFailure(
      message: 'The save engine is not connected in this build.',
      kind: SaveSessionErrorKind.disabled,
      details:
          'This panel is present, but no save layout or repository is wired '
          'yet. Nothing was read or written.',
      recoverable: false,
    );
  }

  void _emitFailure({
    required String message,
    required SaveSessionErrorKind kind,
    String? details,
    bool recoverable = false,
  }) {
    if (isClosed) {
      return;
    }
    final project = _currentProject();
    emit(
      SaveSessionError(
        message: message,
        details: details,
        recoverable: recoverable || project != null,
        kind: kind,
        project: project,
      ),
    );
  }

  SaveProjectUi? _currentProject() {
    final controller = _controller;
    final state = controller?.state;
    if (state == null || state.project == null) {
      return null;
    }
    return _buildProject(state);
  }

  SaveProjectUi _buildProject(SaveSessionState state, {String? statusMessage}) {
    final project = state.project!;
    // One dirty pass and one span diff per slot for the whole summary. Calling
    // `project.dirty` inside `_slotUi` as well made this seven byte walks and
    // six duplicate span diffs per emitted state.
    final dirty = project.dirty;
    final spans = <SaveSlotId, List<ByteSpan>>{
      for (final slotLayout in project.layout.slots)
        slotLayout.id: project.changedSpans(slotLayout.id),
    };
    final slots = <SaveSlotUi>[
      for (final slotLayout in project.layout.slots)
        _slotUi(project, slotLayout, dirty, spans[slotLayout.id]!),
    ];
    final active = _resolveActiveSlot(project);
    _activeSlot = active;
    final message = statusMessage ?? _pendingStatusMessage ?? _statusMessage;
    _statusMessage = message;
    _pendingStatusMessage = null;
    return SaveProjectUi(
      projectId: project.projectId,
      path: project.rootPath,
      backupPath: project.backupPath,
      layoutId: project.layout.id,
      detectedVersion: project.detectedVersion,
      slots: slots,
      activeSlot: active,
      newestSlot: null,
      slotAges: const <SlotAgeUi>[],
      hasUnsavedChanges: dirty.hasUnsavedChanges,
      differsFromOriginal: dirty.differsFromOriginal,
      changedFieldCount: dirty.changedFieldCount,
      changedByteCount: dirty.changedByteCount,
      canUndo: state.canUndo,
      canRedo: state.canRedo,
      canSave: state.canSave,
      issues: state.issues,
      validationSummary: _validationSummary(state.issues),
      statusMessage: message,
      preserveUnknown: project.preserveUnknown,
    );
  }

  SaveSlotUi _slotUi(
    SaveProject project,
    SaveSlotLayout slotLayout,
    DirtyState dirty,
    List<ByteSpan> spans,
  ) {
    final document = project.documents[slotLayout.id];
    return SaveSlotUi(
      id: slotLayout.id,
      relativePath: slotLayout.relativePath,
      isOpen: document != null,
      fieldCount: document?.fields.length ?? 0,
      changedFieldCount: document == null
          ? 0
          : document.fields.where((field) => field.isDirty).length,
      changedByteCount: spans.fold<int>(
        0,
        (total, span) => total + span.length,
      ),
      isDirty: dirty.dirtySlots.contains(slotLayout.id),
      expectedLength: slotLayout.expectedLength,
    );
  }

  SaveSlotId? _resolveActiveSlot(SaveProject project) {
    final selected = _activeSlot;
    if (selected != null && project.documents.containsKey(selected)) {
      return selected;
    }
    return _firstOpenProgressSlot(project) ??
        (project.documents.isEmpty ? null : project.documents.keys.first);
  }

  SaveSlotId? _firstOpenProgressSlot(SaveProject project) {
    for (final slotLayout in project.layout.slots) {
      if (isProgressSlotId(slotLayout.id) &&
          project.documents.containsKey(slotLayout.id)) {
        return slotLayout.id;
      }
    }
    return null;
  }

  _SavedDraft _draftFromController(SaveSessionState state) {
    final project = state.project!;
    final result = _recorder?.lastExport;
    final written = <SlotWriteUi>[];
    if (result != null) {
      final slots = result.writtenPaths.keys.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final slot in slots) {
        written.add(
          SlotWriteUi(
            slot: slot,
            path: result.writtenPaths[slot]!,
            fingerprint: result.fingerprints[slot],
          ),
        );
      }
    }
    final mode = _pendingMode ?? ExportMode.saveInPlace;
    return _SavedDraft(
      project: _buildProject(state),
      path: _pendingDestination ?? project.rootPath,
      mode: mode,
      written: List<SlotWriteUi>.unmodifiable(written),
    );
  }

  String _withPath(String reason) {
    final path = _openingPath;
    return path == null ? reason : '$reason\nFolder: $path';
  }
}

/// One-line footer summary of [issues].
///
/// Provenance notices (`field.unverified` warnings) are reported as
/// informational notes, never as warnings: on a retail save there are thousands
/// of them and none is a problem. The reassurance "No blocking issues" appears
/// only when nothing actionable exists, because that is exactly when the reader
/// needs to be told the alarm is not real.
String _validationSummary(List<ValidationIssue> issues) {
  if (issues.isEmpty) {
    return 'No validation issues';
  }
  var blocking = 0;
  var warnings = 0;
  var notes = 0;
  for (final issue in issues) {
    if (issue.isBlocking) {
      blocking++;
    } else if (issue.isActionableWarning) {
      warnings++;
    } else {
      notes++;
    }
  }
  String plural(int count, String singular) =>
      '$count $singular${count == 1 ? '' : 's'}';
  if (blocking == 0 && warnings == 0) {
    return 'No blocking issues · ${plural(notes, 'informational note')}';
  }
  return <String>[
    if (blocking > 0) plural(blocking, 'blocking issue'),
    if (warnings > 0) plural(warnings, 'warning'),
    if (notes > 0) plural(notes, 'informational note'),
  ].join(' · ');
}

String _formatIssue(ValidationIssue issue) {
  final parts = <String>[
    '[${issue.severity.name}] ${issue.code}',
    issue.slot.value,
    issue.message,
    if (issue.field != null) 'field ${issue.field!.value}',
    if (issue.remedy != null) 'remedy: ${issue.remedy}',
  ];
  return parts.join(' · ');
}

String _normalizePath(String path) {
  var normalized = path.trim().replaceAll('\\', '/');
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

final class _SavedDraft {
  const _SavedDraft({
    required this.project,
    required this.path,
    required this.mode,
    required this.written,
  });

  final SaveProjectUi project;
  final String path;
  final ExportMode mode;
  final List<SlotWriteUi> written;
}

/// Records the last parse/export result so the cubit can map typed failures and
/// report written paths and fingerprints that [SaveSessionState] does not keep.
///
/// [allowOverwrite] is opt-in for one call only. It exists because
/// [SaveSessionController] calls the repository without an overwrite flag; the
/// UI applies it exclusively after the Save As dialog's explicit checkbox.
final class _RecordingSaveRepository implements SaveRepository {
  _RecordingSaveRepository(this._delegate);

  final SaveRepository _delegate;

  ParseResult? lastOpenResult;
  ExportResult? lastExport;
  bool allowOverwrite = false;

  void resetRecording() {
    lastOpenResult = null;
    lastExport = null;
    allowOverwrite = false;
  }

  @override
  Future<ParseResult> open(
    String rootPath, {
    bool preserveUnknown = true,
    bool verifyIntegrity = true,
  }) async {
    final result = await _delegate.open(
      rootPath,
      preserveUnknown: preserveUnknown,
      verifyIntegrity: verifyIntegrity,
    );
    lastOpenResult = result;
    return result;
  }

  @override
  Future<void> ensureOriginalBackup(SaveProject project, BackupPolicy policy) =>
      _delegate.ensureOriginalBackup(project, policy);

  @override
  Future<ExportResult> writeExport(
    ExportPlan plan, {
    bool allowOverwrite = false,
  }) async {
    final result = await _delegate.writeExport(
      plan,
      allowOverwrite: allowOverwrite || this.allowOverwrite,
    );
    lastExport = result;
    return result;
  }

  @override
  Future<SaveProject> reset(
    SaveProject project,
    SaveSlotId slot, {
    bool clearHistory = false,
  }) => _delegate.reset(project, slot, clearHistory: clearHistory);

  @override
  Future<ExportResult> duplicate(
    SaveProject project,
    SaveSlotId slot, {
    required String destinationRoot,
    BackupPolicy policy = BackupPolicy.standard,
    bool allowOverwrite = false,
  }) async {
    final result = await _delegate.duplicate(
      project,
      slot,
      destinationRoot: destinationRoot,
      policy: policy,
      allowOverwrite: allowOverwrite || this.allowOverwrite,
    );
    lastExport = result;
    return result;
  }
}
