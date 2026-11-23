import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/domain/core/edit_command.dart';
import 'package:bomb_flower/domain/core/field_metadata.dart';
import 'package:bomb_flower/domain/core/field_value.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_ui_state.dart';
import 'package:bomb_flower/presentation/shell/tabs/flags_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/v1_gap_panel.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_scope.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_source.dart';
import 'package:bomb_flower/presentation/tabs_support/session_save_tab_source.dart';
import 'package:bomb_flower/presentation/widgets/common/banner.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_toggle.dart';
import 'package:bomb_flower/presentation/widgets/controls/numeric_field.dart';
import 'package:bomb_flower/presentation/widgets/data/edit_table.dart';
import 'package:bomb_flower/presentation/widgets/selectors/searchable_select.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Banner;

import 'support/tab_test_harness.dart';
import 'support/ui_flow_fixture.dart';

/// An in-memory port with the current byte accessors and an edit recorder.
final class _FakeSaveTabSource extends ChangeNotifier implements SaveTabSource {
  _FakeSaveTabSource({
    this.views = const <TabFieldView>[],
    this.open = true,
    this.slot,
  });

  final List<TabFieldView> views;
  final bool open;

  final SaveSlotId? slot;

  /// Commands received through [edit], in order.
  final List<EditCommand> edits = <EditCommand>[];

  @override
  bool get isOpen => open;

  @override
  SaveSlotId? get activeSlot => slot;

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
  String? get rootPath => open ? '/tmp/fake-save' : null;

  @override
  Uint8List? get activeSlotBytes => open ? Uint8List(0) : null;

  @override
  Uint8List? bytesFor(SaveSlotId slot) =>
      isOpen && slot == activeSlot ? Uint8List(0) : null;

  @override
  Listenable get changes => this;

  @override
  List<TabFieldView> viewsFor(EditorTabGroup group) => const <TabFieldView>[];

  @override
  Iterable<TabFieldView> get allViews => views;

  @override
  void edit(EditCommand command) => edits.add(command);

  @override
  void undo() {}

  @override
  void redo() {}
}

/// Delegates every member to a real source and records committed commands.
///
/// The real session source can no longer be injected with a counter, so this
/// thin proxy records the commands the widget actually emitted while keeping
/// the production adapter underneath.
final class _RecordingSource implements SaveTabSource {
  _RecordingSource(this._inner);

  final SaveTabSource _inner;

  /// Commands received from the widget, in order.
  final List<EditCommand> edits = <EditCommand>[];

  @override
  bool get isOpen => _inner.isOpen;

  @override
  String? get rootPath => _inner.rootPath;

  @override
  SaveSlotId? get activeSlot => _inner.activeSlot;

  @override
  Uint8List? get activeSlotBytes => _inner.activeSlotBytes;

  @override
  Uint8List? bytesFor(SaveSlotId slot) => _inner.bytesFor(slot);

  @override
  Listenable get changes => _inner.changes;

  @override
  List<TabFieldView> viewsFor(EditorTabGroup group) => _inner.viewsFor(group);

  @override
  Iterable<TabFieldView> get allViews => _inner.allViews;

  @override
  bool get isDirty => _inner.isDirty;

  @override
  int get changedFieldCount => _inner.changedFieldCount;

  @override
  SaveSlotId? get newestSlot => _inner.newestSlot;

  @override
  List<SlotAge> get slotAges => _inner.slotAges;

  @override
  bool get canUndo => _inner.canUndo;

  @override
  bool get canRedo => _inner.canRedo;

  @override
  void edit(EditCommand command) {
    edits.add(command);
    _inner.edit(command);
  }

  @override
  void undo() => _inner.undo();

  @override
  void redo() => _inner.redo();
}

/// The schema's own ID shape for a `progress.sav` record with [field]'s hash.
String _idFor(FieldRef field) => 'progress.${field.hashHex.substring(2)}';

/// A `progress.sav` view; the source citation is the engine's by default.
TabFieldView _view({
  required String id,
  required String label,
  required FieldValue value,
  FieldKind kind = FieldKind.boolean,
  ByteSpan span = const ByteSpan(0, 4),
  FieldConfidence confidence = FieldConfidence.verified,
  bool readOnly = false,
  String source = 'schema:struct',
  SaveSlotId slot = const SaveSlotId('slot_00'),
}) {
  return TabFieldView(
    descriptor: FieldDescriptor(
      FieldId(id),
      slot,
      label,
      kind,
      span,
      confidence,
      source,
      endianness: Endian.little,
      readOnly: readOnly,
    ),
    value: value,
    isDirty: false,
  );
}

