/// Audit: the eleven tabs render real content, not just a mounted page.
///
/// `test/audit/eleven_tabs_test.dart` proves each tab mounts, is tappable, and
/// is not the retired "Engine pending" placeholder. This file adds the missing
/// half: with the real two-slot save at `.tmp/rt` open, every tab must render at
/// least one label or field row from its own domain.
///
/// The save is opened through the production repository wiring and handed to the
/// tabs through the same [SessionSaveTabSource] + [SaveTabScope] pair the app
/// uses, so the assertions exercise the real adapter, not a fake.
library;

import 'dart:io';

import 'package:bomb_flower/domain/catalogue/actor_catalogue.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/domain/world/world_catalogue.dart' as world;
import 'package:bomb_flower/presentation/shell/tabs/advanced_data_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/collectibles_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/dungeons_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/equipment_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/flags_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/inventory_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/overview_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/player_world_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/progression_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/resources_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/settings_tab.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_scope.dart';
import 'package:bomb_flower/presentation/tabs_support/session_save_tab_source.dart';
import 'package:bomb_flower/presentation/widgets/controls/numeric_field.dart';
import 'package:bomb_flower/presentation/widgets/data/edit_table.dart';
import 'package:bomb_flower/presentation/widgets/data/stat_tile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Banner;

import '../integration/support/progress_chain.dart';
import '../presentation/tabs/support/tab_test_harness.dart';

/// Real two-slot fixture; both sizes are part of the fixture contract.
const String _fixtureRoot = '.tmp/rt';
const int _slotZeroLength = 122852;
const int _slotOneLength = 122940;

/// `Sequence_CurrentBanc` in `.tmp/rt/slot_00`, verified against the bundled
/// map catalogue.
const String _storedSceneKey = 'HyruleField_Child';

late SaveProject _project;
late SessionSaveTabSource _source;
late FieldGroupsCatalogue _fieldGroups;
late ActorCatalogue _actorCatalogue;
late world.WorldCatalogue _worldCatalogue;

