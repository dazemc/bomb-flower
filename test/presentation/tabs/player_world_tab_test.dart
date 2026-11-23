import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bomb_flower/domain/core/edit_command.dart';
import 'package:bomb_flower/domain/core/field_metadata.dart';
import 'package:bomb_flower/domain/core/field_value.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/domain/world/world_catalogue.dart' as world;
import 'package:bomb_flower/presentation/shell/tabs/player_world_tab.dart';
import 'package:bomb_flower/presentation/tabs_support/field_editor.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_scope.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_source.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_toggle.dart';
import 'package:bomb_flower/presentation/widgets/controls/numeric_field.dart';
import 'package:bomb_flower/presentation/widgets/selectors/searchable_select.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/tab_test_harness.dart';

/// An in-memory port with the current byte accessors and an edit recorder.
final class _FakeSaveTabSource extends ChangeNotifier implements SaveTabSource {
  _FakeSaveTabSource({
    this.isOpen = true,
    this.activeSlot,
    this.isDirty = false,
    this.changedFieldCount = 0,
    List<SlotAge> slotAges = const <SlotAge>[],
    Map<EditorTabGroup, List<TabFieldView>> views =
        const <EditorTabGroup, List<TabFieldView>>{},
  }) : slotAges = List<SlotAge>.unmodifiable(slotAges),
       _views = Map<EditorTabGroup, List<TabFieldView>>.of(views);

  @override
  final bool isOpen;

  @override
  final SaveSlotId? activeSlot;

  @override
  final bool isDirty;

  @override
  final int changedFieldCount;

  @override
  SaveSlotId? get newestSlot => null;

  @override
  final List<SlotAge> slotAges;

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
  bool isDirty = false,
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
    isDirty: isDirty,
  );
}

FieldKind _kindFor(FieldValue value) {
  return switch (value) {
    BoolValue() => FieldKind.boolean,
    StringValue() => FieldKind.string,
    VectorValue() => FieldKind.vector,
    _ => FieldKind.integer,
  };
}

int _float32Bits(double value) {
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  return data.getUint32(0, Endian.little);
}

List<TabFieldView> _populatedViews({
  String scene = 'KokiriForest_Child',
  FieldConfidence dungeonConfidence = FieldConfidence.verified,
}) {
  return <TabFieldView>[
    _view(
      'Player_Pos_For_Map',
      VectorValue(<double>[100.5, -2.25, 12]),
      kind: FieldKind.vector,
      span: const ByteSpan(0, 12),
    ),
    _view(
      'Player_Rot_For_Map',
      IntValue(_float32Bits(math.pi / 2)),
      span: const ByteSpan(12, 4),
    ),
    _view(
      'Sequence_CurrentBanc',
      StringValue(scene),
      span: const ByteSpan(16, 64),
    ),
    _view(
      'DungeonRoom',
      const IntValue(3),
      confidence: dungeonConfidence,
      span: const ByteSpan(80, 4),
    ),
    _view(
      'Sequence_IsChildhood',
      const BoolValue(true),
      span: const ByteSpan(84, 1),
    ),
  ];
}

late world.WorldCatalogue _catalogue;

Future<void> _pumpTab(WidgetTester tester, _FakeSaveTabSource source) {
  addTearDown(source.dispose);
  return pumpTab(
    tester,
    SaveTabScope(
      source: source,
      child: PlayerWorldTab(catalogue: _catalogue),
    ),
    size: const Size(1100, 700),
  );
}

