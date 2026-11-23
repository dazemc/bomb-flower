import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/data/stone_table.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Row {
  const _Row(this.name, this.level, this.area);

  final String name;
  final int level;
  final String area;
}

const _rows = <_Row>[
  _Row('Kokiri Forest', 1, 'Forest'),
  _Row('Deku Tree', 3, 'Dungeon'),
  _Row('Hyrule Field', 5, 'Field'),
];

final _columns = <StoneTableColumn<_Row>>[
  StoneTableColumn<_Row>(label: 'Area', cell: (row) => row.name, flex: 2),
  StoneTableColumn<_Row>(
    label: 'Level',
    cell: (row) => row.level.toString(),
    width: 90,
    sortable: true,
  ),
  StoneTableColumn<_Row>(
    label: 'Kind',
    cell: (row) => row.area,
    flex: 1,
    sortable: true,
  ),
];

Future<void> pumpTable(
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
  testWidgets('renders headers, rows, and 36 px row heights', (tester) async {
    await pumpTable(tester, StoneTable<_Row>(columns: _columns, rows: _rows));

    expect(find.text('Area'), findsOneWidget);
    expect(find.text('Level'), findsOneWidget);
    expect(find.text('Kokiri Forest'), findsOneWidget);
    expect(find.text('Hyrule Field'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(StoneTable.rowKey(0))).height,
      moreOrLessEquals(36, epsilon: 0.5),
    );
  });

  testWidgets('tapping a row reports the typed row and index', (tester) async {
    final tapped = <(_Row, int)>[];
    await pumpTable(
      tester,
      StoneTable<_Row>(
        columns: _columns,
        rows: _rows,
        onRowTap: (row, index) => tapped.add((row, index)),
      ),
    );

    await tester.tap(find.byKey(StoneTable.rowKey(1)));
    await tester.pump();
    expect(tapped, <(_Row, int)>[(_rows[1], 1)]);
  });

  testWidgets('sortable headers toggle direction and report each tap', (
    tester,
  ) async {
    final sorts = <(int, bool)>[];
    await pumpTable(
      tester,
      StoneTable<_Row>(
        columns: _columns,
        rows: _rows,
        onSort: (index, ascending) => sorts.add((index, ascending)),
      ),
    );

    await tester.tap(find.byKey(StoneTable.headerKey(1)));
    await tester.pump();
    expect(sorts, <(int, bool)>[(1, true)]);
    expect(
      find.descendant(
        of: find.byKey(StoneTable.headerKey(1)),
        matching: find.byIcon(Icons.arrow_upward),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(StoneTable.headerKey(1)));
    await tester.pump();
    expect(sorts, <(int, bool)>[(1, true), (1, false)]);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);

    await tester.tap(find.byKey(StoneTable.headerKey(0)));
    await tester.pump();
    expect(sorts.length, 2, reason: 'non-sortable header must not call onSort');
  });

  testWidgets('selected row shows a check mark and selected semantics', (
    tester,
  ) async {
    await pumpTable(
      tester,
      StoneTable<_Row>(
        key: const ValueKey<String>('table'),
        columns: _columns,
        rows: _rows,
        selectedIndex: 1,
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(StoneTable.rowKey(1)),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.byKey(StoneTable.rowKey(1))).label,
      contains('Selected'),
    );
  });

  testWidgets('arrow navigation and Enter select by keyboard', (tester) async {
    final tapped = <int>[];
    await pumpTable(
      tester,
      StoneTable<_Row>(
        columns: _columns,
        rows: _rows,
        autofocus: true,
        onRowTap: (_, index) => tapped.add(index),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tapped, <int>[1]);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(tapped, <int>[1, 2]);
  });

  testWidgets('sortable headers are Tab stops and Enter sorts them', (
    tester,
  ) async {
    final sorts = <(int, bool)>[];
    await pumpTable(
      tester,
      StoneTable<_Row>(
        columns: _columns,
        rows: _rows,
        autofocus: true,
        onSort: (index, ascending) => sorts.add((index, ascending)),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sorts, isNotEmpty);
  });

  testWidgets('empty rows show the message under the header', (tester) async {
    await pumpTable(
      tester,
      StoneTable<_Row>(
        columns: _columns,
        rows: const <_Row>[],
        emptyMessage: 'No areas match this filter',
      ),
    );

    expect(find.text('Area'), findsOneWidget);
    expect(find.text('No areas match this filter'), findsOneWidget);
    expect(find.byKey(StoneTable.rowKey(0)), findsNothing);
  });

  testWidgets('under 900 px the table keeps a 900 px content and scrolls', (
    tester,
  ) async {
    await pumpTable(
      tester,
      StoneTable<_Row>(columns: _columns, rows: _rows),
      size: const Size(800, 800),
    );

    final scroll = find.byKey(StoneTable.horizontalScrollKey);
    expect(scroll, findsOneWidget);
    final scrollable = find
        .descendant(of: scroll, matching: find.byType(Scrollable))
        .first;
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      greaterThan(0),
    );

    await tester.drag(scroll, const Offset(-200, 0));
    await tester.pump();
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(0),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 1100 px no horizontal scroll wrapper is needed', (
    tester,
  ) async {
    await pumpTable(tester, StoneTable<_Row>(columns: _columns, rows: _rows));

    expect(find.byKey(StoneTable.horizontalScrollKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long cell text wraps at 1.3x without overflow', (tester) async {
    final longRows = <_Row>[
      const _Row(
        'Kokiri Forest and the Lost Woods beyond the stepping stones',
        7,
        'A very long classification string',
      ),
    ];
    await pumpTable(
      tester,
      StoneTable<_Row>(columns: _columns, rows: longRows),
      size: const Size(1000, 800),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(StoneTable.rowKey(0)), findsOneWidget);
  });
}
