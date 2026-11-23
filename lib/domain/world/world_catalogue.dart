/// Immutable, verified Longshot map, start-position and dungeon catalogue.
///
/// The save stores string identities, not N64 numeric scene ids. This library
/// therefore accepts the 80 known map strings and their 62 base scene strings,
/// warns on any other non-numeric string, and rejects purely numeric ids.
///
/// The model class [MapEntry] intentionally has the product name. Import this
/// library with a prefix when `dart:core`'s `MapEntry` is also in scope:
///
/// ```dart
/// import 'package:bomb_flower/domain/world/world_catalogue.dart' as world;
/// ```
library;

import 'dart:convert';

/// Result of validating a string that will be written into a Longshot map or
/// scene field.
enum MapValidation {
  /// One of the 80 known map keys, one of the 62 base scenes, or an exact
  /// `baseScene/mapKey` path from the catalogue.
  known,

  /// A non-numeric string the catalogue does not know. The layout accepts it,
  /// but the game's behaviour is untested; do not present it as verified.
  unknownWarn,

  /// A purely numeric N64-style scene id. Longshot string fields do not use a
  /// numeric scene-id space.
  rejectedNumericId;

  /// Whether the value matches a catalogued identity.
  bool get isKnown => this == MapValidation.known;

  /// Whether the value is a numeric id that must not be written.
  bool get isRejected => this == MapValidation.rejectedNumericId;

  /// Whether a UI may write the value only after an explicit warning.
  bool get requiresConfirmation => this == MapValidation.unknownWarn;
}

/// One named spawn point from `StartPos.byml.zs`.
final class StartPosition {
  /// Creates a start position.
  const StartPosition({
    required this.key,
    required this.mapKey,
    required this.name,
    required this.rawName,
    required this.isDefault,
    required this.position,
    required this.rotation,
  });

  /// Reads one start position; [mapKey] comes from the enclosing map entry.
  factory StartPosition.fromJson(
    Map<String, Object?> json, {
    required String mapKey,
  }) {
    return StartPosition(
      key: _string(json, 'key'),
      mapKey: mapKey,
      name: _string(json, 'name'),
      rawName: _string(json, 'rawName'),
      isDefault: _bool(json, 'default'),
      position: _doubleList(json['position'], 'position'),
      rotation: _doubleList(json['rotation'], 'rotation'),
    );
  }

  /// Stable catalogue key, `mapKey/(default)` or `mapKey/rawName`.
  final String key;

  /// The map this spawn belongs to.
  final String mapKey;

  /// Display label; `(default)` for the 45 empty-named entries.
  final String name;

  /// The exact BYML name; empty for a default entry.
  final String rawName;

  /// Whether the BYML name was empty.
  final bool isDefault;

  /// Translation in metres as stored in the game data.
  final List<double> position;

  /// Rotation in radians as stored in the game data.
  final List<double> rotation;

  @override
  String toString() => 'StartPosition($key, $name)';
}

/// One of the 80 map identities from `GameBancInfo`/`GameBancParam`.
final class MapEntry {
  /// Creates a map entry.
  MapEntry({
    required this.key,
    required this.displayName,
    required this.baseScene,
    required Iterable<StartPosition> startPositions,
    required this.isDungeon,
    required this.dungeonIndex,
    required this.observed,
  }) : startPositions = List<StartPosition>.unmodifiable(startPositions);

  /// Reads a map entry from the generated JSON.
  factory MapEntry.fromJson(Map<String, Object?> json) {
    final key = _string(json, 'key');
    final starts = _objectList(json['startPositions'], 'startPositions')
        .map((entry) => StartPosition.fromJson(entry, mapKey: key))
        .toList(growable: false);
    return MapEntry(
      key: key,
      displayName: _string(json, 'displayName'),
      baseScene: _string(json, 'baseScene'),
      startPositions: starts,
      isDungeon: _bool(json, 'isDungeon'),
      dungeonIndex: _nullableInt(json['dungeonIndex'], 'dungeonIndex'),
      observed: _bool(json, 'observed'),
    );
  }