void main() {
  setUpAll(() {
    _catalogue = world.loadWorldCatalogue(
      File('assets/world/scenes.json').readAsStringSync(),
    );
  });

  testWidgets('populated player and world fields render with decoded values', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.playerWorld: _populatedViews(),
      },
    );
    await _pumpTab(tester, source);

    expect(find.text('Player/World'), findsOneWidget);
    expect(
      tester
          .widget<NumericField>(find.byKey(PlayerWorldTab.positionXKey))
          .value,
      100.5,
    );
    expect(
      tester
          .widget<NumericField>(find.byKey(PlayerWorldTab.positionYKey))
          .value,
      -2.25,
    );
    expect(
      tester
          .widget<NumericField>(find.byKey(PlayerWorldTab.positionZKey))
          .value,
      12,
    );
    expect(
      tester
          .widget<NumericField>(find.byKey(PlayerWorldTab.rotationFieldKey))
          .value,
      closeTo(90, 0.0001),
    );
    expect(find.byKey(PlayerWorldTab.rotationDegreesKey), findsOneWidget);
    expect(find.text('90.000°'), findsOneWidget);
    expect(find.text('Kokiri Forest'), findsOneWidget);
    expect(find.text('Stored key: KokiriForest_Child'), findsOneWidget);
    expect(find.text('DungeonRoom'), findsOneWidget);
    expect(find.byType(BrassToggle), findsOneWidget);
    expect(find.text('Not stored in this save'), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('selecting a map emits one SetBytes starting with its key', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.playerWorld: _populatedViews(),
      },
    );
    await _pumpTab(tester, source);

    await tester.ensureVisible(find.byKey(PlayerWorldTab.sceneSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SearchableSelect.fieldKey));
    await tester.pumpAndSettle();
    expect(find.byKey(SearchableSelect.panelKey), findsOneWidget);
    await tester.enterText(
      find.byKey(SearchableSelect.searchFieldKey),
      'Deku Tree',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inside the Deku Tree').last);
    await tester.pumpAndSettle();

    expect(source.edits, hasLength(1));
    final command = source.edits.single;
    expect(command, isA<SetBytes>());
    final write = command as SetBytes;
    expect(write.field, const FieldId('Sequence_CurrentBanc'));
    expect(write.target, const ByteSpan(16, 64));
    expect(write.bytes.length, 64);
    const key = 'InsideTheDekuTree';
    expect(String.fromCharCodes(write.bytes.take(key.length)), key);
    expect(write.bytes.skip(key.length).every((int byte) => byte == 0), isTrue);
  });

  testWidgets('rotation edit emits one SetScalar with the degrees float bits', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.playerWorld: <TabFieldView>[
          _view(
            'Player_Rot_For_Map',
            IntValue(_float32Bits(0)),
            span: const ByteSpan(12, 4),
          ),
        ],
      },
    );
    await _pumpTab(tester, source);

    final input = find.descendant(
      of: find.byKey(PlayerWorldTab.rotationFieldKey),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, '45');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(source.edits, hasLength(1));
    final command = source.edits.single;
    expect(command, isA<SetScalar>());
    final write = command as SetScalar;
    expect(write.field, const FieldId('Player_Rot_For_Map'));
    expect(write.value, _float32Bits(45 * math.pi / 180));
    expectNoOverflow(tester);
  });

  testWidgets('rotation outside a half turn shows a warning, not a clamp', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.playerWorld: <TabFieldView>[
          _view(
            'Player_Rot_For_Map',
            IntValue(_float32Bits(4)),
            span: const ByteSpan(12, 4),
          ),
        ],
      },
    );
    await _pumpTab(tester, source);

    expect(find.byKey(PlayerWorldTab.rotationWarningKey), findsOneWidget);
    expect(find.text('Rotation outside ±180°'), findsOneWidget);
    final field = tester.widget<NumericField>(
      find.byKey(PlayerWorldTab.rotationFieldKey),
    );
    expect(field.value, closeTo(4 * 180 / math.pi, 0.001));
  });

  testWidgets('missing scene shows Not stored in this save', (tester) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.playerWorld: <TabFieldView>[
          for (final view in _populatedViews())
            if (view.descriptor.label != 'Sequence_CurrentBanc') view,
        ],
      },
    );
    await _pumpTab(tester, source);

    expect(find.text('Not stored in this save'), findsOneWidget);
    expect(find.byKey(PlayerWorldTab.sceneSelectKey), findsNothing);
  });

  testWidgets('an unverified field is disabled and emits nothing', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.playerWorld: _populatedViews(
          dungeonConfidence: FieldConfidence.unverified,
        ),
      },
    );
    await _pumpTab(tester, source);

    expect(find.byKey(FieldEditor.disabledValueKey), findsOneWidget);
    expect(find.text('unverified fields cannot be edited'), findsOneWidget);
    await tester.ensureVisible(find.byKey(FieldEditor.disabledValueKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FieldEditor.disabledValueKey));
    await tester.pump();
    expect(source.edits, isEmpty);
  });

  testWidgets('falls back to allViews when the player/world group is empty', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.overview: _populatedViews(),
      },
    );
    await _pumpTab(tester, source);

    expect(find.byKey(PlayerWorldTab.positionXKey), findsOneWidget);
    expect(find.byKey(PlayerWorldTab.sceneSelectKey), findsOneWidget);
    expect(find.text('Not stored in this save'), findsNothing);
  });

  testWidgets('closed source shows the open-a-save empty state', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(isOpen: false);
    await _pumpTab(tester, source);

    expect(find.text('Open a save to begin'), findsOneWidget);
    expect(find.byKey(PlayerWorldTab.positionXKey), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('player and world tab fits 1100x700 without overflow', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      activeSlot: SaveSlotId.progress(0),
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.playerWorld: _populatedViews(),
      },
      isDirty: true,
      changedFieldCount: 2,
    );
    await _pumpTab(tester, source);

    expect(tester.view.physicalSize, const Size(1100, 700));
    expectNoOverflow(tester);
  });
}
