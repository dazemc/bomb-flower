import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/domain/catalogue/actor_catalogue.dart';
import 'package:bomb_flower/domain/core/edit_command.dart';
import 'package:bomb_flower/domain/core/field_metadata.dart';
import 'package:bomb_flower/domain/core/field_value.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/presentation/shell/tabs/equipment_tab.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_scope.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_source.dart';
import 'package:bomb_flower/presentation/widgets/selectors/searchable_select.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/tab_test_harness.dart';

/// An in-memory source with byte accessors and an edit recorder.
final class _FakeSaveTabSource extends ChangeNotifier implements SaveTabSource {
  _FakeSaveTabSource({
    Map<EditorTabGroup, List<TabFieldView>> views =
        const <EditorTabGroup, List<TabFieldView>>{},
  }) : _views = Map<EditorTabGroup, List<TabFieldView>>.of(views);

  @override
  SaveSlotId? get activeSlot => null;

  @override
  String? get rootPath => '/tmp/fake-save';

  @override
  Uint8List? get activeSlotBytes => null;

  @override
  Uint8List? bytesFor(SaveSlotId slot) => null;

  @override
  bool get isOpen => true;

  @override
  bool get isDirty => false;

  @override
  int get changedFieldCount => 0;

  @override
  SaveSlotId? get newestSlot => null;

  @override
  List<SlotAge> get slotAges => const <SlotAge>[];

  final Map<EditorTabGroup, List<TabFieldView>> _views;

  /// Commands received through [edit], in order.
  final List<EditCommand> edits = <EditCommand>[];

  @override
  bool get canUndo => false;

  @override
  bool get canRedo => false;

  @override
  Listenable get changes => this;

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
  void undo() {}

  @override
  void redo() {}
}

late ActorCatalogue _catalogue;

TabFieldView _slotView(
  String label,
  String? stored, {
  int index = 0,
  FieldConfidence confidence = FieldConfidence.verified,
  bool readOnly = false,
}) {
  return TabFieldView(
    descriptor: FieldDescriptor(
      FieldId(label),
      SaveSlotId.progress(0),
      label,
      FieldKind.string,
      ByteSpan(index * 64, 64),
      confidence,
      'schema:gamedata_110 String64',
      readOnly: readOnly,
    ),
    value: stored == null ? null : StringValue(stored),
    isDirty: false,
  );
}

const List<String> _nineLabels = <String>[
  'PlayerStatus.AnotherEraEquipShield',
  'PlayerStatus.AnotherEraEquipWeapon',
  'PlayerStatus.EquipArmor',
  'PlayerStatus.EquipBoot',
  'PlayerStatus.EquipHandArmor',
  'PlayerStatus.EquipHeadArmor',
  'PlayerStatus.EquipOcarina',
  'PlayerStatus.EquipShield',
  'PlayerStatus.EquipWeapon',
];

List<TabFieldView> _nineSlots() {
  return <TabFieldView>[
    _slotView(_nineLabels[0], 'Weapon_Shield_Mirror', index: 0),
    _slotView(_nineLabels[1], 'Weapon_Sword_Master', index: 1),
    _slotView(_nineLabels[2], 'Armor_Adult_Zora', index: 2),
    _slotView(_nineLabels[3], 'Armor_Adult_HoverBoot', index: 3),
    _slotView(_nineLabels[4], 'Armor_Adult_Gauntlet_Silver', index: 4),
    _slotView(_nineLabels[5], 'Armor_Child_Mask_Zora', index: 5),
    _slotView(_nineLabels[6], 'Item_Ocarina_Time', index: 6),
    _slotView(_nineLabels[7], 'Weapon_Shield_Hylian', index: 7),
    _slotView(_nineLabels[8], 'Weapon_Sword_Kokiri', index: 8),
  ];
}

Finder _selectFinder() {
  return find.byWidgetPredicate((Widget widget) => widget is SearchableSelect);
}

Future<void> _pumpTab(WidgetTester tester, _FakeSaveTabSource source) {
  addTearDown(source.dispose);
  return pumpTab(
    tester,
    SaveTabScope(
      source: source,
      child: EquipmentTab(catalogue: _catalogue),
    ),
    size: const Size(1100, 700),
  );
}

