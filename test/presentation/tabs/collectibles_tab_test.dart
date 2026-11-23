import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/domain/core/edit_command.dart';
import 'package:bomb_flower/domain/core/field_metadata.dart';
import 'package:bomb_flower/domain/core/field_value.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_ui_state.dart';
import 'package:bomb_flower/presentation/shell/tabs/collectibles_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/v1_gap_panel.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_scope.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_source.dart';
import 'package:bomb_flower/presentation/tabs_support/session_save_tab_source.dart';
import 'package:bomb_flower/presentation/widgets/common/banner.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_toggle.dart';
import 'package:bomb_flower/presentation/widgets/controls/numeric_field.dart';
import 'package:bomb_flower/presentation/widgets/data/edit_table.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Banner;

import 'support/tab_test_harness.dart';
import 'support/ui_flow_fixture.dart';

/// `PouchData.Item_Token_Gold.StockNum`, the named token stock count.
const String _stockLabel = 'PouchData.Item_Token_Gold.StockNum';
const String _stockId = 'collectibles.stock';

/// `HyruleField_Defeat_BigPoe_01`, one of the ten Big Poe defeat flags.
const String _poeLabel = 'HyruleField_Defeat_BigPoe_01';
const String _poeId = 'collectibles.poe01';

/// `GatheringTokenGold_Near`, a Gold Skulltula event flag.
const String _tokenLabel = 'GatheringTokenGold_Near';
const String _tokenId = 'collectibles.tokenNear';

/// An in-memory port with the current byte accessors and an edit recorder.
final class _FakeSaveTabSource extends ChangeNotifier implements SaveTabSource {
  _FakeSaveTabSource({this.views = const <TabFieldView>[], this.open = true});

  final List<TabFieldView> views;
  final bool open;

  /// Commands received through [edit], in order.
  final List<EditCommand> edits = <EditCommand>[];

  @override
  bool get isOpen => open;

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
      readOnly: readOnly,
    ),
    value: value,
    isDirty: false,
  );
}

List<TabFieldView> _anchorViews() => <TabFieldView>[
  _view(
    id: _stockId,
    label: _stockLabel,
    kind: FieldKind.integer,
    value: const IntValue(2),
    // Test input, not a schema claim: the fixture's own value is measured.
    min: 0,
    max: 99,
  ),
  _view(
    id: _poeId,
    label: _poeLabel,
    kind: FieldKind.boolean,
    value: const BoolValue(false),
  ),
  _view(
    id: _tokenId,
    label: _tokenLabel,
    kind: FieldKind.boolean,
    value: const BoolValue(true),
    confidence: FieldConfidence.inferred,
  ),
];

late FieldGroupsCatalogue _catalogue;

