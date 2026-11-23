/// Pure-Dart save-session state machine.
///
/// No Flutter or bloc import lives here. A later presentation agent can wrap
/// this controller in a cubit or expose its state through a stream.
library;

import '../core/core.dart';
import 'ports.dart';
import 'save_engine.dart';

/// Session lifecycle.
enum SessionStatus { closed, opening, ready, saving, saved, error }

/// Immutable session state.
final class const SaveSessionState({
  required final SessionStatus status,
  final SaveProject? project,
  final String? error,
  final bool busy = false,
  final List<ValidationIssue> issues = const <ValidationIssue>[],
}) {
  /// Whether undo is available.
  bool get canUndo => project?.history.canUndo ?? false;

  /// Whether redo is available.
  bool get canRedo => project?.history.canRedo ?? false;

  /// Whether a save would write something.
  bool get canSave => project != null && !project!.dirty.isClean && !busy;

  /// Whether blocking validation issues exist.
  bool get hasBlockingErrors =>
      issues.any((issue) => issue.severity == Severity.error);

  @override
  String toString() =>
      'SaveSessionState(${status.name}, busy: $busy, '
      'project: ${project?.projectId})';
}

/// Events accepted by [SaveSessionController].
sealed class SaveSessionEvent {
  /// Allows subclasses to be const.
  const SaveSessionEvent();
}

/// Open [path].
final class const OpenSaveRequested(final String path) extends SaveSessionEvent;

/// Release the current project without writing.
final class const CloseRequested() extends SaveSessionEvent;

/// Save to the open root.
final class const SaveRequested() extends SaveSessionEvent;

/// Write current state to [destinationPath].
final class const SaveAsRequested(final String destinationPath)
    extends SaveSessionEvent;

/// Copy a slot's original bytes to [destinationPath].
final class const DuplicateRequested(
  final String destinationPath, {
  final SaveSlotId? slot,
}) extends SaveSessionEvent;

/// Reset one slot, or every slot when [slot] is null.
final class const ResetRequested({
  final SaveSlotId? slot,
  final bool clearHistory = false,
}) extends SaveSessionEvent;

/// Undo the newest edit.
final class const UndoRequested() extends SaveSessionEvent;

/// Redo the newest undone edit.
final class const RedoRequested() extends SaveSessionEvent;

/// Apply [command].
final class const FieldEditRequested(final EditCommand command)
    extends SaveSessionEvent;

/// Re-run validation.
final class const ValidateRequested() extends SaveSessionEvent;

/// Controller for one open save session.
final class SaveSessionController {
  /// Creates a controller around [engine] and [repository].
  SaveSessionController({
    required this.engine,
    required this.repository,
    SaveSessionState? initialState,
  }) : _state =
           initialState ?? const SaveSessionState(status: SessionStatus.closed);

  /// Pure engine.
  final SaveEngine engine;

  /// Data-layer repository.
  final SaveRepository repository;

  final List<void Function(SaveSessionState)> _listeners =
      <void Function(SaveSessionState)>[];

  SaveSessionState _state;

  /// Current state.
  SaveSessionState get state => _state;

  /// Registers [listener] for state changes.
  void addListener(void Function(SaveSessionState) listener) {
    _listeners.add(listener);
  }

  /// Removes [listener].
  void removeListener(void Function(SaveSessionState) listener) {
    _listeners.remove(listener);
  }

  /// Releases listeners.
  void dispose() => _listeners.clear();

  /// Dispatches [event].
  Future<void> dispatch(SaveSessionEvent event) async {
    switch (event) {
      case OpenSaveRequested(:final path):
        await open(path);
      case CloseRequested():
        close();
      case SaveRequested():
        await save();
      case SaveAsRequested(:final destinationPath):
        await saveAs(destinationPath);
      case DuplicateRequested(:final destinationPath, :final slot):
        await duplicate(destinationPath, slot: slot);
      case ResetRequested(:final slot, :final clearHistory):
        await reset(slot: slot, clearHistory: clearHistory);
      case FieldEditRequested(:final command):
        edit(command);
      case UndoRequested():
        undo();
      case RedoRequested():
        redo();
      case ValidateRequested():
        validate();
    }
  }

  /// Opens [path] read-only.
  Future<void> open(String path) async {
    final previous = _state.project;
    _emit(
      SaveSessionState(
        status: SessionStatus.opening,
        project: previous,
        busy: true,
        issues: _state.issues,
      ),
    );
    final result = await repository.open(path);
    switch (result) {
      case ParseOk(:final project):
        _emit(
          SaveSessionState(
            status: SessionStatus.ready,
            project: project,
            issues: engine.validate(project),
          ),
        );
      case ParseUnverified(:final project):
        _emit(
          SaveSessionState(
            status: SessionStatus.ready,
            project: project,
            issues: engine.validate(project),
          ),
        );
      case ParseUnsupported(:final reason):
        _emit(
          SaveSessionState(
            status: SessionStatus.error,
            project: previous,
            error: reason,
            issues: _state.issues,
          ),
        );
      case ParseCorrupt(:final reason):
        _emit(
          SaveSessionState(
            status: SessionStatus.error,
            project: previous,
            error: reason,
            issues: _state.issues,
          ),
        );
    }
  }

  /// Releases the project; never writes.
  void close() {
    _emit(const SaveSessionState(status: SessionStatus.closed));
  }

  /// Applies one edit and validates the result.
  void edit(EditCommand command) {
    final project = _state.project;
    if (project == null) {
      _emitError('No project is open');
      return;
    }
    try {
      final updated = engine.apply(project, command);
      _emit(
        SaveSessionState(
          status: SessionStatus.ready,
          project: updated,
          issues: engine.validate(updated),
        ),
      );
    } on FieldWriteException catch (error) {
      _emit(
        SaveSessionState(
          status: SessionStatus.ready,
          project: project,
          error: error.toString(),
          issues: _state.issues,
        ),
      );
    }
  }

