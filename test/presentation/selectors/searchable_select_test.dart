import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/common/parchment_panel.dart';
import 'package:bomb_flower/presentation/widgets/selectors/searchable_select.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Option {
  const _Option(this.label, this.group, [this.subtitle]);

  final String label;
  final String group;
  final String? subtitle;
}

const _options = <_Option>[
  _Option('Kokiri Sword', 'Equipment', 'Starting sword'),
  _Option('Kokiri Shield', 'Equipment', 'Deku shield'),
  _Option('Master Sword', 'Equipment'),
  _Option('Deku Nut', 'Items'),
  _Option('Ocarina of Time', 'Items'),
];

class _Harness extends StatefulWidget {
  const _Harness({
    required this.items,
    this.initial,
    this.width = 460,
    this.autofocus = false,
    this.picked,
  });

  final List<_Option> items;
  final _Option? initial;
  final double width;
  final bool autofocus;
  final List<_Option>? picked;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late _Option? value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: SearchableSelect<_Option>(
        items: widget.items,
        itemLabel: (item) => item.label,
        itemSubtitle: (item) => item.subtitle,
        value: value,
        autofocus: widget.autofocus,
        label: 'Inventory item',
        groupBy: (item) => item.group,
        emptyMessage: 'No items in this category',
        onChanged: (item) {
          widget.picked?.add(item);
          setState(() => value = item);
        },
      ),
    );
  }
}

Future<void> pumpSelect(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1100, 800),
  TextScaler textScaler = TextScaler.noScaling,
  bool inPanel = false,
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
          child: inPanel
              ? ParchmentPanel(
                  child: Align(alignment: Alignment.topLeft, child: child),
                )
              : child,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> openSelect(WidgetTester tester) async {
  await tester.tap(find.byKey(SearchableSelect.fieldKey));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('renders the current value in a compact field', (tester) async {
    await pumpSelect(
      tester,
      _Harness(items: _options, initial: _options.first),
    );

    expect(find.text('Inventory item'), findsOneWidget);
    expect(find.text('Kokiri Sword'), findsOneWidget);
  });

  testWidgets('tap opens the panel with a result count and search box', (
    tester,
  ) async {
    await pumpSelect(tester, const _Harness(items: _options));
    await openSelect(tester);

    expect(find.byKey(SearchableSelect.panelKey), findsOneWidget);
    expect(find.byKey(SearchableSelect.searchFieldKey), findsOneWidget);
    expect(find.text('5 results'), findsOneWidget);
    expect(find.text('EQUIPMENT'), findsOneWidget);
    expect(find.text('ITEMS'), findsOneWidget);
  });

  testWidgets('typing kok filters to the Kokiri entries', (tester) async {
    await pumpSelect(tester, const _Harness(items: _options));
    await openSelect(tester);

    await tester.enterText(find.byKey(SearchableSelect.searchFieldKey), 'kok');
    await tester.pump();

    expect(find.text('2 results'), findsOneWidget);
    final panel = find.byKey(SearchableSelect.panelKey);
    expect(
      find.descendant(of: panel, matching: find.text('Kokiri Sword')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('Kokiri Shield')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('Master Sword')),
      findsNothing,
    );
  });

  testWidgets('diacritic-insensitive search finds Kókiri', (tester) async {
    const accented = <_Option>[_Option('Kókiri Tunic', 'Equipment')];
    await pumpSelect(tester, const _Harness(items: accented));
    await openSelect(tester);

    await tester.enterText(find.byKey(SearchableSelect.searchFieldKey), 'kok');
    await tester.pump();

    expect(find.text('1 result'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(SearchableSelect.panelKey),
        matching: find.text('Kókiri Tunic'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no-match state names the query and the empty message', (
    tester,
  ) async {
    await pumpSelect(tester, const _Harness(items: _options));
    await openSelect(tester);

    await tester.enterText(
      find.byKey(SearchableSelect.searchFieldKey),
      'ganon',
    );
    await tester.pump();

    expect(find.text('0 results'), findsOneWidget);
    expect(find.text('No matches for "ganon"'), findsOneWidget);
    expect(find.text('No items in this category'), findsOneWidget);
    expect(find.byKey(SearchableSelect.emptyKey), findsOneWidget);
  });

  testWidgets('Enter selects the highlighted option', (tester) async {
    final picked = <_Option>[];
    await pumpSelect(tester, _Harness(items: _options, picked: picked));
    await openSelect(tester);

    await tester.enterText(
      find.byKey(SearchableSelect.searchFieldKey),
      'shield',
    );
    await tester.pump();
    expect(find.text('1 result'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(picked.map((item) => item.label), <String>['Kokiri Shield']);
  });

  testWidgets('Arrow Down moves the highlight before Enter', (tester) async {
    final picked = <_Option>[];
    await pumpSelect(tester, _Harness(items: _options, picked: picked));
    await openSelect(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(picked.map((item) => item.label), <String>['Kokiri Shield']);
  });

  testWidgets('Escape closes without selecting', (tester) async {
    final picked = <_Option>[];
    await pumpSelect(tester, _Harness(items: _options, picked: picked));
    await openSelect(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(picked, isEmpty);
    expect(find.byKey(SearchableSelect.panelKey), findsNothing);
    expect(find.byKey(SearchableSelect.fieldKey), findsOneWidget);
  });

  testWidgets('tapping outside closes without selecting', (tester) async {
    final picked = <_Option>[];
    await pumpSelect(tester, _Harness(items: _options, picked: picked));
    await openSelect(tester);

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(picked, isEmpty);
    expect(find.byKey(SearchableSelect.panelKey), findsNothing);
  });

  testWidgets('the current value is checked in the list', (tester) async {
    await pumpSelect(
      tester,
      _Harness(items: _options, initial: _options.first),
    );
    await openSelect(tester);

    expect(
      find.descendant(
        of: find.byKey(SearchableSelect.panelKey),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets('keyboard Enter opens from the focused field', (tester) async {
    await pumpSelect(tester, const _Harness(items: _options, autofocus: true));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(SearchableSelect.panelKey), findsOneWidget);
  });

  testWidgets('works at 1100 px inside a parchment panel and caps at 360', (
    tester,
  ) async {
    final many = <_Option>[
      for (var index = 0; index < 24; index++)
        _Option('Catalogue entry $index', 'Catalogue'),
    ];
    await pumpSelect(tester, _Harness(items: many, width: 480), inPanel: true);
    await openSelect(tester);

    final panel = find.byKey(SearchableSelect.panelKey);
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, moreOrLessEquals(480, epsilon: 1));
    expect(tester.getSize(panel).height, lessThanOrEqualTo(360));
    expect(
      find.descendant(of: panel, matching: find.byType(ListView)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('long labels survive 1.3x text in a narrow panel', (
    tester,
  ) async {
    const long = <_Option>[
      _Option(
        'The Legend of the Hero of Time as recorded in the Kokiri village '
            'archive',
        'Lore',
      ),
    ];
    await pumpSelect(
      tester,
      _Harness(items: long, width: 320, initial: long.first),
      size: const Size(900, 800),
      textScaler: const TextScaler.linear(1.3),
    );
    await openSelect(tester);

    expect(tester.takeException(), isNull);
    expect(find.byKey(SearchableSelect.panelKey), findsOneWidget);
  });
}
