import 'dart:typed_data';

import 'package:bomb_flower/domain/core/edit_command.dart';
import 'package:bomb_flower/domain/core/field_metadata.dart';
import 'package:bomb_flower/domain/core/field_value.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/presentation/shell/tabs/resources_tab.dart';
import 'package:bomb_flower/presentation/tabs_support/field_editor.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_scope.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_source.dart';
import 'package:bomb_flower/presentation/widgets/controls/numeric_field.dart';
import 'package:bomb_flower/presentation/widgets/data/stat_tile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/tab_test_harness.dart';

/// An in-memory port with the current byte accessors and an edit recorder.
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
  List<SlotAge> get slotAges => const <SlotAge>[];

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
  String? get rootPath => isOpen ? '/tmp/fake-save' : null;

  @override
  Uint8List? get activeSlotBytes => isOpen ? Uint8List(0) : null;

  @override
  Uint8List? bytesFor(SaveSlotId slot) =>
      isOpen && slot == activeSlot ? Uint8List(0) : null;

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
  void undo() => undoCount++;

  @override
  void redo() => redoCount++;
}

TabFieldView _view(
  String label,
  FieldValue value, {
  FieldKind? kind,
  ByteSpan span = const ByteSpan(0, 4),
  FieldConfidence confidence = FieldConfidence.verified,
  bool readOnly = false,
}) {
  return TabFieldView(
    descriptor: FieldDescriptor(
      FieldId(label),
      SaveSlotId.progress(0),
      label,
      kind ?? _kindFor(value),
      span,
      confidence,
      'schema:test',
      endianness: Endian.little,
      readOnly: readOnly,
    ),
    value: value,
    isDirty: false,
  );
}

FieldKind _kindFor(FieldValue value) {
  return switch (value) {
    BoolValue() => FieldKind.boolean,
    _ => FieldKind.integer,
  };
}

const List<String> _upgradeLabels = <String>[
  'IsGet.Item_FairyBless_DefenseDouble',
  'IsGet.Item_FairyBless_MP',
  'IsGet.Item_FairyBless_MPDouble',
  'GoronCity_GetBombBag_fromGoron006',
  'MiniGame_Diving_ShilverScale_First',
  'MiniGame_Fishing_GetGoldScale',
  'MiniGame_HitTarget_HrlCity_Get_BulletBag',
  'MiniGame_HitTarget_Kakariko_Get_Quiver',
  'MiniGame_HorseBackArchery_Get_Quiver',
  'Npc_Zora_002_Adult_GoldScale',
];

/// Realistic views: verified scalars and inferred booleans.
List<TabFieldView> _populatedViews({
  int life = 56,
  int maxLife = 80,
  int? mp = 24,
  int mpMax = 48,
  int rupees = 250,
  FieldConfidence upgradeConfidence = FieldConfidence.inferred,
}) {
  return <TabFieldView>[
    _view('PlayerStatus.Life', IntValue(life), span: const ByteSpan(0, 4)),
    _view(
      'PlayerStatus.MaxLife',
      IntValue(maxLife),
      span: const ByteSpan(4, 4),
    ),
    if (mp != null)
      _view('PlayerStatus.MP', IntValue(mp), span: const ByteSpan(8, 4)),
    _view('PlayerStatus.MPMax', IntValue(mpMax), span: const ByteSpan(12, 4)),
    _view(
      'PlayerStatus.CurrentRupee',
      IntValue(rupees),
      span: const ByteSpan(16, 4),
    ),
    for (var index = 0; index < _upgradeLabels.length; index++)
      _view(
        _upgradeLabels[index],
        BoolValue(index.isEven),
        span: ByteSpan(20 + index, 1),
        confidence: upgradeConfidence,
      ),
  ];
}

Future<void> _pumpResources(
  WidgetTester tester,
  _FakeSaveTabSource source, {
  Size size = const Size(1100, 700),
}) {
  addTearDown(source.dispose);
  return pumpTab(
    tester,
    SaveTabScope(source: source, child: const ResourcesTab()),
    size: size,
  );
}

NumericField _numericField(WidgetTester tester, Key key) {
  return tester.widget<NumericField>(
    find.descendant(of: find.byKey(key), matching: find.byType(NumericField)),
  );
}

Finder _numericInput(Key key) {
  return find.descendant(of: find.byKey(key), matching: find.byType(TextField));
}

