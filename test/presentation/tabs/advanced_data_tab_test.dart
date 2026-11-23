import 'dart:typed_data';

import 'package:bomb_flower/domain/core/edit_command.dart';
import 'package:bomb_flower/domain/core/field_metadata.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/presentation/shell/tabs/advanced_data_tab.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_scope.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_source.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_toggle.dart';
import 'package:bomb_flower/presentation/widgets/hex/hex.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/tab_test_harness.dart';

/// Length of the fixture progress slot used by the save engine.
const int _bufferLength = 120572;

/// An in-memory source: no `dart:io`, no file access, and a defensive copy of
/// its bytes on every read.
final class _FakeSaveTabSource extends ChangeNotifier implements SaveTabSource {
  _FakeSaveTabSource({List<TabFieldView> views = const <TabFieldView>[]})
    : _views = List<TabFieldView>.unmodifiable(views),
      _bytes = Uint8List.fromList(
        List<int>.generate(_bufferLength, (int index) => index % 256),
      );

  final Uint8List _bytes;
  final List<TabFieldView> _views;

  /// Commands received through [edit], in order.
  final List<EditCommand> edits = <EditCommand>[];

  @override
  final bool isOpen = true;

  @override
  final bool isDirty = false;

  @override
  int get changedFieldCount => isDirty ? 1 : 0;

  @override
  String? get rootPath => '/tmp/fake-save';

  @override
  SaveSlotId? get activeSlot => SaveSlotId.account;

  @override
  SaveSlotId? get newestSlot => SaveSlotId.account;

  @override
  List<SlotAge> get slotAges => const <SlotAge>[];

  @override
  Uint8List? get activeSlotBytes => isOpen ? Uint8List.fromList(_bytes) : null;

  @override
  Uint8List? bytesFor(SaveSlotId slot) =>
      slot == SaveSlotId.account ? Uint8List.fromList(_bytes) : null;

  @override
  Listenable get changes => this;

  @override
  List<TabFieldView> viewsFor(EditorTabGroup group) =>
      group == EditorTabGroup.advanced ? _views : const <TabFieldView>[];

  @override
  Iterable<TabFieldView> get allViews => _views;

  @override
  bool canUndo = false;

  @override
  bool canRedo = false;

  @override
  void edit(EditCommand command) => edits.add(command);

  @override
  void undo() {}

  @override
  void redo() {}
}

TabFieldView _fieldView({
  required String id,
  required String label,
  required int offset,
  int length = 4,
  FieldKind kind = FieldKind.integer,
  bool isDirty = false,
  String? issueMessage,
}) {
  return TabFieldView(
    descriptor: FieldDescriptor(
      FieldId(id),
      SaveSlotId.account,
      label,
      kind,
      ByteSpan(offset, length),
      FieldConfidence.verified,
      'test fixture citation',
    ),
    value: null,
    isDirty: isDirty,
    issueMessage: issueMessage,
  );
}

/// The two editable verified fields the fake slot exposes.
const int _fieldAOffset = 100;
const int _fieldBOffset = 1000;

List<TabFieldView> _editableFields({
  bool fieldADirty = false,
  String? fieldBIssue,
}) {
  return <TabFieldView>[
    _fieldView(
      id: 'test.fieldA',
      label: 'Fixture A',
      offset: _fieldAOffset,
      isDirty: fieldADirty,
    ),
    _fieldView(
      id: 'test.fieldB',
      label: 'Fixture B',
      offset: _fieldBOffset,
      issueMessage: fieldBIssue,
    ),
  ];
}

Future<_FakeSaveTabSource> _pumpTab(
  WidgetTester tester, {
  List<TabFieldView>? views,
  HexEditorController? controller,
}) async {
  final fake = _FakeSaveTabSource(views: views ?? _editableFields());
  addTearDown(fake.dispose);
  await pumpTab(
    tester,
    SaveTabScope(
      source: fake,
      child: AdvancedDataTab(controller: controller),
    ),
  );
  return fake;
}

HexEditorController _liveController(WidgetTester tester) {
  return tester
      .widget<HexEditor>(find.byKey(AdvancedDataTab.editorKey))
      .controller;
}

