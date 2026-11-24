import 'dart:async';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart' hide Banner;

import '../../../data/system/directory_lister.dart';
import '../../../data/system/directory_picker.dart';
import '../../../data/system/longshot_launcher.dart';
import '../../../data/system/longshot_launcher_resolver.dart';
import '../../../data/system/open_diagnostics.dart';
import '../../bloc/save_session/save_session_cubit.dart';
import '../../bloc/save_session/save_session_ui_state.dart';
import '../../dialogs/open_save_dialog.dart';
import '../../dialogs/reset_slot_dialog.dart';
import '../../dialogs/save_as_dialog.dart';
import '../../shell/tabs/settings_tab.dart';
import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_typography.dart';
import '../common/banner.dart';
import '../common/bomb_flower_mark.dart';
import '../common/procedural_painters.dart';
import '../controls/control_icon_button.dart';
import 'file_action_bar.dart';

/// Height of the custom title bar, in logical pixels.
const double kAppTitleBarHeight = BombFlowerSpacing.titleBarHeight;

/// Frameless window chrome: wood grain, brand mark, save identity slot, dirty
/// indicator slot, the file action group, and the three window controls.
///
/// [interactive] must be false in widget tests. The bar still lays out and
/// paints, but every native bitsdojo call becomes a no-op.
///
/// The file actions are driven by the ambient [SaveSessionCubit] when one is
/// available; [session] can inject one instead, and a null session simply
/// disables every action. Failures are surfaced in the centre slot so an action
/// can never fail silently.
class AppTitleBar extends StatefulWidget {
  const AppTitleBar({
    super.key,
    this.interactive = true,
    this.isDirty = false,
    this.saveName,
    this.session,
    this.saveFolderProbe,
    this.recentPaths,
    this.directoryPicker,
    this.directoryLister,
    this.settingsStore,
    this.launcher,
    this.launcherResolver,
    this.onOpenPath,
    this.onHelp,
    this.onNewSave,
  });

  final bool interactive;
  final bool isDirty;

  /// Current save identity. Null means no file is open; the center slot says so
  /// rather than inventing a filename.
  final String? saveName;

  /// Session backing the file actions. Null looks the cubit up from context.
  final SaveSessionCubit? session;

  /// Filesystem inspector for the Open and Save As dialogs.
  final SaveFolderProbe? saveFolderProbe;

  /// Recent-folder store for the Open dialog.
  final RecentPathsStore? recentPaths;

  /// Optional native folder chooser for Save As and Duplicate.
  final DirectoryPicker? directoryPicker;

  /// Directory listing port for the in-app Open picker.
  final DirectoryLister? directoryLister;

  /// Store the Launch action reads the launcher path from. Null falls back to a
  /// fresh [InMemorySettingsStore], whose launcher path is unset.
  final SettingsStore? settingsStore;

  /// Launcher seam. Null falls back to the real detached process starter.
  final LongshotLauncher? launcher;

  /// Use-time resolver for when the stored launcher path is unset. Null falls
  /// back to environment, next-to-app and `PATH` discovery.
  final LongshotLauncherResolver? launcherResolver;

  /// The app's single open path. Null keeps this bar's local open-and-log.
  final Future<void> Function(String path)? onOpenPath;

  /// Opens the help surface. Null disables the help button, but the bar is
  /// still usable: help needs no session and no project.
  final VoidCallback? onHelp;

