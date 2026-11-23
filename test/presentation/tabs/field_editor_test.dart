import 'dart:typed_data';

import 'package:bomb_flower/domain/core/edit_command.dart';
import 'package:bomb_flower/domain/core/field_metadata.dart';
import 'package:bomb_flower/domain/core/field_value.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/presentation/tabs_support/field_editor.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_source.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_toggle.dart';
import 'package:bomb_flower/presentation/widgets/controls/numeric_field.dart';
import 'package:bomb_flower/presentation/widgets/data/provenance_badge.dart';
import 'package:bomb_flower/presentation/widgets/selectors/searchable_select.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/tab_test_harness.dart';

const String _source = 'progress.sav offset 0x1C (verified by layout research)';

/// An in-memory source that records commands and imports no `dart:io`.
final class _FakeSaveTabSource extends ChangeNotifier implements SaveTabSource {
  /// Commands received through [edit], in order.
  final List<EditCommand> edits = <EditCommand>[];

  @override
  bool get isOpen => true;

  @override
  String? get rootPath => null;

  @override
  SaveSlotId? get activeSlot => null;

  @override
  Uint8List? get activeSlotBytes => null;

  @override
  Uint8List? bytesFor(SaveSlotId slot) => null;

  @override
  Listenable get changes => this;

  @override
  List<TabFieldView> viewsFor(EditorTabGroup group) {
    return const <TabFieldView>[];
  }

  @override
  Iterable<TabFieldView> get allViews => const <TabFieldView>[];

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

  @override
  void edit(EditCommand command) => edits.add(command);

  @override
  void undo() {}

  @override
  void redo() {}
}

FieldDescriptor _descriptor({
  FieldKind kind = FieldKind.integer,
  ByteSpan span = const ByteSpan(0, 4),
  FieldConfidence confidence = FieldConfidence.verified,
  num? min,
  num? max,
  Map<String, int> choices = const <String, int>{},
  bool readOnly = false,
  Endian endianness = Endian.big,
}) {
  return FieldDescriptor(
    const FieldId('test.field'),
    SaveSlotId.account,
    'Test field',
    kind,
    span,
    confidence,
    _source,
    endianness: endianness,
    min: min,
    max: max,
    choices: choices,
    readOnly: readOnly,
  );
}

TabFieldView _view(
  FieldDescriptor descriptor,
  FieldValue? value, {
  bool isDirty = false,
  String? issueMessage,
}) {
  return TabFieldView(
    descriptor: descriptor,
    value: value,
    isDirty: isDirty,
    issueMessage: issueMessage,
  );
}

