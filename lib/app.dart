import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import 'domain/core/validation.dart';
import 'presentation/bloc/save_session/save_session_cubit.dart';
import 'presentation/bloc/save_session/save_session_ui_state.dart';
import 'presentation/bloc/shell/shell_cubit.dart';
import 'presentation/shell/app_shell.dart';
import 'presentation/tabs_support/save_tab_scope.dart';
import 'presentation/tabs_support/save_tab_source.dart';
import 'presentation/tabs_support/session_save_tab_source.dart';
import 'presentation/theme/bomb_flower_theme.dart';

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
  });

  /// Whether the native window chrome is live.
  final bool enableWindowChrome;

  /// The live save session, or `null` for a hermetic test build.
  ///
  /// When null the app owns a [SaveSessionCubit.disabled] that reports typed
  /// errors without touching the filesystem, and closes it on dispose. An
  /// injected cubit is never closed by this widget.
  final SaveSessionCubit? session;

  @override
  State<BombFlowerApp> createState() => _BombFlowerAppState();
}

class _BombFlowerAppState extends State<BombFlowerApp> {
  late SaveSessionCubit _session;
  late _SessionChanges _changes;
  bool _ownsSession = false;

  @override
  void initState() {
    super.initState();
    _attach(widget.session);
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
    _changes = _SessionChanges(_session.stream);
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
    _detach();
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bomb Flower',
      debugShowCheckedModeBanner: false,
      theme: BombFlowerThemeData.build(),
      home: BlocProvider<ShellCubit>(
        create: (_) =>
            ShellCubit(windowChromeEnabled: widget.enableWindowChrome),
        child: BlocProvider<SaveSessionCubit>.value(
          value: _session,
          child: ListenableBuilder(
            listenable: _changes,
            builder: (context, _) =>
                SaveTabScope(source: _createSource(), child: const AppShell()),
          ),
        ),
      ),
    );
  }
}

/// Bridges the session cubit's state stream to the [Listenable] the tab source
/// exposes, so a tab rebuilds once per emitted session state.
final class _SessionChanges extends ChangeNotifier {
  _SessionChanges(Stream<SaveSessionUiState> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<SaveSessionUiState> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