  /// The exact string stored in `Sequence_CurrentBanc`, such as
  /// `KokiriForest_Child`.
  final String key;

  /// Longshot's English map label, such as `Kokiri Forest`.
  final String displayName;

  /// The base scene string, such as `KokiriForest`.
  final String baseScene;

  /// All named spawn points on this map.
  final List<StartPosition> startPositions;

  /// Whether this is one of the ten pause-menu dungeon maps.
  final bool isDungeon;

  /// Catalogue dungeon order, or `null` for a non-dungeon map.
  ///
  /// This follows the ten N64 pause-menu dungeon maps as a display
  /// convention. The remake's own pause-menu order was not verified.
  final int? dungeonIndex;

  /// Whether one of the three sample saves was observed on this map.
  final bool observed;

  @override
  String toString() => 'MapEntry($key, $displayName)';
}

/// One of the 62 base scene identities derived from the 80 map names.
final class BaseSceneEntry {
  /// Creates a base scene entry.
  BaseSceneEntry({
    required this.key,
    required this.displayName,
    required Iterable<String> maps,
    required this.observed,
  }) : maps = List<String>.unmodifiable(maps);

  /// Reads a base scene from the generated JSON.
  factory BaseSceneEntry.fromJson(Map<String, Object?> json) {
    return BaseSceneEntry(
      key: _string(json, 'key'),
      displayName: _string(json, 'displayName'),
      maps: _stringList(json['maps'], 'maps'),
      observed: _bool(json, 'observed'),
    );
  }

  /// The base string, such as `KokiriForest`.
  final String key;

  /// Longshot's English label, such as `Kokiri Forest`.
  final String displayName;

  /// The map keys that belong to this base scene.
  final List<String> maps;

  /// Whether one of the observed samples used a map in this scene.
  final bool observed;

  @override
  String toString() => 'BaseSceneEntry($key, $displayName)';
}

/// One of the ten pause-menu dungeon maps.
final class DungeonEntry {
  /// Creates a dungeon entry.
  const DungeonEntry({
    required this.mapKey,
    required this.displayName,
    required this.boss,
    required this.bossStageKey,
    required this.bossKind,
    required this.hasBossHeartContainer,
    required this.dungeonIndex,
  });

  /// Reads a dungeon entry from the generated JSON.
  factory DungeonEntry.fromJson(Map<String, Object?> json) {
    return DungeonEntry(
      mapKey: _string(json, 'mapKey'),
      displayName: _string(json, 'displayName'),
      boss: _string(json, 'boss'),
      bossStageKey: _string(json, 'bossStageKey'),
      bossKind: _string(json, 'bossKind'),
      hasBossHeartContainer: _bool(json, 'hasBossHeartContainer'),
      dungeonIndex: _int(json, 'dungeonIndex'),
    );
  }

  /// The dungeon's map key, such as `InsideTheDekuTree`.
  final String mapKey;

  /// Longshot's English dungeon label.
  final String displayName;

  /// The boss or mini-boss name, never empty.
  final String boss;

  /// The map key of the boss or mini-boss stage, such as `GohmaStage`.
  final String bossStageKey;

  /// `boss` or `mini-boss`.
  final String bossKind;

  /// Whether Longshot places a boss heart container in this dungeon.
  final bool hasBossHeartContainer;

  /// Catalogue dungeon order; see [MapEntry.dungeonIndex].
  final int dungeonIndex;

  @override
  String toString() => 'DungeonEntry($mapKey, $boss)';
}

/// One scene/map pair observed in a repository sample save.
final class ObservedScene {
  /// Creates an observation.
  const ObservedScene({
    required this.save,
    required this.scene,
    required this.mapPath,
    required this.banc,
  });