  /// Opens the new-save dialog. Null disables the button; like help, it is
  /// independent of whether a save is currently open.
  final VoidCallback? onNewSave;

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar> {
  /// The last action failure, shown in place of the save identity.
  String? _actionError;

  void _startDragging() {
    if (widget.interactive) appWindow.startDragging();
  }

  void _minimize() {
    if (widget.interactive) appWindow.minimize();
  }

  void _maximizeOrRestore() {
    if (widget.interactive) appWindow.maximizeOrRestore();
  }

  void _close() {
    if (widget.interactive) appWindow.close();
  }

  /// The injected session, else the ambient one, else null when neither exists.
  ///
  /// `BlocProvider.of` rewraps a miss in a [FlutterError], so this uses
  /// [ReadContext.read], which throws the typed [ProviderNotFoundException]
  /// that means "this bar was pumped without a session".
  SaveSessionCubit? _sessionOf(BuildContext context) {
    final injected = widget.session;
    if (injected != null) {
      return injected;
    }
    try {
      return context.read<SaveSessionCubit>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// The project carried by [state], or null when nothing is open.
  SaveProjectUi? _projectOf(SaveSessionUiState state) {
    return switch (state) {
      SaveSessionReady(:final project) => project,
      SaveSessionSaving(:final project) => project,
      SaveSessionSaved(:final project) => project,
      SaveSessionPendingDiscard(:final project) => project,
      SaveSessionError(:final project) => project,
      SaveSessionClosed() || SaveSessionOpening() => null,
    };
  }

  /// Mirrors the cubit's failure into the centre slot, or clears it on success.
  void _syncError(SaveSessionCubit cubit) {
    if (!mounted) {
      return;
    }
    final state = cubit.state;
    final message = state is SaveSessionError ? state.message : null;
    if (message == _actionError) {
      return;
    }
    setState(() => _actionError = message);
  }

  Future<void> _open(SaveSessionCubit cubit) async {
    final path = await OpenSaveDialog.show(
      context,
      probe: widget.saveFolderProbe ?? const IoSaveFolderProbe(),
      recentPaths: widget.recentPaths ?? RecentPathsFileStore(),
      directoryLister: widget.directoryLister,
      settingsStore: widget.settingsStore,
      initialPath: cubit.openProject?.rootPath,
    );
    if (!mounted || path == null) {
      return;
    }
    final openPath = widget.onOpenPath;
    if (openPath != null) {
      // One open path for the whole app: folder-shape diagnosis, one log line,
      // and the same session state as the startup env var and drops.
      await openPath(path);
      if (!mounted) {
        return;
      }
      _syncError(cubit);
      return;
    }
    debugPrint('[open-picker] chose=$path');
    final before = cubit.lastOpenResult;
    await cubit.openPath(path);
    if (!mounted) {
      return;
    }
    _syncError(cubit);
    final result = cubit.lastOpenResult;
    final state = cubit.state;
    if (result != null && !identical(before, result)) {
      final mapped = openOutcomeOf(result);
      debugPrint(
        formatOpenLogLine(
          path: path,
          outcome: mapped.outcome,
          reason: mapped.reason,
        ),
      );
    } else {
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
  }

  Future<void> _save(SaveSessionCubit cubit) async {
    await cubit.save();
    _syncError(cubit);
  }

  Future<void> _saveAs(SaveSessionCubit cubit, SaveProjectUi project) async {
    final request = await SaveAsDialog.show(
      context,
      project: project,
      probe: widget.saveFolderProbe ?? const IoSaveFolderProbe(),
      directoryPicker: widget.directoryPicker,
    );
    if (!mounted || request == null) {
      return;
    }
    await cubit.saveAs(request.destinationPath, overwrite: request.overwrite);
    _syncError(cubit);
  }

  Future<void> _duplicate(SaveSessionCubit cubit, SaveProjectUi project) async {
    final request = await SaveAsDialog.show(
      context,
      project: project,
      probe: widget.saveFolderProbe ?? const IoSaveFolderProbe(),
      directoryPicker: widget.directoryPicker,
    );
    if (!mounted || request == null) {
      return;
    }
    await cubit.duplicate(request.destinationPath);
    _syncError(cubit);
  }

  Future<void> _reset(SaveSessionCubit cubit, SaveProjectUi project) async {
    final confirmed = await ResetSlotDialog.show(
      context,
      slotLabel: project.activeSlot?.value ?? 'the open slots',
      backupPath: project.backupPath,
    );
    if (!mounted || !confirmed) {
      return;
    }
    await cubit.reset(slot: project.activeSlot, confirm: true);
    _syncError(cubit);
  }

  void _undo(SaveSessionCubit cubit) {
    cubit.undo();
    _syncError(cubit);
  }

  void _redo(SaveSessionCubit cubit) {
    cubit.redo();
    _syncError(cubit);
  }

  /// Starts the configured launcher. Independent of any open save, so the
  /// action works before a project is loaded.
  ///
  /// An unset preference is resolved at use time rather than defaulted to a
  /// path from another machine. If resolution finds nothing, no process is
  /// started: the banner says so and points at Settings. A resolved path is
  /// launched as-is and is not persisted.
  Future<void> _launch() async {
    final store = widget.settingsStore ?? InMemorySettingsStore();
    final preferences = await store.load();
    if (!mounted) {
      return;
    }
    var path = preferences.launcherPath.trim();
    if (path.isEmpty) {
      path = (widget.launcherResolver ?? const IoLongshotLauncherResolver())
          .resolve()
          .trim();
    }
    if (path.isEmpty) {
      setState(() => _actionError = kNoLongshotLauncherConfigured);
      return;
    }
    final result = await (widget.launcher ?? const IoLongshotLauncher()).launch(
      path,
    );
    if (!mounted) {
      return;
    }
    setState(() => _actionError = result.started ? null : result.message);
  }

  /// The file action group, enabled from the current session state.
  Widget _actionGroup(SaveSessionCubit? cubit, SaveSessionUiState? state) {
    if (cubit == null || state == null) {
      return FileActionBar(
        onOpen: null,
        onSave: null,
        onSaveAs: null,
        onDuplicate: null,
        onReset: null,
        onUndo: null,
        onRedo: null,
        onLaunch: () => unawaited(_launch()),
        disabledReason: 'Open a save first',
      );
    }
    final project = _projectOf(state);
    if (project == null) {
      return FileActionBar(
        onOpen: () => unawaited(_open(cubit)),
        onSave: null,
        onSaveAs: null,
        onDuplicate: null,
        onReset: null,
        onUndo: null,
        onRedo: null,
        onLaunch: () => unawaited(_launch()),
        disabledReason: 'Open a save first',
      );
    }
    return FileActionBar(
      onOpen: () => unawaited(_open(cubit)),
      onSave: project.hasUnsavedChanges ? () => unawaited(_save(cubit)) : null,
      onSaveAs: () => unawaited(_saveAs(cubit, project)),
      onDuplicate: () => unawaited(_duplicate(cubit, project)),
      onReset: () => unawaited(_reset(cubit, project)),
      onUndo: project.canUndo ? () => _undo(cubit) : null,
      onRedo: project.canRedo ? () => _redo(cubit) : null,
      onLaunch: () => unawaited(_launch()),
    );
  }

  /// One session-independent shell action (new save, help), styled like the
  /// file-action cluster and wide enough to be an easy title-bar target.
  Widget _shellAction({
    required Key key,
    required IconData icon,
    required String tooltip,
    required String semanticsLabel,
    required VoidCallback? onPressed,
  }) {
    return ControlIconButton(
      key: key,
      icon: icon,
      onPressed: onPressed,
      semanticLabel: semanticsLabel,
      tooltip: tooltip,
      size: BombFlowerSpacing.titleBarButtonWidth,
      iconSize: 15,
      foregroundColor: BombFlowerColors.bone,
      borderColor: BombFlowerColors.woodLight,
      hoverColor: BombFlowerColors.canopyHover,
      focusColor: BombFlowerColors.brassFocus,
    );
  }

  /// Save identity, or the last action failure in its place.
  Widget _centreSlot() {
    final error = _actionError;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: BombFlowerSpacing.lg),
        child: Banner(
          key: const Key('title-bar-action-error'),
          variant: BannerVariant.danger,
          title: error,
          onDismiss: () => setState(() => _actionError = null),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            widget.saveName ?? 'No save open',
            key: const Key('title-bar-save-name'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BombFlowerTypography.button.copyWith(
              color: BombFlowerColors.bone,
            ),
          ),
        ),
        const SizedBox(width: BombFlowerSpacing.sm),
        Semantics(
          label: widget.isDirty ? 'Unsaved changes' : null,
          child: Container(
            key: const Key('title-bar-dirty-indicator'),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isDirty
                  ? BombFlowerColors.brass
                  : Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _sessionOf(context);
    return SizedBox(
      height: kAppTitleBarHeight,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: const WoodGrainPainter(
            top: BombFlowerColors.woodDark,
            bottom: BombFlowerColors.wood,
            seed: 5,
          ),
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: Row(
              children: <Widget>[
                // The window drag region stops before the file actions.
                // Keeping the action cluster outside this detector is what
                // lets a real click reach it: the drag recognizer accepts
                // after 2 px of precise-pointer (mouse) movement, and once it
                // wins the gesture arena the button's tap is cancelled. Empty
                // title-bar space and the centre slot still drag the window.
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => _startDragging(),
                    onDoubleTap: _maximizeOrRestore,
                    child: Row(
                      children: <Widget>[
                        const SizedBox(width: BombFlowerSpacing.xl),
                        const BombFlowerMark(size: 32, onDark: true),
                        const SizedBox(width: 10),
                        Text(
                          'BOMB FLOWER',
                          style: BombFlowerTypography.label.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            color: BombFlowerColors.bone,
                          ),
                        ),
                        const SizedBox(width: BombFlowerSpacing.xl),
                        Expanded(child: Center(child: _centreSlot())),
                      ],
                    ),
                  ),
                ),
                if (session == null)
                  _actionGroup(null, null)
                else
                  BlocBuilder<SaveSessionCubit, SaveSessionUiState>(
                    bloc: session,
                    builder: (context, state) => _actionGroup(session, state),
                  ),
                // Session-independent actions: they work before any save is
                // open, so they sit outside the session-driven group. Both
                // live outside the drag region above, or a real click would
                // lose the gesture arena to the window drag recognizer.
                _shellAction(
                  key: const Key('shell-action-new-save'),
                  icon: Icons.add_box_outlined,
                  tooltip: 'New save…',
                  semanticsLabel: 'Create a new save',
                  onPressed: widget.onNewSave,
                ),
                _shellAction(
                  key: const Key('shell-action-help'),
                  icon: Icons.help_outline,
                  tooltip: 'Help (F1)',
                  semanticsLabel: 'Help',
                  onPressed: widget.onHelp,
                ),
                _TitleBarButton(
                  tooltip: 'Minimize',
                  semanticsLabel: 'Minimize window',
                  onPressed: _minimize,
                  glyph: _WindowGlyph.minimize,
                ),
                _TitleBarButton(
                  tooltip: 'Maximize',
                  semanticsLabel: 'Maximize or restore window',
                  onPressed: _maximizeOrRestore,
                  glyph: _WindowGlyph.maximize,
                ),
                _TitleBarButton(
                  tooltip: 'Close',
                  semanticsLabel: 'Close window',
                  onPressed: _close,
                  glyph: _WindowGlyph.close,
                  danger: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _WindowGlyph { minimize, maximize, close }

class _TitleBarButton extends StatefulWidget {
  const _TitleBarButton({
    required this.tooltip,
    required this.semanticsLabel,
    required this.onPressed,
    required this.glyph,
    this.danger = false,
  });

  final String tooltip;
  final String semanticsLabel;
  final VoidCallback onPressed;
  final _WindowGlyph glyph;
  final bool danger;

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final fill = _pressed
        ? widget.danger
              ? BombFlowerColors.dangerPressed
              : BombFlowerColors.canopyPressed
        : _hovered
        ? widget.danger
              ? BombFlowerColors.dangerStrong
              : BombFlowerColors.canopyHover
        : Colors.transparent;

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: Tooltip(
        message: widget.tooltip,
        child: FocusableActionDetector(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed();
                return null;
              },
            ),
          },
          onShowHoverHighlight: (value) {
            if (_hovered != value) setState(() => _hovered = value);
          },
          onShowFocusHighlight: (value) {
            if (_focused != value) setState(() => _focused = value);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {},
              onPanUpdate: (_) {},
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: widget.onPressed,
              child: SizedBox(
                width: BombFlowerSpacing.titleBarButtonWidth,
                height: kAppTitleBarHeight,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: AnimatedContainer(
                        duration: BombFlowerMotion.adaptive(
                          context,
                          BombFlowerMotion.hover,
                        ),
                        color: fill,
                      ),
                    ),
                    Center(
                      child: CustomPaint(
                        size: const Size.square(12),
                        painter: _WindowGlyphPainter(
                          glyph: widget.glyph,
                          color: BombFlowerColors.bone,
                        ),
                      ),
                    ),
                    if (_focused)
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: const FocusRingPainter(
                                color: BombFlowerColors.brassFocus,
                                radius: BombFlowerRadii.sm,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowGlyphPainter extends CustomPainter {
  const _WindowGlyphPainter({required this.glyph, required this.color});

  final _WindowGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 16;
    canvas.save();
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (glyph) {
      case _WindowGlyph.minimize:
        canvas.drawLine(const Offset(4, 11), const Offset(12, 11), paint);
      case _WindowGlyph.maximize:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(4, 4, 8, 8),
            const Radius.circular(1.5),
          ),
          paint,
        );
      case _WindowGlyph.close:
        paint.strokeWidth = 1.4;
        canvas.drawLine(const Offset(4, 4), const Offset(12, 12), paint);
        canvas.drawLine(const Offset(12, 4), const Offset(4, 12), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WindowGlyphPainter oldDelegate) {
    return glyph != oldDelegate.glyph || color != oldDelegate.color;
  }
}
