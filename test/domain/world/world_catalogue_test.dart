import 'dart:io';

import 'package:bomb_flower/domain/world/world_catalogue.dart' as world;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('verified world catalogue', () {
    late world.WorldCatalogue catalogue;

    setUpAll(() async {
      final file = File('assets/world/scenes.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'run `dart run tool/gen_catalogues.dart` to create it',
      );
      catalogue = world.loadWorldCatalogue(await file.readAsString());
    });

    test(
      'loads 80 maps, 62 base scenes, 415 starts, 10 dungeons and 3 saves',
      () {
        expect(catalogue.maps, hasLength(80));
        expect(catalogue.baseScenes, hasLength(62));
        expect(catalogue.startPositions, hasLength(415));
        expect(catalogue.dungeons, hasLength(10));
        expect(catalogue.observed, hasLength(3));
        expect(catalogue.maps.where((map) => map.observed), hasLength(3));
        expect(
          catalogue.maps.fold<int>(
            0,
            (total, map) => total + map.startPositions.length,
          ),
          415,
        );
      },
    );

    test('has no duplicate map, base scene, dungeon or start keys', () {
      final mapKeys = catalogue.maps.map((map) => map.key).toList();
      expect(mapKeys.toSet(), hasLength(mapKeys.length));

      final sceneKeys = catalogue.baseScenes.map((scene) => scene.key).toList();
      expect(sceneKeys.toSet(), hasLength(sceneKeys.length));

      final dungeonMaps = catalogue.dungeons
          .map((dungeon) => dungeon.mapKey)
          .toList();
      expect(dungeonMaps.toSet(), hasLength(dungeonMaps.length));

      final startKeys = catalogue.startPositions
          .map((start) => start.key)
          .toList();
      expect(startKeys.toSet(), hasLength(startKeys.length));
    });

    test('every dungeon has a boss stage and a non-empty boss label', () {
      for (final dungeon in catalogue.dungeons) {
        expect(dungeon.boss.trim(), isNotEmpty, reason: dungeon.mapKey);
        expect(catalogue.byKey(dungeon.bossStageKey), isNotNull);
        expect(catalogue.dungeonFor(dungeon.mapKey), isNotNull);
      }
      expect(
        catalogue.dungeons.where((dungeon) => dungeon.hasBossHeartContainer),
        hasLength(8),
      );
      expect(
        catalogue.dungeons.where((dungeon) => dungeon.bossKind == 'mini-boss'),
        hasLength(2),
      );
    });

    test('dungeon marks and indices agree with the dungeon records', () {
      final dungeonMaps = catalogue.maps.where((map) => map.isDungeon).toList();
      expect(dungeonMaps, hasLength(10));
      for (final map in dungeonMaps) {
        expect(map.dungeonIndex, isNotNull);
        final dungeon = catalogue.dungeonFor(map.key);
        expect(dungeon, isNotNull);
        expect(dungeon!.dungeonIndex, map.dungeonIndex);
      }
      for (final map in catalogue.maps.where((map) => !map.isDungeon)) {
        expect(map.dungeonIndex, isNull);
      }
    });

    test('all 415 start positions carry a default flag and coordinates', () {
      final defaults = catalogue.startPositions
          .where((start) => start.isDefault)
          .toList();
      expect(defaults, hasLength(45));
      for (final start in defaults) {
        expect(start.name, '(default)');
        expect(start.rawName, isEmpty);
        expect(start.key, '${start.mapKey}/(default)');
      }
      for (final start in catalogue.startPositions) {
        expect(start.position, hasLength(3));
        expect(start.rotation, hasLength(3));
        expect(catalogue.byKey(start.mapKey), isNotNull);
        if (!start.isDefault) {
          expect(start.name, start.rawName);
          expect(start.key, '${start.mapKey}/${start.rawName}');
        }
      }
      expect(catalogue.startPositionsFor('KokiriForest_Child'), isNotEmpty);
      expect(catalogue.startPositionsFor('NowhereLand'), isEmpty);
    });

    test('all 80 maps and 62 base scenes validate as known', () {
      for (final map in catalogue.maps) {
        expect(
          catalogue.validateMapPath(map.key),
          world.MapValidation.known,
          reason: map.key,
        );
        expect(
          catalogue.validateMapPath('${map.baseScene}/${map.key}'),
          world.MapValidation.known,
          reason: '${map.baseScene}/${map.key}',
        );
      }
      for (final scene in catalogue.baseScenes) {
        expect(
          catalogue.validateMapPath(scene.key),
          world.MapValidation.known,
          reason: scene.key,
        );
      }
    });

    test(
      'validates the observed paths and rejects unknown or numeric input',
      () {
        expect(
          catalogue.validateMapPath('KokiriForest/KokiriForest_Child'),
          world.MapValidation.known,
        );
        expect(
          catalogue.validateMapPath('Market/Market_Child'),
          world.MapValidation.known,
        );
        expect(
          catalogue.validateMapPath('NowhereLand'),
          world.MapValidation.unknownWarn,
        );
        expect(
          catalogue.validateMapPath('KokiriForest/NowhereLand'),
          world.MapValidation.unknownWarn,
        );
        expect(
          catalogue.validateMapPath('NowhereLand/KokiriForest_Child'),
          world.MapValidation.unknownWarn,
        );
        expect(catalogue.validateMapPath(''), world.MapValidation.unknownWarn);
        for (final numeric in <String>[
          '42',
          '0',
          '-1',
          '0x55',
          '0X2A',
          ' 42 ',
        ]) {
          expect(
            catalogue.validateMapPath(numeric),
            world.MapValidation.rejectedNumericId,
            reason: numeric,
          );
        }
      },
    );

    test(
      'search is case- and diacritic-insensitive over key and display name',
      () {
        final kokiri = catalogue.search('kokiri');
        expect(kokiri.map((map) => map.displayName), contains('Kokiri Forest'));
        expect(
          catalogue.search('KOKIRI').map((map) => map.displayName),
          contains('Kokiri Forest'),
        );
        expect(
          catalogue.search('kókírí').map((map) => map.displayName),
          contains('Kokiri Forest'),
        );
        expect(catalogue.search('forest'), isNotEmpty);
        expect(catalogue.search('nowhere-land'), isEmpty);
      },
    );

    test('observed saves agree with the verified paths and scenes', () {
      for (final observation in catalogue.observed) {
        final map = catalogue.byKey(observation.banc);
        expect(map, isNotNull, reason: observation.save);
        expect(observation.mapPath, '${observation.scene}/${observation.banc}');
        expect(map!.baseScene, observation.scene);
        expect(map.observed, isTrue);
      }
      expect(
        catalogue.observed.map((observation) => observation.save),
        <String>['castle-gate', 'kokiri-start', 'market-entrance'],
      );
      expect(
        catalogue.byKey('KokiriForest_Child')?.displayName,
        'Kokiri Forest',
      );
      expect(catalogue.byKey('NotAMap'), isNull);
      expect(
        catalogue.baseSceneByKey('KokiriForest')?.maps,
        contains('KokiriForest_Child'),
      );
    });

    test('asset provenance keeps its citations', () {
      final sources = catalogue.provenance['sources'];
      expect(sources, isA<List<Object?>>());
      expect((sources! as List<Object?>).length, greaterThanOrEqualTo(8));
      expect(catalogue.provenance['notVerified'], isA<List<Object?>>());
    });
  });
}