void main() {
  testWidgets('renders the real 120,572-byte active slot buffer', (
    tester,
  ) async {
    await _pumpTab(tester);

    expect(find.byKey(AdvancedDataTab.unlockToggleKey), findsOneWidget);
    expect(find.byKey(AdvancedDataTab.restoreBannerKey), findsNothing);

    final lengthText = tester.widget<Text>(
      find.byKey(AdvancedDataTab.bufferLengthKey),
    );
    expect(lengthText.data, contains('120572'));

    final cell = find.byKey(HexEditor.cellKey(0));
    expect(cell, findsOneWidget);
    expect(
      find.descendant(of: cell, matching: find.text('00')),
      findsOneWidget,
    );

    expectNoOverflow(tester);
  });

  testWidgets('locked editing refuses writes with a StateError', (
    tester,
  ) async {
    await _pumpTab(tester);

    final toggle = tester.widget<BrassToggle>(
      find.byKey(AdvancedDataTab.unlockToggleKey),
    );
    expect(toggle.value, isFalse);

    final controller = _liveController(tester);
    expect(controller.readOnly, isTrue);
    expect(controller.editableRange, isNull);
    expect(() => controller.writeByte(_fieldAOffset, 1), throwsStateError);

    expectNoOverflow(tester);
  });

  testWidgets('unlocked editing emits exactly one SetBytes for the field', (
    tester,
  ) async {
    final fake = await _pumpTab(tester);

    await tester.tap(find.byKey(AdvancedDataTab.unlockToggleKey));
    await tester.pump();

    final controller = _liveController(tester);
    expect(controller.readOnly, isFalse);
    expect(controller.editableRange?.start, 0);
    expect(controller.editableRange?.end, _bufferLength);

    controller.writeByte(_fieldAOffset, 1);
    await tester.pump();

    expect(fake.edits, hasLength(1));
    final command = fake.edits.single;
    expect(command, isA<SetBytes>());
    final set = command as SetBytes;
    expect(set.field, const FieldId('test.fieldA'));
    expect(set.target, const ByteSpan(_fieldAOffset, 4));
    expect(set.bytes, hasLength(4));
    expect(set.bytes.first, 1);
    expect(controller.bytes[_fieldAOffset], 1);

    expectNoOverflow(tester);
  });

  testWidgets('an offset outside every field is restored and reported', (
    tester,
  ) async {
    final fake = await _pumpTab(tester);

    await tester.tap(find.byKey(AdvancedDataTab.unlockToggleKey));
    await tester.pump();
    final controller = _liveController(tester);

    controller.writeByte(5, 0xAB);
    await tester.pump();

    expect(controller.bytes[5], 5, reason: 'index 5 of the fixture is 0x05');
    expect(fake.edits, isEmpty);
    expect(find.byKey(AdvancedDataTab.restoreBannerKey), findsOneWidget);
    expect(
      find.textContaining('was not inside an editable named field'),
      findsOneWidget,
    );

    expectNoOverflow(tester);
  });

  testWidgets('a write past the buffer throws and the tab still renders', (
    tester,
  ) async {
    await _pumpTab(tester);

    await tester.tap(find.byKey(AdvancedDataTab.unlockToggleKey));
    await tester.pump();
    final controller = _liveController(tester);

    expect(
      () => controller.writeByte(_bufferLength, 0),
      throwsA(isA<RangeError>()),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(HexEditor.cellKey(0)), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('searching DE AD reports one match', (tester) async {
    final bytes = Uint8List(32);
    bytes[8] = 0xDE;
    bytes[9] = 0xAD;
    final controller = HexEditorController(bytes: bytes);
    addTearDown(controller.dispose);

    await _pumpTab(tester, controller: controller);

    await tester.enterText(find.byKey(HexEditor.searchFieldKey), 'DE AD');
    await tester.pump();

    expect(find.text('1 match'), findsOneWidget);

    expectNoOverflow(tester);
  });

  testWidgets('a dirty field paints a modified mark; an issue paints invalid', (
    tester,
  ) async {
    await _pumpTab(
      tester,
      views: _editableFields(fieldADirty: true, fieldBIssue: 'Fixture issue'),
    );

    final editor = tester.widget<HexEditor>(
      find.byKey(AdvancedDataTab.editorKey),
    );
    expect(editor.marks[_fieldAOffset], ByteMarkKind.modified);
    expect(editor.marks[_fieldBOffset], ByteMarkKind.invalid);

    final dirtyCell = tester.widget<HexByteCell>(
      find.byKey(HexEditor.cellKey(_fieldAOffset)),
    );
    expect(dirtyCell.mark, ByteMarkKind.modified);

    expect(find.text('Modified'), findsOneWidget);
    expect(find.text('Invalid'), findsOneWidget);

    expectNoOverflow(tester);
  });
}