Future<void> _pumpCollectibles(
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
      child: tab ?? CollectiblesTab(catalogue: _catalogue),
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

String _countReadout(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(EditTable.countKey)).data!;

EditTableRow _tableRow(WidgetTester tester, String id) {
  final table = tester.widget<EditTable>(find.byType(EditTable));
  return table.rows.firstWhere((EditTableRow row) => row.id == id);
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

/// The longest collectibles catalogue name, measured at runtime.
String _longestName() {
  return _catalogue
      .forTab(EditorTabGroup.collectibles)
      .expand((FieldGroup group) => group.fields)
      .map((FieldRef field) => field.name)
      .reduce((String a, String b) => a.length >= b.length ? a : b);
}

void main() {
  setUpAll(() async {
    _catalogue = FieldGroupsCatalogue.load(
      await File('assets/fields/groups.json').readAsString(),
    );
  });

  testWidgets('renders the catalogue header, count label, and anchor row', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpCollectibles(tester, source);

    expect(find.text('Collectibles'), findsOneWidget);

    final table = tester.widget<EditTable>(find.byType(EditTable));
    final named = table.rows.length;
    final editable = table.rows
        .where((EditTableRow row) => row.isEditable)
        .length;
    final stats = _catalogue.stats.forTab(EditorTabGroup.collectibles);
    final hashOnly = stats.unnamed == 0
        ? 'no hash-only fields'
        : '${stats.unnamed} hash-only fields';

    // Measured, never literal: named comes from the built rows and the
    // hash-only phrase comes from the catalogue's own stat.
    expect(named, 159);
    expect(stats.named, 159);
    expect(stats.unnamed, 0);
    expect(stats.groups, 6);
    expect(
      find.text(
        '$named named fields · $hashOnly · $editable of $named editable',
      ),
      findsOneWidget,
    );
    expect(editable, 2, reason: 'two verified anchor views are editable');
    expect(find.byType(V1GapPanel), findsNothing);

    await _search(tester, 'StockNum');
    expect(_row(_stockId), findsOneWidget);
    expect(find.text(_stockLabel), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('the 159-row table is virtualised', (tester) async {
    final source = _FakeSaveTabSource();
    await _pumpCollectibles(tester, source);

    final table = tester.widget<EditTable>(find.byType(EditTable));
    expect(table.rows, hasLength(159));
    expect(_countReadout(tester), 'Showing 159 of 159 fields · 0 editable');

    // The first row is inside the viewport; the last is far outside it.
    expect(_row(table.rows.first.id), findsOneWidget);
    expect(
      _row(table.rows.last.id),
      findsNothing,
      reason: 'the list must not build every one of the 159 rows',
    );
    expectNoOverflow(tester);
  });

  testWidgets('search filters rows and reports the exact count readout', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpCollectibles(tester, source);

    await _search(tester, 'StockNum');
    expect(_row(_stockId), findsOneWidget);
    expect(_row(_poeId), findsNothing);
    expect(_countReadout(tester), 'Showing 1 of 159 fields · 2 editable');

    await _search(tester, 'Defeat_BigPoe_01');
    expect(_row(_poeId), findsOneWidget);
    expect(_row(_stockId), findsNothing);
    expect(_countReadout(tester), 'Showing 1 of 159 fields · 2 editable');
    expectNoOverflow(tester);
  });

  testWidgets('integer commit emits exactly one SetScalar; bad text none', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpCollectibles(tester, source);
    await _search(tester, 'StockNum');

    final row = _tableRow(tester, _stockId);
    expect(row.kind, EditCellKind.integer);
    expect(row.intValue, 2, reason: 'the typed seed comes from IntValue');
    expect(_cell(_stockId), findsOneWidget);

    // A non-integer never reaches the engine.
    await tester.enterText(_cellInput(_stockId), 'not-a-number');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(source.edits, isEmpty);

    // Enter commits one whole number.
    final target = _differentValue(row);
    await tester.enterText(_cellInput(_stockId), '$target');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(source.edits, hasLength(1));
    final command = source.edits.single;
    expect(command, isA<SetScalar>());
    expect((command as SetScalar).field, const FieldId(_stockId));
    expect(command.value, target);
    expectNoOverflow(tester);
  });

  testWidgets('a boolean commit emits exactly one SetScalar', (tester) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpCollectibles(tester, source);
    await _search(tester, 'Defeat_BigPoe_01');

    expect(_tableRow(tester, _poeId).kind, EditCellKind.boolean);
    await tester.tap(_cell(_poeId));
    await tester.pump();

    expect(source.edits, hasLength(1));
    final command = source.edits.single;
    expect(command, isA<SetScalar>());
    expect((command as SetScalar).field, const FieldId(_poeId));
    expect(command.value, 1);
    expectNoOverflow(tester);
  });

  testWidgets('read-only rows state their reason and emit nothing', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpCollectibles(tester, source);

    await _search(tester, 'GatheringTokenGold_Near');
    const inferredReason =
        'Field name is prefix-derived (inferred), so the meaning is not '
        'verified';
    expect(find.text(inferredReason), findsOneWidget);
    expect(_tableRow(tester, _tokenId).isEditable, isFalse);
    expect(
      find.descendant(of: _row(_tokenId), matching: find.byType(BrassToggle)),
      findsNothing,
    );
    expect(
      find.descendant(of: _row(_tokenId), matching: find.byType(NumericField)),
      findsNothing,
    );
    await tester.tapAt(
      tester.getTopLeft(_row(_tokenId)) + const Offset(12, 32),
    );
    await tester.pump();
    expect(source.edits, isEmpty);
    expectNoOverflow(tester);
  });

  testWidgets('a field absent from the save stays visible and read-only', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <TabFieldView>[_anchorViews().first],
    );
    await _pumpCollectibles(tester, source);

    await _search(tester, 'Defeat_BigPoe_01');
    expect(find.text(editTableNotStoredReason), findsOneWidget);
    final missing = _tableRow(tester, 'catalogue:0xacdfefef');
    expect(missing.label, _poeLabel);
    expect(missing.isEditable, isFalse);
    expect(_row(_poeId), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('the longest catalogue name cannot overflow its label cell', (
    tester,
  ) async {
    final longName = _longestName();
    final source = _FakeSaveTabSource(
      views: <TabFieldView>[
        _view(
          id: 'collectibles.longest',
          label: longName,
          kind: FieldKind.boolean,
          value: const BoolValue(false),
        ),
      ],
    );

    Future<void> exercise() async {
      await _search(tester, longName);
      final model = _tableRow(tester, 'collectibles.longest');
      expect(model.label, longName, reason: 'the model never truncates');
      final label = tester.widget<Text>(
        find.descendant(
          of: _row('collectibles.longest'),
          matching: find.text(longName),
        ),
      );
      expect(label.maxLines, 1);
      expect(label.overflow, TextOverflow.ellipsis);
      expectNoOverflow(tester);
    }

    await _pumpCollectibles(tester, source);
    await exercise();

    // The narrowest mandated viewport, then the other one.
    await _pumpCollectibles(
      tester,
      source,
      size: tabTestViewports[0],
      disposeSource: false,
    );
    await exercise();

    await _pumpCollectibles(
      tester,
      source,
      size: tabTestViewports[1],
      disposeSource: false,
    );
    await exercise();
  });

  testWidgets('catalogue failure is a warning banner and no editors', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpCollectibles(
      tester,
      source,
      tab: CollectiblesTab(
        catalogueLoader: () async => throw StateError('groups.json missing'),
      ),
    );
    await tester.pump();

    final banner = tester.widget<Banner>(
      find.byKey(CollectiblesTab.catalogueUnavailableKey),
    );
    expect(banner.variant, BannerVariant.warning);
    expect(find.byKey(EditTable.errorKey), findsOneWidget);
    expect(find.textContaining('groups.json missing'), findsWidgets);
    expect(find.byType(NumericField), findsNothing);
    expect(_row(_stockId), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('no open save shows the shared empty state', (tester) async {
    final source = _FakeSaveTabSource(views: _anchorViews(), open: false);
    addTearDown(source.dispose);
    await pumpTab(tester, const CollectiblesTab());

    expect(find.text('Open a save to begin'), findsOneWidget);
    expect(find.byType(EditTable), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('the table fits 1100x700 and 1280x720', (tester) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpCollectibles(tester, source);
    expectNoOverflow(tester);

    await _pumpCollectibles(
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

      testWidgets('a collectible edit stays inside one span and undoes', (
        tester,
      ) async {
        final fixture = await _openFixture(tester);
        final source = fixture.source;
        final before = source.activeSlotBytes!;

        await pumpTab(
          tester,
          SaveTabScope(
            source: source,
            child: CollectiblesTab(catalogue: _catalogue),
          ),
        );

        final table = tester.widget<EditTable>(find.byType(EditTable));
        final editable = table.rows
            .where((EditTableRow row) => row.isEditable)
            .toList(growable: false);
        expect(
          editable,
          isNotEmpty,
          reason: 'the fixture must supply at least one editable row',
        );

        final row = editable.first;
        final view = source.allViews.firstWhere(
          (TabFieldView view) => view.descriptor.label == row.label,
        );
        await _search(tester, row.label);

        if (row.kind == EditCellKind.integer) {
          final target = _differentValue(row);
          await tester.enterText(_cellInput(row.id), '$target');
          await tester.testTextInput.receiveAction(TextInputAction.done);
        } else {
          expect(row.kind, EditCellKind.boolean);
          await tester.tap(_cell(row.id));
        }
        await tester.pump();

        expect(source.edits, hasLength(1));
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

      testWidgets('the fixture measures 159 named, 159 editable rows and no '
          'hash-only fields', (tester) async {
        final fixture = await _openFixture(tester);
        final stats = _catalogue.stats.forTab(EditorTabGroup.collectibles);

        // The catalogue is the source of the row set; assert it first so a
        // changed groups.json fails here rather than against a stale literal.
        expect(stats.named, 159);
        expect(stats.unnamed, 0);

        await pumpTab(
          tester,
          SaveTabScope(
            source: fixture.source,
            child: CollectiblesTab(catalogue: _catalogue),
          ),
        );

        final rows = tester.widget<EditTable>(find.byType(EditTable)).rows;
        expect(rows, hasLength(stats.named));
        expect(rows, hasLength(159));

        final editable = rows
            .where((EditTableRow row) => row.isEditable)
            .toList(growable: false);
        expect(editable, hasLength(159));
        expect(editable, hasLength(rows.length));

        // The header count line is the tab's own measured claim.
        expect(
          find.text(
            '159 named fields · no hash-only fields · '
            '159 of 159 editable',
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
  final workspace = Directory.systemTemp.createTempSync(
    'bomb_flower_collectibles_',
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
