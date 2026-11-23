import 'dart:typed_data';

import 'package:bomb_flower/domain/core/edit_command.dart';
import 'package:bomb_flower/domain/core/field_metadata.dart';
import 'package:bomb_flower/domain/core/field_value.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/presentation/shell/tabs/inventory_tab.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_scope.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_source.dart';
import 'package:bomb_flower/presentation/widgets/controls/rune_checkbox.dart';
import 'package:bomb_flower/presentation/widgets/selectors/searchable_select.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/tab_test_harness.dart';

/// An in-memory port that records every edit the tab emits.
final class _FakeSaveTabSource extends ChangeNotifier implements SaveTabSource {
  _FakeSaveTabSource({
    Map<EditorTabGroup, List<TabFieldView>> views =
        const <EditorTabGroup, List<TabFieldView>>{},
  }) : _views = Map<EditorTabGroup, List<TabFieldView>>.of(views);

  @override
  bool get isOpen => true;

  @override
  SaveSlotId? get activeSlot => null;

  @override
  bool get isDirty => false;

  @override
  int get changedFieldCount => 0;

  @override
  SaveSlotId? get newestSlot => null;

  @override
  bool get canUndo => false;

  @override
  bool get canRedo => false;

  final Map<EditorTabGroup, List<TabFieldView>> _views;

  /// Commands received through [edit], in order.
  final List<EditCommand> edits = <EditCommand>[];

  /// How many times [undo] was called.
  int undoCount = 0;

  /// How many times [redo] was called.
  int redoCount = 0;

  @override
  String? get rootPath => isOpen ? '/tmp/bomb-flower-save' : null;

  @override
  Uint8List? get activeSlotBytes => isOpen ? Uint8List(0) : null;

  @override
  Uint8List? bytesFor(SaveSlotId slot) =>
      isOpen && slot == activeSlot ? Uint8List(0) : null;

  @override
  Listenable get changes => this;

  @override
  List<SlotAge> get slotAges => const <SlotAge>[];

  @override
  List<TabFieldView> viewsFor(EditorTabGroup group) {
    return _views[group] ?? const <TabFieldView>[];
  }

  @override
  Iterable<TabFieldView> get allViews =>
      _views.values.expand((List<TabFieldView> views) => views);

  @override
  void edit(EditCommand command) => edits.add(command);

  @override
  void undo() => undoCount++;

  @override
  void redo() => redoCount++;
}

const Map<String, int> _bottleChoices = <String, int>{
  'Empty': 0,
  'Fairy': 1,
  'Potion_Red': 2,
  'Potion_Green': 3,
  'Potion_Blue': 4,
  'Milk': 5,
  'Potion_Yellow': 6,
  'Potion_Purple': 7,
  'Potion_Orange': 8,
  'Potion_Magenta': 9,
  'Ocarina_Time': 10,
  'Ocarina_Wind': 11,
  'Chateau_Romani': 12,
};

int _nextOffset = 0;

TabFieldView _boolView(
  String label, {
  required bool value,
  bool isDirty = false,
}) {
  return TabFieldView(
    descriptor: FieldDescriptor(
      FieldId(label),
      SaveSlotId.progress(0),
      label,
      FieldKind.boolean,
      ByteSpan(_nextOffset++, 1),
      FieldConfidence.verified,
      'schema:test (verified)',
    ),
    value: BoolValue(value),
    isDirty: isDirty,
  );
}

TabFieldView _enumView(String label, {required String key}) {
  return TabFieldView(
    descriptor: FieldDescriptor(
      FieldId(label),
      SaveSlotId.progress(0),
      label,
      FieldKind.enumeration,
      ByteSpan(_nextOffset++, 1),
      FieldConfidence.verified,
      'schema:test (verified)',
      choices: _bottleChoices,
    ),
    value: EnumValue(key: key, rawValue: _bottleChoices[key]),
    isDirty: false,
  );
}

TabFieldView _stockView(int value) {
  return TabFieldView(
    descriptor: FieldDescriptor(
      FieldId('PouchData.Item_Token_Gold.StockNum'),
      SaveSlotId.progress(0),
      'PouchData.Item_Token_Gold.StockNum',
      FieldKind.integer,
      ByteSpan(_nextOffset++, 4),
      FieldConfidence.inferred,
      'schema:test (inferred)',
    ),
    value: IntValue(value),
    isDirty: false,
  );
}

const String _bottleA = 'PlayerStatus.AssignableItem.BottleInfo.BottleA';

List<TabFieldView> _acquisitionViews() {
  return <TabFieldView>[
    _boolView('IsGet.Item_Arrow_Fire', value: true),
    _boolView('IsGet.Item_Bomb_Bag', value: false),
    _boolView('IsGet.Weapon_Sword', value: true, isDirty: true),
    _boolView('IsGet.Armor_Adult_Goron', value: false),
  ];
}

Map<EditorTabGroup, List<TabFieldView>> _populatedViews({
  bool includeStock = false,
}) {
  final views = <TabFieldView>[
    ..._acquisitionViews(),
    _enumView('$_bottleA.BottleItem', key: 'Empty'),
    _boolView('$_bottleA.IsValid', value: true),
    if (includeStock) _stockView(35),
  ];
  return <EditorTabGroup, List<TabFieldView>>{EditorTabGroup.inventory: views};
}

