import 'package:bomb_flower/domain/core/edit_command.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_scope.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_source.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory source. It imports no `dart:io`, which is the compile-time
/// proof that the port can be implemented without file access.
final class _FakeSaveTabSource extends ChangeNotifier implements SaveTabSource {
  _FakeSaveTabSource({
    this.activeSlot,
    this.isOpen = true,
    this.isDirty = false,
    this.changedFieldCount = 0,
    this.newestSlot,
    List<SlotAge> slotAges = const <SlotAge>[],
    Map<EditorTabGroup, List<TabFieldView>> views =
        const <EditorTabGroup, List<TabFieldView>>{},
  }) : slotAges = List<SlotAge>.unmodifiable(slotAges),
       _views = Map<EditorTabGroup, List<TabFieldView>>.of(views);

  @override
  final SaveSlotId? activeSlot;

  @override
  final bool isOpen;

  @override
  final bool isDirty;

  @override
  final int changedFieldCount;

  @override
  final SaveSlotId? newestSlot;

  @override
  final List<SlotAge> slotAges;

  final Map<EditorTabGroup, List<TabFieldView>> _views;

  /// Commands received through [edit], in order.
  final List<EditCommand> edits = <EditCommand>[];

  /// How many times [undo] was called.
  int undoCount = 0;

  /// How many times [redo] was called.
  int redoCount = 0;

  @override
  bool canUndo = false;

  @override
  bool canRedo = false;

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

void main() {
  testWidgets('maybeOf returns null outside a scope', (tester) async {
    SaveTabSource? observed = _FakeSaveTabSource();
    await tester.pumpWidget(
      Builder(
        builder: (BuildContext context) {
          observed = SaveTabScope.maybeOf(context);
          return const SizedBox.shrink();
        },
      ),
    );

    expect(observed, isNull);
  });

  testWidgets('of outside a scope throws a StateError naming SaveTabScope', (
    tester,
  ) async {
    Object? error;
    await tester.pumpWidget(
      Builder(
        builder: (BuildContext context) {
          try {
            SaveTabScope.of(context);
          } on Object catch (caught) {
            error = caught;
          }
          return const SizedBox.shrink();
        },
      ),
    );

    expect(error, isA<StateError>());
    expect(error.toString(), contains('SaveTabScope'));
  });

  testWidgets('inside the scope maybeOf and of return the same instance', (
    tester,
  ) async {
    final fake = _FakeSaveTabSource();
    addTearDown(fake.dispose);
    SaveTabSource? viaMaybe;
    SaveTabSource? viaOf;

    await tester.pumpWidget(
      SaveTabScope(
        source: fake,
        child: Builder(
          builder: (BuildContext context) {
            viaMaybe = SaveTabScope.maybeOf(context);
            viaOf = SaveTabScope.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(viaMaybe, same(fake));
    expect(viaOf, same(fake));
  });

  testWidgets('notifyListeners propagates through changes', (tester) async {
    final fake = _FakeSaveTabSource();
    addTearDown(fake.dispose);
    var notifications = 0;
    SaveTabSource? scoped;

    await tester.pumpWidget(
      SaveTabScope(
        source: fake,
        child: Builder(
          builder: (BuildContext context) {
            scoped = SaveTabScope.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    scoped!.changes.addListener(() => notifications++);
    fake.notifyListeners();

    expect(notifications, 1);
  });

  testWidgets('viewsFor and allViews return what the fake supplies', (
    tester,
  ) async {
    final overviewViews = <TabFieldView>[];
    final fake = _FakeSaveTabSource(
      views: <EditorTabGroup, List<TabFieldView>>{
        EditorTabGroup.overview: overviewViews,
      },
    );
    addTearDown(fake.dispose);

    expect(fake.viewsFor(EditorTabGroup.overview), same(overviewViews));
    expect(fake.viewsFor(EditorTabGroup.inventory), isEmpty);
    expect(fake.allViews, isEmpty);
  });

  test('the port can be implemented without dart:io (compile-time proof)', () {
    final modifiedAt = DateTime.utc(2026, 11, 22);
    final SaveTabSource source = _FakeSaveTabSource(
      activeSlot: SaveSlotId.account,
      isOpen: false,
      isDirty: true,
      changedFieldCount: 3,
      newestSlot: SaveSlotId.options,
      slotAges: <SlotAge>[
        SlotAge(
          slot: SaveSlotId.account,
          progressPath: 'progress.sav',
          modifiedAt: modifiedAt,
        ),
      ],
    );

    expect(source, isA<SaveTabSource>());
    expect(source.changes, same(source));
    expect(source.activeSlot, SaveSlotId.account);
    expect(source.isOpen, isFalse);
    expect(source.isDirty, isTrue);
    expect(source.changedFieldCount, 3);
    expect(source.newestSlot, SaveSlotId.options);
    expect(source.slotAges.single.modifiedAt, modifiedAt);
  });
}