  /// Undoes the newest edit.
  void undo() {
    final project = _state.project;
    if (project == null) {
      return;
    }
    final updated = engine.undo(project);
    _emit(
      SaveSessionState(
        status: SessionStatus.ready,
        project: updated,
        issues: engine.validate(updated),
      ),
    );
  }

  /// Redoes the newest undone edit.
  void redo() {
    final project = _state.project;
    if (project == null) {
      return;
    }
    final updated = engine.redo(project);
    _emit(
      SaveSessionState(
        status: SessionStatus.ready,
        project: updated,
        issues: engine.validate(updated),
      ),
    );
  }

  /// Re-runs validation without changing bytes.
  void validate() {
    final project = _state.project;
    if (project == null) {
      return;
    }
    _emit(
      SaveSessionState(
        status: _state.status,
        project: project,
        issues: engine.validate(project),
        busy: _state.busy,
      ),
    );
  }

  /// Saves in place.
  Future<void> save() async {
    final project = _state.project;
    if (project == null) {
      return;
    }
    if (project.history.inTransaction) {
      project.history.commitTransaction();
    }
    final plan = engine.planExport(
      project,
      destinationRoot: project.rootPath,
      mode: ExportMode.saveInPlace,
    );
    await _export(plan);
  }

  /// Saves current state to [destinationPath].
  Future<void> saveAs(String destinationPath) async {
    final project = _state.project;
    if (project == null) {
      return;
    }
    if (project.history.inTransaction) {
      project.history.commitTransaction();
    }
    final plan = engine.planExport(
      project,
      destinationRoot: destinationPath,
      mode: ExportMode.saveAs,
    );
    await _export(plan);
  }

  /// Copies one slot's original bytes to [destinationPath].
  Future<void> duplicate(String destinationPath, {SaveSlotId? slot}) async {
    final project = _state.project;
    if (project == null) {
      return;
    }
    final target =
        slot ??
        (project.layout.slots.isEmpty
            ? SaveSlotId.account
            : project.layout.slots.first.id);
    _emit(
      SaveSessionState(
        status: SessionStatus.saving,
        project: project,
        busy: true,
        issues: _state.issues,
      ),
    );
    final result = await repository.duplicate(
      project,
      target,
      destinationRoot: destinationPath,
      policy: BackupPolicy.standard,
    );
    if (result.succeeded) {
      _emit(
        SaveSessionState(
          status: SessionStatus.saved,
          project: result.project ?? project,
          issues: result.issues,
        ),
      );
    } else {
      _emit(
        SaveSessionState(
          status: SessionStatus.ready,
          project: project,
          error: result.error ?? 'Duplicate failed',
          issues: result.issues,
        ),
      );
    }
  }

  /// Resets one slot, or every open slot when [slot] is null.
  Future<void> reset({SaveSlotId? slot, bool clearHistory = false}) async {
    var project = _state.project;
    if (project == null) {
      return;
    }
    final slots = slot != null
        ? <SaveSlotId>[slot]
        : <SaveSlotId>[
            for (final slotLayout in project.layout.slots)
              if (project.documents.containsKey(slotLayout.id)) slotLayout.id,
          ];
    for (final target in slots) {
      project = await repository.reset(
        project!,
        target,
        clearHistory: clearHistory,
      );
    }
    _emit(
      SaveSessionState(
        status: SessionStatus.ready,
        project: project,
        issues: engine.validate(project!),
      ),
    );
  }

  /// Opens a transaction group.
  void beginTransaction(String label) {
    final project = _state.project;
    if (project == null) {
      return;
    }
    project.history.beginTransaction(label);
    _emit(
      SaveSessionState(
        status: _state.status,
        project: project,
        issues: _state.issues,
      ),
    );
  }

  /// Commits the open transaction.
  void commitTransaction() {
    final project = _state.project;
    if (project == null) {
      return;
    }
    project.history.commitTransaction();
    _emit(
      SaveSessionState(
        status: _state.status,
        project: project,
        issues: engine.validate(project),
      ),
    );
  }

  /// Rolls back the open transaction and restores its starting bytes.
  void rollbackTransaction() {
    final project = _state.project;
    if (project == null) {
      return;
    }
    final before = project.history.rollbackTransaction();
    final updated = before == null
        ? project
        : engine.restoreSnapshot(project, before);
    _emit(
      SaveSessionState(
        status: _state.status,
        project: updated,
        issues: engine.validate(updated),
      ),
    );
  }

  Future<void> _export(ExportPlan plan) async {
    final project = _state.project;
    if (project == null) {
      return;
    }
    _emit(
      SaveSessionState(
        status: SessionStatus.saving,
        project: project,
        busy: true,
        issues: _state.issues,
      ),
    );
    final result = await repository.writeExport(plan);
    if (result.succeeded) {
      final updated = result.project ?? project;
      _emit(
        SaveSessionState(
          status: SessionStatus.saved,
          project: updated,
          issues: engine.validate(updated),
        ),
      );
    } else {
      _emit(
        SaveSessionState(
          status: SessionStatus.ready,
          project: project,
          error: result.error ?? 'Export was refused',
          issues: result.issues,
        ),
      );
    }
  }

  void _emitError(String message) {
    _emit(
      SaveSessionState(
        status: _state.status,
        project: _state.project,
        error: message,
        issues: _state.issues,
        busy: _state.busy,
      ),
    );
  }

  void _emit(SaveSessionState next) {
    _state = next;
    for (final listener in List<void Function(SaveSessionState)>.of(
      _listeners,
    )) {
      listener(next);
    }
  }
}