Future<_FakeSaveTabSource> _pumpEditor(
  WidgetTester tester,
  TabFieldView view, {
  Size size = const Size(1100, 700),
}) async {
  final fake = _FakeSaveTabSource();
  addTearDown(fake.dispose);
  await pumpTab(
    tester,
    Center(
      child: SizedBox(
        width: 420,
        child: FieldEditor(view: view, source: fake),
      ),
    ),
    size: size,
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _commitText(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  test('formatFieldValue renders every decoded value honestly', () {
    expect(formatFieldValue(null), 'No decoded value');
    expect(formatFieldValue(const IntValue(42)), '42');
    expect(
      formatFieldValue(const EnumValue(key: 'sword', rawValue: 0)),
      'sword',
    );
    expect(
      formatFieldValue(const EnumValue(key: '', rawValue: 7)),
      'Unknown value 7',
    );
    expect(formatFieldValue(const BoolValue(true)), 'On');
    expect(formatFieldValue(const BoolValue(false)), 'Off');
    expect(formatFieldValue(const BitfieldValue(0x1f)), '0x1f');
    expect(formatFieldValue(const StringValue('Iron Sword')), 'Iron Sword');
    expect(
      formatFieldValue(const PositionValue(x: 1, y: 2.5, z: -3.25)),
      '(1.00, 2.50, -3.25)',
    );
    expect(
      formatFieldValue(VectorValue(<double>[1, 2.5, -3.25])),
      '(1, 2.5, -3.25)',
    );
    expect(
      formatFieldValue(
        ListValue(<FieldValue>[const IntValue(1), const StringValue('x')]),
      ),
      '[1, x]',
    );
    expect(formatFieldValue(ListValue(const <FieldValue>[])), '[]');
  });

  testWidgets('integer field emits exactly one SetScalar', (tester) async {
    final fake = await _pumpEditor(
      tester,
      _view(_descriptor(min: 0, max: 100), const IntValue(5)),
    );

    await _commitText(tester, find.byKey(NumericField.fieldKey), '42');

    expect(fake.edits.length, 1);
    final SetScalar command = fake.edits.single as SetScalar;
    expect(command.field, const FieldId('test.field'));
    expect(command.value, 42);
  });

  testWidgets('invalid integer text emits nothing', (tester) async {
    final fake = await _pumpEditor(
      tester,
      _view(_descriptor(min: 0, max: 100), const IntValue(5)),
    );

    await _commitText(tester, find.byKey(NumericField.fieldKey), '2.5');

    expect(fake.edits, isEmpty);
    expect(find.text('Enter a whole number.'), findsOneWidget);
  });

  testWidgets('out-of-range integer emits nothing', (tester) async {
    final fake = await _pumpEditor(
      tester,
      _view(_descriptor(min: 0, max: 100), const IntValue(5)),
    );

    await _commitText(tester, find.byKey(NumericField.fieldKey), '101');

    expect(fake.edits, isEmpty);
    expect(find.text('Must be at most 100.'), findsOneWidget);
  });

  testWidgets('boolean toggle emits one SetScalar', (tester) async {
    final fake = await _pumpEditor(
      tester,
      _view(_descriptor(kind: FieldKind.boolean), const BoolValue(false)),
    );

    await tester.tap(find.byKey(BrassToggle.controlKey));
    await tester.pumpAndSettle();

    expect(fake.edits.length, 1);
    final SetScalar command = fake.edits.single as SetScalar;
    expect(command.field, const FieldId('test.field'));
    expect(command.value, 1);
  });

  testWidgets('enumeration select emits one SetEnum', (tester) async {
    final fake = await _pumpEditor(
      tester,
      _view(
        _descriptor(
          kind: FieldKind.enumeration,
          choices: const <String, int>{'sword': 0, 'shield': 1, 'tunic': 2},
        ),
        const EnumValue(key: 'sword', rawValue: 0),
      ),
    );

    await tester.tap(find.byKey(SearchableSelect.fieldKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tunic'));
    await tester.pumpAndSettle();

    expect(fake.edits.length, 1);
    final SetEnum command = fake.edits.single as SetEnum;
    expect(command.field, const FieldId('test.field'));
    expect(command.key, 'tunic');
  });

  testWidgets('string commit emits one SetBytes with NUL padding', (
    tester,
  ) async {
    const span = ByteSpan(0x20, 8);
    final fake = await _pumpEditor(
      tester,
      _view(
        _descriptor(kind: FieldKind.string, span: span),
        const StringValue('Sword'),
      ),
    );

    await _commitText(tester, find.byKey(FieldEditor.stringFieldKey), 'Iron');

    expect(fake.edits.length, 1);
    final SetBytes command = fake.edits.single as SetBytes;
    expect(command.field, const FieldId('test.field'));
    expect(command.target, span);
    expect(
      command.bytes,
      orderedEquals(<int>[0x49, 0x72, 0x6f, 0x6e, 0, 0, 0, 0]),
    );
  });

  testWidgets('non-ASCII string emits nothing', (tester) async {
    final fake = await _pumpEditor(
      tester,
      _view(
        _descriptor(kind: FieldKind.string, span: const ByteSpan(0x20, 8)),
        const StringValue('Sword'),
      ),
    );

    await _commitText(tester, find.byKey(FieldEditor.stringFieldKey), 'Café');

    expect(fake.edits, isEmpty);
    expect(find.text('Use printable ASCII characters only.'), findsOneWidget);
  });

  testWidgets('overlong string emits nothing', (tester) async {
    final fake = await _pumpEditor(
      tester,
      _view(
        _descriptor(kind: FieldKind.string, span: const ByteSpan(0x20, 8)),
        const StringValue('Sword'),
      ),
    );

    await _commitText(
      tester,
      find.byKey(FieldEditor.stringFieldKey),
      'ABCDEFGH',
    );

    expect(fake.edits, isEmpty);
    expect(find.text('Text must be at most 7 characters.'), findsOneWidget);
  });

  testWidgets('vector commit emits one 12-byte SetBytes', (tester) async {
    const span = ByteSpan(0x30, 12);
    final fake = await _pumpEditor(
      tester,
      _view(
        _descriptor(kind: FieldKind.position, span: span),
        const PositionValue(x: 1, y: 2, z: 3),
      ),
    );

    await _commitText(
      tester,
      find.descendant(
        of: find.byKey(FieldEditor.vectorComponentKeys[0]),
        matching: find.byType(TextField),
      ),
      '4',
    );

    expect(fake.edits.length, 1);
    final SetBytes command = fake.edits.single as SetBytes;
    expect(command.field, const FieldId('test.field'));
    expect(command.target, span);
    expect(command.bytes.length, 12);
    final data = ByteData.sublistView(command.bytes);
    expect(data.getFloat32(0, Endian.little), 4);
    expect(data.getFloat32(4, Endian.little), 2);
    expect(data.getFloat32(8, Endian.little), 3);
  });

  testWidgets('read-only field renders disabled and emits nothing', (
    tester,
  ) async {
    final fake = await _pumpEditor(
      tester,
      _view(_descriptor(readOnly: true), const IntValue(7)),
    );

    expect(find.byType(NumericField), findsNothing);
    expect(find.byKey(FieldEditor.disabledValueKey), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Read-only field'), findsOneWidget);
    expect(fake.edits, isEmpty);
  });

  testWidgets('provenance badge shows the source citation as a tooltip', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      _view(_descriptor(min: 0, max: 100), const IntValue(5)),
    );

    final Tooltip tooltip = tester.widget<Tooltip>(
      find.descendant(
        of: find.byType(ProvenanceBadge),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, _source);
    final ProvenanceBadge badge = tester.widget<ProvenanceBadge>(
      find.byType(ProvenanceBadge),
    );
    expect(badge.level, ProvenanceLevel.verified);
    expect(badge.source, _source);
  });

  testWidgets('modified and invalid marks render', (tester) async {
    await _pumpEditor(
      tester,
      _view(
        _descriptor(min: 0, max: 100),
        const IntValue(5),
        isDirty: true,
        issueMessage: 'Must be between 1 and 99.',
      ),
    );

    expect(find.text('MODIFIED'), findsOneWidget);
    expect(find.text('INVALID'), findsOneWidget);
    expect(find.text('Must be between 1 and 99.'), findsOneWidget);
  });

  testWidgets('fits 1100x700 without overflow', (tester) async {
    await _pumpEditor(
      tester,
      _view(_descriptor(min: 0, max: 100), const IntValue(5)),
      size: const Size(1100, 700),
    );

    expectNoOverflow(tester);
  });
}
