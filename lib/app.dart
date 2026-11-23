import 'dart:async';

import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import 'data/system/directory_picker.dart';
import 'data/system/dropped_folder.dart';
import 'data/system/open_diagnostics.dart';
import 'domain/core/validation.dart';
import 'presentation/bloc/save_session/save_session_cubit.dart';
import 'presentation/bloc/save_session/save_session_ui_state.dart';
import 'presentation/bloc/shell/shell_cubit.dart';
import 'presentation/bloc/shell/shell_state.dart';
import 'presentation/dialogs/open_save_dialog.dart';
import 'presentation/shell/app_shell.dart';
import 'presentation/tabs_support/save_tab_scope.dart';
import 'presentation/tabs_support/save_tab_source.dart';
import 'presentation/tabs_support/session_save_tab_source.dart';
import 'presentation/theme/bomb_flower_theme.dart';
import 'presentation/widgets/common/open_save_scope.dart';

/// Prefix the save-session cubit writes before the attempted folder.
const String _folderLinePrefix = 'Folder: ';

/// The layout-resolver failure wording that names the attempted folder.
final RegExp _layoutPathPattern = RegExp(r'no layout for "([^"]+)"');

/// Channel the native runner reports dropped paths on.
///
/// One method, `folderDropped`, with the absolute path of the first dropped
/// file or folder as its only argument.
const MethodChannel _dropChannel = MethodChannel('bomb_flower/drop');

/// Root widget.
///
/// [enableWindowChrome] is false in widget tests: bitsdojo's native window
/// calls do not exist in a headless test binding, so the title bar renders but
/// its controls become no-ops.
class BombFlowerApp extends StatefulWidget {
  const BombFlowerApp({
    super.key,
    this.enableWindowChrome = true,
    this.session,
    this.saveFolderProbe,
    this.recentPaths,
    this.directoryPicker,
    this.initialOpenPath,
  });

  /// Whether the native window chrome is live.
  final bool enableWindowChrome;

  /// A folder to open once the first frame is scheduled, or `null`.
  ///
  /// Startup uses this instead of calling the session directly so every open
  /// goes through one path: folder-shape diagnosis, then the log line.
  final String? initialOpenPath;

  /// The live save session, or `null` for a hermetic test build.
  ///
  /// When null the app owns a [SaveSessionCubit.disabled] that reports typed
  /// errors without touching the filesystem, and closes it on dispose. An
  /// injected cubit is never closed by this widget.
  final SaveSessionCubit? session;

  /// Folder inspector used by the open-save dialog.
  ///
  /// Resolved lazily when the dialog first opens so an app that never opens a
  /// folder does no filesystem work and tests stay hermetic.
  final SaveFolderProbe? saveFolderProbe;

  /// Recent-folder port used by the open-save dialog; resolved lazily.
  final RecentPathsStore? recentPaths;

  /// Optional native folder chooser used by the open-save dialog.
  final DirectoryPicker? directoryPicker;

  @override
  State<BombFlowerApp> createState() => _BombFlowerAppState();
}

class _BombFlowerAppState extends State<BombFlowerApp> {
  late SaveSessionCubit _session;
  late _SessionChanges _changes;
  late final ShellCubit _shell;
  bool _ownsSession = false;

  /// A folder-shape refusal that never reached the engine.
  ///
  /// It takes precedence over the session's own error because it explains the
  /// user's selection mistake, not the save's contents.
  OpenFailureNotice? _preflightFailure;

