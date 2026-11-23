import 'dart:typed_data';

import 'package:bomb_flower/presentation/bloc/shell/shell_cubit.dart';
import 'package:bomb_flower/presentation/bloc/shell/tab_definition.dart';
import 'package:bomb_flower/presentation/shell/app_shell.dart';
import 'package:bomb_flower/presentation/shell/tabs/inventory_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/settings_tab.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_scope.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_source.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/domain/core/edit_command.dart';
import 'package:bomb_flower/domain/core/field_metadata.dart';
import 'package:bomb_flower/domain/core/field_value.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A minimal in-memory source: enough for the shell, no engine, no files.
final class _StubSource extends ChangeNotifier implements SaveTabSource {
  _StubSource(this._views);

  final List<TabFieldView> _views;

  @override
  bool get isOpen => true;

  @override
  String? get rootPath => '/tmp/bomb-flower-liveness';

  @override
  SaveSlotId? get activeSlot => null;

  @override
  Uint8List? get activeSlotBytes => Uint8List(0);

  @override
  Uint8List? bytesFor(SaveSlotId slot) => Uint8List(0);

  @override
  Listenable get changes => this;

  @override
  List<TabFieldView> viewsFor(EditorTabGroup group) => const <TabFieldView>[];

  @override
  Iterable<TabFieldView> get allViews => _views;

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
  void edit(EditCommand command) {}

  @override
  void undo() {}

  @override
  void redo() {}
}

int _offset = 0;

List<TabFieldView> _acquisitionViews(int count) {
  return <TabFieldView>[
    for (var index = 0; index < count; index++)
      TabFieldView(
        descriptor: FieldDescriptor(
          FieldId('IsGet.Item_$index'),
          SaveSlotId.progress(0),
          'IsGet.Item_$index',
          FieldKind.boolean,
          ByteSpan(_offset++, 1),
          FieldConfidence.verified,
          'schema:test (verified)',
        ),
        value: BoolValue(index.isEven),
        isDirty: false,
      ),
  ];
}

void _useView(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Counts rebuilds of [T] while installed.
int Function() _countBuilds<T extends Widget>() {
  var builds = 0;
  debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {
    if (element.widget is T) {
      builds++;
    }
  };
  addTearDown(() => debugOnRebuildDirtyWidget = null);
  return () => builds;
}

/// Pumps the real shell over [source] at a desktop viewport.
Future<ShellCubit> _pumpShell(
  WidgetTester tester,
  SaveTabSource source, {
  Size size = const Size(1100, 700),
}) async {
  _useView(tester, size);
  final shell = ShellCubit(windowChromeEnabled: false);
  addTearDown(shell.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      home: BlocProvider<ShellCubit>.value(
        value: shell,
        child: SaveTabScope(
          source: source,
          child: AppShell(settingsStore: InMemorySettingsStore()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
  return shell;
}

Finder _page(ShellTab tab, {bool onstage = true}) => find.byKey(
  Key('tab-page-${tab.name}'),
  skipOffstage: onstage ? true : false,
);

void main() {
  testWidgets('no tab page exists until its tab is first selected', (
    tester,
  ) async {
    final source = _StubSource(_acquisitionViews(4));
    final builds = _countBuilds<InventoryTab>();
    final shell = await _pumpShell(tester, source);

    // Overview is the starting tab; the other ten pages were never built.
    expect(_page(ShellTab.overview), findsOneWidget);
    expect(_page(ShellTab.inventory, onstage: false), findsNothing);
    expect(_page(ShellTab.settings, onstage: false), findsNothing);
    expect(builds(), 0);

    shell.selectTab(ShellTab.inventory);
    await tester.pumpAndSettle();

    expect(_page(ShellTab.inventory), findsOneWidget);
    expect(builds(), greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a revisit reuses the mounted page instead of rebuilding it', (
    tester,
  ) async {
    final source = _StubSource(_acquisitionViews(4));
    final builds = _countBuilds<InventoryTab>();
    final shell = await _pumpShell(tester, source);

    shell.selectTab(ShellTab.inventory);
    await tester.pumpAndSettle();
    final firstVisitState = tester.state<State>(_page(ShellTab.inventory));
    final buildsAfterFirstVisit = builds();
    expect(buildsAfterFirstVisit, greaterThan(0));

    shell.selectTab(ShellTab.settings);
    await tester.pumpAndSettle();

    // Off stage, so the ordinary finder no longer sees it ...
    expect(_page(ShellTab.inventory), findsNothing);
    // ... but the element and its state are still mounted.
    expect(_page(ShellTab.inventory, onstage: false), findsOneWidget);

    shell.selectTab(ShellTab.inventory);
    await tester.pumpAndSettle();

    expect(_page(ShellTab.settings, onstage: false), findsOneWidget);
    expect(_page(ShellTab.inventory), findsOneWidget);
    expect(
      identical(
        tester.state<State>(_page(ShellTab.inventory)),
        firstVisitState,
      ),
      isTrue,
      reason: 'a revisit must keep the page state, not re-create it',
    );
    expect(
      builds(),
      buildsAfterFirstVisit,
      reason: 'a revisit must not rebuild the page body',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scrolling Inventory for 60 frames scrolls and rebuilds nothing',
    (tester) async {
      final source = _StubSource(_acquisitionViews(300));
      final builds = _countBuilds<InventoryTab>();
      final shell = await _pumpShell(tester, source);

      shell.selectTab(ShellTab.inventory);
      await tester.pumpAndSettle();
      expect(builds(), greaterThan(0));
      final buildsAfterOpen = builds();

      final anchor = find.text('Acquisition');
      final before = tester.getTopLeft(anchor);

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      tester.binding.handlePointerEvent(
        pointer.hover(tester.getCenter(_page(ShellTab.inventory))),
      );
      for (var frame = 0; frame < 60; frame++) {
        tester.binding.handlePointerEvent(pointer.scroll(const Offset(0, 40)));
        await tester.pump();
      }

      final after = tester.getTopLeft(anchor);
      expect(
        after.dy,
        lessThan(before.dy),
        reason: 'the wheel events must actually move the page',
      );
      expect(
        builds(),
        buildsAfterOpen,
        reason: 'scrolling must not rebuild the tab body',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
