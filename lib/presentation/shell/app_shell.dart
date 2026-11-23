import 'dart:async';

import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/system/directory_lister.dart';
import '../../data/system/directory_picker.dart';
import '../../data/system/longshot_launcher.dart';
import '../bloc/shell/shell_cubit.dart';
import '../bloc/shell/shell_state.dart';
import '../bloc/shell/tab_definition.dart';
import '../theme/bomb_flower_colors.dart';
import '../theme/bomb_flower_spacing.dart';
import '../theme/bomb_flower_typography.dart';
import '../widgets/chrome/app_title_bar.dart';
import '../widgets/common/brass_button.dart';
import '../widgets/common/error_state.dart';
import '../widgets/common/procedural_painters.dart';
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
    this.saveFolderProbe,
    this.directoryLister,
    this.settingsStore,
    this.longshotLauncher,
  });

  /// A failed open to render instead of the tab content, or `null`.
  final OpenFailureNotice? openFailure;

  /// Retries the failed open. A null value disables the retry button.
  final VoidCallback? onRetryOpen;

  /// Shows the open-save dialog so the user can choose another folder.
  final Future<void> Function(BuildContext context)? onOpenAnotherSave;

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
                                child: switch (widget.openFailure) {
                                  final notice? => _OpenFailureView(
                                    notice: notice,
                                    onRetry: widget.onRetryOpen,
                                    onOpenAnotherSave: widget.onOpenAnotherSave,
                                  ),
                                  null => _ShellTabContent(
                                    activeTab: state.activeTab,
                                    settingsStore: _settingsStore,
                                  ),
                                },
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

class _ShellTabContent extends StatelessWidget {
  const _ShellTabContent({
    required this.activeTab,
    required this.settingsStore,
  });

  final ShellTab activeTab;

  /// Shared with the title bar so an edit in Settings applies immediately.
  final SettingsStore settingsStore;

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
        store: settingsStore,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : BombFlowerMotion.tab,
      switchInCurve: BombFlowerMotion.standardCurve,
      switchOutCurve: BombFlowerMotion.standardCurve,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (child, animation) {
        if (reduceMotion) return child;
        final settle = Tween<Offset>(
          begin: const Offset(0, 0.008),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: settle, child: child),
        );
      },
      child: _pageFor(activeTab),
    );
  }
}
