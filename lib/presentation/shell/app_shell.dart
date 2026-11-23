import 'dart:async';

import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart' hide Banner;

import '../../data/system/directory_lister.dart';
import '../../data/system/directory_picker.dart';
import '../../data/system/longshot_launcher.dart';
import '../bloc/save_session/save_session_cubit.dart';
import '../bloc/shell/shell_cubit.dart';
import '../bloc/shell/shell_state.dart';
import '../bloc/shell/tab_definition.dart';
import '../dialogs/new_save_dialog.dart';
import '../theme/bomb_flower_colors.dart';
import '../theme/bomb_flower_spacing.dart';
import '../theme/bomb_flower_typography.dart';
import '../widgets/chrome/app_title_bar.dart';
import '../widgets/common/banner.dart';
import '../widgets/common/brass_button.dart';
import '../widgets/common/error_state.dart';
import '../widgets/common/procedural_painters.dart';
import '../widgets/help/help_scope.dart';
import '../widgets/help/help_surface.dart';
import 'shell_nav_rail.dart';
import 'shell_status_footer.dart';
import 'tabs/advanced_data_tab.dart';
import 'tabs/collectibles_tab.dart';
import 'tabs/dungeons_tab.dart';
import 'tabs/equipment_tab.dart';
import 'tabs/flags_tab.dart';
import 'tabs/inventory_tab.dart';
import 'tabs/overview_tab.dart';
import 'tabs/placeholder_tab.dart';
import 'tabs/player_world_tab.dart';
import 'tabs/progression_tab.dart';
import 'tabs/resources_tab.dart';
import 'tabs/settings_tab.dart';

/// A failed save-open worth a persistent panel instead of the empty state.
///
/// [path] is the folder the open targeted, when it can be recovered; it drives
/// the retry action and the visible folder line. [details] is the session's
/// technical context, shown verbatim when no path is known.
final class OpenFailureNotice {
  /// Creates a notice.
  const OpenFailureNotice({required this.message, this.details, this.path});

  /// Friendly, primary explanation.
  final String message;

  /// Technical context from the session error.
  final String? details;

  /// The folder the open attempted, when known.
  final String? path;
}