/// Pumps [tab] under the real save source in the app theme at 1100x700.
///
/// [pumpTab] performs one frame; two more let the async Settings store and the
/// first `AnimatedBuilder` pass settle without waiting on an endless animation.
Future<void> _pumpTab(WidgetTester tester, Widget tab) async {
  await pumpTab(tester, SaveTabScope(source: _source, child: tab));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() async {
    final slotZero = File('$_fixtureRoot/slot_00/progress.sav');
    final slotOne = File('$_fixtureRoot/slot_01/progress.sav');
    expect(
      slotZero.existsSync(),
      isTrue,
      reason:
          'real-save fixture missing at ${slotZero.path}; stage the two-slot '
          'copy at $_fixtureRoot (slot_00 $_slotZeroLength B, slot_01 '
          '$_slotOneLength B) and re-run',
    );
    expect(
      slotOne.existsSync(),
      isTrue,
      reason: 'real-save fixture missing at ${slotOne.path}',
    );
    expect(slotZero.lengthSync(), _slotZeroLength, reason: slotZero.path);
    expect(slotOne.lengthSync(), _slotOneLength, reason: slotOne.path);

    final opened = await createProgressRepository(await loadGameDataSchema())
        .open(_fixtureRoot);
    expect(
      opened,
      isA<ParseUnverified>(),
      reason:
          'expected the real fixture to open as ParseUnverified, got '
          '${describeParseResult(opened)}',
    );
    _project = (opened as ParseUnverified).project;
    expect(_project.documents.keys, contains(SaveSlotId.progress(0)));

    _fieldGroups = FieldGroupsCatalogue.load(
      File('assets/fields/groups.json').readAsStringSync(),
    );
    _actorCatalogue = loadActorCatalogue(
      File('assets/catalogue/actors.json').readAsStringSync(),
    );
    _worldCatalogue = world.loadWorldCatalogue(
      File('assets/world/scenes.json').readAsStringSync(),
    );
  });

  setUp(() {
    _source = SessionSaveTabSource(
      project: () => _project,
      edit: (_) {},
      undo: () {},
      redo: () {},
    );
  });

  testWidgets('overview should render the real Life and Rupees totals', (
    tester,
  ) async {
    await _pumpTab(tester, const OverviewTab());

    // source: lib/presentation/shell/tabs/overview_tab.dart:164-175 — the
    // `overview-life` tile shows 'Life' and '$life / $maxLife' in quarter
    // hearts; :184-191 — `overview-rupees` shows formatRupees(CurrentRupee).
    // source: lib/domain/formatting/hearts.dart:81-90 — 16 quarter hearts is 4.
    final life = tester.widget<StatTile>(
      find.byKey(const Key('overview-life')),
    );
    expect(life.label, 'Life');
    expect(life.value, '4 / 4');
    expect(life.unit, 'hearts');

    final rupees = tester.widget<StatTile>(
      find.byKey(const Key('overview-rupees')),
    );
    expect(rupees.value, '27');
  });

  testWidgets(
    'resources should render the real Life, heart readout and Rupees',
    (tester) async {
      await _pumpTab(tester, const ResourcesTab());

      // source: lib/presentation/shell/tabs/resources_tab.dart:231-253 — the
      // `resources-life` slot and the `resources-hearts` read-out;
      // :318-333 — the `resources-rupees` slot and `resources-rupees-readout`
      // StatTile. slot_00 stores Life 16, MaxLife 16, CurrentRupee 27.
      final life = tester.widget<NumericField>(
        find.descendant(
          of: find.byKey(ResourcesTab.lifeFieldKey),
          matching: find.byType(NumericField),
        ),
      );
      expect(life.value, 16);
      expect(
        tester.widget<Text>(find.byKey(ResourcesTab.heartsReadoutKey)).data,
        '4 hearts / 4 hearts',
      );
      final rupees = tester.widget<StatTile>(
        find.byKey(ResourcesTab.rupeesReadoutKey),
      );
      expect(rupees.value, '27');
    },
  );

  testWidgets('player/world should render the real position, rotation, scene '
      'and dungeon-room fields', (tester) async {
    await _pumpTab(tester, PlayerWorldTab(catalogue: _worldCatalogue));

    // source: lib/presentation/shell/tabs/player_world_tab.dart:175-186 — the
    // Placement group renders `FieldEditor` for Player_Pos_For_Map and
    // _RotationField for Player_Rot_For_Map; :466-471 — 'Rotation' heading;
    // :206-215 — DungeonRoom and Sequence_IsChildhood render as FieldEditor.
    // source: lib/presentation/tabs_support/field_editor.dart:151 — a FieldEditor
    // label is the descriptor label.
    expect(find.text('Player_Pos_For_Map'), findsOneWidget);
    expect(find.text('Rotation'), findsOneWidget);
    expect(find.byKey(PlayerWorldTab.rotationDegreesKey), findsOneWidget);
    expect(find.text('DungeonRoom'), findsOneWidget);

    // source: lib/presentation/shell/tabs/player_world_tab.dart:740-758 — the
    // scene select and 'Stored key: $stored' caption; slot_00 stores
    // HyruleField_Child.
    expect(find.byKey(PlayerWorldTab.sceneSelectKey), findsOneWidget);
    expect(find.text('Stored key: $_storedSceneKey'), findsOneWidget);
  });

  testWidgets('inventory should render real acquisition flags and bottles', (
    tester,
  ) async {
    await _pumpTab(tester, const InventoryTab());

    // source: lib/presentation/shell/tabs/inventory_tab.dart:245-247 — the
    // 'Acquisition' heading; :330-331 — each acquisition view renders as a
    // RuneCheckbox labelled with its field name.
    expect(find.text('Acquisition'), findsOneWidget);
    expect(find.text('IsGet.Weapon_Shield_Mirror'), findsOneWidget);

    // source: lib/presentation/shell/tabs/inventory_tab.dart:122-133 — with no
    // inventory grouping the fallback keeps only IsGet.* and BottleInfo.* views,
    // so the stock count is honestly reported absent at :170-173.
    expect(
      find.text(
        'PouchData.Item_Token_Gold.StockNum is not stored in this save.',
      ),
      findsOneWidget,
    );

    // source: lib/presentation/shell/tabs/inventory_tab.dart:383-385 — 'Bottles'
    // heading; :545-546 — each bottle panel is titled 'Bottle $letter'.
    expect(find.text('Bottle A'), findsOneWidget);
  });

  testWidgets('equipment should render the real equipped sword slot', (
    tester,
  ) async {
    await _pumpTab(tester, EquipmentTab(catalogue: _actorCatalogue));

    // source: lib/presentation/shell/tabs/equipment_tab.dart:373-378 —
    // 'Equipped slots'; :533-535 — FieldRow is labelled with the slot field
    // name; :606-633 — _StoredValue renders the raw stored actor string.
    expect(find.text('Equipped slots'), findsOneWidget);
    // The production adapter exposes both open slots, so the same slot label
    // appears once per document; the active slot is first.
    expect(find.text('PlayerStatus.EquipWeapon'), findsWidgets);
    final storedSword = find
        .byKey(EquipmentTab.slotStoredKey('PlayerStatus.EquipWeapon'))
        .first;
    expect(storedSword, findsOneWidget);
    expect(
      find.descendant(
        of: storedSword,
        matching: find.text('Weapon_Sword_Kokiri'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('progression should render a real event row and the Sun\'s Song '
      'flag', (tester) async {
    await _pumpTab(tester, ProgressionTab(catalogue: _fieldGroups));

    // source: lib/presentation/shell/tabs/progression_tab.dart:180-187 — one
    // row per catalogue field, built by buildEditTableRows; :247-265 — EditTable
    // renders the rows and its search box.
    // catalogue: assets/fields/groups.json "progression" group
    // "progression.events" starts with HavePlayedEvent.BancChangeArrive.
    expect(find.text('HavePlayedEvent.BancChangeArrive'), findsOneWidget);

    // catalogue: assets/fields/groups.json "progression.melodies" contains
    // IsGet.Item_Melody_SunSong; searching the tab's own table surfaces it.
    await tester.enterText(
      find.byKey(EditTable.searchFieldKey),
      'IsGet.Item_Melody_SunSong',
    );
    await tester.pump();
    // Scoped to the row list: the search box itself echoes the query.
    expect(
      find.descendant(
        of: find.byKey(EditTable.listKey),
        matching: find.text('IsGet.Item_Melody_SunSong'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('dungeons should render a real dungeon row and Fire Temple flag', (
    tester,
  ) async {
    await _pumpTab(tester, DungeonsTab(catalogue: _fieldGroups));

    // source: lib/presentation/shell/tabs/dungeons_tab.dart:180-187 — rows come
    // from the catalogue; :245-263 — EditTable renders them.
    // catalogue: assets/fields/groups.json "dungeons" group
    // "dungeons.info.DodongoCavern" starts with DungeonInfo.DodongoCavern.
    expect(find.text('DungeonInfo.DodongoCavern.IsGetCompass'), findsOneWidget);

    // catalogue: "dungeons.info.FireTemple" holds
    // DungeonInfo.FireTemple.IsGetBossKey.
    await tester.enterText(
      find.byKey(EditTable.searchFieldKey),
      'DungeonInfo.FireTemple.IsGetBossKey',
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(EditTable.listKey),
        matching: find.text('DungeonInfo.FireTemple.IsGetBossKey'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('collectibles should render real Gold Skulltula and magic-bean '
      'rows', (tester) async {
    await _pumpTab(tester, CollectiblesTab(catalogue: _fieldGroups));

    // source: lib/presentation/shell/tabs/collectibles_tab.dart:182-189 — rows
    // come from the catalogue; :260-278 — EditTable renders them.
    // catalogue: assets/fields/groups.json "collectibles.goldSkulltula" starts
    // with GatheringTokenGold_Father_BacktoHuman.
    expect(find.text('GatheringTokenGold_Father_BacktoHuman'), findsOneWidget);

    // catalogue: "collectibles.beans" holds Gimmick_MagicBeanSoil_KokiriForest.
    await tester.enterText(
      find.byKey(EditTable.searchFieldKey),
      'Gimmick_MagicBeanSoil_KokiriForest',
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(EditTable.listKey),
        matching: find.text('Gimmick_MagicBeanSoil_KokiriForest'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('flags should render a real Bool flag row and the named section '
      'label', (tester) async {
    await _pumpTab(tester, FlagsTab(catalogue: _fieldGroups));

    // source: lib/presentation/shell/tabs/flags_tab.dart:130-132 — the named
    // section label; :354-379 — _sectionRow renders it; :306-327 — EditTable
    // renders one row per named Bool. catalogue: "flags.boolFlags" starts with
    // ActionGuide_IsEnd.ActivationAmiibo.
    expect(find.textContaining('Named Bool fields'), findsOneWidget);
    expect(find.text('ActionGuide_IsEnd.ActivationAmiibo'), findsOneWidget);

    // A second named flag resolves from the same save-backed table.
    await tester.enterText(
      find.byKey(EditTable.searchFieldKey),
      'ActionGuide_IsEnd.AgonyStone',
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(EditTable.listKey),
        matching: find.text('ActionGuide_IsEnd.AgonyStone'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('advanced data should render the real active-slot hex buffer', (
    tester,
  ) async {
    await _pumpTab(tester, const AdvancedDataTab());

    // source: lib/presentation/shell/tabs/advanced_data_tab.dart:377-383 — the
    // buffer-length read-out; :412-422 — HexEditor keyed
    // `advanced-hex-editor` with title 'Raw bytes'.
    // slot_00/progress.sav is 122,852 bytes.
    expect(find.byKey(AdvancedDataTab.editorKey), findsOneWidget);
    expect(
      find.text('$_slotZeroLength bytes in the active slot buffer'),
      findsOneWidget,
    );
    expect(find.text('Raw bytes'), findsOneWidget);
  });

  testWidgets('settings should render the real backup-policy control and '
      'empty recents state', (tester) async {
    await _pumpTab(tester, SettingsTab());

    // source: lib/presentation/shell/tabs/settings_tab.dart:328-343 — the
    // 'Backup policy' section owns the SearchableSelect keyed
    // SettingsTab.backupPolicyKey; :285-291 — the empty recents message.
    expect(find.text('Backup policy'), findsOneWidget);
    expect(find.byKey(SettingsTab.backupPolicyKey), findsOneWidget);
    expect(find.text('No recent save folders recorded.'), findsOneWidget);
  });
}