/// One on-disk Bool the schema never named: `Unnamed 0x…`, read-only.
TabFieldView _hashOnlyView(int index, {bool value = false}) {
  final hex = (0x01000000 + index).toRadixString(16).padLeft(8, '0');
  return _view(
    id: 'progress.$hex',
    label: 'Unnamed 0x$hex',
    value: BoolValue(value),
    confidence: FieldConfidence.unverified,
    readOnly: true,
    source: 'unverified',
  );
}

late FieldGroupsCatalogue _catalogue;
late List<FieldRef> _flagFields;

/// The flags catalogue as the production engine resolves it.
FieldRef _fieldA = const FieldRef(
  hash: 0,
  name: '',
  type: '',
  section: null,
  defaultPreview: '',
  provenance: FieldProvenance.verified,
);
FieldRef _fieldB = _fieldA;

/// First field whose name no other catalogue name contains, so a search for it
/// matches exactly one row.
FieldRef _uniqueNamedFrom(int start) {
  for (final field in _flagFields.skip(start)) {
    final needle = field.name.toLowerCase();
    final hits = _flagFields
        .where((FieldRef other) => other.name.toLowerCase().contains(needle))
        .length;
    if (hits == 1) {
      return field;
    }
  }
  fail('no flags catalogue name is a unique search needle');
}

Future<void> _pumpFlags(
  WidgetTester tester,
  _FakeSaveTabSource source, {
  Size size = const Size(1100, 700),
  Widget? tab,
  bool disposeSource = true,
}) {
  if (disposeSource) {
    addTearDown(source.dispose);
  }
  return pumpTab(
    tester,
    SaveTabScope(
      source: source,
      child: tab ?? FlagsTab(catalogue: _catalogue),
    ),
    size: size,
  );
}

Finder _row(String id) => find.byKey(EditTable.rowKey(id));
Finder _cell(String id) => find.byKey(ValueKey<String>('edit-table-cell-$id'));

Finder _builtRows() {
  return find.byWidgetPredicate((Widget widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('edit-table-row-');
  });
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(EditTable.searchFieldKey), text);
  await tester.pump();
}

EditTable _table(WidgetTester tester) =>
    tester.widget<EditTable>(find.byType(EditTable));

