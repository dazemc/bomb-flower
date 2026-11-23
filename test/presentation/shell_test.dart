import 'package:bomb_flower/app.dart';
import 'package:bomb_flower/presentation/bloc/shell/shell_cubit.dart';
import 'package:bomb_flower/presentation/bloc/shell/tab_definition.dart';
import 'package:bomb_flower/presentation/shell/app_shell.dart';
import 'package:bomb_flower/presentation/shell/shell_status_footer.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_colors.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_spacing.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/chrome/app_title_bar.dart';
import 'package:bomb_flower/presentation/widgets/common/banner.dart'
    as common_banner;
import 'package:bomb_flower/presentation/widgets/common/brass_button.dart';
import 'package:bomb_flower/presentation/widgets/common/confirm_dialog.dart';
import 'package:bomb_flower/presentation/widgets/common/empty_state.dart';
import 'package:bomb_flower/presentation/widgets/common/error_state.dart';
import 'package:bomb_flower/presentation/widgets/common/loading_state.dart';
import 'package:bomb_flower/presentation/widgets/common/parchment_panel.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void _useView(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpApp(
  WidgetTester tester, {
  Size size = const Size(1360, 880),
}) async {
  _useView(tester, size);
  await tester.pumpWidget(const BombFlowerApp(enableWindowChrome: false));
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _sendShortcut(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

void main() {
  group('ShellCubit', () {
    test('switches tabs and cycles with wrap-around', () {
      final cubit = ShellCubit();
      addTearDown(cubit.close);

      expect(cubit.state.activeTab, ShellTab.overview);
      cubit.selectTab(ShellTab.inventory);
      expect(cubit.state.activeTab, ShellTab.inventory);

      cubit.cycleTab(1);
      expect(cubit.state.activeTab, ShellTab.equipment);
      cubit.cycleTab(-1);
      expect(cubit.state.activeTab, ShellTab.inventory);

      cubit.selectTab(ShellTab.settings);
      cubit.cycleTab(1);
      expect(cubit.state.activeTab, ShellTab.overview);
      cubit.cycleTab(-1);
      expect(cubit.state.activeTab, ShellTab.settings);
    });

    test('collapses the rail below the 1280 breakpoint', () {
      final cubit = ShellCubit();
      addTearDown(cubit.close);

      expect(cubit.state.navCollapsed, isFalse);
      cubit.setViewportWidth(1279.9);
      expect(cubit.state.navCollapsed, isTrue);
      cubit.setViewportWidth(1280);
      expect(cubit.state.navCollapsed, isFalse);
      cubit.setViewportWidth(1100);
      expect(cubit.state.navCollapsed, isTrue);
      cubit.setViewportWidth(2560);
      expect(cubit.state.navCollapsed, isFalse);
    });

    test('maps direct keyboard shortcuts without collisions', () {
      expect(
        shellTabForShortcut(key: LogicalKeyboardKey.digit1, alt: true),
        ShellTab.overview,
      );
      expect(
        shellTabForShortcut(key: LogicalKeyboardKey.digit3, alt: true),
        ShellTab.inventory,
      );
      expect(
        shellTabForShortcut(key: LogicalKeyboardKey.digit8, alt: true),
        ShellTab.collectibles,
      );
      expect(
        shellTabForShortcut(key: LogicalKeyboardKey.digit0, alt: true),
        ShellTab.flags,
      );
      expect(
        shellTabForShortcut(
          key: LogicalKeyboardKey.digit0,
          alt: true,
          shift: true,
        ),
        ShellTab.advancedData,
      );
      expect(
        shellTabForShortcut(key: LogicalKeyboardKey.comma, ctrl: true),
        ShellTab.settings,
      );
      expect(
        shellTabForShortcut(key: LogicalKeyboardKey.digit9, alt: true),
        isNull,
      );
      expect(
        shellTabForShortcut(key: LogicalKeyboardKey.digit3, ctrl: true),
        isNull,
      );
      expect(
        shellTabForShortcut(
          key: LogicalKeyboardKey.digit3,
          alt: true,
          meta: true,
        ),
        isNull,
      );
      expect(
        shellCycleDeltaForShortcut(key: LogicalKeyboardKey.tab, ctrl: true),
        1,
      );
      expect(
        shellCycleDeltaForShortcut(
          key: LogicalKeyboardKey.tab,
          ctrl: true,
          shift: true,
        ),
        -1,
      );
      expect(shellCycleDeltaForShortcut(key: LogicalKeyboardKey.tab), isNull);
    });

    test('handleShortcut consumes jumps and cycles', () {
      final cubit = ShellCubit();
      addTearDown(cubit.close);

      expect(
        cubit.handleShortcut(key: LogicalKeyboardKey.digit3, alt: true),
        isTrue,
      );
      expect(cubit.state.activeTab, ShellTab.inventory);

      expect(
        cubit.handleShortcut(key: LogicalKeyboardKey.digit0, alt: true),
        isTrue,
      );
      expect(cubit.state.activeTab, ShellTab.flags);

      expect(
        cubit.handleShortcut(key: LogicalKeyboardKey.comma, ctrl: true),
        isTrue,
      );
      expect(cubit.state.activeTab, ShellTab.settings);

      expect(
        cubit.handleShortcut(key: LogicalKeyboardKey.tab, ctrl: true),
        isTrue,
      );
      expect(cubit.state.activeTab, ShellTab.overview);

      expect(cubit.handleShortcut(key: LogicalKeyboardKey.keyA), isFalse);
    });

    test('tab definitions cover eleven unique tabs with shortcuts', () {
      expect(kTabDefinitions, hasLength(11));
      expect(
        kTabDefinitions.map((definition) => definition.tab),
        ShellTab.values,
      );
      expect(
        kTabDefinitions.map((definition) => definition.shortcutLabel).toSet(),
        hasLength(11),
      );
      for (final definition in kTabDefinitions) {
        expect(definition.title, isNotEmpty);
        expect(definition.purpose, isNotEmpty);
        expect(definition.shortcutLabel, isNotEmpty);
      }
    });
  });

  group('AppShell', () {
    testWidgets('renders title bar, eleven tabs, overview, and footer', (
      tester,
    ) async {
      await _pumpApp(tester);

      expect(find.byType(AppTitleBar), findsOneWidget);
      expect(tester.getSize(find.byType(AppTitleBar)).height, 44);
      expect(find.text('BOMB FLOWER'), findsOneWidget);
      expect(
        find.byKey(const Key('title-bar-dirty-indicator')),
        findsOneWidget,
      );

      expect(
        tester.getSize(find.byKey(const Key('shell-nav-rail'))).width,
        BombFlowerSpacing.navRailWidth,
      );
      for (final definition in kTabDefinitions) {
        expect(
          find.byKey(Key('nav-tab-${definition.tab.name}')),
          findsOneWidget,
          reason: '${definition.title} nav row must exist',
        );
      }

      expect(find.byKey(const Key('tab-page-overview')), findsOneWidget);
      // No save is open in the shell, so the real overview renders its
      // open-a-save empty state rather than the dashboard.
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Open a save to begin'), findsOneWidget);

      expect(find.byType(ShellStatusFooter), findsOneWidget);
      expect(tester.getSize(find.byType(ShellStatusFooter)).height, 28);
      expect(find.text('Validation: engine pending'), findsOneWidget);
      expect(find.textContaining('No save file open'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switches tab content when a nav row is tapped', (
      tester,
    ) async {
      await _pumpApp(tester);

      await tester.tap(find.byKey(const Key('nav-tab-inventory')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tab-page-inventory')), findsOneWidget);
      expect(find.byKey(const Key('tab-page-overview')), findsNothing);
      expect(find.text('Inventory'), findsWidgets);

      final cubit = BlocProvider.of<ShellCubit>(
        tester.element(find.byType(AppShell)),
      );
      expect(cubit.state.activeTab, ShellTab.inventory);
      expect(tester.takeException(), isNull);
    });

    testWidgets('collapses to 64 px below 1280 and restores at 1280', (
      tester,
    ) async {
      await _pumpApp(tester, size: const Size(1100, 700));

      expect(
        tester.getSize(find.byKey(const Key('shell-nav-rail'))).width,
        BombFlowerSpacing.navRailIconOnlyWidth,
      );
      expect(find.text('CHARACTER'), findsNothing);
      expect(find.text('Advanced Data'), findsNothing);
      expect(find.byKey(const Key('tab-page-overview')), findsOneWidget);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1280, 720);
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(const Key('shell-nav-rail'))).width,
        BombFlowerSpacing.navRailWidth,
      );
      expect(find.text('Advanced Data'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stays overflow-free at 1280x720 and caps content at 2560', (
      tester,
    ) async {
      await _pumpApp(tester, size: const Size(1280, 720));
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(2560, 1440);
      await tester.pumpAndSettle();

      // The overview's empty state has no parchment panel, so switch to a tab
      // that renders one (Settings is a placeholder tab) before measuring.
      await tester.tap(find.byKey(const Key('nav-tab-settings')));
      await tester.pumpAndSettle();

      final panel = tester.getSize(find.byType(ParchmentPanel).first);
      expect(panel.width, lessThanOrEqualTo(1680));
      expect(tester.takeException(), isNull);
    });

    testWidgets('title bar is inert with window chrome disabled', (
      tester,
    ) async {
      await _pumpApp(tester, size: const Size(1100, 700));

      expect(find.byType(AppTitleBar), findsOneWidget);
      expect(tester.getSize(find.byType(AppTitleBar)).height, 44);
      expect(find.byKey(const Key('title-bar-save-name')), findsOneWidget);

      for (final tooltip in <String>['Minimize', 'Maximize', 'Close']) {
        expect(find.byTooltip(tooltip), findsOneWidget);
        await tester.tap(find.byTooltip(tooltip));
        await tester.pump();
      }

      // Let the title bar's double-tap recognizer timer expire.
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('every tab renders its page and real content', (
      tester,
    ) async {
      await _pumpApp(tester);

      for (final definition in kTabDefinitions) {
        await tester.tap(find.byKey(Key('nav-tab-${definition.tab.name}')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(Key('tab-page-${definition.tab.name}')),
          findsOneWidget,
          reason: '${definition.title} page should be mounted',
        );
        // Save-backed tabs show the open-a-save empty state with no save open;
        // placeholder tabs still show their design purpose line.
        final rendersPurpose = find.text(definition.purpose).evaluate().isNotEmpty;
        final rendersEmpty =
            find.text('Open a save to begin').evaluate().isNotEmpty;
        expect(
          rendersPurpose || rendersEmpty,
          isTrue,
          reason:
              '${definition.title} should render either its purpose or the '
              'open-a-save empty state',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard shortcuts switch and cycle tabs', (tester) async {
      await _pumpApp(tester);
      expect(FocusManager.instance.primaryFocus, isNotNull);

      await _sendShortcut(
        tester,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.digit3,
      );
      expect(find.byKey(const Key('tab-page-inventory')), findsOneWidget);

      await _sendShortcut(
        tester,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.digit0,
      );
      expect(find.byKey(const Key('tab-page-flags')), findsOneWidget);

      await _sendShortcut(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.comma,
      );
      expect(find.byKey(const Key('tab-page-settings')), findsOneWidget);

      await _sendShortcut(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.tab,
      );
      expect(find.byKey(const Key('tab-page-overview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('common states', () {
    testWidgets('destructive confirm is explicit and returns a decision', (
      tester,
    ) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: BombFlowerThemeData.build(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return BrassButton(
                  label: 'Overwrite save',
                  variant: BrassButtonVariant.destructive,
                  onPressed: () async {
                    result = await ConfirmDialog.show(
                      context,
                      title: 'Overwrite save?',
                      message:
                          'This will replace the selected save with the '
                          'current draft.',
                      detail: 'This cannot be undone.',
                      destructive: true,
                      confirmLabel: 'Overwrite save',
                    );
                  },
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Overwrite save').first);
      await tester.pumpAndSettle();
      expect(find.text('Overwrite save?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      await tester.tap(find.text('Overwrite save').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overwrite save').last);
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty, error, loading, and banner render with semantics', (
      tester,
    ) async {
      var retries = 0;
      var dismissed = false;
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: BombFlowerThemeData.build(),
          home: Scaffold(
            backgroundColor: BombFlowerColors.parchment,
            body: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  EmptyState(
                    title: 'No save file open.',
                    message: 'Open a save to inspect its inventory.',
                    primaryAction: BrassButton(
                      label: 'Open save',
                      onPressed: () {},
                    ),
                  ),
                  ErrorState(
                    message: "Couldn't read Player/World.",
                    details: 'FormatException: fixture ended at byte 0x1F',
                    onRetry: () => retries++,
                  ),
                  const MediaQuery(
                    data: MediaQueryData(disableAnimations: true),
                    child: LoadingState(
                      label: 'Reading save…',
                      detail: 'No save file open',
                    ),
                  ),
                  common_banner.Banner(
                    title: 'Backup complete',
                    message: 'The previous save was copied.',
                    variant: common_banner.BannerVariant.success,
                    onDismiss: () => dismissed = true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('No save file open.'), findsOneWidget);
      expect(find.text("Couldn't read Player/World."), findsOneWidget);
      expect(find.text('Reading save…'), findsOneWidget);
      expect(find.text('Backup complete'), findsOneWidget);

      await tester.tap(find.text('Show details'));
      await tester.pump();
      expect(find.textContaining('FormatException'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retries, 1);

      await tester.ensureVisible(find.text('Backup complete'));
      await tester.pump();
      expect(find.bySemanticsLabel('Dismiss notification'), findsOneWidget);
      await tester.tap(find.byKey(const Key('banner-dismiss')));
      await tester.pump();
      expect(dismissed, isTrue);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  });
}
