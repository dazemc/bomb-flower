/// Generates the verified Longshot world and actor-name catalogues.
///
/// This is a standalone Dart CLI: it imports no Flutter libraries and does not
/// write to Longshot. It reads the validated scene extraction plus, optionally,
/// Longshot's own C sources to check display names and boss-dungeon membership.
///
/// Usage, from the repository root:
///
/// ```sh
/// dart run tool/gen_catalogues.dart \
///   --scenes /tmp/opencode/catalogue/scenes/scenes.longshot.json \
///   --area-names /home/daze/GitHub/Longshot/host/oot_area_names.c \
///   --cheat-items /home/daze/GitHub/Longshot/gpu/vk/oot_cheat_items.h \
///   --heart-containers /home/daze/GitHub/Longshot/host/oot_heart_containers.c \
///   --out assets
/// ```
///
/// Every path except `--out` falls back to an environment variable and then to
/// the developer paths above. The output is canonical JSON: object keys are
/// sorted at every level, arrays have documented stable orders, and no
/// timestamp or absolute input path is embedded, so repeated runs are
/// byte-identical.
library;

import 'dart:convert';
import 'dart:io';

/// The validated scene extraction, resolved from this script's own location so
/// the default holds for any working directory.
String get _defaultScenes {
  const relative = '.tmp/catalogue/scenes/scenes.longshot.json';
  final script = Platform.script;
  if (script.scheme == 'file') {
    // `tool/` sits directly under the repository root.
    final scriptFile = File(script.toFilePath()).absolute;
    if (scriptFile.existsSync()) {
      final fromRepoRoot = '${scriptFile.parent.parent.path}/$relative';
      if (File(fromRepoRoot).existsSync()) {
        return fromRepoRoot;
      }
    }
  }
  // `Platform.script` does not name the real file (e.g. a compiled snapshot or
  // AOT binary), so fall back to the process working directory.
  return relative;
}

const String _defaultLongshotRoot = '/home/daze/GitHub/Longshot';
const String _defaultOut = 'assets';

const String _gameTitle =
    'The Legend of Zelda: Ocarina of Time (Nintendo Switch 2)';
const String _gameVersion = '131072';
const String _gameBuild = 'e0f3ccfa';
const String _gameProgram = '0400486024DEC000';

const int _expectedMapCount = 80;
const int _expectedBaseSceneCount = 62;
const int _expectedStartCount = 415;
const int _expectedDefaultStartCount = 45;
const int _expectedDungeonCount = 10;
const int _expectedObservedCount = 3;
const int _expectedActorCount = 86;
const int _expectedBossDungeonCount = 8;

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    stdout.writeln(_usage);
    return;
  }

  try {
    final paths = options.resolvePaths();
    final scenesFile = File(paths.scenes);
    if (!scenesFile.existsSync()) {
      throw StateError(
        'scene catalogue not found: ${scenesFile.absolute.path}\n'
        'That file comes from the validated Longshot scene extraction. Point '
        'at a copy with --scenes <path> or BOMB_FLOWER_SCENES.',
      );
    }
    final scenesJson = _readObject(scenesFile);

    final areaNames = paths.areaNames == null
        ? null
        : _AreaNames.parse(File(paths.areaNames!).readAsStringSync());

    final cheatItemsFile = File(paths.cheatItems);
    if (!cheatItemsFile.existsSync()) {
      throw StateError('actor source not found: ${paths.cheatItems}');
    }
    final actorRows = _parseCheatItems(cheatItemsFile.readAsStringSync());

    final heartDungeons = paths.heartContainers == null
        ? null
        : _parseHeartDungeons(File(paths.heartContainers!).readAsStringSync());

    final world = _buildWorld(
      scenesJson,
      areaNames: areaNames,
      heartDungeons: heartDungeons,
    );
    final actors = _buildActors(actorRows);

    final out = Directory(paths.out);
    final worldFile = File('${out.path}/world/scenes.json');
    final actorFile = File('${out.path}/catalogue/actors.json');
    await worldFile.parent.create(recursive: true);
    await actorFile.parent.create(recursive: true);
    await worldFile.writeAsString(_canonicalJson(world), flush: true);
    await actorFile.writeAsString(_canonicalJson(actors), flush: true);

    final mapCount = (world['maps']! as List<Object?>).length;
    final baseSceneCount = (world['baseScenes']! as List<Object?>).length;
    final startCount =
        (world['counts']! as Map<String, Object?>)['startPositions'];
    final dungeonCount = (world['dungeons']! as List<Object?>).length;
    final observedCount = (world['observed']! as List<Object?>).length;
    final actorCount = (actors['counts']! as Map<String, Object?>)['total'];

    stdout.writeln('Wrote ${worldFile.path}');
    stdout.writeln(
      '  maps: $mapCount, base scenes: $baseSceneCount, '
      'start positions: $startCount, dungeons: $dungeonCount, '
      'observed: $observedCount',
    );
    stdout.writeln('Wrote ${actorFile.path}');
    stdout.writeln('  actor/item rows: $actorCount');
  } on Object catch (error, stackTrace) {
    stderr.writeln('gen_catalogues: $error');
    stderr.writeln(stackTrace);
    exitCode = 64;
  }
}

