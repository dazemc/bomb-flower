import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/domain/core/edit_command.dart';
import 'package:bomb_flower/domain/core/field_metadata.dart';
import 'package:bomb_flower/domain/core/field_value.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_ui_state.dart';
import 'package:bomb_flower/presentation/shell/tabs/dungeons_tab.dart';
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

/// `Gohma_DefeatBoss`, a Bool at `progress.sav` offset 1172.
const String _bossId = 'progress.6b093b51';
const String _bossLabel = 'Gohma_DefeatBoss';
const int _bossOffset = 1172;

/// `DungeonInfo.FireTemple.IsGetBossKey`, a Bool at offset 4236.
const String _bossKeyId = 'progress.b72d73df';
const String _bossKeyLabel = 'DungeonInfo.FireTemple.IsGetBossKey';

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
  required FieldValue value,
  ByteSpan span = const ByteSpan(0, 4),
  FieldConfidence confidence = FieldConfidence.verified,
  bool readOnly = false,
}) {
  return TabFieldView(
    descriptor: FieldDescriptor(
      FieldId(id),
      const SaveSlotId('slot_00'),
      label,
      FieldKind.boolean,
      span,
      confidence,
      'schema:string',
      endianness: Endian.little,
      readOnly: readOnly,
    ),
    value: value,
    isDirty: false,
  );
}

List<TabFieldView> _anchorViews({bool boss = false}) => <TabFieldView>[
  _view(
    id: _bossId,
    label: _bossLabel,
    value: BoolValue(boss),
    span: const ByteSpan(_bossOffset, 4),
  ),
  _view(
    id: _bossKeyId,
    label: _bossKeyLabel,
    value: const BoolValue(false),
    span: const ByteSpan(4236, 4),
  ),
];

late FieldGroupsCatalogue _catalogue;

Future<void> _pumpDungeons(
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
      child: tab ?? DungeonsTab(catalogue: _catalogue),
    ),
    size: size,
  );
}