void main() {
  setUpAll(() {
    _catalogue = loadActorCatalogue(
      File('assets/catalogue/actors.json').readAsStringSync(),
    );
  });

  testWidgets('renders the nine reported slots at 1100x700', (tester) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.equipment: _nineSlots(),
      },
    );
    await _pumpTab(tester, source);

    for (final label in _nineLabels) {
      expect(find.byKey(EquipmentTab.slotStoredKey(label)), findsOneWidget);
    }
    // The head-armor slot has no verified actor family, so it has no select.
    expect(_selectFinder(), findsNWidgets(8));
    expect(find.text('Weapon_Sword_Kokiri'), findsOneWidget);
    expect(
      find.text('No verified head-armor actor in the catalogue'),
      findsOneWidget,
    );
    expectNoOverflow(tester);
  });

  testWidgets('renders only the three slots the source reports', (
    tester,
  ) async {
    const reported = <String>{
      'PlayerStatus.EquipWeapon',
      'PlayerStatus.EquipShield',
      'PlayerStatus.EquipBoot',
    };
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.equipment: _nineSlots()
            .where(
              (TabFieldView view) => reported.contains(view.descriptor.label),
            )
            .toList(),
      },
    );
    await _pumpTab(tester, source);

    for (final label in reported) {
      expect(find.byKey(EquipmentTab.slotStoredKey(label)), findsOneWidget);
    }
    expect(
      find.byKey(EquipmentTab.slotStoredKey('PlayerStatus.EquipOcarina')),
      findsNothing,
    );
    expect(_selectFinder(), findsNWidgets(3));
    expectNoOverflow(tester);
  });

  testWidgets('selecting a sword emits one SetBytes starting Weapon_Sword_', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.equipment: _nineSlots(),
      },
    );
    await _pumpTab(tester, source);

    final select = find.byKey(
      EquipmentTab.slotSelectKey('PlayerStatus.EquipWeapon'),
    );
    await tester.ensureVisible(select);
    await tester.pumpAndSettle();
    await tester.tap(select);
    await tester.pumpAndSettle();
    expect(find.byKey(SearchableSelect.panelKey), findsOneWidget);

    await tester.enterText(
      find.byKey(SearchableSelect.searchFieldKey),
      'Master Sword',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Master Sword').last);
    await tester.pumpAndSettle();

    expect(source.edits, hasLength(1));
    final command = source.edits.single;
    expect(command, isA<SetBytes>());
    final write = command as SetBytes;
    expect(write.field, const FieldId('PlayerStatus.EquipWeapon'));
    expect(write.target, const ByteSpan(512, 64));
    expect(write.bytes, hasLength(64));
    const expected = 'Weapon_Sword_Master';
    expect(String.fromCharCodes(write.bytes.take(expected.length)), expected);
    expect(
      write.bytes.skip(expected.length).every((int byte) => byte == 0),
      isTrue,
    );
    expect(write.bytes.take(expected.length).first, isNot(0));
  });

  testWidgets('an invalid custom actor shows an error and emits nothing', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.equipment: _nineSlots(),
      },
    );
    await _pumpTab(tester, source);

    final input = find.byKey(
      EquipmentTab.customInputKey('PlayerStatus.EquipWeapon'),
    );
    await tester.ensureVisible(input);
    await tester.pumpAndSettle();
    await tester.enterText(input, 'Sword_Kokiri');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(source.edits, isEmpty);
    expect(
      find.textContaining('must start with "Weapon_Sword_"'),
      findsOneWidget,
    );
    expect(find.text('Sword_Kokiri'), findsOneWidget);
  });

  testWidgets('a valid custom actor emits exactly one SetBytes', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.equipment: _nineSlots(),
      },
    );
    await _pumpTab(tester, source);

    final input = find.byKey(
      EquipmentTab.customInputKey('PlayerStatus.EquipWeapon'),
    );
    await tester.ensureVisible(input);
    await tester.pumpAndSettle();
    await tester.enterText(input, 'Weapon_Sword_Biggoron');
    final apply = find.byKey(
      EquipmentTab.customApplyKey('PlayerStatus.EquipWeapon'),
    );
    await tester.tap(apply);
    await tester.pump();

    expect(source.edits, hasLength(1));
    final write = source.edits.single as SetBytes;
    expect(write.field, const FieldId('PlayerStatus.EquipWeapon'));
    const expected = 'Weapon_Sword_Biggoron';
    expect(String.fromCharCodes(write.bytes.take(expected.length)), expected);
    expect(
      write.bytes.skip(expected.length).every((int byte) => byte == 0),
      isTrue,
    );
  });

  testWidgets('an empty stored slot renders None', (tester) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.equipment: <TabFieldView>[
          _slotView('PlayerStatus.EquipWeapon', '', index: 0),
          _slotView('PlayerStatus.EquipShield', 'Weapon_Shield_Deku', index: 1),
          _slotView(
            'PlayerStatus.EquipBoot',
            'Armor_Adult_HeavyBoot',
            index: 2,
          ),
        ],
      },
    );
    await _pumpTab(tester, source);

    final stored = tester.widget<Text>(
      find.descendant(
        of: find.byKey(EquipmentTab.slotStoredKey('PlayerStatus.EquipWeapon')),
        matching: find.byType(Text),
      ),
    );
    expect(stored.data, 'None');
    expect(find.text('None (empty slot)'), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('head armor is read-only with no verified actor list', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.equipment: _nineSlots(),
      },
    );
    await _pumpTab(tester, source);

    expect(
      find.byKey(EquipmentTab.slotSelectKey('PlayerStatus.EquipHeadArmor')),
      findsNothing,
    );
    expect(
      find.byKey(EquipmentTab.customInputKey('PlayerStatus.EquipHeadArmor')),
      findsNothing,
    );
    expect(
      find.text('No verified head-armor actor in the catalogue'),
      findsOneWidget,
    );
    expect(find.text('Armor_Child_Mask_Zora'), findsOneWidget);
    expect(source.edits, isEmpty);
  });

  testWidgets('a save with no equipment slots says Not stored in this save', (
    tester,
  ) async {
    final source = _FakeSaveTabSource();
    await _pumpTab(tester, source);

    expect(find.byKey(EquipmentTab.slotsNotStoredKey), findsOneWidget);
    expect(find.text('Not stored in this save'), findsOneWidget);
    expect(_selectFinder(), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('a read-only descriptor disables the slot and emits nothing', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.equipment: <TabFieldView>[
          _slotView(
            'PlayerStatus.EquipWeapon',
            'Weapon_Sword_Kokiri',
            readOnly: true,
          ),
        ],
      },
    );
    await _pumpTab(tester, source);

    expect(
      find.byKey(EquipmentTab.slotSelectKey('PlayerStatus.EquipWeapon')),
      findsNothing,
    );
    expect(
      find.byKey(EquipmentTab.customInputKey('PlayerStatus.EquipWeapon')),
      findsNothing,
    );
    expect(find.text('Read-only field'), findsOneWidget);
    expect(source.edits, isEmpty);
  });
}
