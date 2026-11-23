/// Generates the per-tab field-group catalogue for the editor.
///
/// This is a standalone Dart CLI. It reads only the checked-in, hash-verified
/// schema asset and writes only [defaultOutputPath]. It never reads a save, the
/// game dump, or another repository.
///
/// Usage, from the repository root:
///
/// ```sh
/// dart run tool/gen_field_groups.dart
/// dart run tool/gen_field_groups.dart <schema.json> <out/groups.json>
/// ```
///
/// The output is deterministic: tabs follow [EditorTabGroup.values], groups
/// follow the fixed order in [_tabSpecs], fields are sorted by name, and JSON
/// object keys are inserted in a fixed order. No timestamp, absolute path, or
/// host-specific value is embedded. Running the tool twice produces identical
/// bytes (and therefore an identical SHA-256).
///
/// Group membership is derived from documented name-prefix and exact-name rules
/// in [_tabSpecs]; hashes are never typed by hand. A group member must be an
/// on-disk (`presentOnDisk`) field with a non-null verified name. Unnamed fields
/// appear only as counts or as name-free opaque hashes under `advanced`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';

/// Default schema input, relative to the repository root.
const String defaultSchemaPath = 'assets/schema/gamedata_110.json';

/// Default catalogue output, relative to the repository root.
const String defaultOutputPath = 'assets/fields/groups.json';

/// Bumped when a grouping rule changes in a way that changes membership.
const int groupingRulesVersion = 1;

/// Hashes whose decoded value differs across the three repository fixtures
/// (`kokiri-start`, `castle-gate`, `market-entrance`).
///
/// This is observation evidence, not a name source. It is a constant so the
/// generator stays deterministic and does not require the local fixtures.
const Set<int> observedFieldHashes = <int>{
  492931546, // Sequence_CurrentBanc
  1348845581, // Npc_Hylia_035_Child_CustomerMovedPlaza
  1541139535, // Npc_Hylia_036_Child_CustomerMovedPlaza
  1691387530, // Npc_Hylia_065_Child_ArrivedAction2
  2517292394, // Player_Pos_For_Map
  2605883235, // DungeonRoom
  2762926285, // Player_Rot_For_Map
  2915025514, // HavePlayedEvent.Dm_HrlCastle_0005
  3364238320, // IsVisitLocation.Market
  3679322570, // Market_Minigame_HitHitTarget_CloseDoor
  3766245956, // Market_Npc_Hylia_052_Child_RunningRichard
  3780348574, // SubEvent_FindRichard_RandomAppear_01
};

/// Runs the generator.
Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }
  if (args.length > 2) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  final schemaPath = args.isNotEmpty ? args[0] : defaultSchemaPath;
  final outputPath = args.length > 1 ? args[1] : defaultOutputPath;

  try {
    final schemaSource = await File(schemaPath).readAsString();
    final schema = GameDataSchema.fromJsonString(schemaSource);
    final output = buildFieldGroupsJson(schema);
    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsString(output, flush: true);
    stdout.write(renderCountTable(schema, output));
    stdout.writeln('Wrote $outputPath');
  } on Object catch (error, stackTrace) {
    stderr.writeln('gen_field_groups: $error');
    stderr.writeln(stackTrace);
    exitCode = 64;
  }
}