const String _usage = '''
Generates assets/world/scenes.json and assets/catalogue/actors.json.

Options:
  --scenes <path>             validated scenes.longshot.json
  --area-names <path>         Longshot host/oot_area_names.c (optional)
  --cheat-items <path>        Longshot gpu/vk/oot_cheat_items.h
  --heart-containers <path>   Longshot host/oot_heart_containers.c (optional)
  --longshot-root <path>      root used for the optional defaults above
  --out <dir>                 output root (default: assets)
  --help                      show this text
''';

/// The paths of the inputs this run will read and the output root it owns.
final class _Paths {
  const _Paths({
    required this.scenes,
    required this.areaNames,
    required this.cheatItems,
    required this.heartContainers,
    required this.out,
  });

  final String scenes;
  final String? areaNames;
  final String cheatItems;
  final String? heartContainers;
  final String out;
}

final class _Options {
  const _Options(this.values, {required this.help});

  final Map<String, String> values;
  final bool help;

  static const Set<String> _known = <String>{
    'scenes',
    'area-names',
    'cheat-items',
    'heart-containers',
    'longshot-root',
    'out',
  };

  static _Options parse(List<String> args) {
    final values = <String, String>{};
    var help = false;
    for (var index = 0; index < args.length; index++) {
      final argument = args[index];
      if (argument == '--help' || argument == '-h') {
        help = true;
        continue;
      }
      if (!argument.startsWith('--')) {
        throw FormatException('unexpected argument: $argument');
      }
      final equals = argument.indexOf('=');
      if (equals >= 0) {
        values[argument.substring(2, equals)] = argument.substring(equals + 1);
        continue;
      }
      if (index + 1 >= args.length) {
        throw FormatException('missing value for $argument');
      }
      values[argument.substring(2)] = args[++index];
    }
    for (final key in values.keys) {
      if (!_known.contains(key)) {
        throw FormatException('unknown option: --$key');
      }
    }
    return _Options(values, help: help);
  }

  _Paths resolvePaths() {
    final longshotRoot =
        values['longshot-root'] ??
        Platform.environment['LONGSHOT_ROOT'] ??
        _defaultLongshotRoot;
    String? optional(String explicitKey, String relative) {
      final explicit = values[explicitKey];
      if (explicit != null) {
        return explicit;
      }
      final path = '$longshotRoot/$relative';
      return File(path).existsSync() ? path : null;
    }

    return _Paths(
      scenes:
          values['scenes'] ??
          Platform.environment['BOMB_FLOWER_SCENES'] ??
          _defaultScenes,
      areaNames: optional('area-names', 'host/oot_area_names.c'),
      cheatItems:
          values['cheat-items'] ?? '$longshotRoot/gpu/vk/oot_cheat_items.h',
      heartContainers: optional(
        'heart-containers',
        'host/oot_heart_containers.c',
      ),
      out:
          values['out'] ??
          Platform.environment['BOMB_FLOWER_CATALOGUE_OUT'] ??
          _defaultOut,
    );
  }
}

/// Resolves map display names exactly as `host/oot_area_names.c` does.
final class _AreaNames {
  _AreaNames(this.table);