  @override
  void initState() {
    super.initState();
    _shell = ShellCubit(windowChromeEnabled: widget.enableWindowChrome);
    _attach(widget.session);
    _dropChannel.setMethodCallHandler(_handleDropCall);
    final initial = widget.initialOpenPath?.trim();
    if (initial != null && initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_openPath(initial));
        }
      });
    }
  }

  @override
  void didUpdateWidget(BombFlowerApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      _detach();
      _attach(widget.session);
    }
  }

  void _attach(SaveSessionCubit? injected) {
    _ownsSession = injected == null;
    _session = injected ?? SaveSessionCubit.disabled();
    _changes = _SessionChanges(
      _session.stream,
      onState: (state) {
        _applyChrome(state);
        // A refusal from a previous attempt must not outlive a new open.
        if (_preflightFailure != null && state is! SaveSessionError) {
          _preflightFailure = null;
        }
      },
    );
    _applyChrome(_session.state);
  }

  /// Pushes the session's view of the open save into the shell chrome.
  ///
  /// The session stays authoritative; the shell only renders what it reports.
  void _applyChrome(SaveSessionUiState state) {
    if (!mounted) {
      return;
    }
    final project = _projectOf(state);
    if (project == null) {
      _shell.clearSaveSession();
      return;
    }
    _shell.showSaveSession(
      saveName: _saveName(project),
      filePath: project.path,
      revision: '${project.detectedVersion}',
      isDirty: project.hasUnsavedChanges,
      statusMessage: project.statusMessage,
      validationSummary: project.validationSummary,
      validationHealth: project.hasBlockingErrors
          ? ShellValidationHealth.errors
          : project.actionableWarningCount > 0
          ? ShellValidationHealth.warnings
          : ShellValidationHealth.ok,
    );
  }

  static SaveProjectUi? _projectOf(SaveSessionUiState state) => switch (state) {
    SaveSessionReady(:final project) => project,
    SaveSessionSaving(:final project) => project,
    SaveSessionPendingDiscard(:final project) => project,
    SaveSessionSaved(:final project) => project,
    SaveSessionError(:final project) => project,
    SaveSessionOpening() || SaveSessionClosed() => null,
  };

  /// Folder name plus active slot, for example `kokiri-start · slot_00`.
  static String _saveName(SaveProjectUi project) {
    final folder = _baseName(project.path);
    final slot = project.activeSlot?.value;
    return slot == null ? folder : '$folder · $slot';
  }

  static String _baseName(String path) {
    final trimmed = path.trim();
    final index = trimmed.lastIndexOf(RegExp(r'[/\\]'));
    return index < 0 ? trimmed : trimmed.substring(index + 1);
  }

  /// The single open path: diagnose the folder shape, open, then log one line.
  ///
  /// Every attempt is logged exactly once, including refusals that never reach
  /// the engine. Only the path and the engine's own reason text are logged;
  /// save bytes and field values are never in scope here.
  Future<void> _openPath(String rawPath) async {
    final path = rawPath.trim();
    if (path.isEmpty) {
      return;
    }
    final probe = widget.saveFolderProbe ?? const IoSaveFolderProbe();
    final info = await probe.inspect(path);
    final slotMessage = slotFolderMisselection(info);
    if (slotMessage != null) {
      if (mounted) {
        setState(() {
          _preflightFailure = OpenFailureNotice(
            message: slotMessage,
            details: 'Slot folder: $path',
            path: path,
          );
        });
      }
      debugPrint(
        formatOpenLogLine(
          path: path,
          outcome: OpenOutcome.unsupported,
          reason: slotMessage,
        ),
      );
      return;
    }
    if (_preflightFailure != null && mounted) {
      setState(() => _preflightFailure = null);
    }

    final before = _session.lastOpenResult;
    await _session.openPath(path);
    if (!mounted) {
      return;
    }
    final after = _session.lastOpenResult;
    final result = identical(before, after) ? null : after;
    if (result != null) {
      final mapped = openOutcomeOf(result);
      debugPrint(
        formatOpenLogLine(
          path: path,
          outcome: mapped.outcome,
          reason: mapped.reason,
        ),
      );
      return;
    }
    final state = _session.state;
    debugPrint(
      formatOpenLogLine(
        path: path,
        outcome: OpenOutcome.unsupported,
        reason: state is SaveSessionError
            ? state.message
            : 'the attempt was refused before the engine parsed it',
      ),
    );
  }

  /// Handles one path dropped onto the window. Never throws to the platform.
  ///
  /// The platform reply is sent before any filesystem work. The native runner
  /// fires and forgets, and a reply that waited on real I/O would never be
  /// pumped by the widget-test binding's fake clock.
  Future<void> _handleDropCall(MethodCall call) async {
    if (call.method != 'folderDropped') {
      return;
    }
    final argument = call.arguments;
    if (argument is! String) {
      return;
    }
    unawaited(_openDroppedPath(argument));
  }

  /// Resolves one dropped path, then opens the root or reports the refusal.
  ///
  /// A save root opens through the existing [_openPath], which writes exactly
  /// one log line. A refusal never reaches the engine, so it only sets the
  /// preflight notice the existing failure panel renders; no path content is
  /// read or logged beyond the path itself.
  Future<void> _openDroppedPath(String rawPath) async {
    final result = await resolveDroppedFolder(rawPath);
    if (!mounted) {
      return;
    }
    switch (result) {
      case DroppedFolderRoot(:final path):
        unawaited(_openPath(path));
      case DroppedFolderInvalid(:final path, :final reason):
        setState(() {
          _preflightFailure = OpenFailureNotice(
            message: reason,
            details: 'Dropped: $path',
            path: path,
          );
        });
    }
  }

  /// A fresh source per session state.
  ///
  /// [SaveTabScope.updateShouldNotify] compares source identity, so a new
  /// instance makes a tab that rendered the closed state rebuild once a
  /// startup open lands. The closures always read the live cubit.
  SessionSaveTabSource _createSource() {
    return SessionSaveTabSource(
      project: () => _session.openProject,
      edit: _session.edit,
      undo: _session.undo,
      redo: _session.redo,
      issues: _issues,
      activeSlot: () => _uiProject()?.activeSlot,
      slotAges: _slotAges,
      changes: _changes,
      canUndo: () => _uiProject()?.canUndo ?? false,
      canRedo: () => _uiProject()?.canRedo ?? false,
    );
  }

  void _detach() {
    _changes.dispose();
    if (_ownsSession && !_session.isClosed) {
      unawaited(_session.close());
    }
  }

  @override
  void dispose() {
    _dropChannel.setMethodCallHandler(null);
    _detach();
    unawaited(_shell.close());
    super.dispose();
  }

  SaveProjectUi? _uiProject() => switch (_session.state) {
    SaveSessionReady(:final project) => project,
    SaveSessionSaving(:final project) => project,
    SaveSessionPendingDiscard(:final project) => project,
    SaveSessionSaved(:final project) => project,
    SaveSessionError(:final project) => project,
    SaveSessionOpening() || SaveSessionClosed() => null,
  };

  List<ValidationIssue> _issues() =>
      _uiProject()?.issues ?? const <ValidationIssue>[];

  List<SlotAge> _slotAges() {
    final project = _uiProject();
    if (project == null) {
      return const <SlotAge>[];
    }
    return <SlotAge>[
      for (final age in project.slotAges)
        SlotAge(
          slot: age.slot,
          progressPath: age.progressPath,
          modifiedAt: age.modifiedAt,
        ),
    ];
  }

  /// Best-effort recovery of the folder a failed open targeted.
  ///
  /// [SaveSessionError] carries no path, so this prefers the folder the session
  /// last reported opening, then parses the two shapes
  /// [SaveSessionCubit] writes into its `details`: a trailing `Folder: <path>`
  /// line (resolver succeeded, repository failed) and the layout resolver's
  /// `no layout for "<path>"` sentence (resolution failed before any opening
  /// state). This couples presentation to the cubit's wording because the bloc
  /// layer is out of scope here; a wording change only costs the retry
  /// affordance, never the panel itself. Odd input resolves to `null`.
  String? _attemptedOpenPath(SaveSessionError error) {
    final opened = _changes.lastOpenPath;
    if (opened != null && opened.isNotEmpty) {
      return opened;
    }
    return _pathFromDetails(error.details);
  }

  String? _pathFromDetails(String? details) {
    if (details == null || details.isEmpty) {
      return null;
    }
    for (final line in details.split('\n').reversed) {
      final trimmed = line.trim();
      if (trimmed.startsWith(_folderLinePrefix)) {
        final path = trimmed.substring(_folderLinePrefix.length).trim();
        if (path.isNotEmpty) {
          return path;
        }
      }
    }
    final path = _layoutPathPattern.firstMatch(details)?.group(1)?.trim();
    return path == null || path.isEmpty ? null : path;
  }

  /// Opens the save-folder dialog and opens whatever folder it returns.
  ///
  /// The probe and recent-path ports default lazily so an app that never opens
  /// the dialog performs no filesystem work.
  Future<void> _openAnotherSave(
    BuildContext context,
    String? initialPath,
  ) async {
    final chosen = await OpenSaveDialog.show(
      context,
      probe: widget.saveFolderProbe ?? const IoSaveFolderProbe(),
      recentPaths: widget.recentPaths ?? RecentPathsFileStore(),
      directoryPicker: widget.directoryPicker,
      initialPath: initialPath,
    );
    if (!mounted) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final trimmed = chosen?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }
    unawaited(_openPath(trimmed));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bomb Flower',
      debugShowCheckedModeBanner: false,
      theme: BombFlowerThemeData.build(),
      home: BlocProvider<ShellCubit>.value(
        value: _shell,
        child: BlocProvider<SaveSessionCubit>.value(
          value: _session,
          child: ListenableBuilder(
            listenable: _changes,
            builder: (context, _) {
              final state = _session.state;
              // Only a failed open with nothing behind it replaces the tabs; a
              // failure on a live project leaves that project's tabs usable.
              final sessionFailure =
                  state is SaveSessionError && state.project == null
                  ? state
                  : null;
              final failure =
                  _preflightFailure ??
                  (sessionFailure == null
                      ? null
                      : OpenFailureNotice(
                          message: sessionFailure.message,
                          details: sessionFailure.details,
                          path: _attemptedOpenPath(sessionFailure),
                        ));
              final retryPath = sessionFailure == null ? null : failure?.path;
              return SaveTabScope(
                source: _createSource(),
                child: OpenSaveScope(
                  open: (shellContext) =>
                      _openAnotherSave(shellContext, failure?.path),
                  child: AppShell(
                    saveFolderProbe: widget.saveFolderProbe,
                    openFailure: failure,
                    onRetryOpen: retryPath == null
                        ? null
                        : () => unawaited(_openPath(retryPath)),
                    onOpenAnotherSave: (shellContext) =>
                        _openAnotherSave(shellContext, failure?.path),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Bridges the session cubit's state stream to the [Listenable] the tab source
/// exposes, so a tab rebuilds once per emitted session state.
final class _SessionChanges extends ChangeNotifier {
  _SessionChanges(Stream<SaveSessionUiState> stream, {this.onState}) {
    _subscription = stream.listen((state) {
      // Remember the folder being opened so a later failure can offer a retry
      // even though the error state carries no path. Never cleared on error.
      if (state is SaveSessionOpening && state.path.isNotEmpty) {
        lastOpenPath = state.path;
      }
      onState?.call(state);
      notifyListeners();
    });
  }

  /// Called for every session state, before listeners rebuild.
  final void Function(SaveSessionUiState state)? onState;

  late final StreamSubscription<SaveSessionUiState> _subscription;

  /// The most recent folder the session reported opening.
  String? lastOpenPath;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
