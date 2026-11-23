import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/domain/core/edit_command.dart';
import 'package:bomb_flower/domain/core/field_metadata.dart';
import 'package:bomb_flower/domain/core/field_value.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_ui_state.dart';
import 'package:bomb_flower/presentation/shell/tabs/progression_tab.dart';
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

/// `AllSage_MeetSheikCount`, an Int at `progress.sav` offset 81996.
const String _intId = 'progress.c96ddd27';
const String _intLabel = 'AllSage_MeetSheikCount';
const int _intOffset = 81996;

/// `HavePlayedEvent.Dm_Deku_BossIn`, a Bool at offset 508.
const String _boolId = 'progress.00c0a2f6';
const String _boolLabel = 'HavePlayedEvent.Dm_Deku_BossIn';

/// `Step_SageOfSpirit`, the tab's only Enum, at offset 93276.
const String _enumId = 'progress.19189e9d';
const String _enumLabel = 'Step_SageOfSpirit';

/// Fake-only choice table: the key names are test input, not schema claims.
const Map<String, int> _enumChoices = <String, int>{
  'None': 0,
  'SageOfSpiritAwake': 1,
};

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
  List<TabFieldView> viewsFor(EditorTabGroup group) =>
      const <TabFieldView>[];

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
  List<TabFieldView> viewsFor(EditorTabGroup group) =>
      _inner.viewsFor(group);

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

/// Re-presents one real field as a string cell.
///
/// The catalogue's Progression groups contain no String field, so exercising
/// the length-preserving text path on the real engine needs one view presented
/// as text. Only presentation changes: the id, slot, span, and the engine's own
/// descriptor stay the save's.
final class _StringCellSource implements SaveTabSource {
  _StringCellSource(this._inner, {required this.label, required this.text});

  final _RecordingSource _inner;
  final String label;
  final String text;

  /// Commands this proxy forwarded to the real engine.
  List<EditCommand> get edits => _inner.edits;

  TabFieldView _override(TabFieldView view) {
    final descriptor = view.descriptor;
    if (descriptor.label != label) return view;
    return TabFieldView(
      descriptor: FieldDescriptor(
        descriptor.id,
        descriptor.slot,
        descriptor.label,
        FieldKind.string,
        descriptor.span,
        descriptor.confidence,
        descriptor.source,
        endianness: descriptor.endianness,
        readOnly: descriptor.readOnly,
      ),
      value: StringValue(text),
      isDirty: view.isDirty,
      issueMessage: view.issueMessage,
    );
  }

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
  List<TabFieldView> viewsFor(EditorTabGroup group) => <TabFieldView>[
    for (final view in _inner.viewsFor(group)) _override(view),
  ];

  @override
  Iterable<TabFieldView> get allViews => _inner.allViews.map(_override);

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
  void edit(EditCommand command) => _inner.edit(command);

  @override
  void undo() => _inner.undo();

  @override
  void redo() => _inner.redo();
}

TabFieldView _view({
  required String id,
  required String label,
  required FieldKind kind,
  required FieldValue value,
  ByteSpan span = const ByteSpan(0, 4),
  FieldConfidence confidence = FieldConfidence.verified,
  bool readOnly = false,
  num? min,
  num? max,
  Map<String, int> choices = const <String, int>{},
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
      'schema:string',
      endianness: Endian.little,
      min: min,
      max: max,
      choices: choices,
      readOnly: readOnly,
    ),
    value: value,
    isDirty: false,
  );
}

List<TabFieldView> _anchorViews() => <TabFieldView>[
  _view(
    id: _intId,
    label: _intLabel,
    kind: FieldKind.integer,
    value: const IntValue(2),
    span: const ByteSpan(_intOffset, 4),
    min: 0,
    max: 6,
  ),
  _view(
    id: _boolId,
    label: _boolLabel,
    kind: FieldKind.boolean,
    value: const BoolValue(true),
    span: const ByteSpan(508, 4),
  ),
  _view(
    id: _enumId,
    label: _enumLabel,
    kind: FieldKind.enumeration,
    value: const EnumValue(key: 'None', rawValue: 0),
    span: const ByteSpan(93276, 4),
    choices: _enumChoices,
  ),
];

late FieldGroupsCatalogue _catalogue;

Future<void> _pumpProgression(
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
      child: tab ?? ProgressionTab(catalogue: _catalogue),
    ),
    size: size,
  );
}

Finder _row(String id) => find.byKey(EditTable.rowKey(id));
Finder _cell(String id) => find.byKey(ValueKey<String>('edit-table-cell-$id'));

Finder _cellInput(String id) =>
    find.descendant(of: _cell(id), matching: find.byType(TextField));

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(EditTable.searchFieldKey), text);
  await tester.pump();
}

/// One whole number the row's own bounds allow and that differs from its value.
int _differentValue(EditTableRow row) {
  final current = row.intValue!;
  final min = row.min?.toInt();
  final max = row.max?.toInt();
  var candidate = current == 0 ? 1 : 0;
  if (min != null && candidate < min) candidate = min;
  if (max != null && candidate > max) candidate = max;
  expect(
    candidate,
    isNot(current),
    reason: 'the test needs a value the editor will actually commit',
  );
  return candidate;
}