  final Map<String, String> table;

  static _AreaNames parse(String source) {
    final table = <String, String>{};
    final entries = RegExp(r'\{"([^"]+)",\s*"([^"]+)"\}');
    for (final match in entries.allMatches(source)) {
      table[match.group(1)!] = match.group(2)!;
    }
    if (table.length < 60) {
      throw StateError(
        'oot_area_names.c yielded only ${table.length} names; expected at '
        'least 60',
      );
    }
    return _AreaNames(table);
  }

  String resolve(String key) {
    var candidate = key;
    var masterQuest = false;
    if (candidate.endsWith('_MQ') && candidate.length > 3) {
      candidate = candidate.substring(0, candidate.length - 3);
      masterQuest = true;
    }
    var name = table[candidate];
    if (name == null) {
      candidate = _stripSuffix(candidate, '_Alternative');
      name = table[candidate];
      if (name == null) {
        final child = _stripSuffix(candidate, '_Child');
        if (child != candidate) {
          candidate = child;
          name = table[candidate];
        } else {
          final adult = _stripSuffix(candidate, '_Adult');
          if (adult != candidate) {
            candidate = adult;
            name = table[candidate];
          }
        }
      }
    }
    if (name != null) {
      return masterQuest ? '$name (Master Quest)' : name;
    }
    return _humanize(candidate);
  }

  static String _stripSuffix(String value, String suffix) {
    if (value.length <= suffix.length || !value.endsWith(suffix)) {
      return value;
    }
    return value.substring(0, value.length - suffix.length);
  }

  /// The C fallback: `_` is a space, and a capital after a small letter gets a
  /// space before it.
  static String _humanize(String key) {
    final buffer = StringBuffer();
    var previous = '';
    for (var index = 0; index < key.length; index++) {
      final source = key[index];
      final character = source == '_' ? ' ' : source;
      final isUpper =
          character.codeUnitAt(0) >= 0x41 && character.codeUnitAt(0) <= 0x5a;
      final previousIsLower =
          previous.isNotEmpty &&
          previous.codeUnitAt(0) >= 0x61 &&
          previous.codeUnitAt(0) <= 0x7a;
      if (index > 0 && isUpper && previousIsLower) {
        buffer.write(' ');
      }
      if (!(character == ' ' &&
          buffer.isNotEmpty &&
          buffer.toString().endsWith(' '))) {
        buffer.write(character);
      }
      previous = source;
    }
    return buffer.toString().trimRight();
  }
}

