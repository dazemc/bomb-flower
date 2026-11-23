import 'dart:typed_data';

import 'package:bomb_flower/domain/core/edit_command.dart';
import 'package:bomb_flower/domain/core/field_metadata.dart';
import 'package:bomb_flower/domain/core/field_value.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/presentation/shell/tabs/overview_tab.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_scope.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_source.dart';
import 'package:bomb_flower/presentation/widgets/common/banner.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_toggle.dart';
import 'package:bomb_flower/presentation/widgets/controls/numeric_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Banner;

import 'support/tab_test_harness.dart';

/// An in-memory port. It records undo, redo, and edit calls so a test can prove
/// the overview is a read-only dashboard.
final class _FakeSaveTabSource extends ChangeNotifier implements SaveTabSource {
  _FakeSaveTabSource({
    this.isOpen = true,
    this.activeSlot,
    this.isDirty = false,
    this.changedFieldCount = 0,
    this.newestSlot,
    this.canUndo = false,
    this.canRedo = false,
    List<TabFieldView> views = const <TabFieldView>[],
  }) : _views = List<TabFieldView>.of(views);

  @override
  final bool isOpen;

  @override
  final SaveSlotId? activeSlot;

  @override
  final bool isDirty;

  @override
  final int changedFieldCount;

  @override
  final SaveSlotId? newestSlot;

  @override
  bool canUndo;

  @override
  bool canRedo;

  final List<TabFieldView> _views;

  /// Commands received through [edit], in order.
  final List<EditCommand> edits = <EditCommand>[];

  /// How many times [undo] was called.
  int undoCount = 0;

  /// How many times [redo] was called.
  int redoCount = 0;

  @override
  String? get rootPath => isOpen ? '/tmp/bomb-flower-save' : null;

  @override
  Uint8List? get activeSlotBytes => isOpen ? Uint8List(0) : null;

  @override
  Uint8List? bytesFor(SaveSlotId slot) =>
      isOpen && slot == activeSlot ? Uint8List(0) : null;

  @override
  Listenable get changes => this;

  @override
  List<SlotAge> get slotAges => const <SlotAge>[];

  @override
  List<TabFieldView> viewsFor(EditorTabGroup group) {
    return group == EditorTabGroup.overview ? _views : const <TabFieldView>[];
  }

  @override
  Iterable<TabFieldView> get allViews => _views;

  @override
  void edit(EditCommand command) => edits.add(command);

  @override
  void undo() => undoCount++;

  @override
  void redo() => redoCount++;
}

TabFieldView _view(
  String label,
  FieldValue? value, {
  bool isDirty = false,
  String? issueMessage,
}) {
  return TabFieldView(
    descriptor: FieldDescriptor(
      FieldId(label),
      SaveSlotId.progress(0),
      label,
      _kindFor(value),
      const ByteSpan(0, 4),
      FieldConfidence.verified,
      'schema:test',
    ),
    value: value,
    isDirty: isDirty,
    issueMessage: issueMessage,
  );
}

FieldKind _kindFor(FieldValue? value) {
  return switch (value) {
    BoolValue() => FieldKind.boolean,
    StringValue() => FieldKind.string,
    _ => FieldKind.integer,
  };
}

List<TabFieldView> _populatedViews() {
  return <TabFieldView>[
    _view('PlayerStatus.Life', const IntValue(14)),
    _view('PlayerStatus.MaxLife', const IntValue(20)),
    _view('PlayerStatus.CurrentRupee', const IntValue(120572)),
    _view('PlayerStatus.MP', const IntValue(0)),
    _view('PlayerStatus.MPMax', const IntValue(48)),
    _view('Sequence_CurrentBanc', const StringValue('KokiriForest_Child')),
    _view('Sequence_IsChildhood', const BoolValue(true), isDirty: true),
  ];
}

Finder _textInKey(Key key, String text) {
  return find.descendant(of: find.byKey(key), matching: find.text(text));
}

Future<void> _pumpOverview(WidgetTester tester, _FakeSaveTabSource source) {
  addTearDown(source.dispose);
  return pumpTab(
    tester,
    SaveTabScope(source: source, child: const OverviewTab()),
  );
}

