import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/selectors/item_grid.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _items = <String>[
  for (var index = 0; index < 24; index++) 'Item ${index + 1}',
];

Future<void> pumpGrid(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1100, 800),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      builder: (context, appChild) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: appChild!,
        );
      },
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: child,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('lays out six by four 72 px slots', (tester) async {
    await pumpGrid(tester, ItemGrid<String>(items: _items));

    expect(find.byKey(ItemGrid.slotKey(0)), findsOneWidget);
    expect(find.byKey(ItemGrid.slotKey(23)), findsOneWidget);
    expect(find.byKey(ItemGrid.slotKey(24)), findsNothing);
    expect(tester.getSize(find.byKey(ItemGrid.slotKey(0))), const Size(72, 72));
    expect(find.text('Item 1'), findsOneWidget);
  });

  testWidgets('tapping a filled slot reports its index', (tester) async {
    final selected = <int>[];
    await pumpGrid(
      tester,
      ItemGrid<String>(items: _items, onSelected: selected.add),
    );

    await tester.tap(find.byKey(ItemGrid.slotKey(2)));
    await tester.pump();
    expect(selected, <int>[2]);
  });

  testWidgets('arrow keys move the roving selection by row and column', (
    tester,
  ) async {
    final selected = <int>[];
    await pumpGrid(
      tester,
      ItemGrid<String>(items: _items, onSelected: selected.add),
    );

    await tester.tap(find.byKey(ItemGrid.slotKey(0)));
    await tester.pump();
    expect(selected, <int>[0]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(selected.last, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(selected.last, 7);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(selected.last, 11);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(selected.last, 11, reason: 'right at the row end stays put');
  });

  testWidgets('Enter selects the highlighted slot', (tester) async {
    final selected = <int>[];
    await pumpGrid(
      tester,
      ItemGrid<String>(
        items: _items,
        selectedIndex: 4,
        autofocus: true,
        onSelected: selected.add,
      ),
    );

    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, <int>[4]);
  });

  testWidgets('modified and invalid corner marks are in the slot semantics', (
    tester,
  ) async {
    await pumpGrid(
      tester,
      ItemGrid<String>(
        items: _items,
        modifiedSlots: const <int>{0},
        invalidSlots: const <int>{1},
      ),
    );

    final modified = tester.getSemantics(
      find.bySemanticsLabel(RegExp('Slot 1, Item 1, modified')),
    );
    final invalid = tester.getSemantics(
      find.bySemanticsLabel(RegExp('Slot 2, Item 2, invalid')),
    );
    expect(modified.label, contains('modified'));
    expect(invalid.label, contains('invalid'));
    expect(
      find.descendant(
        of: find.byKey(ItemGrid.slotKey(0)),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );
  });

  testWidgets('empty slots are dashed, disabled, and named by position', (
    tester,
  ) async {
    await pumpGrid(tester, ItemGrid<String>(items: _items.take(2).toList()));

    final empty = tester.getSemantics(
      find.bySemanticsLabel('Slot 4, Empty slot'),
    );
    expect(empty.label, 'Slot 4, Empty slot');
    expect(empty, isSemantics(isEnabled: false));
    final tooltip = tester.widget<Tooltip>(
      find.descendant(
        of: find.byKey(ItemGrid.slotKey(3)),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, 'Empty slot');
  });

  testWidgets('selected slot shows a check mark as well as a tint', (
    tester,
  ) async {
    await pumpGrid(tester, ItemGrid<String>(items: _items, selectedIndex: 1));

    expect(
      find.descendant(
        of: find.byKey(ItemGrid.slotKey(1)),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets('long item labels survive 1.3x text in the slots', (
    tester,
  ) async {
    final long = <String>[
      for (var index = 0; index < 24; index++)
        'Extremely long catalogue item name number $index',
    ];
    await pumpGrid(
      tester,
      ItemGrid<String>(items: long),
      size: const Size(900, 800),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(ItemGrid.slotKey(23)), findsOneWidget);
  });
}