Map<String, Object?> _buildWorld(
  Map<String, Object?> source, {
  required _AreaNames? areaNames,
  required Set<String>? heartDungeons,
}) {
  final mapRows = _objects(source['known_map_names'], 'known_map_names');
  final sceneRows = _objects(source['known_scene_names'], 'known_scene_names');
  final startRows = _objects(source['start_positions'], 'start_positions');
  final dungeonRows = _objects(source['dungeons'], 'dungeons');
  final observedRows = _objects(source['observed'], 'observed');

  _expectCount('maps', mapRows.length, _expectedMapCount);
  _expectCount('base scenes', sceneRows.length, _expectedBaseSceneCount);
  _expectCount('start positions', startRows.length, _expectedStartCount);
  _expectCount('dungeons', dungeonRows.length, _expectedDungeonCount);
  _expectCount('observed saves', observedRows.length, _expectedObservedCount);

  final displayNames = <String, String>{};
  final mismatches = <String>[];
  for (final row in mapRows) {
    final key = _string(row, 'map_key');
    final scratchName = _string(row, 'display_name');
    final resolved = areaNames?.resolve(key) ?? scratchName;
    if (areaNames != null && resolved != scratchName) {
      mismatches.add(
        '$key: Longshot says "$resolved", scratch says '
        '"$scratchName"',
      );
    }
    displayNames[key] = resolved;
  }
  if (mismatches.isNotEmpty) {
    throw StateError(
      'display-name disagreement between scratch JSON and '
      'oot_area_names.c:\n${mismatches.join('\n')}',
    );
  }

  final dungeonIndexByMap = <String, int>{};
  final dungeonRowsByMap = <String, Map<String, Object?>>{};
  for (final row in dungeonRows) {
    final mapKey = _string(row, 'map_key');
    final index = _integer(row, 'dungeon_index_n64_reference');
    if (dungeonIndexByMap.containsKey(mapKey)) {
      throw StateError('duplicate dungeon map key: $mapKey');
    }
    dungeonIndexByMap[mapKey] = index;
    dungeonRowsByMap[mapKey] = row;
  }

  final observedByMap = <String, String>{};
  final observed = <Map<String, Object?>>[];
  for (final row in observedRows) {
    final save = _string(row, 'save');
    final scene = _string(row, 'caption_scene_684');
    final mapPath = _string(row, 'caption_map_748');
    final banc = _string(row, 'sequence_current_banc');
    if (mapPath != '$scene/$banc') {
      throw StateError('$save: map path "$mapPath" is not "$scene/$banc"');
    }
    if (!displayNames.containsKey(banc)) {
      throw StateError('$save: observed map "$banc" is not one of the 80');
    }
    observedByMap[banc] = save;
    observed.add(<String, Object?>{
      'save': save,
      'scene': scene,
      'mapPath': mapPath,
      'banc': banc,
    });
  }
  observed.sort(
    (a, b) => (a['save']! as String).compareTo(b['save']! as String),
  );

  final startsByMap = <String, List<Map<String, Object?>>>{};
  final startKeys = <String>{};
  var defaultStarts = 0;
  for (final row in startRows) {
    final mapKey = _string(row, 'map_key');
    if (!displayNames.containsKey(mapKey)) {
      throw StateError('start position for unknown map: $mapKey');
    }
    final rawName = _string(row, 'start_pos_name');
    final name = _string(row, 'name');
    final isDefault = rawName.isEmpty;
    if (isDefault && name != '(default)') {
      throw StateError('$mapKey: empty start name is labelled "$name"');
    }
    if (isDefault) {
      defaultStarts++;
    }
    final key = '$mapKey/${isDefault ? '(default)' : rawName}';
    if (!startKeys.add(key)) {
      throw StateError('duplicate start position key: $key');
    }
    final start = <String, Object?>{
      'key': key,
      'name': name,
      'rawName': rawName,
      'default': isDefault,
      'position': _doubles(row['pos'], 'pos'),
      'rotation': _doubles(row['rot'], 'rot'),
    };
    startsByMap.putIfAbsent(mapKey, () => <Map<String, Object?>>[]).add(start);
  }
  _expectCount(
    'default start positions',
    defaultStarts,
    _expectedDefaultStartCount,
  );
  for (final starts in startsByMap.values) {
    starts.sort(_compareStarts);
  }

  final maps = <Map<String, Object?>>[];
  for (final row in mapRows) {
    final key = _string(row, 'map_key');
    final baseScene = _string(row, 'scene_key');
    final starts = startsByMap[key] ?? const <Map<String, Object?>>[];
    maps.add(<String, Object?>{
      'key': key,
      'displayName': displayNames[key]!,
      'baseScene': baseScene,
      'startPositions': starts,
      'isDungeon': dungeonIndexByMap.containsKey(key),
      'dungeonIndex': dungeonIndexByMap[key],
      'observed': observedByMap.containsKey(key),
    });
  }
  maps.sort((a, b) => (a['key']! as String).compareTo(b['key']! as String));

  final mapKeys = maps.map((map) => map['key']! as String).toSet();
  final sceneMaps = <String, List<String>>{};
  for (final row in sceneRows) {
    final key = _string(row, 'scene_key');
    final mapsInScene = _strings(row['maps'], 'maps');
    for (final mapKey in mapsInScene) {
      if (!mapKeys.contains(mapKey)) {
        throw StateError('base scene $key names unknown map $mapKey');
      }
    }
    sceneMaps[key] = mapsInScene;
  }

  final baseScenes = <Map<String, Object?>>[];
  for (final row in sceneRows) {
    final key = _string(row, 'scene_key');
    final scratchName = _string(row, 'display_name');
    final displayName = areaNames?.resolve(key) ?? scratchName;
    baseScenes.add(<String, Object?>{
      'key': key,
      'displayName': displayName,
      'maps': sceneMaps[key]!,
      'observed': observedByMap.keys.any(
        (mapKey) => sceneMaps[key]!.contains(mapKey),
      ),
    });
  }
  baseScenes.sort(
    (a, b) => (a['key']! as String).compareTo(b['key']! as String),
  );

  final bossDungeons =
      heartDungeons ??
      <String>{
        for (final row in dungeonRows)
          if (row['n64_reference_boss_scene_id'] != null)
            _string(row, 'map_key'),
      };
  _expectCount('boss dungeons', bossDungeons.length, _expectedBossDungeonCount);

  final dungeons = <Map<String, Object?>>[];
  for (final row in dungeonRows) {
    final mapKey = _string(row, 'map_key');
    if (!mapKeys.contains(mapKey)) {
      throw StateError('dungeon map not among the 80: $mapKey');
    }
    final bossStageKey = _string(row, 'boss_map_key');
    if (!mapKeys.contains(bossStageKey)) {
      throw StateError('$mapKey: boss stage not among the 80: $bossStageKey');
    }
    final hasHeart = bossDungeons.contains(mapKey);
    dungeons.add(<String, Object?>{
      'mapKey': mapKey,
      'displayName': displayNames[mapKey]!,
      'boss': _bossLabel(row, areaNames),
      'bossStageKey': bossStageKey,
      'bossKind': hasHeart ? 'boss' : 'mini-boss',
      'hasBossHeartContainer': hasHeart,
      'dungeonIndex': dungeonIndexByMap[mapKey],
    });
  }
  dungeons.sort(
    (a, b) => (a['dungeonIndex']! as int).compareTo(b['dungeonIndex']! as int),
  );

  return <String, Object?>{
    'provenance': _worldProvenance(
      areaNamesAvailable: areaNames != null,
      heartContainersAvailable: heartDungeons != null,
    ),
    'counts': <String, Object?>{
      'maps': maps.length,
      'baseScenes': baseScenes.length,
      'startPositions': startRows.length,
      'defaultStartPositions': defaultStarts,
      'dungeons': dungeons.length,
      'bossDungeons': bossDungeons.length,
      'observed': observed.length,
    },
    'maps': maps,
    'baseScenes': baseScenes,
    'dungeons': dungeons,
    'observed': observed,
  };
}