Finder _row(String id) => find.byKey(EditTable.rowKey(id));
Finder _cell(String id) => find.byKey(ValueKey<String>('edit-table-cell-$id'));

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(EditTable.searchFieldKey), text);
  await tester.pump();
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
    await _pumpDungeons(tester, source);

    expect(find.text('Dungeons'), findsOneWidget);
    expect(
      find.text('42 named fields · no hash-only fields · 2 of 42 editable'),
      findsOneWidget,
    );
    expect(find.byType(V1GapPanel), findsNothing);

    await _search(tester, 'Gohma');
    expect(_row(_bossId), findsOneWidget);
    expect(
      find.descendant(of: _row(_bossId), matching: find.text(_bossLabel)),
      findsOneWidget,
    );
    expectNoOverflow(tester);
  });

  testWidgets('search filters rows and reports the exact count readout', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpDungeons(tester, source);

    await _search(tester, 'Gohma_DefeatBoss');
    expect(_row(_bossId), findsOneWidget);
    expect(_row(_bossKeyId), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(EditTable.countKey)).data,
      'Showing 1 of 42 fields · 2 editable',
    );

    await _search(tester, 'IsGetBossKey');
    expect(_row(_bossKeyId), findsOneWidget);
    expect(_row(_bossId), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('a boolean toggle emits exactly one SetScalar', (tester) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpDungeons(tester, source);
    await _search(tester, 'Gohma');

    final table = tester.widget<EditTable>(find.byType(EditTable));
    final row = table.rows.firstWhere((EditTableRow row) => row.id == _bossId);
    expect(row.kind, EditCellKind.boolean);
    expect(
      row.boolValue,
      isFalse,
      reason: 'the typed seed comes from BoolValue',
    );
    expect(_cell(_bossId), findsOneWidget);

    await tester.tap(_cell(_bossId));
    await tester.pump();

    expect(source.edits, hasLength(1));
    final command = source.edits.single;
    expect(command, isA<SetScalar>());
    expect((command as SetScalar).field, const FieldId(_bossId));
    expect(command.value, 1, reason: 'false toggles to true and writes 1');
    expectNoOverflow(tester);
  });

  testWidgets('read-only rows state their reason and emit nothing', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      views: <TabFieldView>[
        _view(
          id: _bossKeyId,
          label: _bossKeyLabel,
          value: const BoolValue(false),
          span: const ByteSpan(4236, 4),
          confidence: FieldConfidence.inferred,
        ),
        _view(
          id: _bossId,
          label: _bossLabel,
          value: const BoolValue(true),
          span: const ByteSpan(_bossOffset, 4),
          readOnly: true,
        ),
      ],
    );
    await _pumpDungeons(tester, source);

    await _search(tester, 'IsGetBossKey');
    const inferredReason =
        'Field name is prefix-derived (inferred), so the meaning is not '
        'verified';
    expect(find.text(inferredReason), findsOneWidget);
    expect(
      find.descendant(of: _row(_bossKeyId), matching: find.byType(BrassToggle)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: _row(_bossKeyId),
        matching: find.byType(NumericField),
      ),
      findsNothing,
    );
    await tester.tapAt(
      tester.getTopLeft(_row(_bossKeyId)) + const Offset(12, 32),
    );
    await tester.pump();
    expect(source.edits, isEmpty);

    await _search(tester, 'Gohma_DefeatBoss');
    expect(find.text(editTableFixedWidthReason), findsOneWidget);
    expect(
      find.descendant(
        of: _row(_bossId),
        matching: find.byWidgetPredicate(
          (Widget widget) => widget is SearchableSelect<dynamic>,
        ),
      ),
      findsNothing,
    );
    await tester.tapAt(tester.getTopLeft(_row(_bossId)) + const Offset(12, 32));
    await tester.pump();
    expect(source.edits, isEmpty);
    expectNoOverflow(tester);
  });

  testWidgets('catalogue failure is a warning banner and no editors', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpDungeons(
      tester,
      source,
      tab: DungeonsTab(
        catalogueLoader: () async => throw StateError('groups.json missing'),
      ),
    );
    await tester.pump();

    final banner = tester.widget<Banner>(
      find.byKey(DungeonsTab.catalogueUnavailableKey),
    );
    expect(banner.variant, BannerVariant.warning);
    expect(find.byKey(EditTable.errorKey), findsOneWidget);
    expect(find.textContaining('groups.json missing'), findsWidgets);
    expect(find.byKey(EditTable.listKey), findsNothing);
    expect(find.byType(BrassToggle), findsNWidgets(2));
    expect(_row(_bossId), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('no open save shows the shared empty state', (tester) async {
    final source = _FakeSaveTabSource(views: _anchorViews(), open: false);
    addTearDown(source.dispose);
    await pumpTab(tester, const DungeonsTab());

    expect(find.text('Open a save to begin'), findsOneWidget);
    expect(find.byType(EditTable), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('the table fits 1100x700 and 1280x720', (tester) async {
    final source = _FakeSaveTabSource(views: _anchorViews());
    await _pumpDungeons(tester, source);
    expectNoOverflow(tester);

    await _pumpDungeons(
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

      testWidgets('a boolean toggle changes one span and undo restores bytes', (
        tester,
      ) async {
        final fixture = await _openFixture(tester);
        final source = fixture.source;
        final before = source.activeSlotBytes!;

        final view = source.allViews.firstWhere(
          (TabFieldView view) => view.descriptor.label == _bossLabel,
        );
        expect(view.descriptor.id.value, _bossId);
        expect(view.descriptor.span, const ByteSpan(_bossOffset, 4));

        await pumpTab(
          tester,
          SaveTabScope(
            source: source,
            child: DungeonsTab(catalogue: _catalogue),
          ),
        );
        expect(
          find.text(
            '42 named fields · no hash-only fields · 42 of 42 editable',
          ),
          findsOneWidget,
        );
        await _search(tester, 'Gohma');

        final table = tester.widget<EditTable>(find.byType(EditTable));
        final row = table.rows.firstWhere(
          (EditTableRow row) => row.id == _bossId,
        );
        expect(row.isEditable, isTrue);
        expect(row.boolValue, isNotNull);
        expect(row.kind, EditCellKind.boolean);

        await tester.tap(_cell(_bossId));
        await tester.pump();

        expect(source.edits, hasLength(1));
        final command = source.edits.single;
        expect(command, isA<SetScalar>());
        expect((command as SetScalar).field, const FieldId(_bossId));
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
    'bomb_flower_dungeons_',
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