void main() {
  setUpAll(() async {
    _catalogue = FieldGroupsCatalogue.load(
      await File('assets/fields/groups.json').readAsString(),
    );
  });

  testWidgets('renders the catalogue header and a real anchor row', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpProgression(tester, source);

    expect(find.text('Progression'), findsOneWidget);
    expect(
      find.text('297 named fields · no hash-only fields · 3 of 297 editable'),
      findsOneWidget,
    );
    expect(find.byType(V1GapPanel), findsNothing);

    await _search(tester, 'MeetSheikCount');
    expect(_row(_intId), findsOneWidget);
    expect(find.text(_intLabel), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('search filters rows and reports the exact count readout', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpProgression(tester, source);

    await _search(tester, 'MeetSheikCount');
    expect(_row(_intId), findsOneWidget);
    expect(_row(_enumId), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(EditTable.countKey)).data,
      'Showing 1 of 297 fields · 3 editable',
    );

    await _search(tester, 'Step_SageOfSpirit');
    expect(_row(_enumId), findsOneWidget);
    expect(_row(_intId), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(EditTable.countKey)).data,
      'Showing 1 of 297 fields · 3 editable',
    );
    expectNoOverflow(tester);
  });

  testWidgets('integer commit emits exactly one SetScalar; bad text emits none', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpProgression(tester, source);
    await _search(tester, 'MeetSheikCount');

    final table = tester.widget<EditTable>(find.byType(EditTable));
    final row = table.rows.firstWhere((EditTableRow row) => row.id == _intId);
    expect(row.kind, EditCellKind.integer);
    expect(row.intValue, 2, reason: 'the typed seed comes from IntValue');
    expect(_cell(_intId), findsOneWidget);

    // A non-integer never reaches the engine.
    await tester.enterText(_cellInput(_intId), 'not-a-number');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(source.edits, isEmpty);

    // Enter commits one whole number.
    final target = _differentValue(row);
    await tester.enterText(_cellInput(_intId), '$target');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(source.edits, hasLength(1));
    final command = source.edits.single;
    expect(command, isA<SetScalar>());
    expect((command as SetScalar).field, const FieldId(_intId));
    expect(command.value, target);
    expectNoOverflow(tester);
  });

  testWidgets('enumeration choice emits exactly one SetEnum', (tester) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpProgression(tester, source);
    await _search(tester, 'Step_SageOfSpirit');

    final table = tester.widget<EditTable>(find.byType(EditTable));
    final row = table.rows.firstWhere((EditTableRow row) => row.id == _enumId);
    expect(row.kind, EditCellKind.enumeration);
    expect(row.enumKey, 'None');
    expect(row.choices, _enumChoices.keys.toList());

    await tester.tap(_cell(_enumId));
    await tester.pump();
    expect(find.byKey(SearchableSelect.panelKey), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(SearchableSelect.panelKey),
        matching: find.text('SageOfSpiritAwake'),
      ),
    );
    await tester.pump();

    expect(source.edits, hasLength(1));
    final command = source.edits.single;
    expect(command, isA<SetEnum>());
    expect((command as SetEnum).field, const FieldId(_enumId));
    expect(command.key, 'SageOfSpiritAwake');
    expectNoOverflow(tester);
  });

  testWidgets('read-only rows state their reason and emit nothing', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <TabFieldView>[
        _view(
          id: _boolId,
          label: _boolLabel,
          kind: FieldKind.boolean,
          value: const BoolValue(true),
          span: const ByteSpan(508, 4),
          confidence: FieldConfidence.inferred,
        ),
        _view(
          id: _enumId,
          label: _enumLabel,
          kind: FieldKind.enumeration,
          value: const EnumValue(key: 'None', rawValue: 0),
          span: const ByteSpan(93276, 4),
          choices: _enumChoices,
          readOnly: true,
        ),
      ],
    );
    await _pumpProgression(tester, source);

    await _search(tester, 'Dm_Deku_BossIn');
    const inferredReason =
        'Field name is prefix-derived (inferred), so the meaning is not '
        'verified';
    expect(find.text(inferredReason), findsOneWidget);
    expect(
      find.descendant(of: _row(_boolId), matching: find.byType(BrassToggle)),
      findsNothing,
    );
    expect(
      find.descendant(of: _row(_boolId), matching: find.byType(NumericField)),
      findsNothing,
    );
    await tester.tapAt(
      tester.getTopLeft(_row(_boolId)) + const Offset(12, 32),
    );
    await tester.pump();
    expect(source.edits, isEmpty);

    await _search(tester, 'Step_SageOfSpirit');
    expect(find.text(editTableFixedWidthReason), findsOneWidget);
    expect(
      find.descendant(
        of: _row(_enumId),
        matching: find.byWidgetPredicate(
          (Widget widget) => widget is SearchableSelect<dynamic>,
        ),
      ),
      findsNothing,
    );
    await tester.tapAt(
      tester.getTopLeft(_row(_enumId)) + const Offset(12, 32),
    );
    await tester.pump();
    expect(source.edits, isEmpty);
    expectNoOverflow(tester);
  });

  testWidgets('views from another slot stay read-only', (tester) async {
    final source = _FakeSaveTabSource(
      slot: const SaveSlotId('slot_00'),
      views: <TabFieldView>[
        ..._anchorViews().take(1),
        _view(
          id: _boolId,
          label: _boolLabel,
          kind: FieldKind.boolean,
          value: const BoolValue(true),
          span: const ByteSpan(508, 4),
          slot: const SaveSlotId('slot_01'),
        ),
      ],
    );
    await _pumpProgression(tester, source);
    await _search(tester, 'Dm_Deku_BossIn');

    expect(find.text(editTableNotStoredReason), findsOneWidget);
    expect(_row(_boolId), findsNothing);
    expect(_row('catalogue:0x00c0a2f6'), findsOneWidget);
  });

  testWidgets('catalogue failure is a warning banner and no editors', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpProgression(
      tester,
      source,
      tab: ProgressionTab(
        catalogueLoader: () async => throw StateError('groups.json missing'),
      ),
    );
    await tester.pump();

    final banner = tester.widget<Banner>(
      find.byKey(ProgressionTab.catalogueUnavailableKey),
    );
    expect(banner.variant, BannerVariant.warning);
    expect(find.byKey(EditTable.errorKey), findsOneWidget);
    expect(find.textContaining('groups.json missing'), findsWidgets);
    expect(find.byType(NumericField), findsNothing);
    expect(_row(_intId), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('no open save shows the shared empty state', (tester) async {
    final source = _FakeSaveTabSource(views: _anchorViews(), open: false);
    addTearDown(source.dispose);
    await pumpTab(tester, const ProgressionTab());

    expect(find.text('Open a save to begin'), findsOneWidget);
    expect(find.byType(EditTable), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('the table fits 1100x700 and 1280x720', (tester) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpProgression(tester, source);
    expectNoOverflow(tester);

    await _pumpProgression(
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

      testWidgets('an integer edit changes one span and undo restores bytes', (
        tester,
      ) async {
        final fixture = await _openFixture(tester);
        final source = fixture.source;
        final before = source.activeSlotBytes!;

        final view = source.allViews.firstWhere(
          (TabFieldView view) => view.descriptor.label == _intLabel,
        );
        expect(view.descriptor.id.value, _intId);
        expect(view.descriptor.span, const ByteSpan(_intOffset, 4));

        await pumpTab(
          tester,
          SaveTabScope(
            source: source,
            child: ProgressionTab(catalogue: _catalogue),
          ),
        );
        expect(
          find.text(
            '297 named fields · no hash-only fields · 297 of 297 editable',
          ),
          findsOneWidget,
        );
        await _search(tester, 'MeetSheikCount');

        final table = tester.widget<EditTable>(find.byType(EditTable));
        final row = table.rows.firstWhere(
          (EditTableRow row) => row.id == _intId,
        );
        expect(row.isEditable, isTrue);
        expect(row.intValue, isNotNull);
        expect(row.kind, EditCellKind.integer);

        final target = _differentValue(row);
        await tester.enterText(_cellInput(_intId), '$target');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(source.edits, hasLength(1));
        expect(source.edits.single, isA<SetScalar>());

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

      testWidgets('a string-cell edit is length-preserving by construction', (
        tester,
      ) async {
        final fixture = await _openFixture(tester);
        // The tab's own catalogue has no String field, so this test re-presents
        // a real 4-byte Bool as a string cell. Only presentation changes; the
        // id, span, and engine descriptor are the save's own.
        final source = _StringCellSource(
          fixture.source,
          label: _boolLabel,
          text: 'AB',
        );
        final before = source.activeSlotBytes!;

        final view = source.allViews.firstWhere(
          (TabFieldView view) => view.descriptor.label == _boolLabel,
        );
        expect(view.descriptor.kind, FieldKind.string);
        expect(view.descriptor.span.length, 4);

        await pumpTab(
          tester,
          SaveTabScope(
            source: source,
            child: ProgressionTab(catalogue: _catalogue),
          ),
        );
        await _search(tester, 'Dm_Deku_BossIn');

        final table = tester.widget<EditTable>(find.byType(EditTable));
        final row = table.rows.firstWhere(
          (EditTableRow row) => row.id == _boolId,
        );
        expect(row.kind, EditCellKind.string);
        expect(row.textValue, 'AB');
        expect(row.textCap, 3);

        await tester.enterText(_cellInput(_boolId), 'CD');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(source.edits, hasLength(1));
        final command = source.edits.single;
        expect(command, isA<SetBytes>());
        final written = command as SetBytes;
        expect(written.field, const FieldId(_boolId));
        expect(written.target, view.descriptor.span);
        expect(written.bytes, hasLength(view.descriptor.span.length));

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
  final workspace = Directory.systemTemp.createTempSync(
    'bomb_flower_progression_',
  );
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