Future<_FakeSaveTabSource> _pumpInventory(
  WidgetTester tester, {
  Map<EditorTabGroup, List<TabFieldView>>? views,
  Size size = const Size(1100, 700),
}) async {
  final source = _FakeSaveTabSource(views: views ?? _populatedViews());
  addTearDown(source.dispose);
  await pumpTab(
    tester,
    SaveTabScope(source: source, child: const InventoryTab()),
    size: size,
  );
  return source;
}

Finder _row(String label) =>
    find.byKey(ValueKey<String>('inventory-acquisition-$label'));

void main() {
  testWidgets('renders acquisition flags, counts, and a bottle card', (
    tester,
  ) async {
    await _pumpInventory(tester);

    expect(find.text('Inventory'), findsWidgets);
    expect(find.text('IsGet.Item_Arrow_Fire'), findsWidgets);
    expect(find.text('4 of 4 acquisition flags'), findsOneWidget);
    expect(find.text('Bottle A'), findsOneWidget);
    expect(find.text('Bottle E'), findsOneWidget);
    expect(find.byKey(SearchableSelect.fieldKey), findsOneWidget);

    expectNoOverflow(tester);
  });

  testWidgets('one toggle emits exactly one SetScalar', (tester) async {
    final source = await _pumpInventory(tester);
    final row = _row('IsGet.Item_Bomb_Bag');
    await tester.ensureVisible(row);
    await tester.pump();

    await tester.tap(
      find.descendant(of: row, matching: find.byType(RuneCheckbox)),
    );
    await tester.pump();

    expect(source.edits, hasLength(1));
    expect(source.edits.single, SetScalar(FieldId('IsGet.Item_Bomb_Bag'), 1));
    expectNoOverflow(tester);
  });

  testWidgets('search narrows the list and updates the count text', (
    tester,
  ) async {
    await _pumpInventory(tester);
    final search = find.byKey(const Key('inventory-acquisition-search'));
    await tester.ensureVisible(search);
    await tester.pump();

    await tester.enterText(search, 'arrow');
    await tester.pump();

    expect(find.text('1 of 4 acquisition flags'), findsOneWidget);
    expect(_row('IsGet.Item_Arrow_Fire'), findsOneWidget);
    expect(_row('IsGet.Weapon_Sword'), findsNothing);

    await tester.enterText(search, 'no-such-flag');
    await tester.pump();

    expect(find.text('0 of 4 acquisition flags'), findsOneWidget);
    expect(
      find.text('No acquisition flags match "no-such-flag".'),
      findsOneWidget,
    );
    expectNoOverflow(tester);
  });

  testWidgets('bottle enumeration selection emits exactly one SetEnum', (
    tester,
  ) async {
    final source = await _pumpInventory(tester);
    final select = find.byKey(SearchableSelect.fieldKey);
    await tester.ensureVisible(select);
    await tester.pump();

    await tester.tap(select);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fairy'));
    await tester.pumpAndSettle();

    expect(source.edits, hasLength(1));
    expect(
      source.edits.single,
      SetEnum(FieldId('$_bottleA.BottleItem'), 'Fairy'),
    );
    expectNoOverflow(tester);
  });

  testWidgets('shows the stock and ammo caveat without fabricating a count', (
    tester,
  ) async {
    await _pumpInventory(tester);

    expect(find.text(InventoryTab.stockCaveat), findsOneWidget);
    expect(find.byKey(const Key('inventory-stock')), findsNothing);
    expect(find.byKey(const Key('inventory-stock-absent')), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('shows a named stock count read-only when the save stores it', (
    tester,
  ) async {
    final source = await _pumpInventory(
      tester,
      views: _populatedViews(includeStock: true),
    );

    await tester.ensureVisible(find.byKey(const Key('inventory-stock')));
    await tester.pump();

    expect(find.byKey(const Key('inventory-stock')), findsOneWidget);
    expect(find.textContaining(': 35'), findsOneWidget);
    expect(find.byKey(const Key('inventory-stock-absent')), findsNothing);
    expect(source.edits, isEmpty);
    expectNoOverflow(tester);
  });

  testWidgets('an absent bottle shows Not stored in this save', (tester) async {
    await _pumpInventory(tester);

    final bottleB = find.byKey(const Key('inventory-bottle-B'));
    await tester.ensureVisible(bottleB);
    await tester.pump();

    expect(
      find.descendant(
        of: bottleB,
        matching: find.text('Not stored in this save'),
      ),
      findsOneWidget,
    );
    expectNoOverflow(tester);
  });

  testWidgets('an unmapped source shows an explicit state instead of a grid', (
    tester,
  ) async {
    await _pumpInventory(
      tester,
      views: const <EditorTabGroup, List<TabFieldView>>{},
    );

    expect(
      find.text('Inventory fields are not mapped by this source'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('inventory-acquired-grid')), findsNothing);
    expect(find.text(InventoryTab.stockCaveat), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('does not overflow at 1100 by 700', (tester) async {
    await _pumpInventory(tester, size: const Size(1100, 700));

    expectNoOverflow(tester);
    expect(
      find.byKey(const Key('inventory-acquisition-search')),
      findsOneWidget,
    );
  });
}
