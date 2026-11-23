import 'package:bomb_flower/app.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/bloc/shell/tab_definition.dart';
import 'package:bomb_flower/presentation/shell/tabs/inventory_tab.dart';
import 'package:bomb_flower/presentation/widgets/common/empty_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'chrome/app_title_bar_actions_test.dart' show buildCubit, disposeCubit;

/// The empty-state title every tab shows with no save open.
const String emptyTitle = 'Open a save to begin';

/// A stable text only the populated Overview renders.
const String overviewDataText =
    'Read-only dashboard. Editing lives in Resources and Player & World.';

void useWideView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1360, 880);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> pumpApp(WidgetTester tester, {SaveSessionCubit? session}) async {
  useWideView(tester);
  await tester.pumpWidget(
    BombFlowerApp(enableWindowChrome: false, session: session),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

Finder navTab(ShellTab tab) => find.byKey(Key('nav-tab-${tab.name}'));

/// Starts a switch and stops halfway through the 180 ms transition.
Future<void> pumpMidSwitch(WidgetTester tester, ShellTab tab) async {
  await tester.tap(navTab(tab));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 90));
}

/// Starts a switch and lets it settle.
Future<void> switchTo(WidgetTester tester, ShellTab tab) async {
  await pumpMidSwitch(tester, tab);
  await tester.pumpAndSettle();
}

/// The visible shape of an empty state: copy plus the laid-out ink.
typedef EmptyManifest = ({
  String title,
  String message,
  TextStyle? titleStyle,
  TextStyle? messageStyle,
  Rect titleRect,
  Rect messageRect,
});

EmptyManifest emptyManifest(WidgetTester tester) {
  final empty = tester.widget<EmptyState>(find.byType(EmptyState));
  final titleFinder = find.text(empty.title);
  final messageFinder = find.text(empty.message);
  return (
    title: empty.title,
    message: empty.message,
    titleStyle: tester.widget<Text>(titleFinder).style,
    messageStyle: tester.widget<Text>(messageFinder).style,
    titleRect: tester.getRect(titleFinder),
    messageRect: tester.getRect(messageFinder),
  );
}

void main() {
  testWidgets('a tab switch never renders two empty-state titles at once', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text(emptyTitle), findsOneWidget);

    await pumpMidSwitch(tester, ShellTab.inventory);

    // Mid-transition the incoming page is only halfway faded in. The outgoing
    // page must already be gone, or both transparent copies show through the
    // canopy and the glyphs double-expose at different heights.
    expect(find.text(emptyTitle), findsOneWidget);
    expect(find.byKey(const Key('tab-page-overview')), findsNothing);
    expect(find.byKey(const Key('tab-page-inventory')), findsOneWidget);
  });

  testWidgets('returning to a tab restores its empty-state manifest', (
    tester,
  ) async {
    await pumpApp(tester);
    final overviewFirst = emptyManifest(tester);

    await switchTo(tester, ShellTab.inventory);
    final inventoryFirst = emptyManifest(tester);
    expect(find.byKey(const Key('tab-page-inventory')), findsOneWidget);
    expect(find.byKey(const Key('tab-page-overview')), findsNothing);

    await switchTo(tester, ShellTab.overview);
    expect(emptyManifest(tester), overviewFirst);

    await switchTo(tester, ShellTab.inventory);
    expect(emptyManifest(tester), inventoryFirst);
  });

  testWidgets('a data tab is unchanged after switching away and back', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');

    await pumpApp(tester, session: harness.cubit);
    expect(find.text(overviewDataText), findsOneWidget);
    final overviewRect = tester.getRect(find.text(overviewDataText));
    final overviewStyle = tester
        .widget<Text>(find.text(overviewDataText))
        .style;

    await switchTo(tester, ShellTab.inventory);
    expect(find.text(InventoryTab.stockCaveat), findsOneWidget);
    final inventoryRect = tester.getRect(find.text(InventoryTab.stockCaveat));

    await switchTo(tester, ShellTab.overview);
    expect(find.text(overviewDataText), findsOneWidget);
    expect(tester.getRect(find.text(overviewDataText)), overviewRect);
    expect(
      tester.widget<Text>(find.text(overviewDataText)).style,
      overviewStyle,
    );

    await switchTo(tester, ShellTab.inventory);
    expect(find.text(InventoryTab.stockCaveat), findsOneWidget);
    expect(tester.getRect(find.text(InventoryTab.stockCaveat)), inventoryRect);
    expect(find.byKey(const Key('tab-page-inventory')), findsOneWidget);
    expect(find.byKey(const Key('tab-page-overview')), findsNothing);
  });
}