  /// Reads an observation from the generated JSON.
  factory ObservedScene.fromJson(Map<String, Object?> json) {
    return ObservedScene(
      save: _string(json, 'save'),
      scene: _string(json, 'scene'),
      mapPath: _string(json, 'mapPath'),
      banc: _string(json, 'banc'),
    );
  }

  /// Sample save directory name, such as `kokiri-start`.
  final String save;

  /// `caption.sav` scene string at 684.
  final String scene;

  /// `caption.sav` map path at 748.
  final String mapPath;

  /// `Sequence_CurrentBanc`, the last component of [mapPath].
  final String banc;

  @override
  String toString() => 'ObservedScene($save, $mapPath)';
}

/// The verified Longshot world catalogue.
final class WorldCatalogue {
  /// Creates a catalogue and checks its cross-references.
  WorldCatalogue({
    required Map<String, Object?> provenance,
    required Iterable<MapEntry> maps,
    required Iterable<BaseSceneEntry> baseScenes,
    required Iterable<DungeonEntry> dungeons,
    required Iterable<ObservedScene> observed,
  }) : provenance = _freezeMap(provenance),
       maps = List<MapEntry>.unmodifiable(maps),
       baseScenes = List<BaseSceneEntry>.unmodifiable(baseScenes),
       dungeons = List<DungeonEntry>.unmodifiable(dungeons),
       observed = List<ObservedScene>.unmodifiable(observed) {
    _index();
  }

  /// Reads a catalogue from already-decoded JSON.
  factory WorldCatalogue.fromJson(Map<String, Object?> json) {
    return WorldCatalogue(
      provenance: _object(json['provenance'], 'provenance'),
      maps: _objectList(
        json['maps'],
        'maps',
      ).map(MapEntry.fromJson).toList(growable: false),
      baseScenes: _objectList(
        json['baseScenes'],
        'baseScenes',
      ).map(BaseSceneEntry.fromJson).toList(growable: false),
      dungeons: _objectList(
        json['dungeons'],
        'dungeons',
      ).map(DungeonEntry.fromJson).toList(growable: false),
      observed: _objectList(
        json['observed'],
        'observed',
      ).map(ObservedScene.fromJson).toList(growable: false),
    );
  }

  /// Provenance and citation record from the asset.
  final Map<String, Object?> provenance;

  /// The 80 maps, sorted by key in the generated asset.
  final List<MapEntry> maps;

  /// The 62 base scenes, sorted by key.
  final List<BaseSceneEntry> baseScenes;

  /// The ten pause-menu dungeon maps, in catalogue order.
  final List<DungeonEntry> dungeons;

  /// The three scene/map pairs seen in sample saves.
  final List<ObservedScene> observed;

  late final Map<String, MapEntry> _byKey;
  late final Map<String, BaseSceneEntry> _baseSceneByKey;
  late final Map<String, DungeonEntry> _dungeonByMap;
  late final List<StartPosition> _startPositions;

  /// All 415 start positions across all maps.
  List<StartPosition> get startPositions => _startPositions;

  /// Looks up a map by its exact game string.
  MapEntry? byKey(String key) => _byKey[key];

  /// Looks up a base scene by its exact game string.
  BaseSceneEntry? baseSceneByKey(String key) => _baseSceneByKey[key];

  /// Looks up the dungeon record for a dungeon map key.
  DungeonEntry? dungeonFor(String mapKey) => _dungeonByMap[mapKey];

  /// Start positions for [mapKey], empty when the map is unknown.
  List<StartPosition> startPositionsFor(String mapKey) =>
      _byKey[mapKey]?.startPositions ?? const <StartPosition>[];

  /// Case- and diacritic-insensitive substring search over map keys and
  /// display names.
  List<MapEntry> search(String query) {
    final needle = _fold(query);
    final matches = <MapEntry>[
      for (final map in maps)
        if (_fold(map.key).contains(needle) ||
            _fold(map.displayName).contains(needle))
          map,
    ];
    matches.sort((a, b) {
      final byDisplay = _fold(a.displayName).compareTo(_fold(b.displayName));
      return byDisplay != 0 ? byDisplay : a.key.compareTo(b.key);
    });
    return List<MapEntry>.unmodifiable(matches);
  }

