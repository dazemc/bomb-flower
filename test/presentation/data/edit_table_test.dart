import 'package:bomb_flower/domain/core/field_metadata.dart';
import 'package:bomb_flower/domain/core/field_value.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_source.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_colors.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_toggle.dart';
import 'package:bomb_flower/presentation/widgets/controls/numeric_field.dart';
import 'package:bomb_flower/presentation/widgets/data/edit_table.dart';
import 'package:bomb_flower/presentation/widgets/data/provenance_badge.dart';
import 'package:bomb_flower/presentation/widgets/selectors/searchable_select.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, TextInputAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../tabs/support/tab_test_harness.dart';

const String _source = 'progress.sav offset 0x1C (verified by layout research)';

EditTableRow _row(
  String id, {
  String? label,
  String type = 'Int',
  String value = '12',
  ProvenanceLevel level = ProvenanceLevel.verified,
  String source = _source,
  bool isModified = false,
  EditCellKind? kind = EditCellKind.integer,
  String? readOnlyReason,
  num? min,
  num? max,
  List<String> choices = const <String>[],
  int? textCap,
  String? issueMessage,
  int? intValue,
  bool? boolValue,
  String? enumKey,
  String? textValue,
}) {
  return EditTableRow(
    id: id,
    label: label ?? id,
    typeLabel: type,
    valueLabel: value,
    level: level,
    source: source,
    isModified: isModified,
    kind: kind,
    readOnlyReason: readOnlyReason,
    min: min,
    max: max,
    choices: choices,
    textCap: textCap,
    issueMessage: issueMessage,
    intValue: kind == EditCellKind.integer ? (intValue ?? 0) : null,
    boolValue: kind == EditCellKind.boolean ? (boolValue ?? false) : null,
    enumKey: kind == EditCellKind.enumeration ? (enumKey ?? '') : null,
    textValue: kind == EditCellKind.string ? (textValue ?? '') : null,
  );
}

List<EditTableRow> _manyRows(int count) {
  return <EditTableRow>[
    for (var index = 0; index < count; index++)
      _row(
        'field-$index',
        label: 'catalogue.field.$index',
        type: index.isEven ? 'Int' : 'Bool',
        value: '$index',
        isModified: index.isEven,
        kind: index.isEven ? EditCellKind.integer : EditCellKind.boolean,
        min: index.isEven ? 0 : null,
        max: index.isEven ? 1000 : null,
        intValue: index,
        boolValue: index.isEven,
      ),
  ];
}

List<EditTableRow> _integerRows(int count) {
  return <EditTableRow>[
    for (var index = 0; index < count; index++)
      _row(
        'field-$index',
        label: 'catalogue.field.$index',
        value: '$index',
        min: 0,
        max: 1000,
        intValue: index,
      ),
  ];
}

Widget _table(
  List<EditTableRow> rows, {
  void Function(String id, int value)? onInteger,
  void Function(String id, bool value)? onBoolean,
  void Function(String id, String key)? onEnumeration,
  void Function(String id, String text)? onText,
  String? errorMessage,
}) {
  return EditTable(
    rows: rows,
    onInteger: onInteger ?? (_, _) {},
    onBoolean: onBoolean ?? (_, _) {},
    onEnumeration: onEnumeration ?? (_, _) {},
    onText: onText ?? (_, _) {},
    errorMessage: errorMessage,
  );
}

FieldRef _ref(
  String name, {
  String type = 'Int',
  FieldProvenance provenance = FieldProvenance.verified,
  int hash = 0x31ab5580,
}) {
  return FieldRef(
    hash: hash,
    name: name,
    type: type,
    section: 1,
    defaultPreview: '0',
    provenance: provenance,
  );
}

TabFieldView _view(
  String label, {
  String? id,
  FieldKind kind = FieldKind.integer,
  FieldConfidence confidence = FieldConfidence.verified,
  FieldValue? value = const IntValue(7),
  bool readOnly = false,
  num? min,
  num? max,
  Map<String, int> choices = const <String, int>{},
  int spanLength = 4,
  bool isDirty = false,
  String? issueMessage,
}) {
  return TabFieldView(
    descriptor: FieldDescriptor(
      FieldId(id ?? label),
      SaveSlotId.account,
      label,
      kind,
      ByteSpan(16, spanLength),
      confidence,
      confidence == FieldConfidence.verified ? _source : 'no citation',
      min: min,
      max: max,
      choices: choices,
      readOnly: readOnly,
    ),
    value: value,
    isDirty: isDirty,
    issueMessage: issueMessage,
  );
}

