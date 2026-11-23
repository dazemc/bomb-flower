// Proves that no converted save tab falls back to the read-only `V1GapPanel`.
//
// This file used to assert that Collectibles and Flags rendered the read-only
// gap panel. Both tabs now render the shared virtualised `EditTable` instead:
// one row per catalogue field, editable only where the save's own descriptor
// says so. The two cases were kept — only their assertions changed — so a
// regression that reverts either tab to `V1GapPanel` fails here.
//
// Nothing in `lib/` instantiates `V1GapPanel` any more, so the class is
// retained only for this file and backwards compatibility, not as the current
// surface of any tab.
import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/domain/core/edit_command.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/presentation/bloc/shell/tab_definition.dart';
import 'package:bomb_flower/presentation/shell/tabs/collectibles_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/flags_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/v1_gap_panel.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_scope.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_source.dart';
import 'package:bomb_flower/presentation/widgets/common/section_header.dart';
import 'package:bomb_flower/presentation/widgets/data/edit_table.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Banner;

import 'support/tab_test_harness.dart';

/// An in-memory port: open, no fields, and no bytes behind it.
///
/// The tab's rows come from the injected catalogue, not the source, so an
/// empty source still renders every catalogue row; it just leaves each one
/// without a resolved value.
final class _FakeSaveTabSource extends ChangeNotifier implements SaveTabSource {
  _FakeSaveTabSource();

  @override
  bool get isOpen => true;

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
  String? get rootPath => '/tmp/fake-save';

  @override
  Uint8List? get activeSlotBytes => Uint8List(0);

  @override
  Uint8List? bytesFor(SaveSlotId slot) => null;

  @override
  Listenable get changes => this;

  @override
  List<TabFieldView> viewsFor(EditorTabGroup group) => const <TabFieldView>[];

  @override
  Iterable<TabFieldView> get allViews => const <TabFieldView>[];

  @override
  void edit(EditCommand command) {}

  @override
  void undo() {}

  @override
  void redo() {}
}

/// One tab that must render an editable table instead of the gap panel.
final class _TabCase {
  const _TabCase({
    required this.name,
    required this.tab,
    required this.build,
    required this.rows,
  });

  final String name;
  final ShellTab tab;
  final Widget Function(FieldGroupsCatalogue catalogue) build;

  /// Named-field row count, verified against the `kokiri-start` fixture.
  final int rows;
}

const List<_TabCase> _cases = <_TabCase>[
  _TabCase(
    name: 'Collectibles',
    tab: ShellTab.collectibles,
    build: _collectibles,
    rows: 159,
  ),
  _TabCase(
    name: 'Flags',
    tab: ShellTab.flags,
    build: _flags,
    rows: 3443,
  ),
];

Widget _collectibles(FieldGroupsCatalogue catalogue) =>
    CollectiblesTab(catalogue: catalogue);

Widget _flags(FieldGroupsCatalogue catalogue) =>
    FlagsTab(catalogue: catalogue);

void main() {
  late FieldGroupsCatalogue catalogue;

  setUpAll(() async {
    catalogue = FieldGroupsCatalogue.load(
      await File('assets/fields/groups.json').readAsString(),
    );
  });

  for (final item in _cases) {
    testWidgets('${item.name} renders the editable table, not the gap panel', (
      tester,
    ) async {
      final source = _FakeSaveTabSource();
      addTearDown(source.dispose);

      await pumpTab(
        tester,
        SaveTabScope(source: source, child: item.build(catalogue)),
        size: const Size(1100, 700),
      );

      expect(find.byType(V1GapPanel), findsNothing);
      expect(find.byType(EditTable), findsOneWidget);
      expect(
        tester.widget<EditTable>(find.byType(EditTable)).rows.length,
        item.rows,
      );

      expect(
        find.descendant(
          of: find.byType(SectionHeader),
          matching: find.text(item.tab.definition.purpose),
        ),
        findsOneWidget,
      );

      expectNoOverflow(tester);
    });
  }
}