  /// Validates a candidate value for a map or scene string field.
  ///
  /// Accepts an exact map key, an exact base scene key, or an exact
  /// `baseScene/mapKey` path. Numeric N64-style ids are rejected; every other
  /// non-numeric string is an unknown warning.
  MapValidation validateMapPath(String value) {
    final trimmed = value.trim();
    if (_decimalId.hasMatch(trimmed) || _hexId.hasMatch(trimmed)) {
      return MapValidation.rejectedNumericId;
    }
    if (_byKey.containsKey(value) || _baseSceneByKey.containsKey(value)) {
      return MapValidation.known;
    }
    final slash = value.indexOf('/');
    if (slash > 0 &&
        slash < value.length - 1 &&
        value.indexOf('/', slash + 1) < 0) {
      final scene = value.substring(0, slash);
      final mapKey = value.substring(slash + 1);
      final map = _byKey[mapKey];
      if (map != null && map.baseScene == scene) {
        return MapValidation.known;
      }
    }
    return MapValidation.unknownWarn;
  }

  void _index() {
    final byKey = <String, MapEntry>{};
    final starts = <StartPosition>[];
    final startKeys = <String>{};
    for (final map in maps) {
      if (byKey.containsKey(map.key)) {
        throw FormatException('duplicate map key: ${map.key}');
      }
      byKey[map.key] = map;
      if (map.isDungeon != (map.dungeonIndex != null)) {
        throw FormatException(
          '${map.key}: isDungeon and dungeonIndex disagree',
        );
      }
      for (final start in map.startPositions) {
        if (start.mapKey != map.key) {
          throw FormatException(
            '${start.key}: mapKey ${start.mapKey} does not match ${map.key}',
          );
        }
        if (!startKeys.add(start.key)) {
          throw FormatException('duplicate start position key: ${start.key}');
        }
        starts.add(start);
      }
    }

    final baseSceneByKey = <String, BaseSceneEntry>{};
    for (final scene in baseScenes) {
      if (baseSceneByKey.containsKey(scene.key)) {
        throw FormatException('duplicate base scene key: ${scene.key}');
      }
      baseSceneByKey[scene.key] = scene;
      for (final mapKey in scene.maps) {
        final map = byKey[mapKey];
        if (map == null) {
          throw FormatException('${scene.key}: names unknown map $mapKey');
        }
        if (map.baseScene != scene.key) {
          throw FormatException(
            '${scene.key}: $mapKey belongs to ${map.baseScene}',
          );
        }
      }
    }
    for (final map in maps) {
      if (!baseSceneByKey.containsKey(map.baseScene)) {
        throw FormatException(
          '${map.key}: unknown base scene ${map.baseScene}',
        );
      }
    }

    final dungeonByMap = <String, DungeonEntry>{};
    for (final dungeon in dungeons) {
      if (dungeonByMap.containsKey(dungeon.mapKey)) {
        throw FormatException('duplicate dungeon map: ${dungeon.mapKey}');
      }
      final map = byKey[dungeon.mapKey];
      if (map == null) {
        throw FormatException('dungeon map not found: ${dungeon.mapKey}');
      }
      if (!map.isDungeon || map.dungeonIndex != dungeon.dungeonIndex) {
        throw FormatException(
          '${dungeon.mapKey}: dungeon record does not match map entry',
        );
      }
      if (!byKey.containsKey(dungeon.bossStageKey)) {
        throw FormatException(
          '${dungeon.mapKey}: unknown boss stage ${dungeon.bossStageKey}',
        );
      }
      dungeonByMap[dungeon.mapKey] = dungeon;
    }
    for (final map in maps.where((entry) => entry.isDungeon)) {
      if (!dungeonByMap.containsKey(map.key)) {
        throw FormatException('${map.key}: dungeon record is missing');
      }
    }

    for (final observation in observed) {
      final map = byKey[observation.banc];
      if (map == null) {
        throw FormatException(
          '${observation.save}: unknown observed map ${observation.banc}',
        );
      }
      if (map.baseScene != observation.scene) {
        throw FormatException(
          '${observation.save}: scene ${observation.scene} does not match '
          '${map.baseScene}',
        );
      }
      if (observation.mapPath != '${observation.scene}/${observation.banc}') {
        throw FormatException(
          '${observation.save}: mapPath ${observation.mapPath} is not '
          'scene/banc',
        );
      }
    }

    _byKey = Map<String, MapEntry>.unmodifiable(byKey);
    _baseSceneByKey = Map<String, BaseSceneEntry>.unmodifiable(baseSceneByKey);
    _dungeonByMap = Map<String, DungeonEntry>.unmodifiable(dungeonByMap);
    _startPositions = List<StartPosition>.unmodifiable(starts);
  }