int _compareStarts(Map<String, Object?> a, Map<String, Object?> b) {
  final aDefault = a['default']! as bool;
  final bDefault = b['default']! as bool;
  if (aDefault != bDefault) {
    return aDefault ? -1 : 1;
  }
  final byName = (a['name']! as String).toLowerCase().compareTo(
    (b['name']! as String).toLowerCase(),
  );
  if (byName != 0) {
    return byName;
  }
  return (a['key']! as String).compareTo(b['key']! as String);
}

String _bossLabel(Map<String, Object?> row, _AreaNames? areaNames) {
  final raw = _string(row, 'boss_name');
  final mini = raw.indexOf(' (mini-boss');
  if (mini >= 0) {
    return raw.substring(0, mini);
  }
  final none = RegExp(r'^None \(([^;)]*)\)').firstMatch(raw);
  if (none != null) {
    return none.group(1)!.replaceFirst(RegExp(r' mini-boss$'), '').trim();
  }
  if (raw == 'None') {
    final stage = _string(row, 'boss_map_key');
    final label = areaNames?.resolve(stage) ?? stage;
    for (final prefix in <String>[
      'Fighting the ',
      'Fighting an ',
      'Fighting a ',
      'Fighting ',
    ]) {
      if (label.startsWith(prefix)) {
        return label.substring(prefix.length);
      }
    }
    return label;
  }
  return raw;
}