void main() {
  testWidgets('populated health, magic, rupees, and upgrades render', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.resources: _populatedViews(),
      },
    );
    await _pumpResources(tester, source);

    expect(find.text('Resources'), findsOneWidget);
    expect(_numericField(tester, ResourcesTab.lifeFieldKey).value, 56);
    expect(_numericField(tester, ResourcesTab.maxLifeFieldKey).value, 80);
    expect(_numericField(tester, ResourcesTab.mpFieldKey).value, 24);
    expect(_numericField(tester, ResourcesTab.mpMaxFieldKey).value, 48);
    expect(_numericField(tester, ResourcesTab.rupeesFieldKey).value, 250);
    expect(find.text('14 hearts / 20 hearts'), findsOneWidget);
    expect(
      tester.widget<StatTile>(find.byKey(ResourcesTab.rupeesReadoutKey)).value,
      '250',
    );
    for (final label in _upgradeLabels) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Not stored in this save'), findsNothing);
    expect(find.byKey(ResourcesTab.healthErrorsKey), findsNothing);
    expect(find.byKey(ResourcesTab.healthWarningsKey), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('editing Life emits exactly one SetScalar', (tester) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.resources: _populatedViews(),
      },
    );
    await _pumpResources(tester, source);

    final input = _numericInput(ResourcesTab.lifeFieldKey);
    await tester.ensureVisible(input);
    await tester.pump();
    await tester.enterText(input, '40');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(source.edits, hasLength(1));
    final command = source.edits.single;
    expect(command, isA<SetScalar>());
    final written = command as SetScalar;
    expect(written.field, const FieldId('PlayerStatus.Life'));
    expect(written.value, 40);
    expect(source.undoCount, 0);
    expect(source.redoCount, 0);
  });

  testWidgets('Life above MaxLife shows the error banner', (tester) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.resources: _populatedViews(life: 100, maxLife: 80),
      },
    );
    await _pumpResources(tester, source);

    expect(find.byKey(ResourcesTab.healthErrorsKey), findsOneWidget);
    expect(find.textContaining('exceeds MaxLife'), findsWidgets);
    expect(find.byKey(ResourcesTab.healthWarningsKey), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('700 rupees shows the wallet-convention warning naming 500', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.resources: _populatedViews(rupees: 700),
      },
    );
    await _pumpResources(tester, source);

    expect(find.byKey(ResourcesTab.rupeesWarningKey), findsOneWidget);
    expect(find.textContaining('500'), findsWidgets);
    final caveat = tester.widget<Text>(
      find.byKey(ResourcesTab.rupeesCaveatKey),
    );
    expect(
      caveat.data,
      contains('Wallet capacity is not stored in this save.'),
    );
    expect(caveat.data, contains('500'));
    expectNoOverflow(tester);
  });

  testWidgets('missing MP shows Not stored in this save', (tester) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.resources: _populatedViews(mp: null),
      },
    );
    await _pumpResources(tester, source);

    expect(find.text('Not stored in this save'), findsOneWidget);
    expect(find.byKey(ResourcesTab.mpFieldKey), findsNothing);
    expect(find.byKey(ResourcesTab.mpMaxFieldKey), findsOneWidget);
  });

  testWidgets('ammo caveat is always visible and no ammo number renders', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.resources: _populatedViews(),
      },
    );
    await _pumpResources(tester, source);

    expect(find.byKey(ResourcesTab.ammoNoticeKey), findsOneWidget);
    expect(
      find.text('Ammo counts are not stored in this save.'),
      findsOneWidget,
    );
    // Only the five stored scalars have numeric editors; no ammo editor exists.
    expect(find.byType(NumericField), findsNWidgets(5));
    expect(find.text('Bombs'), findsNothing);
    expect(find.text('Arrows'), findsNothing);
    expect(find.text('Slingshot'), findsNothing);
  });

  testWidgets('an unverified upgrade field is disabled and emits nothing', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.resources: _populatedViews(
          upgradeConfidence: FieldConfidence.unverified,
        ),
      },
    );
    await _pumpResources(tester, source);

    expect(find.byKey(FieldEditor.disabledValueKey), findsWidgets);
    expect(find.text('unverified fields cannot be edited'), findsWidgets);

    final firstDisabled = find.byKey(FieldEditor.disabledValueKey).first;
    await tester.ensureVisible(firstDisabled);
    await tester.pumpAndSettle();
    await tester.tap(firstDisabled);
    await tester.pump();
    expect(source.edits, isEmpty);
  });

  testWidgets('falls back to allViews when the resources group is empty', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.overview: _populatedViews(),
      },
    );
    await _pumpResources(tester, source);

    expect(_numericField(tester, ResourcesTab.lifeFieldKey).value, 56);
    expect(find.text('Not stored in this save'), findsNothing);
  });

  testWidgets('resources tab fits 1100x700 without overflow', (tester) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.resources: _populatedViews(),
      },
    );
    await _pumpResources(tester, source, size: const Size(1100, 700));

    expect(find.text('Resources'), findsOneWidget);
    expectNoOverflow(tester);
  });
}