/// Builds the complete `groups.json` text for [schema].
///
/// Exposed so tests can verify determinism without spawning a process.
String buildFieldGroupsJson(GameDataSchema schema) {
  _validateObservedHashes(schema);
  final builtTabs = <_BuiltTab>[];
  for (final tabSpec in _tabSpecs(schema)) {
    builtTabs.add(_buildTab(schema, tabSpec));
  }
  if (builtTabs.length != EditorTabGroup.values.length) {
    throw StateError(
      'expected ${EditorTabGroup.values.length} tabs, got ${builtTabs.length}',
    );
  }
  final stats = _buildStats(schema, builtTabs);
  final root = <String, Object?>{
    'schema': <String, Object?>{
      'asset': 'assets/schema/gamedata_110.json',
      'revision': schema.schemaRevision,
      'revisionHex': schema.schemaRevisionHex,
      'game': schema.game,
      'onDiskFields': schema.fields.length,
      'namedFields': schema.namedFields.length,
      'unnamedFields': schema.unnamedFields.length,
      'observedFields': observedFieldHashes.length,
      'groupingRulesVersion': groupingRulesVersion,
    },
    'tabs': <Object?>[for (final tab in builtTabs) _tabJson(tab)],
    'stats': stats,
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(root);
  return '${encoded.replaceAll('\r\n', '\n')}\n';
}

/// Renders the per-tab count table printed by the CLI.
String renderCountTable(GameDataSchema schema, String generatedJson) {
  final decoded = jsonDecode(generatedJson);
  if (decoded is! Map<String, Object?>) {
    throw StateError('generated catalogue is not a JSON object');
  }
  final stats = decoded['stats'];
  if (stats is! Map<String, Object?>) {
    throw StateError('generated catalogue has no stats object');
  }
  final tabs = stats['tabs'];
  if (tabs is! List<Object?>) {
    throw StateError('generated catalogue has no tab stats');
  }
  final buffer = StringBuffer()
    ..writeln(
      'schema ${schema.schemaRevisionHex}: '
      '${schema.fields.length} on-disk, '
      '${schema.namedFields.length} named, '
      '${schema.unnamedFields.length} unnamed',
    )
    ..writeln(
      '${'tab'.padRight(14)} ${'named'.padLeft(6)} '
      '${'unnamed'.padLeft(8)} ${'groups'.padLeft(7)}  caveat',
    );
  for (final value in tabs) {
    final tab = value as Map<String, Object?>;
    final id = tab['id']! as String;
    final named = tab['named']! as int;
    final unnamed = tab['unnamed']! as int;
    final groups = tab['groups']! as int;
    final caveat = tab['caveat']! as String;
    buffer.writeln(
      '${id.padRight(14)} ${'$named'.padLeft(6)} '
      '${'$unnamed'.padLeft(8)} ${'$groups'.padLeft(7)}  $caveat',
    );
  }
  return buffer.toString();
}

const String _usage =
    '''
Generates assets/fields/groups.json from the verified GameData schema.

Usage:
  dart run tool/gen_field_groups.dart [schema.json] [out/groups.json]

Defaults:
  schema  $defaultSchemaPath
  output  $defaultOutputPath

The generator reads no save files and no external repository. Output is
deterministic; running it twice produces identical bytes.
''';

final class _TabSpec {
  const _TabSpec({
    required this.tab,
    required this.caveat,
    required this.groups,
  });

  final EditorTabGroup tab;
  final String caveat;
  final List<_GroupSpec> groups;
}

enum _GroupKind { fields, boolFlags, unnamedFields, empty }

final class _GroupSpec {
  const _GroupSpec({
    required this.id,
    required this.title,
    required this.description,
    required this.rules,
    this.kind = _GroupKind.fields,
    this.exactNames = const <String>[],
    this.patterns = const <String>[],
    this.excludes = const <String>[],
    this.caveat,
    this.provenanceOverride,
  });

  final String id;
  final String title;
  final String description;
  final List<String> rules;
  final _GroupKind kind;
  final List<String> exactNames;
  final List<String> patterns;
  final List<String> excludes;
  final String? caveat;
  final String? provenanceOverride;
}

List<_TabSpec> _tabSpecs(GameDataSchema schema) {
  return <_TabSpec>[
    _TabSpec(
      tab: EditorTabGroup.overview,
      caveat:
          'Life and MaxLife are quarter-hearts (12 = three hearts). '
          'Sequence_IsLoadingBanc is runtime-only and is not in progress.sav.',
      groups: <_GroupSpec>[
        _GroupSpec(
          id: 'overview.headline',
          title: 'Headline scalars',
          description:
              'The small set of exact-name values the overview shows first.',
          rules: <String>[
            'exact verified on-disk names only; no prefix or pattern match',
          ],
          exactNames: <String>[
            'PlayerStatus.Life',
            'PlayerStatus.MaxLife',
            'PlayerStatus.MP',
            'PlayerStatus.MPMax',
            'PlayerStatus.CurrentRupee',
            'Sequence_CurrentBanc',
            'Sequence_IsChildhood',
            'AllSage_AwakeSageCount',
            'DoorOfTime_GetStoneCount',
            'Get_MagicBeans',
          ],
          caveat:
              'MaxLife is capacity, not a current value. There is no stored '
              'wallet maximum.',
        ),
      ],
    ),
    _TabSpec(
      tab: EditorTabGroup.playerWorld,
      caveat:
          'PlayerStatus.CurrentPos, PlayerStatus.CurrentDir, and '
          'Sequence_IsLoadingBanc are runtime-only (SaveFileIndex -1) and are '
          'not editable. No dedicated saved spawn/entrance or camera scalar '
          'has a verified name.',
      groups: <_GroupSpec>[
        _GroupSpec(
          id: 'playerWorld.orientation',
          title: 'Position and rotation',
          description:
              'The saved map position and facing used by the host bridge.',
          rules: <String>['exact verified on-disk names'],
          exactNames: <String>['Player_Pos_For_Map', 'Player_Rot_For_Map'],
        ),
        _GroupSpec(
          id: 'playerWorld.location',
          title: 'Scene, age, and room',
          description:
              'Current banc/scene string, the child/adult flag, and the last '
              'saved dungeon room.',
          rules: <String>['exact verified on-disk names'],
          exactNames: <String>[
            'Sequence_CurrentBanc',
            'Sequence_IsChildhood',
            'DungeonRoom',
          ],
          caveat:
              'Sequence_IsChildhood is the only stored age signal; there is no '
              'Age integer.',
        ),
        _GroupSpec(
          id: 'playerWorld.mapMarkers',
          title: 'Map markers and warp points',
          description: 'Map-icon anchors and the two saved warp-point records.',
          rules: <String>['exact verified on-disk names'],
          exactNames: <String>[
            'UI_FieldMapPlayerAreaNo',
            'UI_DungeonMapPlayerAreaNo',
            'IsSettingMapPlayerIconAnchor',
            'MapIconDeactivateByAreaActor',
            'WarpPoint_DreamWorld.Pos',
            'WarpPoint_DreamWorld.LocationName',
            'WarpPoint_FaroreWind.Pos',
            'WarpPoint_FaroreWind.LocationName',
          ],
          caveat:
              'These are saved map-marker values, not a spawn-point catalogue.',
        ),
      ],
    ),
    _TabSpec(
      tab: EditorTabGroup.inventory,
      caveat:
          'Only three stock/count values have verified names: gold tokens, '
          'magic beans, and giant-sword life. Per-item ammo counts and pouch '
          'contents other than bottles have no verified names. IsGet.* entries '
          'are acquisition flags, not counts.',
      groups: <_GroupSpec>[
        _GroupSpec(
          id: 'inventory.acquisition',
          title: 'Acquired items, weapons, armor, and pouch',
          description:
              'Every verified IsGet item/weapon/armor/pouch acquisition flag.',
          rules: <String>[
            r'name matches ^IsGet\.(Item_|Weapon_|Armor_|Pouch_)',
          ],
          patterns: <String>[r'^IsGet\.(Item_|Weapon_|Armor_|Pouch_)'],
        ),
        _GroupSpec(
          id: 'inventory.pouch',
          title: 'Pouch assignment and stock',
          description:
              'Assignable-item enum for the current era plus the only named '
              'PouchData stock counter.',
          rules: <String>[
            r'name matches ^PouchData\.',
            'exact names PlayerStatus.AssignableItem.Adult and .Child',
            'bottle fields are shown in inventory.bottles instead',
          ],
          exactNames: <String>[
            'PouchData.Item_Token_Gold.StockNum',
            'PlayerStatus.AssignableItem.Adult',
            'PlayerStatus.AssignableItem.Child',
          ],
        ),
        _GroupSpec(
          id: 'inventory.bottles',
          title: 'Bottles',
          description:
              'All five bottle contents and their IsValid flags. The five '
              'BottleItem fields share one 13-member enum table.',
          rules: <String>[
            r'name matches ^PlayerStatus\.AssignableItem\.BottleInfo\..*'
                r'\.(BottleItem|IsValid)$',
          ],
          patterns: <String>[
            r'^PlayerStatus\.AssignableItem\.BottleInfo\..*'
                r'\.(BottleItem|IsValid)$',
          ],
        ),
        _GroupSpec(
          id: 'inventory.ammoCapacity',
          title: 'Ammo, capacity, and counts',
          description:
              'Verified quiver/bullet-bag/bomb-bag/scale/pouch acquisition '
              'flags plus the two named integer counts.',
          rules: <String>[
            r'name matches '
                r'(Quiver|BulletBag|BombBag|DekuNutsPouch|DekuStickPouch|'
                r'ScrubBusinessSeed|GoldScale|ShilverScale)',
            r'excludes ^IsGet\. (already inventory.acquisition) and '
                r'^ActionGuide_IsEnd\. (guide UI, not item state)',
            'exact names Get_MagicBeans and '
                'PlayerStatus.WeaponSwordGiantLife',
          ],
          patterns: <String>[
            r'(Quiver|BulletBag|BombBag|DekuNutsPouch|DekuStickPouch|'
                r'ScrubBusinessSeed|GoldScale|ShilverScale)',
          ],
          excludes: <String>[r'^IsGet\.', r'^ActionGuide_IsEnd\.'],
          exactNames: <String>[
            'Get_MagicBeans',
            'PlayerStatus.WeaponSwordGiantLife',
          ],
          caveat:
              'No arrow, bomb, deku-stick, or deku-nut count field exists. '
              'These are upgrade/acquisition flags.',
        ),
      ],
    ),
    _TabSpec(
      tab: EditorTabGroup.equipment,
      caveat:
          'Equipment slots are String64 asset/id text, not numeric item ids. '
          'No verified gauntlet field exists. PlayerStatus.IsActiveGlassTruth '
          'is runtime-only and is excluded.',
      groups: <_GroupSpec>[
        _GroupSpec(
          id: 'equipment.slots',
          title: 'Equipped slots',
          description:
              'The seven equipment strings plus the two alternative-era slots.',
          rules: <String>[
            r'name matches ^PlayerStatus\.(Equip|AnotherEraEquip)',
          ],
          patterns: <String>[r'^PlayerStatus\.(Equip|AnotherEraEquip)'],
        ),
        _GroupSpec(
          id: 'equipment.acquisition',
          title: 'Weapon and armor acquisition',
          description:
              'Verified IsGet weapon/shield/armor flags for equipment the '
              'player has obtained.',
          rules: <String>[r'name matches ^IsGet\.(Weapon_|Armor_)'],
          patterns: <String>[r'^IsGet\.(Weapon_|Armor_)'],
        ),
        _GroupSpec(
          id: 'equipment.state',
          title: 'Equipment state',
          description:
              'Active head armor, agony-stone equip, defense boost, and giant '
              'sword life.',
          rules: <String>['exact verified on-disk names'],
          exactNames: <String>[
            'PlayerStatus.IsActiveHeadArmor',
            'PlayerStatus.IsEquipAgonyStone',
            'PlayerStatus.IsDefenseUP',
            'PlayerStatus.WeaponSwordGiantLife',
          ],
          caveat: 'No equipment-slot enum exists; slots are strings.',
        ),
      ],
    ),
    _TabSpec(
      tab: EditorTabGroup.resources,
      caveat:
          'No MaxRupee, wallet level, or rupee-capacity field exists. '
          'CurrentRupee is stored without a verified maximum. Ammo fields are '
          'acquisition/upgrade flags, not counts.',
      groups: <_GroupSpec>[
        _GroupSpec(
          id: 'resources.health',
          title: 'Health',
          description: 'Current and maximum life, plus the defense upgrade.',
          rules: <String>['exact verified on-disk names'],
          exactNames: <String>[
            'PlayerStatus.Life',
            'PlayerStatus.MaxLife',
            'IsGet.Item_FairyBless_DefenseDouble',
          ],
          caveat: 'Life values are quarter-hearts; 12 is three hearts.',
        ),
        _GroupSpec(
          id: 'resources.magic',
          title: 'Magic',
          description:
              'Current and maximum MP plus the two magic-capacity blessings.',
          rules: <String>['exact verified on-disk names'],
          exactNames: <String>[
            'PlayerStatus.MP',
            'PlayerStatus.MPMax',
            'IsGet.Item_FairyBless_MP',
            'IsGet.Item_FairyBless_MPDouble',
          ],
        ),
        _GroupSpec(
          id: 'resources.rupees',
          title: 'Rupees',
          description: 'The stored rupee count. No capacity field is known.',
          rules: <String>['exact verified on-disk name'],
          exactNames: <String>['PlayerStatus.CurrentRupee'],
          caveat:
              'Do not clamp this value to an invented wallet maximum; no '
              'MaxRupee field exists.',
        ),
        _GroupSpec(
          id: 'resources.counts',
          title: 'Stored counts',
          description:
              'The named integer counts that are not health, magic, or rupees.',
          rules: <String>['exact verified on-disk names'],
          exactNames: <String>[
            'Get_MagicBeans',
            'PouchData.Item_Token_Gold.StockNum',
            'PlayerStatus.WeaponSwordGiantLife',
            'DreamBossStage_WeaponSwordGiantLife',
          ],
          caveat: 'No generic inventory count table is named in the schema.',
        ),
        _GroupSpec(
          id: 'resources.capacityUpgrades',
          title: 'Capacity upgrades',
          description:
              'Verified quiver, bullet-bag, bomb-bag, and scale upgrade flags.',
          rules: <String>[
            r'name matches '
                r'(Quiver|BulletBag|BombBag|GoldScale|ShilverScale)',
            r'excludes ^IsGet\. and ^ActionGuide_IsEnd\.',
          ],
          patterns: <String>[
            r'(Quiver|BulletBag|BombBag|GoldScale|ShilverScale)',
          ],
          excludes: <String>[r'^IsGet\.', r'^ActionGuide_IsEnd\.'],
        ),
      ],
    ),
    _TabSpec(
      tab: EditorTabGroup.progression,
      caveat:
          'There is no medallion bitmask and no single song mask. Stone and '
          'sage progress is spread across individual flags; the 164 '
          'HavePlayedEvent flags mix cutscene/room state with quest state.',
      groups: <_GroupSpec>[
        _GroupSpec(
          id: 'progression.events',
          title: 'Played events',
          description: 'Every verified HavePlayedEvent flag.',
          rules: <String>[r'name matches ^HavePlayedEvent\.'],
          patterns: <String>[r'^HavePlayedEvent\.'],
          caveat:
              'This includes room, cutscene, and hint state, not only quest '
              'progress.',
        ),
        _GroupSpec(
          id: 'progression.get',
          title: 'Get_* progress',
          description: 'Every verified Get_* flag or count.',
          rules: <String>[r'name matches ^Get_'],
          patterns: <String>[r'^Get_'],
        ),
        _GroupSpec(
          id: 'progression.isGet',
          title: 'IsGet.* progress',
          description:
              'Every verified IsGet flag, including item and equipment '
              'acquisition also shown in their own tabs.',
          rules: <String>[r'name matches ^IsGet\.'],
          patterns: <String>[r'^IsGet\.'],
        ),
        _GroupSpec(
          id: 'progression.sages',
          title: 'Sages and great fairies',
          description:
              'AllSage counters plus verified SageOf/Step_SageOf and '
              'Meet_GreatFairy flags.',
          rules: <String>[
            r'name matches ^(AllSage_|SageOf|Step_SageOf|Meet_GreatFairy)',
          ],
          patterns: <String>[r'^(AllSage_|SageOf|Step_SageOf|Meet_GreatFairy)'],
          caveat:
              'AllSage_AwakeSageCount is a count; the rest are individual '
              'flags.',
        ),
        _GroupSpec(
          id: 'progression.stones',
          title: 'Spiritual stones',
          description:
              'Verified stone-quest flags for Forest, Fire, and Water plus the '
              'Door of Time stone count.',
          rules: <String>[
            r'name matches '
                r'(StoneOfForest|StoneOfFire|StoneOfWater|'
                r'DoorOfTime_GetStoneCount)',
          ],
          patterns: <String>[
            r'(StoneOfForest|StoneOfFire|StoneOfWater|'
                r'DoorOfTime_GetStoneCount)',
          ],
          caveat:
              'Includes dialogue and completion flags; there is no single '
              'stone bitmask.',
        ),
        _GroupSpec(
          id: 'progression.doorOfTime',
          title: 'Door of Time',
          description: 'Every verified DoorOfTime_* field.',
          rules: <String>[r'name matches ^DoorOfTime_'],
          patterns: <String>[r'^DoorOfTime_'],
        ),
        _GroupSpec(
          id: 'progression.melodies',
          title: 'Songs and melodies',
          description:
              'Verified melody acquisition and melody-get flags. The source '
              'spelling Spilit is the Spirit melody.',
          rules: <String>[
            r'name matches '
                r'(Dm_MelodyGet_|IsGet\.Item_Melody_|^Item_Melody_|'
                r'HavePlayedGetEvent\.Item_Melody_)',
          ],
          patterns: <String>[
            r'(Dm_MelodyGet_|IsGet\.Item_Melody_|^Item_Melody_|'
                r'HavePlayedGetEvent\.Item_Melody_)',
          ],
          caveat:
              'There is no single songs-learned bitmask; these are individual '
              'flags.',
        ),
        _GroupSpec(
          id: 'progression.medallions',
          title: 'Medallions',
          description:
              'Reserved for medallion fields. None have a verified name in '
              'this revision.',
          rules: <String>['name matches (?i)medallion; zero matches'],
          kind: _GroupKind.empty,
          provenanceOverride: 'inferred',
          caveat:
              'No field containing Medallion has a verified name. Absence is '
              'not proof that the concept is absent from the save.',
        ),
      ],
    ),
    _TabSpec(
      tab: EditorTabGroup.dungeons,
      caveat:
          'Only three dungeons have named DungeonInfo.* item flags (five '
          'fields). Small keys are per-room flags. DungeonInfo.*.BossRetryNum '
          'is runtime-only. Only one heart-container flag is named.',
      groups: <_GroupSpec>[
        ..._dungeonInfoGroups(schema),
        _GroupSpec(
          id: 'dungeons.smallKeys',
          title: 'Small keys',
          description:
              'Every verified per-room small-key flag, including the four '
              'Gerudo Fortress keys.',
          rules: <String>[r'name matches (SmallKey|_Get_SmallKey)'],
          patterns: <String>[r'(SmallKey|_Get_SmallKey)'],
          caveat:
              'There is no single small-key inventory count; keys are '
              'per-room flags.',
        ),
        _GroupSpec(
          id: 'dungeons.bossFlags',
          title: 'Boss defeat flags',
          description:
              'Verified DefeatBoss/BossOut flags, including the final battle.',
          rules: <String>[r'name matches (DefeatBoss|BossOut)'],
          patterns: <String>[r'(DefeatBoss|BossOut)'],
        ),
        _GroupSpec(
          id: 'dungeons.mapItems',
          title: 'Map items',
          description:
              'Verified dungeon-map and map-icon flags outside DungeonInfo.',
          rules: <String>[
            r'name matches '
                r'(GetDungeonMap|_GetMap$|IsGetMap$|_Mapicon$|MapIcon_Flag$)',
            r'excludes ^DungeonInfo\. and ^MiniGame',
          ],
          patterns: <String>[
            r'(GetDungeonMap|_GetMap$|IsGetMap$|_Mapicon$|MapIcon_Flag$)',
          ],
          excludes: <String>[r'^DungeonInfo\.', r'^MiniGame'],
          caveat: 'DungeonInfo.*.IsGetMap is shown in its per-dungeon group.',
        ),
        _GroupSpec(
          id: 'dungeons.heartContainers',
          title: 'Heart containers',
          description:
              'Verified *_Heart_Container_Obtained flags. Only one is named.',
          rules: <String>[r'name matches _Heart_Container_Obtained'],
          patterns: <String>[r'_Heart_Container_Obtained'],
          caveat:
              'Heart pieces are in collectibles; only boss heart containers '
              'belong here.',
        ),
      ],
    ),
    _TabSpec(
      tab: EditorTabGroup.collectibles,
      caveat:
          'No Gold Skulltula count field exists; only '
          'PouchData.Item_Token_Gold.StockNum and token event flags are named. '
          'Fishing sizes and best times are real numeric records.',
      groups: <_GroupSpec>[
        _GroupSpec(
          id: 'collectibles.goldSkulltula',
          title: 'Gold Skulltula tokens',
          description:
              'The token stock counter plus verified GatheringTokenGold, '
              'HaveEncountered_Token, and token-counter flags.',
          rules: <String>[
            r'name matches '
                r'(GatheringTokenGold|HaveEncountered_Token|'
                r'TokenCounterAppeared|Item_Token_Gold)',
          ],
          patterns: <String>[
            r'(GatheringTokenGold|HaveEncountered_Token|'
                r'TokenCounterAppeared|Item_Token_Gold)',
          ],
          caveat:
              'No total Gold Skulltula count field exists; token stock is the '
              'closest stored count.',
        ),
        _GroupSpec(
          id: 'collectibles.heartPieces',
          title: 'Heart pieces',
          description:
              'Verified HeartPiece/Heart_Piece flags. Boss heart containers '
              'are in dungeons.',
          rules: <String>[r'name matches (HeartPiece|Heart_Piece)'],
          patterns: <String>[r'(HeartPiece|Heart_Piece)'],
        ),
        _GroupSpec(
          id: 'collectibles.beans',
          title: 'Magic beans',
          description:
              'Get_MagicBeans count plus verified MagicBean soil and hint '
              'flags.',
          rules: <String>[r'name matches MagicBean'],
          patterns: <String>[r'MagicBean'],
          caveat:
              'Get_MagicBeans is the count; the soil flags record planted '
              'locations.',
        ),
        _GroupSpec(
          id: 'collectibles.poe',
          title: 'Poes and Big Poes',
          description:
              'Verified Big Poe defeats, Guide Poe progress, and Poe bottle '
              'flags.',
          rules: <String>[
            r'name matches (BigPoe|Bottle_Poe|GuidePoe_|'
                r'IsRespawnAtGuidePoeRuins)',
          ],
          patterns: <String>[
            r'(BigPoe|Bottle_Poe|GuidePoe_|IsRespawnAtGuidePoeRuins)',
          ],
          caveat:
              'No Big Poe count field exists; the ten Hyrule Field defeats are '
              'individual flags.',
        ),
        _GroupSpec(
          id: 'collectibles.fishing',
          title: 'Fishing',
          description: 'Every verified Fishing field, including records.',
          rules: <String>[r'name matches Fishing'],
          patterns: <String>[r'Fishing'],
          caveat:
              'Includes tutorial, weather, and pond-state flags, not only '
              'records.',
        ),
        _GroupSpec(
          id: 'collectibles.highScores',
          title: 'High scores and best times',
          description: 'Verified BestScore/NewScore/BestTime and record flags.',
          rules: <String>[
            r'name matches '
                r'(BestScore|NewScore|BestTime|RecordFish|'
                r'RecordWithSinkingLure|OnceUpdateRecord|IsNewRecord)',
          ],
          patterns: <String>[
            r'(BestScore|NewScore|BestTime|RecordFish|'
                r'RecordWithSinkingLure|OnceUpdateRecord|IsNewRecord)',
          ],
          caveat:
              'Some rows also appear in collectibles.fishing; group counts are '
              'memberships, not a partition.',
        ),
      ],
    ),
    _TabSpec(
      tab: EditorTabGroup.flags,
      caveat:
          '10,212 Bool fields: 3,443 named, 6,769 hash-only. Buckets are '
          'counts; use the query API (flagBuckets/flagFieldsUnder) instead of '
          'rendering 10k rows inline.',
      groups: <_GroupSpec>[
        _GroupSpec(
          id: 'flags.boolFlags',
          title: 'Boolean flags by prefix',
          description:
              'All named Bool fields, bucketed by the first dot or underscore '
              'prefix, plus the hash-only Bool count.',
          rules: <String>[
            'type == Bool',
            r"bucket prefix = first '.' segment, else first '_' segment, "
                'else (other)',
            'unnamed Bool fields are counted, never named',
          ],
          kind: _GroupKind.boolFlags,
        ),
      ],
    ),
    _TabSpec(
      tab: EditorTabGroup.advanced,
      caveat:
          '8,317 of 11,925 on-disk fields have no recovered name. Seven opaque '
          'Binary/BinaryArray/WString16Array records are listed by hash only. '
          'Changing a Binary length requires rebuilding the tail and pointers.',
      groups: <_GroupSpec>[
        _GroupSpec(
          id: 'advanced.unnamed',
          title: 'Hash-only and opaque fields',
          description:
              'Counts of unnamed fields by wire type plus every opaque '
              'Binary/BinaryArray/WString16Array hash.',
          rules: <String>[
            'type counts over all on-disk fields with name == null',
            'opaque hashes: type in Binary, BinaryArray, WString16Array',
            'no fabricated labels; opaque entries carry hash and type only',
          ],
          kind: _GroupKind.unnamedFields,
        ),
      ],
    ),
    _TabSpec(
      tab: EditorTabGroup.settings,
      caveat:
          'No progress.sav fields. App settings are not modelled by this '
          'schema; option.sav is declared in the container map but its fields '
          'were not extracted.',
      groups: <_GroupSpec>[
        _GroupSpec(
          id: 'settings.appSettings',
          title: 'Application settings',
          description:
              'Empty by design: this tab edits application preferences, not '
              'save fields.',
          rules: <String>['no progress.sav field maps to app settings'],
          kind: _GroupKind.empty,
          provenanceOverride: 'verified',
          caveat:
              'option.sav has no extracted fields in this schema. Do not '
              'invent settings keys.',
        ),
      ],
    ),
  ];
}

List<_GroupSpec> _dungeonInfoGroups(GameDataSchema schema) {
  final byDungeon = <String, List<SaveFieldDef>>{};
  final pattern = RegExp(r'^DungeonInfo\.([^.]+)\.');
  for (final field in schema.fields) {
    final name = field.name;
    if (name == null) {
      continue;
    }
    final match = pattern.firstMatch(name);
    if (match == null) {
      continue;
    }
    byDungeon.putIfAbsent(match.group(1)!, () => <SaveFieldDef>[]).add(field);
  }
  final names = byDungeon.keys.toList()..sort();
  return <_GroupSpec>[
    for (final dungeon in names)
      _GroupSpec(
        id: 'dungeons.info.$dungeon',
        title: '$dungeon items',
        description:
            'Named DungeonInfo.$dungeon item flags: map, compass, boss key, '
            'and any other verified member.',
        rules: <String>[
          r'name matches ^DungeonInfo\.'
              '$dungeon'
              r'\.',
        ],
        exactNames: <String>[
          for (final field in byDungeon[dungeon]!..sort(_compareFields))
            field.name!,
        ],
        caveat:
            'Only named DungeonInfo members are shown; BossRetryNum is '
            'runtime-only.',
      ),
  ];
}

final class _BuiltTab {
  _BuiltTab({required this.tab, required this.caveat, required this.groups});

  final EditorTabGroup tab;
  final String caveat;
  final List<_BuiltGroup> groups;
}

final class _BuiltGroup {
  _BuiltGroup({
    required this.id,
    required this.title,
    required this.description,
    required this.provenance,
    required this.fields,
    required this.unnamedCount,
    required this.caveat,
    required this.rules,
    required this.buckets,
    required this.opaqueFields,
  });

  final String id;
  final String title;
  final String description;
  final String provenance;
  final List<SaveFieldDef> fields;
  final int unnamedCount;
  final String? caveat;
  final List<String> rules;
  final List<Map<String, Object?>> buckets;
  final List<SaveFieldDef> opaqueFields;
}

_BuiltTab _buildTab(GameDataSchema schema, _TabSpec spec) {
  final groups = <_BuiltGroup>[
    for (final group in spec.groups) _buildGroup(schema, group),
  ];
  if (groups.isEmpty) {
    throw StateError('${spec.tab.id}: tab has no groups');
  }
  return _BuiltTab(tab: spec.tab, caveat: spec.caveat, groups: groups);
}

_BuiltGroup _buildGroup(GameDataSchema schema, _GroupSpec spec) {
  switch (spec.kind) {
    case _GroupKind.fields:
      final fields = _selectFields(schema, spec);
      if (fields.isEmpty) {
        throw StateError('${spec.id}: no matching on-disk named fields');
      }
      return _BuiltGroup(
        id: spec.id,
        title: spec.title,
        description: spec.description,
        provenance: _groupProvenance(fields, spec.provenanceOverride),
        fields: fields,
        unnamedCount: 0,
        caveat: spec.caveat,
        rules: spec.rules,
        buckets: const <Map<String, Object?>>[],
        opaqueFields: const <SaveFieldDef>[],
      );
    case _GroupKind.boolFlags:
      return _buildBoolFlags(schema, spec);
    case _GroupKind.unnamedFields:
      return _buildUnnamedFields(schema, spec);
    case _GroupKind.empty:
      return _BuiltGroup(
        id: spec.id,
        title: spec.title,
        description: spec.description,
        provenance: spec.provenanceOverride ?? 'inferred',
        fields: const <SaveFieldDef>[],
        unnamedCount: 0,
        caveat: spec.caveat,
        rules: spec.rules,
        buckets: const <Map<String, Object?>>[],
        opaqueFields: const <SaveFieldDef>[],
      );
  }
}

List<SaveFieldDef> _selectFields(GameDataSchema schema, _GroupSpec spec) {
  final selected = <int, SaveFieldDef>{};
  for (final name in spec.exactNames) {
    final field = schema.byNameOnDisk(name);
    if (field == null) {
      throw StateError('${spec.id}: exact name is not an on-disk field: $name');
    }
    selected[field.hash] = field;
  }
  final patterns = <RegExp>[for (final source in spec.patterns) RegExp(source)];
  final excludes = <RegExp>[for (final source in spec.excludes) RegExp(source)];
  for (final field in schema.fields) {
    final name = field.name;
    if (name == null) {
      continue;
    }
    if (!patterns.any((pattern) => pattern.hasMatch(name))) {
      continue;
    }
    if (excludes.any((pattern) => pattern.hasMatch(name))) {
      continue;
    }
    selected[field.hash] = field;
  }
  final fields = selected.values.toList()..sort(_compareFields);
  return List<SaveFieldDef>.unmodifiable(fields);
}

_BuiltGroup _buildBoolFlags(GameDataSchema schema, _GroupSpec spec) {
  final named = <SaveFieldDef>[];
  var unnamed = 0;
  for (final field in schema.fields) {
    if (field.type != SaveType.boolean) {
      continue;
    }
    if (field.name == null) {
      unnamed++;
    } else {
      named.add(field);
    }
  }
  named.sort(_compareFields);
  final grouped = <String, List<SaveFieldDef>>{};
  for (final field in named) {
    grouped
        .putIfAbsent(flagPrefixOf(field.name!), () => <SaveFieldDef>[])
        .add(field);
  }
  final prefixes = grouped.keys.toList()
    ..sort((a, b) {
      final byCount = grouped[b]!.length.compareTo(grouped[a]!.length);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  final buckets = <Map<String, Object?>>[
    for (final prefix in prefixes)
      <String, Object?>{
        'id': 'flags.prefix.${_slug(prefix)}',
        'label': prefix,
        'prefix': prefix,
        'type': 'Bool',
        'namedCount': grouped[prefix]!.length,
        'unnamedCount': 0,
        'totalCount': grouped[prefix]!.length,
        'samples': <String>[
          for (final field in grouped[prefix]!.take(3)) field.name!,
        ],
      },
    <String, Object?>{
      'id': 'flags.unnamedBool',
      'label': 'Unnamed Bool fields',
      'prefix': null,
      'type': 'Bool',
      'namedCount': 0,
      'unnamedCount': unnamed,
      'totalCount': unnamed,
      'samples': const <String>[],
    },
  ];
  return _BuiltGroup(
    id: spec.id,
    title: spec.title,
    description: spec.description,
    provenance: _groupProvenance(named, spec.provenanceOverride),
    fields: List<SaveFieldDef>.unmodifiable(named),
    unnamedCount: unnamed,
    caveat: spec.caveat,
    rules: spec.rules,
    buckets: List<Map<String, Object?>>.unmodifiable(buckets),
    opaqueFields: const <SaveFieldDef>[],
  );
}

_BuiltGroup _buildUnnamedFields(GameDataSchema schema, _GroupSpec spec) {
  final unnamed = schema.fields.where((field) => field.name == null).toList();
  final byType = <SaveType, int>{};
  for (final field in unnamed) {
    byType.update(field.type, (value) => value + 1, ifAbsent: () => 1);
  }
  final types = byType.keys.toList()
    ..sort((a, b) {
      final byCount = byType[b]!.compareTo(byType[a]!);
      return byCount != 0 ? byCount : a.wireName.compareTo(b.wireName);
    });
  final buckets = <Map<String, Object?>>[
    for (final type in types)
      <String, Object?>{
        'id': 'advanced.type.${_slug(type.wireName)}',
        'label': type.wireName,
        'prefix': null,
        'type': type.wireName,
        'namedCount': 0,
        'unnamedCount': byType[type],
        'totalCount': byType[type],
        'samples': const <String>[],
      },
  ];
  const opaqueTypes = <SaveType>{
    SaveType.binary,
    SaveType.binaryArray,
    SaveType.wstring16Array,
  };
  final opaque =
      schema.fields.where((field) => opaqueTypes.contains(field.type)).toList()
        ..sort((a, b) => a.hash.compareTo(b.hash));
  for (final field in opaque) {
    if (field.name != null) {
      throw StateError(
        '${spec.id}: opaque field ${field.name} unexpectedly has a name',
      );
    }
  }
  return _BuiltGroup(
    id: spec.id,
    title: spec.title,
    description: spec.description,
    provenance: spec.provenanceOverride ?? 'inferred',
    fields: const <SaveFieldDef>[],
    unnamedCount: unnamed.length,
    caveat: spec.caveat,
    rules: spec.rules,
    buckets: List<Map<String, Object?>>.unmodifiable(buckets),
    opaqueFields: List<SaveFieldDef>.unmodifiable(opaque),
  );
}

String _groupProvenance(List<SaveFieldDef> fields, String? override) {
  if (override != null) {
    return override;
  }
  if (fields.any((field) => observedFieldHashes.contains(field.hash))) {
    return 'observed';
  }
  if (fields.isNotEmpty &&
      fields.every(
        (field) => field.nameSource == 'host' || field.nameSource == 'struct',
      )) {
    return 'verified';
  }
  return 'inferred';
}

String _fieldProvenance(SaveFieldDef field) {
  if (observedFieldHashes.contains(field.hash)) {
    return 'observed';
  }
  if (field.nameSource == 'host' || field.nameSource == 'struct') {
    return 'verified';
  }
  return 'inferred';
}

void _validateObservedHashes(GameDataSchema schema) {
  for (final hash in observedFieldHashes) {
    final field = schema.byHashOnDisk(hash);
    if (field == null) {
      throw StateError('observed hash ${formatFieldHash(hash)} is not on disk');
    }
    if (field.name == null) {
      throw StateError(
        'observed hash ${formatFieldHash(hash)} has no verified name',
      );
    }
  }
}

Map<String, Object?> _tabJson(_BuiltTab tab) {
  return <String, Object?>{
    'id': tab.tab.id,
    'title': tab.tab.title,
    'caveat': tab.caveat,
    'groups': <Object?>[for (final group in tab.groups) _groupJson(group)],
  };
}

Map<String, Object?> _groupJson(_BuiltGroup group) {
  return <String, Object?>{
    'id': group.id,
    'title': group.title,
    'description': group.description,
    'provenance': group.provenance,
    'unnamedCount': group.unnamedCount,
    'caveat': group.caveat,
    'matchRules': group.rules,
    'fields': <Object?>[for (final field in group.fields) _fieldJson(field)],
    'buckets': group.buckets,
    'opaqueFields': <Object?>[
      for (final field in group.opaqueFields) _opaqueJson(field),
    ],
  };
}

Map<String, Object?> _fieldJson(SaveFieldDef field) {
  final name = field.name;
  if (name == null) {
    throw StateError('cannot emit an unnamed field as a FieldRef');
  }
  return <String, Object?>{
    'hash': field.hash,
    'hashHex': formatFieldHash(field.hash),
    'name': name,
    'type': field.type.wireName,
    'section': field.section,
    'defaultPreview': _defaultPreview(field),
    'provenance': _fieldProvenance(field),
  };
}

Map<String, Object?> _opaqueJson(SaveFieldDef field) {
  return <String, Object?>{
    'hash': field.hash,
    'hashHex': formatFieldHash(field.hash),
    'type': field.type.wireName,
    'section': field.section,
    'recordIndex': field.recordIndex,
    'defaultPreview': _defaultPreview(field),
  };
}

Map<String, Object?> _buildStats(GameDataSchema schema, List<_BuiltTab> tabs) {
  final tabStats = <Map<String, Object?>>[];
  for (final tab in tabs) {
    final hashes = <int>{};
    var unnamed = 0;
    for (final group in tab.groups) {
      for (final field in group.fields) {
        hashes.add(field.hash);
      }
      unnamed += group.unnamedCount;
    }
    tabStats.add(<String, Object?>{
      'id': tab.tab.id,
      'title': tab.tab.title,
      'named': hashes.length,
      'unnamed': unnamed,
      'groups': tab.groups.length,
      'caveat': tab.caveat,
    });
  }
  return <String, Object?>{
    'schemaRevision': schema.schemaRevision,
    'schemaRevisionHex': schema.schemaRevisionHex,
    'onDiskFields': schema.fields.length,
    'namedFields': schema.namedFields.length,
    'unnamedFields': schema.unnamedFields.length,
    'observedFields': observedFieldHashes.length,
    'tabs': tabStats,
  };
}

String _defaultPreview(SaveFieldDef field) {
  if (field.type.isArray) {
    final length = field.arrayLen;
    return length == null
        ? field.type.wireName
        : '${field.type.wireName}[$length]';
  }
  if (field.type == SaveType.enumeration) {
    final label = field.defaultLabel;
    if (label != null) {
      return label;
    }
    final value = field.defaultValue;
    if (value is int) {
      return formatFieldHash(value);
    }
  }
  final value = field.defaultValue;
  if (value == null) {
    return 'null';
  }
  if (value is bool) {
    return value ? 'true' : 'false';
  }
  if (value is int) {
    return '$value';
  }
  if (value is double) {
    return _number(value);
  }
  if (value is String) {
    return jsonEncode(value);
  }
  if (value is Map<String, Object?>) {
    final x = value['x'];
    final y = value['y'];
    final z = value['z'];
    if (x is num && y is num && z is num) {
      return '(${_number(x)}, ${_number(y)}, ${_number(z)})';
    }
  }
  return jsonEncode(value);
}

String _number(num value) {
  if (value is double) {
    if (value == value.truncateToDouble()) {
      return value.toStringAsFixed(1);
    }
    return value.toString();
  }
  return '$value';
}

int _compareFields(SaveFieldDef a, SaveFieldDef b) {
  final byName = a.name!.compareTo(b.name!);
  return byName != 0 ? byName : a.hash.compareTo(b.hash);
}

String _slug(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    if (RegExp(r'[a-z0-9]').hasMatch(character)) {
      buffer.write(character);
    } else {
      buffer.write('_');
    }
  }
  return buffer
      .toString()
      .replaceAll(RegExp('_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
