import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../bloc/shell/shell_cubit.dart';
import '../bloc/shell/shell_state.dart';
import '../bloc/shell/tab_definition.dart';
import '../theme/bomb_flower_spacing.dart';
import '../widgets/chrome/app_title_bar.dart';
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
import 'tabs/player_world_tab.dart';
import 'tabs/progression_tab.dart';
import 'tabs/resources_tab.dart';
import 'tabs/settings_tab.dart';

/// Application shell: 44 px title bar, 232/64 px navigation rail, scrollable
/// tab content capped at 1680 px, and a 28 px status footer.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Leave editing keys alone while a text field has focus. The shell has no
    // editable placeholder fields yet, but this is the permanent seam.
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }

    final keyboard = HardwareKeyboard.instance;
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
                                child: _ShellTabContent(
                                  activeTab: state.activeTab,
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

class _ShellTabContent extends StatelessWidget {
  const _ShellTabContent({required this.activeTab});

  final ShellTab activeTab;

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
      ShellTab.settings => const SettingsTab(key: Key('tab-page-settings')),
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