  @override
  String toString() =>
      'WorldCatalogue(${maps.length} maps, ${baseScenes.length} base scenes, '
      '${_startPositions.length} starts, ${dungeons.length} dungeons)';
}

/// Loads a catalogue from the JSON text of `assets/world/scenes.json`.
WorldCatalogue loadWorldCatalogue(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('world catalogue: expected a JSON object');
  }
  return WorldCatalogue.fromJson(decoded);
}

final RegExp _decimalId = RegExp(r'^-?[0-9]+$');
final RegExp _hexId = RegExp(r'^0[xX][0-9a-fA-F]+$');

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$label: expected an object');
  }
  return value;
}

List<Map<String, Object?>> _objectList(Object? value, String label) {
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

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('$key: expected a string');
  }
  return value;
}

bool _bool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw FormatException('$key: expected a boolean');
  }
  return value;
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('$key: expected an integer');
  }
  return value;
}

int? _nullableInt(Object? value, String label) {
  if (value == null) {
    return null;
  }
  if (value is! int) {
    throw FormatException('$label: expected an integer or null');
  }
  return value;
}

List<String> _stringList(Object? value, String label) {
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

List<double> _doubleList(Object? value, String label) {
  if (value is! List<Object?>) {
    throw FormatException('$label: expected a list');
  }
  return List<double>.unmodifiable(<double>[
    for (final entry in value)
      if (entry is num)
        entry.toDouble()
      else
        throw FormatException('$label: expected a number in the list'),
  ]);
}

Map<String, Object?> _freezeMap(Map<String, Object?> source) {
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final entry in source.entries) entry.key: _freeze(entry.value),
  });
}

Object? _freeze(Object? value) {
  if (value is Map<String, Object?>) {
    return _freezeMap(value);
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(<Object?>[
      for (final entry in value) _freeze(entry),
    ]);
  }
  return value;
}

/// Lower-cases and removes common Latin diacritics for search.
String _fold(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final character = String.fromCharCode(rune);
    buffer.write(_diacritics[character] ?? character);
  }
  return buffer.toString();
}

const Map<String, String> _diacritics = <String, String>{
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'ĉ': 'c',
  'ċ': 'c',
  'ď': 'd',
  'đ': 'd',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ė': 'e',
  'ę': 'e',
  'ě': 'e',
  'ĝ': 'g',
  'ğ': 'g',
  'ġ': 'g',
  'ģ': 'g',
  'ĥ': 'h',
  'ħ': 'h',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'į': 'i',
  'ı': 'i',
  'ĵ': 'j',
  'ķ': 'k',
  'ĺ': 'l',
  'ļ': 'l',
  'ľ': 'l',
  'ł': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ņ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ő': 'o',
  'ŕ': 'r',
  'ř': 'r',
  'ś': 's',
  'š': 's',
  'ş': 's',
  'ș': 's',
  'ť': 't',
  'ț': 't',
  'ţ': 't',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ű': 'u',
  'ų': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ź': 'z',
  'ż': 'z',
  'ž': 'z',
};