/// The dashboard scrolls at 700 px height, so the history controls start below
/// the viewport. Scroll the control into view before tapping it.
Future<void> _tapHistoryControl(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets('populated overview renders every stored value', (tester) async {
    final source = _FakeSaveTabSource(
      activeSlot: SaveSlotId.progress(2),
      views: _populatedViews(),
      isDirty: true,
      changedFieldCount: 2,
    );
    await _pumpOverview(tester, source);

    expect(_textInKey(const Key('overview-life'), '3.5 / 5'), findsOneWidget);
    expect(_textInKey(const Key('overview-life'), 'hearts'), findsOneWidget);
    expect(_textInKey(const Key('overview-rupees'), '120,572'), findsOneWidget);
    expect(_textInKey(const Key('overview-mp'), '0'), findsOneWidget);
    expect(_textInKey(const Key('overview-mp'), 'raw units'), findsOneWidget);
    expect(_textInKey(const Key('overview-mp-max'), '48'), findsOneWidget);
    expect(
      _textInKey(const Key('overview-banc'), 'KokiriForest_Child'),
      findsOneWidget,
    );
    expect(_textInKey(const Key('overview-age'), 'Child'), findsOneWidget);
    expect(_textInKey(const Key('overview-slot'), 'slot_02'), findsOneWidget);
    expect(
      _textInKey(const Key('overview-dirty'), '2 modified fields'),
      findsOneWidget,
    );
    expectNoOverflow(tester);
  });

  testWidgets('closed source shows the open-a-save empty state', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(isOpen: false);
    await _pumpOverview(tester, source);

    expect(find.text('Open a save to begin'), findsOneWidget);
    expect(find.byKey(const Key('overview-life')), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('no scope renders the empty state instead of crashing', (
    tester,
  ) async {
    await pumpTab(tester, const OverviewTab());

    expect(tester.takeException(), isNull);
    expect(find.text('Open a save to begin'), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('newest slot mismatch warns and names both slots', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      activeSlot: SaveSlotId.progress(0),
      newestSlot: SaveSlotId.progress(2),
      views: _populatedViews(),
    );
    await _pumpOverview(tester, source);

    expect(find.text('Newer save on disk'), findsOneWidget);
    final banner = tester.widget<Banner>(
      find.widgetWithText(Banner, 'Newer save on disk'),
    );
    expect(banner.variant, BannerVariant.warning);
    expect(banner.message, contains('slot_00'));
    expect(banner.message, contains('slot_02'));
  });

  testWidgets('up-to-date slots show no warning', (tester) async {
    final source = _FakeSaveTabSource(
      activeSlot: SaveSlotId.progress(0),
      newestSlot: SaveSlotId.progress(0),
      views: _populatedViews(),
    );
    await _pumpOverview(tester, source);

    expect(find.text('Newer save on disk'), findsNothing);
  });

  testWidgets('missing fields show the explicit unavailable tile', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(
      activeSlot: SaveSlotId.progress(0),
      views: <TabFieldView>[
        _view('PlayerStatus.Life', const IntValue(12)),
        _view('PlayerStatus.MaxLife', const IntValue(20)),
      ],
    );
    await _pumpOverview(tester, source);

    expect(_textInKey(const Key('overview-life'), '3 / 5'), findsOneWidget);
    for (final key in <Key>[
      const Key('overview-rupees'),
      const Key('overview-mp'),
      const Key('overview-mp-max'),
      const Key('overview-banc'),
      const Key('overview-age'),
    ]) {
      expect(
        _textInKey(key, 'Not stored in this save'),
        findsOneWidget,
        reason: '$key should be explicit about the missing field',
      );
    }
    expectNoOverflow(tester);
  });

  testWidgets('negative life is unavailable, not an exception', (tester) async {
    final source = _FakeSaveTabSource(
      activeSlot: SaveSlotId.progress(0),
      views: <TabFieldView>[
        _view('PlayerStatus.Life', const IntValue(-4)),
        _view('PlayerStatus.MaxLife', const IntValue(20)),
      ],
    );
    await _pumpOverview(tester, source);

    expect(tester.takeException(), isNull);
    expect(
      _textInKey(const Key('overview-life'), 'Not stored in this save'),
      findsOneWidget,
    );
  });

  testWidgets('issueMessage renders a danger banner', (tester) async {
    final source = _FakeSaveTabSource(
      activeSlot: SaveSlotId.progress(0),
      views: <TabFieldView>[
        _view(
          'PlayerStatus.Life',
          const IntValue(14),
          issueMessage: 'Life is above the saved maximum.',
        ),
        _view('PlayerStatus.MaxLife', const IntValue(20)),
      ],
    );
    await _pumpOverview(tester, source);

    expect(find.text('Field issue'), findsOneWidget);
    final banner = tester.widget<Banner>(
      find.widgetWithText(Banner, 'Field issue'),
    );
    expect(banner.variant, BannerVariant.danger);
    expect(banner.message, 'Life is above the saved maximum.');
  });

  testWidgets('undo and redo taps reach the port only when enabled', (
    tester,
  ) async {
    final source = _FakeSaveTabSource(activeSlot: SaveSlotId.progress(0));
    await _pumpOverview(tester, source);

    await _tapHistoryControl(tester, const Key('overview-undo'));
    await _tapHistoryControl(tester, const Key('overview-redo'));
    expect(source.undoCount, 0);
    expect(source.redoCount, 0);

    source.canUndo = true;
    source.canRedo = true;
    source.notifyListeners();
    await tester.pump();

    await _tapHistoryControl(tester, const Key('overview-undo'));
    await _tapHistoryControl(tester, const Key('overview-redo'));
    expect(source.undoCount, 1);
    expect(source.redoCount, 1);
  });

  testWidgets('overview is read-only and never calls edit', (tester) async {
    final source = _FakeSaveTabSource(
      activeSlot: SaveSlotId.progress(0),
      views: _populatedViews(),
      canUndo: true,
      canRedo: true,
    );
    await _pumpOverview(tester, source);

    expect(source.edits, isEmpty);
    expect(find.byType(NumericField), findsNothing);
    expect(find.byType(BrassToggle), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('dashboard fits 1100x700 without overflow', (tester) async {
    final source = _FakeSaveTabSource(
      activeSlot: SaveSlotId.progress(2),
      newestSlot: SaveSlotId.progress(1),
      views: _populatedViews(),
      isDirty: true,
      changedFieldCount: 12,
      canUndo: true,
      canRedo: true,
    );
    addTearDown(source.dispose);

    await pumpTab(
      tester,
      SaveTabScope(source: source, child: const OverviewTab()),
      size: const Size(1100, 700),
    );

    expectNoOverflow(tester);
  });
}