Map<String, Object?> _worldProvenance({
  required bool areaNamesAvailable,
  required bool heartContainersAvailable,
}) {
  return <String, Object?>{
    'title': 'Longshot map, start-position and dungeon catalogue',
    'generatedBy': 'tool/gen_catalogues.dart',
    'catalogueStatus':
        'partial: string identities only; no numeric remake scene id space '
        'proven',
    'game': <String, Object?>{
      'title': _gameTitle,
      'version': _gameVersion,
      'build': _gameBuild,
      'program': _gameProgram,
    },
    'sources': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'longshot-area-names',
        'path': 'Longshot:host/oot_area_names.c',
        'lines': '1-8, 13-98, 100-126',
        'usedFor':
            'English display names for the 80 maps and their base scenes; '
            'the suffix rules and fallback spelling',
      },
      <String, Object?>{
        'id': 'longshot-banc-rsdb',
        'path':
            'Longshot:work/dump/romfs/RSDB/'
            'GameBancInfo.Product.111.rstbl.byml.zs',
        'usedFor': 'the 80 GameBancInfo row ids',
      },
      <String, Object?>{
        'id': 'longshot-banc-params',
        'path':
            'Longshot:work/dump/romfs/Banc/GameBancParam/'
            '*.game__banc__GameBancParam.bgyml',
        'usedFor': 'the 80 map folder names',
      },
      <String, Object?>{
        'id': 'longshot-start-pos',
        'path':
            'Longshot:work/dump/romfs/Banc/BancBasedResource/StartPos.byml.zs',
        'usedFor':
            'the 415 named start positions, with Trans/Rot in metres and '
            'radians; empty names are the 45 defaults',
      },
      <String, Object?>{
        'id': 'longshot-heart-containers',
        'path': 'Longshot:host/oot_heart_containers.c',
        'lines': '121-124',
        'usedFor':
            'the eight dungeons with a boss heart container; the other two '
            'dungeon maps have mini-boss stages',
      },
      <String, Object?>{
        'id': 'longshot-caption',
        'path': 'Longshot:host/control.c',
        'lines': '1869-1898',
        'usedFor': 'caption.sav scene string at 684 and map path at 748',
      },
      <String, Object?>{
        'id': 'longshot-state-tap',
        'path': 'Longshot:host/oot_state_tap.c',
        'lines': '35-36',
        'usedFor': 'Sequence_CurrentBanc, a String64, as the live map name',
      },
      <String, Object?>{
        'id': 'longshot-observed-saves',
        'path':
            'Longshot:assets/saves/{kokiri-start,castle-gate,market-entrance}/'
            'slot_00/{caption,progress}.sav',
        'usedFor': 'the three observed scene/map strings',
      },
      <String, Object?>{
        'id': 'scratch-scenes',
        'path': '/tmp/opencode/catalogue/scenes/scenes.longshot.json',
        'usedFor':
            'the validated extraction of 80 maps, 62 base scenes, 415 start '
            'positions, 10 dungeons and 3 observations',
      },
      <String, Object?>{
        'id': 'ranges',
        'path': '/tmp/opencode/catalogue/scenes/RANGES.md',
        'lines': 'sections 1.3, 2, 3.1, 3.2 and 6',
        'usedFor': 'validation policy and the explicit uncertainty list',
      },
    ],
    'sourceChecks': <String, Object?>{
      'areaNamesParsed': areaNamesAvailable,
      'heartContainersParsed': heartContainersAvailable,
      'displayNamesMatchedAreaNamesC': areaNamesAvailable,
      'startPositionsMatchCounts': true,
    },
    'verified': <String>[
      '80 map identity strings, from GameBancInfo/GameBancParam',
      '62 base scene identity strings, derived from the 80 map names',
      '415 start positions across the 80 maps; 45 have an empty name '
          '(the default entry)',
      '10 pause-menu dungeon maps; eight have a boss heart container',
      '3 scene/map identities seen in the three sample saves',
    ],
    'notVerified': <String>[
      'No numeric remake scene-id space was found; do not invent one',
      'The remake pause-menu dungeon order was not verified; dungeonIndex is '
          'the catalogue/N64 reference order, not a game-verified order',
      'An unknown non-numeric map string is accepted by the layout parser but '
          'the game behaviour is untested',
      'The 77 maps not observed in a sample save are known from game data, '
          'not verified in a save',
      'Bottom of the Well and Ice Cavern are dungeon maps without a boss '
          'heart container; their boss field names a mini-boss',
    ],
  };
}