void main() {
  setUpAll(() async {
    _catalogue = FieldGroupsCatalogue.load(
      await File('assets/fields/groups.json').readAsString(),
    );
    _flagFields = _catalogue
        .forTab(EditorTabGroup.flags)
        .expand((FieldGroup group) => group.fields)
        .toList(growable: false);
    _fieldA = _uniqueNamedFrom(0);
    _fieldB = _uniqueNamedFrom(1);
  });

  testWidgets(
    'renders the header and measured counts, virtualising 3,443 rows',
    (tester) async {
      final source = _FakeSaveTabSource(
        views: <TabFieldView>[
          _view(
            id: _idFor(_fieldA),
            label: _fieldA.name,
            value: const BoolValue(false),
          ),
        ],
      );
      await _pumpFlags(tester, source);

      expect(find.text('Flags'), findsOneWidget);
      expect(find.byType(V1GapPanel), findsNothing);

      final table = _table(tester);
      expect(
        table.rows,
        hasLength(3443),
        reason: 'one row per named catalogue field',
      );
      final editable = table.rows
          .where((EditTableRow row) => row.isEditable)
          .length;
      expect(editable, 1, reason: 'only the verified view is editable');

      expect(
        find.text(
          '3,443 named fields · 6,769 hash-only · '
          '$editable of 3,443 named editable',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Showing 3,443 of 3,443 fields · 1 editable'),
        findsOneWidget,
      );

      expect(
        find.byKey(EditTable.rowKey(table.rows.last.id)),
        findsNothing,
        reason: 'the last of 3,443 rows must never be built up front',
      );
      expect(_builtRows().evaluate().length, lessThan(3443));

      // The caption states both halves, with the schema's counts.
      expect(find.textContaining('3,443 named Bool fields.'), findsOneWidget);
      expect(
        find.textContaining(
          '6,769 on-disk Bools have no verified name and appear by hash only, '
          'read-only.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('0 present in this save.'),
        findsOneWidget,
        reason: 'the fake source carries no hash-only records',
      );
      expectNoOverflow(tester);
    },
  );

  testWidgets('the table footer groups its field counts', (tester) async {
    final source = _FakeSaveTabSource(
      views: <TabFieldView>[
        _view(
          id: _idFor(_fieldA),
          label: _fieldA.name,
          value: const BoolValue(false),
        ),
      ],
    );
    await _pumpFlags(tester, source);

    final table = _table(tester);
    expect(table.rows, hasLength(3443));
    expect(
      table.rows.where((EditTableRow row) => row.isEditable).length,
      1,
      reason: 'exactly one verified view over the 3,443-row catalogue',
    );
    expect(
      tester.widget<Text>(find.byKey(EditTable.countKey)).data,
      'Showing 3,443 of 3,443 fields · 1 editable',
    );
    expectNoOverflow(tester);
  });

  testWidgets('search filters the named set and the count readout is exact', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <TabFieldView>[
        _view(
          id: _idFor(_fieldA),
          label: _fieldA.name,
          value: const BoolValue(true),
        ),
        _view(
          id: _idFor(_fieldB),
          label: _fieldB.name,
          value: const BoolValue(false),
        ),
      ],
    );
    await _pumpFlags(tester, source);
    expect(
      tester.widget<Text>(find.byKey(EditTable.countKey)).data,
      'Showing 3,443 of 3,443 fields · 2 editable',
    );

    await _search(tester, _fieldA.name);
    expect(_row(_idFor(_fieldA)), findsOneWidget);
    expect(_row(_idFor(_fieldB)), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(EditTable.countKey)).data,
      'Showing 1 of 3,443 fields · 2 editable',
    );

    await _search(tester, _fieldB.name);
    expect(_row(_idFor(_fieldB)), findsOneWidget);
    expect(_row(_idFor(_fieldA)), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(EditTable.countKey)).data,
      'Showing 1 of 3,443 fields · 2 editable',
    );

    await _search(tester, 'no-such-flag-name');
    expect(
      tester.widget<Text>(find.byKey(EditTable.countKey)).data,
      'Showing 0 of 3,443 fields · 2 editable',
    );
    expectNoOverflow(tester);
  });

  testWidgets('one committed bool edit emits exactly one SetScalar', (
    tester,
  ) async {
    final id = _idFor(_fieldA);
    final source = _FakeSaveTabSource(
      views: <TabFieldView>[
        _view(id: id, label: _fieldA.name, value: const BoolValue(false)),
      ],
    );
    await _pumpFlags(tester, source);
    await _search(tester, _fieldA.name);

    final cell = _cell(id);
    await tester.ensureVisible(cell);
    await tester.pump();
    // The cell key is on the BrassToggle itself, so it is the tap target.
    await tester.tap(cell);
    await tester.pump();

    expect(source.edits, hasLength(1));
    final command = source.edits.single;
    expect(command, isA<SetScalar>());
    expect((command as SetScalar).field, FieldId(id));
    expect(command.value, 1, reason: 'false toggles to 1');
    expectNoOverflow(tester);
  });

  testWidgets('inferred and read-only named rows state their reason', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <TabFieldView>[
        _view(
          id: _idFor(_fieldA),
          label: _fieldA.name,
          value: const BoolValue(true),
          confidence: FieldConfidence.inferred,
        ),
        _view(
          id: _idFor(_fieldB),
          label: _fieldB.name,
          value: const BoolValue(true),
          readOnly: true,
        ),
      ],
    );
    await _pumpFlags(tester, source);

    await _search(tester, _fieldA.name);
    expect(
      find.text(
        'Field name is prefix-derived (inferred), so the meaning is not '
        'verified',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _row(_idFor(_fieldA)),
        matching: find.byType(BrassToggle),
      ),
      findsNothing,
    );
    await tester.tapAt(
      tester.getTopLeft(_row(_idFor(_fieldA))) + const Offset(12, 32),
    );
    await tester.pump();
    expect(source.edits, isEmpty);

    await _search(tester, _fieldB.name);
    expect(find.text(editTableFixedWidthReason), findsOneWidget);
    expect(
      find.descendant(
        of: _row(_idFor(_fieldB)),
        matching: find.byType(BrassToggle),
      ),
      findsNothing,
    );
    await tester.tapAt(
      tester.getTopLeft(_row(_idFor(_fieldB))) + const Offset(12, 32),
    );
    await tester.pump();
    expect(source.edits, isEmpty);
    expectNoOverflow(tester);
  });

  testWidgets('a view from another slot is not stored and not editable', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      slot: const SaveSlotId('slot_00'),
      views: <TabFieldView>[
        _view(
          id: _idFor(_fieldA),
          label: _fieldA.name,
          value: const BoolValue(true),
          slot: const SaveSlotId('slot_01'),
        ),
      ],
    );
    await _pumpFlags(tester, source);
    await _search(tester, _fieldA.name);

    expect(find.text(editTableNotStoredReason), findsOneWidget);
    expect(
      _table(tester).rows.where((EditTableRow row) => row.isEditable),
      isEmpty,
    );
    expect(_row(_idFor(_fieldA)), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('the hash-only toggle swaps to a virtualised read-only set', (
    tester,
  ) async {
    final hashOnly = <TabFieldView>[
      for (var index = 0; index < 60; index++) _hashOnlyView(index),
    ];
    final source = _FakeSaveTabSource(
      views: <TabFieldView>[
        _view(
          id: _idFor(_fieldA),
          label: _fieldA.name,
          value: const BoolValue(true),
        ),
        ...hashOnly,
      ],
    );
    await _pumpFlags(tester, source);

    expect(_table(tester).rows, hasLength(3443), reason: 'named set default');

    await tester.tap(find.byKey(FlagsTab.hashOnlyToggleKey));
    await tester.pump();

    final table = _table(tester);
    expect(table.rows, hasLength(60));
    expect(
      table.rows.every((EditTableRow row) => row.kind == null),
      isTrue,
      reason: 'a hash-only row never carries an editor kind',
    );
    expect(
      table.rows.every(
        (EditTableRow row) =>
            row.readOnlyReason == FlagsTab.hashOnlyReadOnlyReason,
      ),
      isTrue,
    );
    expect(
      find.text(
        '3,443 named fields · 6,769 hash-only · '
        '0 of 60 hash-only editable',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(EditTable.countKey)).data,
      'Showing 60 of 60 fields · 0 editable',
    );

    final first = table.rows.first;
    expect(first.label, contains('Unnamed 0x'));
    expect(first.label, contains(first.id.substring('progress.'.length)));
    expect(first.typeLabel, 'Bool');

    final firstRow = _row(first.id);
    expect(firstRow, findsOneWidget);
    expect(
      find.descendant(of: firstRow, matching: find.text(first.label)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: firstRow,
        matching: find.text(FlagsTab.hashOnlyReadOnlyReason),
      ),
      findsOneWidget,
    );
    for (final finder in <Finder>[
      find.byType(BrassToggle),
      find.byType(NumericField),
      find.byWidgetPredicate(
        (Widget widget) => widget is SearchableSelect<dynamic>,
      ),
    ]) {
      expect(
        find.descendant(of: firstRow, matching: finder),
        findsNothing,
        reason: 'a hash-only row must render no editor',
      );
    }

    await tester.tap(firstRow);
    await tester.pump();
    expect(source.edits, isEmpty);

    expect(
      _builtRows().evaluate().length,
      lessThan(table.rows.length),
      reason: 'the hash-only set must be virtualised too',
    );
    expect(find.byKey(EditTable.rowKey(table.rows.last.id)), findsNothing);

    await tester.tap(find.byKey(FlagsTab.hashOnlyToggleKey));
    await tester.pump();
    expect(_table(tester).rows, hasLength(3443));
    expectNoOverflow(tester);
  });

  testWidgets('the longest verified name ellipsises instead of overflowing', (
    tester,
  ) async {
    final longest = _flagFields.reduce(
      (FieldRef a, FieldRef b) => b.name.length > a.name.length ? b : a,
    );
    final id = _idFor(longest);
    final source = _FakeSaveTabSource(
      views: <TabFieldView>[
        _view(id: id, label: longest.name, value: const BoolValue(false)),
      ],
    );
    await _pumpFlags(tester, source);

    for (final size in <Size>[const Size(1100, 700), tabTestViewports.first]) {
      await _pumpFlags(tester, source, size: size, disposeSource: false);
      await _search(tester, longest.name);

      final row = _row(id);
      expect(row, findsOneWidget);
      final label = tester.widget<Text>(
        find.descendant(of: row, matching: find.text(longest.name)),
      );
      expect(label.maxLines, 1);
      expect(label.overflow, TextOverflow.ellipsis);

      final model = _table(tester).rows
          .firstWhere((EditTableRow row) => row.id == id);
      expect(
        model.label,
        longest.name,
        reason: 'ellipsis is presentation only; the verified name is kept',
      );
      expectNoOverflow(tester);
    }
  });

  testWidgets('no open save shows the shared empty state', (tester) async {
    final source = _FakeSaveTabSource(
      views: <TabFieldView>[
        _view(
          id: _idFor(_fieldA),
          label: _fieldA.name,
          value: const BoolValue(true),
        ),
      ],
      open: false,
    );
    addTearDown(source.dispose);
    await pumpTab(tester, const FlagsTab());

    expect(find.text('Open a save to begin'), findsOneWidget);
    expect(find.byType(EditTable), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('catalogue failure is a warning banner and no editors', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <TabFieldView>[
        _view(
          id: _idFor(_fieldA),
          label: _fieldA.name,
          value: const BoolValue(true),
        ),
        _hashOnlyView(0),
      ],
    );
    await _pumpFlags(
      tester,
      source,
      tab: FlagsTab(
        catalogueLoader: () async => throw StateError('groups.json missing'),
      ),
    );
    await tester.pump();

    final banner = tester.widget<Banner>(
      find.byKey(FlagsTab.catalogueUnavailableKey),
    );
    expect(banner.variant, BannerVariant.warning);
    expect(find.byKey(EditTable.errorKey), findsOneWidget);
    expect(find.textContaining('groups.json missing'), findsWidgets);
    expect(_table(tester).rows, isEmpty);
    expect(find.byKey(FlagsTab.hashOnlyToggleKey), findsNothing);
    expect(find.byType(NumericField), findsNothing);
    expect(_cell(_idFor(_fieldA)), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('the table fits 1100x700 and 1280x720', (tester) async {
    final source = _FakeSaveTabSource(
      views: <TabFieldView>[
        _view(
          id: _idFor(_fieldA),
          label: _fieldA.name,
          value: const BoolValue(true),
        ),
      ],
    );
    await _pumpFlags(tester, source);
    expectNoOverflow(tester);

    await _pumpFlags(
      tester,
      source,
      size: tabTestViewports[1],
      disposeSource: false,
    );
    expectNoOverflow(tester);
  });

  group(
    'real save engine',
    skip: uiFlowFixtureAvailable ? null : uiFlowFixtureMissingReason,
    () {
      if (!uiFlowFixtureAvailable) {
        test('no fixture present', () => fail('unreachable: skipped'));
        return;
      }

      testWidgets('the fixture has the schema hash-only Bools and one bool '
          'edit changes one span', (tester) async {
        final fixture = await _openFixture(tester);
        final source = fixture.source;
        final before = source.activeSlotBytes!;
        final schema = _catalogue.stats.forTab(EditorTabGroup.flags);

        await pumpTab(
          tester,
          SaveTabScope(
            source: source,
            child: FlagsTab(catalogue: _catalogue),
          ),
        );

        final named = _table(tester).rows;
        expect(named, hasLength(schema.named));

        // The other half: measure what this save actually holds.
        await tester.tap(find.byKey(FlagsTab.hashOnlyToggleKey));
        await tester.pump();
        final hashOnly = _table(tester).rows;
        expect(
          hashOnly,
          hasLength(schema.unnamed),
          reason:
              'schema claims ${schema.unnamed} hash-only Bools; this save has '
              '${hashOnly.length}',
        );
        expect(hashOnly.every((EditTableRow row) => !row.isEditable), isTrue);
        expect(
          hashOnly.every(
            (EditTableRow row) => row.label.startsWith('Unnamed '),
          ),
          isTrue,
        );

        await tester.tap(find.byKey(FlagsTab.hashOnlyToggleKey));
        await tester.pump();

        final editable = _table(tester).rows
            .where((EditTableRow row) => row.isEditable)
            .toList(growable: false);
        expect(editable, isNotEmpty);
        final row = editable.firstWhere(
          (EditTableRow row) => row.kind == EditCellKind.boolean,
        );
        final view = source.allViews.firstWhere(
          (TabFieldView view) => view.descriptor.id.value == row.id,
        );
        expect(view.descriptor.kind, FieldKind.boolean);

        await _search(tester, row.label);
        final cell = _cell(row.id);
        await tester.ensureVisible(cell);
        await tester.pump();
        await tester.tap(cell);
        await tester.pump();

        expect(source.edits, hasLength(1));
        final command = source.edits.single;
        expect(command, isA<SetScalar>());
        expect((command as SetScalar).field, FieldId(row.id));
        expect(command.value, row.boolValue! ? 0 : 1);

        final after = source.activeSlotBytes!;
        expect(after.length, before.length);
        final differing = differingByteIndices(before, after);
        expect(differing, isNotEmpty);
        for (final index in differing) {
          expect(
            index,
            inInclusiveRange(
              view.descriptor.span.offset,
              view.descriptor.span.end - 1,
            ),
            reason:
                'byte 0x${index.toRadixString(16)} is outside the '
                '${view.descriptor.label} span',
          );
        }

        fixture.session.undo();
        await tester.pump();
        expect(source.activeSlotBytes, orderedEquals(before));
      });

      testWidgets('the fixture measures 3,443 named and 6,769 hash-only rows', (
        tester,
      ) async {
        final fixture = await _openFixture(tester);
        final stats = _catalogue.stats.forTab(EditorTabGroup.flags);

        // Assert the catalogue first: the row set comes from it, so a changed
        // groups.json must fail here rather than against a stale literal.
        expect(stats.named, 3443);
        expect(stats.unnamed, 6769);

        await pumpTab(
          tester,
          SaveTabScope(
            source: fixture.source,
            child: FlagsTab(catalogue: _catalogue),
          ),
        );

        final named = _table(tester).rows;
        expect(named, hasLength(stats.named));
        expect(named, hasLength(3443));
        final editable = named
            .where((EditTableRow row) => row.isEditable)
            .toList(growable: false);
        expect(editable, hasLength(3438));

        // The count line always names both halves.
        expect(
          find.text(
            '3,443 named fields · 6,769 hash-only · '
            '3,438 of 3,443 named editable',
          ),
          findsOneWidget,
        );

        await tester.tap(find.byKey(FlagsTab.hashOnlyToggleKey));
        await tester.pump();

        final hashOnly = _table(tester).rows;
        expect(hashOnly, hasLength(stats.unnamed));
        expect(hashOnly, hasLength(6769));
        expect(hashOnly.where((EditTableRow row) => row.isEditable), isEmpty);
        expect(
          find.text(
            '3,443 named fields · 6,769 hash-only · '
            '0 of 6,769 hash-only editable',
          ),
          findsOneWidget,
        );
      });
    },
  );
}

/// A production-wired session and recording source over a private fixture copy.
final class _Fixture {
  _Fixture({required this.session, required this.source});

  final SaveSessionCubit session;
  final _RecordingSource source;
}

/// Opens the fixture copy and wraps it in the production tab-source adapter.
Future<_Fixture> _openFixture(WidgetTester tester) async {
  final workspace = Directory.systemTemp.createTempSync('bomb_flower_flags_');
  final copyRoot = Directory('${workspace.path}/save');
  addTearDown(() {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  });
  copyUiFlowSlot(uiFlowFixtureRoot(), copyRoot);

  final schema = await tester.runAsync(loadUiFlowSchema);
  final session = openUiFlowSession(schema!);
  addTearDown(() async {
    if (!session.isClosed) {
      await session.close(force: true);
    }
  });
  await tester.runAsync(() => session.openPath(copyRoot.path));
  expect(session.state, isA<SaveSessionReady>());

  final changes = ChangeNotifier();
  addTearDown(changes.dispose);
  final subscription = session.stream.listen((_) => changes.notifyListeners());
  addTearDown(subscription.cancel);

  final base = SessionSaveTabSource(
    project: () => session.openProject,
    edit: session.edit,
    undo: session.undo,
    redo: session.redo,
    changes: changes,
    canUndo: () {
      final state = session.state;
      return state is SaveSessionReady && state.project.canUndo;
    },
    canRedo: () {
      final state = session.state;
      return state is SaveSessionReady && state.project.canRedo;
    },
  );
  return _Fixture(session: session, source: _RecordingSource(base));
}