Finder _cell(String id) => find.byKey(ValueKey<String>('edit-table-cell-$id'));

Finder _listScrollable() {
  return find
      .descendant(
        of: find.byKey(EditTable.listKey),
        matching: find.byType(Scrollable),
      )
      .first;
}

void main() {
  testWidgets('renders headers, virtualises 297 rows, and scrolls to build', (
    tester,
  ) async {
    await pumpTabPage(tester, _table(_manyRows(297)));
    expectNoOverflow(tester);

    expect(find.text('Field'), findsOneWidget);
    expect(find.text('Type'), findsOneWidget);
    expect(find.text('Value'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);

    expect(find.byKey(EditTable.rowKey('field-0')), findsOneWidget);
    expect(
      find.byKey(EditTable.rowKey('field-250')),
      findsNothing,
      reason: 'offscreen rows must not be built by the virtualised list',
    );

    await tester.scrollUntilVisible(
      find.byKey(EditTable.rowKey('field-250')),
      600,
      scrollable: _listScrollable(),
    );
    await tester.pump();

    expect(find.byKey(EditTable.rowKey('field-250')), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('search filters by name and type and reports the exact count', (
    tester,
  ) async {
    final rows = <EditTableRow>[
      _row('player.health', type: 'Int', min: 0, max: 20),
      _row('player.magic', type: 'Int', min: 0, max: 10),
      _row(
        'quest.medallion',
        type: 'Enum',
        value: '—',
        kind: null,
        readOnlyReason: editTableNotStoredReason,
      ),
    ];
    await pumpTabPage(tester, _table(rows));
    expect(find.text('Showing 3 of 3 fields · 2 editable'), findsOneWidget);

    await tester.enterText(find.byKey(EditTable.searchFieldKey), 'magic');
    await tester.pump();
    expect(find.text('Showing 1 of 3 fields · 2 editable'), findsOneWidget);
    expect(find.byKey(EditTable.rowKey('player.health')), findsNothing);
    expect(find.byKey(EditTable.rowKey('player.magic')), findsOneWidget);

    await tester.enterText(find.byKey(EditTable.searchFieldKey), 'enum');
    await tester.pump();
    expect(find.text('Showing 1 of 3 fields · 2 editable'), findsOneWidget);
    expect(find.byKey(EditTable.rowKey('quest.medallion')), findsOneWidget);

    await tester.enterText(find.byKey(EditTable.searchFieldKey), 'no-such');
    await tester.pump();
    expect(find.text('Showing 0 of 3 fields · 2 editable'), findsOneWidget);
    expect(find.text('No fields to display'), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('editable-only and changed-only filters hide rows', (
    tester,
  ) async {
    final rows = <EditTableRow>[
      _row('player.health', isModified: true, min: 0, max: 20),
      _row('player.magic', isModified: false, min: 0, max: 10),
      _row(
        'quest.medallion',
        type: 'Enum',
        value: '—',
        kind: null,
        readOnlyReason: editTableNotStoredReason,
      ),
    ];
    await pumpTabPage(tester, _table(rows));

    await tester.tap(find.byKey(EditTable.editableOnlyKey));
    await tester.pump();
    expect(find.byKey(EditTable.rowKey('quest.medallion')), findsNothing);
    expect(find.byKey(EditTable.rowKey('player.health')), findsOneWidget);
    expect(find.byKey(EditTable.rowKey('player.magic')), findsOneWidget);
    expect(find.text('Showing 2 of 3 fields · 2 editable'), findsOneWidget);

    await tester.tap(find.byKey(EditTable.changedOnlyKey));
    await tester.pump();
    expect(find.byKey(EditTable.rowKey('player.health')), findsOneWidget);
    expect(find.byKey(EditTable.rowKey('player.magic')), findsNothing);
    expect(find.text('Showing 1 of 3 fields · 2 editable'), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('integer commits once on Enter and boolean toggles once', (
    tester,
  ) async {
    final integers = <(String, int)>[];
    final booleans = <(String, bool)>[];
    final rows = <EditTableRow>[
      _row('int-field', label: 'player.health', min: 0, max: 20),
      _row(
        'bool-field',
        label: 'flags.haveItem',
        type: 'Bool',
        value: 'Off',
        kind: EditCellKind.boolean,
      ),
    ];
    await pumpTabPage(
      tester,
      _table(
        rows,
        onInteger: (String id, int value) => integers.add((id, value)),
        onBoolean: (String id, bool value) => booleans.add((id, value)),
      ),
    );

    await tester.enterText(_cell('int-field'), '15');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(integers, <(String, int)>[('int-field', 15)]);

    // Leaving the field commits again only if the value changed; it did not.
    await tester.tap(find.byKey(EditTable.countKey));
    await tester.pump();
    expect(integers, hasLength(1));

    await tester.tap(_cell('bool-field'));
    await tester.pump();
    expect(booleans, <(String, bool)>[('bool-field', true)]);
    expectNoOverflow(tester);
  });

  testWidgets('integer cells seed from intValue, never from the label', (
    tester,
  ) async {
    final rows = <EditTableRow>[
      _row('plain', label: 'player.health', value: '7', intValue: 7, min: 0),
      _row(
        'formatted',
        label: 'player.rupees',
        value: '1,007',
        intValue: 1007,
        min: 0,
        max: 4000,
      ),
    ];
    await pumpTabPage(tester, _table(rows));

    expect(tester.widget<NumericField>(_cell('plain')).value, 7);
    expect(
      tester.widget<NumericField>(_cell('formatted')).value,
      1007,
      reason: 'a formatted label must never be re-parsed into a value',
    );
    expectNoOverflow(tester);
  });

  testWidgets('boolean cells seed from boolValue, never from the label', (
    tester,
  ) async {
    final booleans = <(String, bool)>[];
    final rows = <EditTableRow>[
      _row(
        'bool-field',
        label: 'flags.haveItem',
        type: 'Bool',
        value: 'Off',
        kind: EditCellKind.boolean,
        boolValue: true,
      ),
    ];
    await pumpTabPage(
      tester,
      _table(
        rows,
        onBoolean: (String id, bool value) => booleans.add((id, value)),
      ),
    );

    expect(
      tester.widget<BrassToggle>(_cell('bool-field')).value,
      isTrue,
      reason: 'the label reads Off, so only boolValue can seed the toggle',
    );

    await tester.tap(_cell('bool-field'));
    await tester.pump();
    expect(booleans, <(String, bool)>[('bool-field', false)]);
    expectNoOverflow(tester);
  });

  testWidgets('enumeration seeds only a known key and reports the chosen key', (
    tester,
  ) async {
    final enumerations = <(String, String)>[];
    final rows = <EditTableRow>[
      _row(
        'enum-field',
        label: 'quest.medallion',
        type: 'EnumBrowse',
        value: 'Unknown value 12',
        kind: EditCellKind.enumeration,
        choices: const <String>['On', 'Off'],
        enumKey: 'UnknownValue',
      ),
    ];
    await pumpTabPage(
      tester,
      _table(
        rows,
        onEnumeration: (String id, String key) => enumerations.add((id, key)),
      ),
    );

    expect(
      tester.widget<SearchableSelect<String>>(_cell('enum-field')).value,
      isNull,
      reason: 'an unknown stored key must not be fabricated as a choice',
    );
    expect(find.text('Unknown value 12'), findsOneWidget);

    await tester.tap(_cell('enum-field'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('On'));
    await tester.pump();

    expect(enumerations, <(String, String)>[('enum-field', 'On')]);
    expectNoOverflow(tester);
  });

  testWidgets('read-only rows show the reason and expose no editor', (
    tester,
  ) async {
    final integers = <(String, int)>[];
    final booleans = <(String, bool)>[];
    final rows = <EditTableRow>[
      _row(
        'read-only',
        label: 'vector.position',
        type: 'Vec3',
        value: '(1, 2, 3)',
        kind: null,
        readOnlyReason: editTableOpaqueKindReason,
      ),
    ];
    await pumpTabPage(
      tester,
      _table(
        rows,
        onInteger: (String id, int value) => integers.add((id, value)),
        onBoolean: (String id, bool value) => booleans.add((id, value)),
      ),
    );

    expect(find.text(editTableOpaqueKindReason), findsOneWidget);
    expect(find.text('(1, 2, 3)'), findsOneWidget);
    expect(_cell('read-only'), findsNothing);
    final row = find.byKey(EditTable.rowKey('read-only'));
    expect(
      find.descendant(of: row, matching: find.byType(NumericField)),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.byType(BrassToggle)),
      findsNothing,
    );

    await tester.tapAt(tester.getTopLeft(row) + const Offset(12, 32));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(integers, isEmpty);
    expect(booleans, isEmpty);
    expectNoOverflow(tester);
  });

  testWidgets('keyboard cursor moves, clamps, and Enter focuses its editor', (
    tester,
  ) async {
    await pumpTabPage(tester, _table(_integerRows(20)));

    EditableText editableIn(String id) {
      return tester.widget<EditableText>(
        find.descendant(of: _cell(id), matching: find.byType(EditableText)),
      );
    }

    Future<void> tapRow(String id) async {
      await tester.tapAt(
        tester.getTopLeft(find.byKey(EditTable.rowKey(id))) +
            const Offset(12, 32),
      );
      await tester.pump();
    }

    await tapRow('field-0');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(editableIn('field-1').focusNode.hasFocus, isTrue);

    // Leaving the editor returns the table to its own keyboard stop.
    await tapRow('field-2');
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(find.byKey(EditTable.rowKey('field-19')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(editableIn('field-19').focusNode.hasFocus, isTrue);

    await tapRow('field-19');
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(editableIn('field-0').focusNode.hasFocus, isTrue);
    expectNoOverflow(tester);
  });

  testWidgets('error message renders a banner and no rows', (tester) async {
    await pumpTabPage(
      tester,
      _table(_manyRows(3), errorMessage: 'The save could not be read'),
    );

    expect(find.byKey(EditTable.errorKey), findsOneWidget);
    expect(find.text('The save could not be read'), findsOneWidget);
    expect(find.byKey(EditTable.listKey), findsNothing);
    expect(find.byKey(EditTable.rowKey('field-0')), findsNothing);
    expect(find.byType(NumericField), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('no overflow at 1100x700 or 1280x720', (tester) async {
    await pumpTabPage(tester, _table(_manyRows(297)));
    expectNoOverflow(tester);

    await pumpTab(tester, _table(_manyRows(297)), size: tabTestViewports[1]);
    expectNoOverflow(tester);
  });

  group('buildEditTableRows', () {
    test('editable descriptors keep kind, bounds, choices, and text cap', () {
      final rows = buildEditTableRows(
        catalogueFields: <FieldRef>[
          _ref('player.health'),
          _ref('player.mode', type: 'EnumBrowse'),
          _ref('player.name', type: 'String64'),
        ],
        views: <TabFieldView>[
          _view('player.health', min: 0, max: 20),
          _view(
            'player.mode',
            kind: FieldKind.enumeration,
            choices: const <String, int>{'On': 0, 'Off': 1},
            value: const EnumValue(key: 'On', rawValue: 0),
          ),
          _view(
            'player.name',
            kind: FieldKind.string,
            spanLength: 8,
            value: const StringValue('Kokiri'),
          ),
        ],
      );

      expect(rows, hasLength(3));
      expect(rows[0].id, 'player.health');
      expect(rows[0].label, 'player.health');
      expect(rows[0].typeLabel, 'Int');
      expect(rows[0].isEditable, isTrue);
      expect(rows[0].kind, EditCellKind.integer);
      expect(rows[0].min, 0);
      expect(rows[0].max, 20);
      expect(rows[0].valueLabel, '7');
      expect(rows[0].source, _source);
      expect(rows[0].level, ProvenanceLevel.verified);
      expect(rows[0].intValue, 7);
      expect(rows[0].boolValue, isNull);
      expect(rows[0].enumKey, isNull);
      expect(rows[0].textValue, isNull);

      expect(rows[1].kind, EditCellKind.enumeration);
      expect(rows[1].choices, <String>['On', 'Off']);
      expect(rows[1].textCap, isNull);
      expect(rows[1].enumKey, 'On');

      expect(rows[2].kind, EditCellKind.string);
      expect(rows[2].textCap, 7);
      expect(rows[2].valueLabel, 'Kokiri');
      expect(rows[2].textValue, 'Kokiri');
    });

    test('typed seeds come from decoded values for all four kinds', () {
      final rows = buildEditTableRows(
        catalogueFields: <FieldRef>[
          _ref('a.int'),
          _ref('a.bool', type: 'Bool'),
          _ref('a.enum', type: 'EnumBrowse'),
          _ref('a.text', type: 'String64'),
        ],
        views: <TabFieldView>[
          _view('a.int', value: const IntValue(-4)),
          _view(
            'a.bool',
            kind: FieldKind.boolean,
            value: const BoolValue(true),
          ),
          _view(
            'a.enum',
            kind: FieldKind.enumeration,
            choices: const <String, int>{'On': 0},
            value: const EnumValue(key: 'On', rawValue: 0),
          ),
          _view(
            'a.text',
            kind: FieldKind.string,
            spanLength: 8,
            value: const StringValue('Kokiri'),
          ),
        ],
      );

      expect(rows[0].intValue, -4);
      expect(rows[0].boolValue, isNull);
      expect(rows[0].enumKey, isNull);
      expect(rows[0].textValue, isNull);

      expect(rows[1].boolValue, isTrue);
      expect(rows[1].intValue, isNull);
      expect(rows[1].enumKey, isNull);
      expect(rows[1].textValue, isNull);

      expect(rows[2].enumKey, 'On');
      expect(rows[2].intValue, isNull);
      expect(rows[2].boolValue, isNull);
      expect(rows[2].textValue, isNull);

      expect(rows[3].textValue, 'Kokiri');
      expect(rows[3].intValue, isNull);
      expect(rows[3].boolValue, isNull);
      expect(rows[3].enumKey, isNull);
    });

    test('a verified descriptor with no decoded value is read-only for every '
        'kind', () {
      final rows = buildEditTableRows(
        catalogueFields: <FieldRef>[
          _ref('a.int'),
          _ref('a.bool', type: 'Bool'),
          _ref('a.enum', type: 'EnumBrowse'),
          _ref('a.text', type: 'String64'),
        ],
        views: <TabFieldView>[
          _view('a.int', value: null),
          _view('a.bool', kind: FieldKind.boolean, value: null),
          _view(
            'a.enum',
            kind: FieldKind.enumeration,
            choices: const <String, int>{'On': 0},
            value: null,
          ),
          _view('a.text', kind: FieldKind.string, spanLength: 8, value: null),
        ],
      );

      expect(rows, hasLength(4));
      for (final row in rows) {
        expect(row.kind, isNull, reason: row.label);
        expect(row.isEditable, isFalse, reason: row.label);
        expect(row.readOnlyReason, 'No decoded value', reason: row.label);
        expect(row.intValue, isNull, reason: row.label);
        expect(row.boolValue, isNull, reason: row.label);
        expect(row.enumKey, isNull, reason: row.label);
        expect(row.textValue, isNull, reason: row.label);
      }
    });

    test('a value of the wrong type is read-only, not coerced', () {
      final rows = buildEditTableRows(
        catalogueFields: <FieldRef>[_ref('a.int')],
        views: <TabFieldView>[
          _view('a.int', value: const StringValue('not an integer')),
        ],
      );

      expect(rows.single.kind, isNull);
      expect(rows.single.intValue, isNull);
      expect(rows.single.readOnlyReason, 'No decoded value');
    });

    test('inferred descriptor is read-only with the exact reason', () {
      final rows = buildEditTableRows(
        catalogueFields: <FieldRef>[
          _ref('player.prefix', provenance: FieldProvenance.inferred),
        ],
        views: <TabFieldView>[
          _view(
            'player.prefix',
            confidence: FieldConfidence.inferred,
            min: 0,
            max: 20,
          ),
        ],
      );

      expect(rows.single.isEditable, isFalse);
      expect(rows.single.kind, isNull);
      expect(
        rows.single.readOnlyReason,
        'Field name is prefix-derived (inferred), so the meaning is not '
        'verified',
      );
      expect(rows.single.level, ProvenanceLevel.inferred);
      expect(rows.single.min, isNull);
    });

    test('unverified, fixed-width, and valueless rows state their reason', () {
      final rows = buildEditTableRows(
        catalogueFields: <FieldRef>[
          _ref('a.unverified'),
          _ref('a.fixed'),
          _ref('a.novalue'),
          _ref('a.vector', type: 'Vec3'),
        ],
        views: <TabFieldView>[
          _view('a.unverified', confidence: FieldConfidence.unverified),
          _view('a.fixed', readOnly: true),
          _view('a.novalue', value: null),
          _view(
            'a.vector',
            kind: FieldKind.vector,
            spanLength: 12,
            value: VectorValue(const <double>[1, 2, 3]),
          ),
        ],
      );

      expect(rows[0].readOnlyReason, 'Field has no verified name');
      expect(rows[0].level, ProvenanceLevel.unknown);
      expect(rows[1].readOnlyReason, editTableFixedWidthReason);
      expect(rows[2].readOnlyReason, 'No decoded value');
      expect(rows[3].readOnlyReason, editTableOpaqueKindReason);
      for (final row in rows) {
        expect(row.isEditable, isFalse);
      }
    });

    test('a catalogue field with no view stays visible and read-only', () {
      final rows = buildEditTableRows(
        catalogueFields: <FieldRef>[
          _ref(
            'quest.medallion',
            type: 'EnumBrowse',
            provenance: FieldProvenance.observed,
            hash: 0x1ca2d1b7,
          ),
        ],
        views: const <TabFieldView>[],
      );

      expect(rows, hasLength(1));
      expect(rows.single.id, 'catalogue:0x1ca2d1b7');
      expect(rows.single.label, 'quest.medallion');
      expect(rows.single.typeLabel, 'EnumBrowse');
      expect(rows.single.valueLabel, editTableEmptyValue);
      expect(rows.single.kind, isNull);
      expect(rows.single.readOnlyReason, 'Not stored in this save');
      expect(rows.single.level, ProvenanceLevel.observed);
    });

    test('duplicate catalogue names collapse to the first row', () {
      final rows = buildEditTableRows(
        catalogueFields: <FieldRef>[
          _ref('player.health', type: 'Int'),
          _ref('player.health', type: 'Bool'),
        ],
        views: const <TabFieldView>[],
      );

      expect(rows, hasLength(1));
      expect(rows.single.typeLabel, 'Int');
    });

    test('an empty decoded string shows the dash, never blank text', () {
      final rows = buildEditTableRows(
        catalogueFields: <FieldRef>[_ref('player.name', type: 'String64')],
        views: <TabFieldView>[
          _view(
            'player.name',
            kind: FieldKind.string,
            spanLength: 8,
            value: const StringValue(''),
          ),
        ],
      );

      expect(rows.single.valueLabel, editTableEmptyValue);
      expect(rows.single.valueLabel, isNotEmpty);
      expect(rows.single.textValue, '');
      expect(rows.single.isEditable, isTrue);
      expect(rows.single.textCap, 7);
    });

    test('descriptor issue text and dirty marker are carried through', () {
      final rows = buildEditTableRows(
        catalogueFields: <FieldRef>[_ref('player.health')],
        views: <TabFieldView>[
          _view(
            'player.health',
            isDirty: true,
            issueMessage: 'Health exceeds the maximum',
          ),
        ],
      );

      expect(rows.single.isModified, isTrue);
      expect(rows.single.issueMessage, 'Health exceeds the maximum');
    });
  });

  testWidgets('an inline issue renders in the danger colour', (tester) async {
    final rows = <EditTableRow>[
      _row(
        'player.health',
        min: 0,
        max: 20,
        isModified: true,
        issueMessage: 'Health exceeds the maximum',
      ),
    ];
    await pumpTabPage(tester, _table(rows));

    final issue = tester.widget<Text>(find.text('Health exceeds the maximum'));
    expect(issue.style?.color, BombFlowerColors.danger);
    expect(find.text('Health exceeds the maximum'), findsOneWidget);
    expectNoOverflow(tester);
  });
}