List<Map<String, Object?>> _parseCheatItems(String source) {
  final rows = <Map<String, Object?>>[];
  String? section;
  final lines = source.split('\n');
  final sectionPattern = RegExp(r'OOT_SECTION\("([^"]+)"\)');
  final itemPattern = RegExp(r'OOT_ITEM\("([^"]+)",\s*"([^"]+)",\s*(\d+)\)');
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final sectionMatch = sectionPattern.firstMatch(line);
    if (sectionMatch != null) {
      section = sectionMatch.group(1);
      continue;
    }
    final itemMatch = itemPattern.firstMatch(line);
    if (itemMatch == null) {
      continue;
    }
    if (section == null) {
      throw StateError('OOT_ITEM before OOT_SECTION at line ${index + 1}');
    }
    rows.add(<String, Object?>{
      'section': section,
      'label': itemMatch.group(1),
      'name': itemMatch.group(2),
      'kind': int.parse(itemMatch.group(3)!),
      'line': index + 1,
    });
  }
  _expectCount('actor/item rows', rows.length, _expectedActorCount);
  return rows;
}

Set<String> _parseHeartDungeons(String source) {
  final match = RegExp(
    r'HEART_DUNGEONS\[HEART_CONTAINERS\]\s*=\s*\{(.*?)\};',
    dotAll: true,
  ).firstMatch(source);
  if (match == null) {
    throw StateError('HEART_DUNGEONS was not found');
  }
  final names = RegExp(r'"([^"]+)"')
      .allMatches(match.group(1)!)
      .map((found) => found.group(1)!)
      .toSet();
  _expectCount('heart dungeons', names.length, _expectedBossDungeonCount);
  return names;
}

Map<String, Object?> _buildActors(List<Map<String, Object?>> rows) {
  final equipment = <Map<String, Object?>>[];
  final items = <Map<String, Object?>>[];
  final songs = <Map<String, Object?>>[];
  final bottles = <Map<String, Object?>>[];
  final names = <String>{};

  for (final row in rows) {
    final section = row['section']! as String;
    final name = row['name']! as String;
    final label = row['label']! as String;
    final quantity = row['kind']! as int;
    if (!names.add(name)) {
      throw StateError('duplicate actor/item name: $name');
    }
    final (:bucket, :kind) = _classifyActor(section, name);
    final labelInferred = label.trim().isEmpty;
    final displayName = labelInferred ? name.replaceAll('_', ' ') : label;
    final entry = <String, Object?>{
      'name': name,
      'kind': kind,
      'displayName': displayName,
      'labelInferred': labelInferred,
      'section': section,
      'stackable': quantity == 1,
      'sourceLine': row['line'],
    };
    switch (bucket) {
      case 'equipment':
        equipment.add(entry);
      case 'items':
        items.add(entry);
      case 'songs':
        songs.add(entry);
      case 'bottles':
        bottles.add(entry);
      default:
        throw StateError('unknown actor bucket: $bucket');
    }
  }

  for (final bucket in <List<Map<String, Object?>>>[
    equipment,
    items,
    songs,
    bottles,
  ]) {
    bucket.sort(
      (a, b) => (a['name']! as String).compareTo(b['name']! as String),
    );
  }

  return <String, Object?>{
    'provenance': <String, Object?>{
      'title': 'Longshot actor/item name catalogue',
      'generatedBy': 'tool/gen_catalogues.dart',
      'game': <String, Object?>{
        'title': _gameTitle,
        'version': _gameVersion,
        'build': _gameBuild,
        'program': _gameProgram,
      },
      'source': <String, Object?>{
        'id': 'longshot-cheat-items',
        'path': 'Longshot:gpu/vk/oot_cheat_items.h',
        'lines': '1-110',
        'usedFor':
            'the 86 OOT_ITEM(label, pouch name, kind) rows shared by the '
            'inventory editor and the game side',
      },
      'classification': <String, Object?>{
        'equipment':
            'OOT_SECTION Equipment and Masks; kind is sword, shield, tunic, '
            'boots or mask',
        'items':
            'OOT_SECTION Items except Item_Bottle, all of Upgrades, and Quest '
            'rows other than the twelve melodies',
        'songs': 'Quest rows named Item_Melody_*',
        'bottles': 'the Item_Bottle row',
      },
      'labelPolicy':
          'displayName is the first OOT_ITEM argument, so labelInferred is '
          'false for every row. If a label were absent the generator would '
          'use the exact game string with underscores replaced by spaces and '
          'set labelInferred true.',
      'excluded': <String>[
        'OOT_CHEAT_ITEM_PROBES spellings are unverified guesses and are not '
            'accepted names; the game logs them to check the real spelling.',
        'The N64 ItemID catalogue (items.json) is not applicable to Longshot '
            'and is not imported.',
      ],
      'notVerified': <String>[
        'Whether the save container accepts every one of these strings in '
            'every slot is not proven by the header alone',
        'Display labels are the inventory editor labels, not game-localized '
            'message text',
      ],
    },
    'counts': <String, Object?>{
      'equipment': equipment.length,
      'items': items.length,
      'songs': songs.length,
      'bottles': bottles.length,
      'total': equipment.length + items.length + songs.length + bottles.length,
    },
    'equipment': equipment,
    'items': items,
    'songs': songs,
    'bottles': bottles,
  };
}