/// Application shell: 44 px title bar, 232/64 px navigation rail, scrollable
/// tab content capped at 1680 px, and a 28 px status footer.
///
/// The shell is a pure view: [openFailure] replaces the tab content with a
/// persistent failure panel, and every action it offers is an optional callback
/// supplied by whoever owns the session.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.openFailure,
    this.onRetryOpen,
    this.onOpenAnotherSave,
    this.onOpenPath,
    this.unverifiedFieldCount = 0,
    this.saveFolderProbe,
    this.directoryLister,
    this.settingsStore,
    this.longshotLauncher,
    this.newSaveSchemaLoader,
    this.newSavePersist,
    this.newSaveDirectoryPicker,
  });

  /// A failed open to render instead of the tab content, or `null`.
  final OpenFailureNotice? openFailure;

  /// Retries the failed open. A null value disables the retry button.
  final VoidCallback? onRetryOpen;

  /// Shows the open-save dialog so the user can choose another folder.
  final Future<void> Function(BuildContext context)? onOpenAnotherSave;

  /// The app's single open path, used by the title bar so its Open action
  /// writes the same `open <path> -> …` line as every other entry point.
  final Future<void> Function(String path)? onOpenPath;

  /// How many fields opened read-only because their meaning is unverified.
  ///
  /// Non-zero shows one dismissible notice above the tab content; the field
  /// layer already refuses edits, so this only explains why.
  final int unverifiedFieldCount;

  /// Filesystem probe handed to the title bar's file actions, so tests can
  /// substitute a fake. A null value falls back to the real IO probe there.
  final SaveFolderProbe? saveFolderProbe;

  /// Directory listing port handed to the title bar's open-save picker so
  /// tests can keep the dialog hermetic.
  final DirectoryLister? directoryLister;

  /// Preferences store shared by the Settings tab and the title bar, so a path
  /// edited there reaches the Launch action without a restart. A null value
  /// makes the shell own one [InMemorySettingsStore].
  final SettingsStore? settingsStore;

  /// Launcher used by the title bar. A null value uses the real detached
  /// process starter.
  final LongshotLauncher? longshotLauncher;

  /// Schema loader for the new-save dialog. A null value loads the bundled
  /// `gamedata_110.json` asset, which is what production uses.
  final GameDataSchemaLoader? newSaveSchemaLoader;

  /// Writer for the new-save dialog. A null value uses the real
  /// [NewSaveWriter], so tests must inject one to stay off disk.
  final NewSavePersist? newSavePersist;

  /// Folder chooser for the new-save dialog. A null value uses the system
  /// chooser.
  final DirectoryPicker? newSaveDirectoryPicker;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// One store for the whole shell: Settings writes it, the title bar reads it.
  late final SettingsStore _settingsStore =
      widget.settingsStore ?? InMemorySettingsStore();

  /// One launcher seam for the title bar.
  late final LongshotLauncher _launcher =
      widget.longshotLauncher ?? const IoLongshotLauncher();

  /// Whether the unverified-fields notice was dismissed for this open.
  bool _unverifiedDismissed = false;

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unverifiedFieldCount != widget.unverifiedFieldCount) {
      _unverifiedDismissed = false;
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;

    // Ctrl+O is the app's open-save shortcut and must work at every width,
    // including where the title-bar Open action collapses. It is intercepted
    // first because it is not a tab shortcut and must not be swallowed by the
    // text-field guard. The callback is the one existing open path.
    if (keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed &&
        !keyboard.isMetaPressed &&
        event.logicalKey == LogicalKeyboardKey.keyO) {
      final open = widget.onOpenAnotherSave;
      if (open != null) {
        unawaited(open(context));
        return KeyEventResult.handled;
      }
    }

    // F1 opens the static help surface. Checked before the text-field guard so
    // it works even while a field has focus; it is an unmodified function key,
    // so it cannot collide with typing. Ctrl+O above keeps its own binding.
    if (!keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed &&
        !keyboard.isMetaPressed &&
        event.logicalKey == LogicalKeyboardKey.f1) {
      unawaited(HelpSurface.show(context));
      return KeyEventResult.handled;
    }

    // Leave editing keys alone while a text field has focus. The shell has no
    // editable placeholder fields yet, but this is the permanent seam.
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }

    final consumed = context.read<ShellCubit>().handleShortcut(
      key: event.logicalKey,
      alt: keyboard.isAltPressed,
      ctrl: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      meta: keyboard.isMetaPressed,
    );
    return consumed ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  /// Opens the in-app new-save dialog, then reopens the created save through
  /// [AppShell.onOpenPath].
  ///
  /// The session is read only to pre-fill the destination folder; the shell
  /// writes no save bytes and sends the result back through the app's single
  /// open path. A missing [SaveSessionCubit] provider is not an error: the
  /// dialog simply opens with an empty destination field.
  Future<void> _showNewSave() async {
    String? root;
    try {
      root = context.read<SaveSessionCubit>().openProject?.rootPath;
    } on ProviderNotFoundException {
      root = null;
    }
    final outcome = await NewSaveDialog.show(
      context,
      schemaLoader: widget.newSaveSchemaLoader,
      persist: widget.newSavePersist,
      directoryPicker: widget.newSaveDirectoryPicker,
      initialRoot: root,
    );
    if (!mounted || outcome == null) {
      return;
    }
    final open = widget.onOpenPath;
    if (open != null) {
      // The root directly holds slot_00, the shape the save-root resolver
      // accepts, so the created save reopens through the normal open path.
      await open(outcome.rootDirectory);
    }
  }

  /// Keep cubit state in step with the LayoutBuilder threshold. Post-frame so
  /// the first paint already uses the correct rail width without emitting
  /// during build.
  void _maybeSyncViewport(double width) {
    final cubit = context.read<ShellCubit>();
    final collapsed = width < ShellCubit.navCollapseBreakpoint;
    if (collapsed == cubit.state.navCollapsed) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cubit.setViewportWidth(width);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: BlocBuilder<ShellCubit, ShellState>(
        builder: (context, state) {
          return Scaffold(
            body: Column(
              children: <Widget>[
                AppTitleBar(
                  interactive: state.windowChromeEnabled,
                  isDirty: state.isDirty,
                  saveName: state.saveName,
                  saveFolderProbe: widget.saveFolderProbe,
                  directoryLister: widget.directoryLister,
                  settingsStore: _settingsStore,
                  launcher: _launcher,
                  onOpenPath: widget.onOpenPath,
                  onHelp: () => unawaited(HelpSurface.show(context)),
                  onNewSave: () => unawaited(_showNewSave()),
                ),
                if (widget.unverifiedFieldCount > 0 && !_unverifiedDismissed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      BombFlowerSpacing.md,
                      BombFlowerSpacing.sm,
                      BombFlowerSpacing.md,
                      0,
                    ),
                    child: Banner(
                      key: const Key('open-unverified-banner'),
                      variant: BannerVariant.warning,
                      title:
                          'Opened with ${widget.unverifiedFieldCount} '
                          'unverified fields — those fields are read-only',
                      onDismiss: () =>
                          setState(() => _unverifiedDismissed = true),
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final autoCollapsed =
                          constraints.maxWidth <
                          ShellCubit.navCollapseBreakpoint;
                      final collapsed = autoCollapsed || state.navCollapsed;
                      _maybeSyncViewport(constraints.maxWidth);

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          SizedBox(
                            key: const Key('shell-nav-rail'),
                            width: collapsed
                                ? BombFlowerSpacing.navRailIconOnlyWidth
                                : BombFlowerSpacing.navRailWidth,
                            child: ShellNavRail(
                              activeTab: state.activeTab,
                              collapsed: collapsed,
                              onSelect: (tab) {
                                context.read<ShellCubit>().selectTab(tab);
                              },
                            ),
                          ),
                          Expanded(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: const CanopyTexturePainter(),
                                child: HelpScope(
                                  open: (helpContext) =>
                                      HelpSurface.show(helpContext),
                                  child: NewSaveScope(
                                    create: (_) => _showNewSave(),
                                    child: switch (widget.openFailure) {
                                      final notice? => _OpenFailureView(
                                        notice: notice,
                                        onRetry: widget.onRetryOpen,
                                        onOpenAnotherSave:
                                            widget.onOpenAnotherSave,
                                      ),
                                      null => _ShellTabContent(
                                        activeTab: state.activeTab,
                                        settingsStore: _settingsStore,
                                      ),
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                ShellStatusFooter(state: state),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OpenFailureView extends StatelessWidget {
  const _OpenFailureView({
    required this.notice,
    required this.onRetry,
    required this.onOpenAnotherSave,
  });

  final OpenFailureNotice notice;
  final VoidCallback? onRetry;
  final Future<void> Function(BuildContext context)? onOpenAnotherSave;

  @override
  Widget build(BuildContext context) {
    final path = notice.path;
    final details = notice.details;
    final openAnother = onOpenAnotherSave;
    return TabPageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ErrorState(
            key: const Key('open-failure-panel'),
            title: 'Could not open save',
            message: notice.message,
            details: details,
            onRetry: onRetry,
            retryLabel: 'Retry',
          ),
          const SizedBox(height: BombFlowerSpacing.xl),
          if (path != null) ...<Widget>[
            Text(
              'Folder attempted',
              style: BombFlowerTypography.label.copyWith(
                color: BombFlowerColors.boneMuted,
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.xs),
            Text(
              path,
              key: const Key('open-failure-path'),
              style: BombFlowerTypography.body.copyWith(
                color: BombFlowerColors.bone,
              ),
            ),
          ] else if (details != null)
            // No path to show, so the technical context stays visible instead
            // of hiding behind the details expander.
            Text(
              details,
              key: const Key('open-failure-details'),
              style: BombFlowerTypography.caption.copyWith(
                color: BombFlowerColors.boneMuted,
              ),
            ),
          const SizedBox(height: BombFlowerSpacing.xl),
          BrassButton(
            key: const Key('open-failure-open-another'),
            label: 'Open another save…',
            icon: Icons.folder_open,
            variant: BrassButtonVariant.secondary,
            onDark: true,
            onPressed: openAnother == null ? null : () => openAnother(context),
          ),
        ],
      ),
    );
  }
}

class _ShellTabContent extends StatefulWidget {
  const _ShellTabContent({
    required this.activeTab,
    required this.settingsStore,
  });

  final ShellTab activeTab;

  /// Shared with the title bar so an edit in Settings applies immediately.
  final SettingsStore settingsStore;

  @override
  State<_ShellTabContent> createState() => _ShellTabContentState();
}

/// Keeps every visited tab mounted and hides it with [Offstage].
///
/// The eleven pages are expensive to construct: each derives field views from
/// the open project and builds its tables from them. Building one lazily on
/// first visit and then keeping its element subtree alive means a revisit costs
/// a layout pass instead of a full rebuild, and per-tab state (search text,
/// page cursor, scroll offset) survives switching away.
///
/// Only the active page is on stage, so exactly one page is painted — the same
/// single-exposure result the previous `AnimatedSwitcher` achieved by dropping
/// the outgoing page. The incoming page still fades and settles in.
///
/// Offstage pages stay out of the focus tree and their tickers are muted, so a
/// hidden tab cannot steal focus or keep an animation running.
class _ShellTabContentState extends State<_ShellTabContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: BombFlowerMotion.tab,
    value: 1,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _transition,
    curve: BombFlowerMotion.standardCurve,
  );
  late final Animation<Offset> _settle = Tween<Offset>(
    begin: const Offset(0, 0.008),
    end: Offset.zero,
  ).animate(_curve);

  /// Tabs built so far, in navigation order so stacking is deterministic.
  final List<ShellTab> _mounted = <ShellTab>[];

  @override
  void initState() {
    super.initState();
    _mounted.add(widget.activeTab);
  }

  @override
  void didUpdateWidget(_ShellTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTab == widget.activeTab) {
      return;
    }
    if (!_mounted.contains(widget.activeTab)) {
      _mounted
        ..add(widget.activeTab)
        ..sort((a, b) => a.index.compareTo(b.index));
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _transition.value = 1;
    } else {
      _transition.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _transition.dispose();
    super.dispose();
  }

  Widget _pageFor(ShellTab tab) {
    return switch (tab) {
      ShellTab.overview => const OverviewTab(key: Key('tab-page-overview')),
      ShellTab.playerWorld => const PlayerWorldTab(
        key: Key('tab-page-playerWorld'),
      ),
      ShellTab.inventory => const InventoryTab(key: Key('tab-page-inventory')),
      ShellTab.equipment => const EquipmentTab(key: Key('tab-page-equipment')),
      ShellTab.resources => const ResourcesTab(key: Key('tab-page-resources')),
      ShellTab.progression => const ProgressionTab(
        key: Key('tab-page-progression'),
      ),
      ShellTab.dungeons => const DungeonsTab(key: Key('tab-page-dungeons')),
      ShellTab.collectibles => const CollectiblesTab(
        key: Key('tab-page-collectibles'),
      ),
      ShellTab.flags => const FlagsTab(key: Key('tab-page-flags')),
      ShellTab.advancedData => const AdvancedDataTab(
        key: Key('tab-page-advancedData'),
      ),
      ShellTab.settings => SettingsTab(
        key: const Key('tab-page-settings'),
        store: widget.settingsStore,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pages = <Widget>[
      for (final tab in _mounted)
        Offstage(
          offstage: tab != widget.activeTab,
          child: ExcludeFocus(
            excluding: tab != widget.activeTab,
            child: _pageFor(tab),
          ),
        ),
    ];
    final stack = Stack(fit: StackFit.expand, children: pages);
    if (reduceMotion) {
      return stack;
    }
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: _settle, child: stack),
    );
  }
}