({String bucket, String kind}) _classifyActor(String section, String name) {
  switch (section) {
    case 'Equipment':
      return (bucket: 'equipment', kind: _equipmentKind(name));
    case 'Masks':
      return (bucket: 'equipment', kind: 'mask');
    case 'Items':
      if (name == 'Item_Bottle') {
        return (bucket: 'bottles', kind: 'bottle');
      }
      return (bucket: 'items', kind: 'item');
    case 'Upgrades':
      return (bucket: 'items', kind: 'upgrade');
    case 'Quest':
      if (name.startsWith('Item_Melody_')) {
        return (bucket: 'songs', kind: 'song');
      }
      return (bucket: 'items', kind: 'quest');
    default:
      throw StateError('unknown OOT_SECTION: $section');
  }
}

String _equipmentKind(String name) {
  if (name.startsWith('Weapon_Sword_')) {
    return 'sword';
  }
  if (name.startsWith('Weapon_Shield_')) {
    return 'shield';
  }
  if (name == 'Armor_Adult_Goron' || name == 'Armor_Adult_Zora') {
    return 'tunic';
  }
  if (name.endsWith('Boot')) {
    return 'boots';
  }
  if (name.startsWith('Armor_Child_Mask_')) {
    return 'mask';
  }
  throw StateError('unclassified Equipment row: $name');
}

Map<String, Object?> _readObject(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw FormatException('${file.path}: expected a JSON object');
  }
  return decoded;
}

List<Map<String, Object?>> _objects(Object? value, String label) {
  if (value is! List<Object?>) {
    throw FormatException('$label: expected a list');
  }
  return <Map<String, Object?>>[
    for (final entry in value)
      if (entry is Map<String, Object?>)
        entry
      else
        throw FormatException('$label: expected an object in the list'),
  ];
}

String _string(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! String) {
    throw FormatException('$key: expected a string');
  }
  return value;
}

int _integer(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! int) {
    throw FormatException('$key: expected an integer');
  }
  return value;
}

List<String> _strings(Object? value, String label) {
  if (value is! List<Object?>) {
    throw FormatException('$label: expected a list');
  }
  return <String>[
    for (final entry in value)
      if (entry is String)
        entry
      else
        throw FormatException('$label: expected a string in the list'),
  ];
}

List<double> _doubles(Object? value, String label) {
  if (value is! List<Object?> || value.length != 3) {
    throw FormatException('$label: expected three numbers');
  }
  return <double>[
    for (final entry in value)
      if (entry is num)
        entry.toDouble()
      else
        throw FormatException('$label: expected a number'),
  ];
}

void _expectCount(String label, int actual, int expected) {
  if (actual != expected) {
    throw StateError('$label: expected $expected, found $actual');
  }
}

/// Canonical JSON: sorted object keys, two-space indent, one trailing newline.
String _canonicalJson(Object? value) {
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(_sortKeys(value))}\n';
}

Object? _sortKeys(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _sortKeys(value[key]),
    };
  }
  if (value is List<Object?>) {
    return <Object?>[for (final entry in value) _sortKeys(entry)];
  }
  return value;
}
