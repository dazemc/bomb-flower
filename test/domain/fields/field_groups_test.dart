import 'dart:convert';
import 'dart:io';

import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/gen_field_groups.dart' as generator;

void main() {
  group('verified field-group catalogue', () {
    late GameDataSchema schema;
    late FieldGroupsCatalogue catalogue;

    setUpAll(() async {
      final schemaFile = File('assets/schema/gamedata_110.json');
      final groupsFile = File('assets/fields/groups.json');
      expect(
        groupsFile.existsSync(),
        isTrue,
        reason: 'run `dart run tool/gen_field_groups.dart` to create it',
      );
      schema = GameDataSchema.fromJsonString(await schemaFile.readAsString());
      catalogue = FieldGroupsCatalogue.load(await groupsFile.readAsString());
    });

    test('loads exactly the eleven tabs in enum order', () {
      expect(
        catalogue.stats.tabs.map((row) => row.tab),
        orderedEquals(EditorTabGroup.values),
      );
      for (final tab in EditorTabGroup.values) {
        expect(catalogue.forTab(tab), isNotEmpty, reason: tab.id);
        expect(catalogue.stats.forTab(tab).tab, tab);
      }
      expect(
        catalogue.groups.map((group) => group.id).toSet(),
        hasLength(catalogue.groups.length),
      );
    });

    test('every field exists in the schema with its exact name and type', () {
      for (final group in catalogue.groups) {
        for (final field in group.fields) {
          final definition = schema.byHashOnDisk(field.hash);
          expect(
            definition,
            isNotNull,
            reason: '${group.id}: missing ${field.name} ${field.hashHex}',
          );
          expect(
            definition!.name,
            field.name,
            reason: '${field.hashHex} name mismatch in ${group.id}',
          );
          expect(
            definition.type.wireName,
            field.type,
            reason: '${field.name} type mismatch',
          );
          expect(
            definition.section,
            field.section,
            reason: '${field.name} section mismatch',
          );
          expect(definition.presentOnDisk, isTrue, reason: field.name);
          expect(definition.verified, isTrue, reason: field.name);
          expect(field.name.trim(), isNotEmpty, reason: group.id);
        }
      }
    });

    test('no group references a null or fabricated name', () {
      final names = schema.namedFields.map((field) => field.name).toSet();
      for (final group in catalogue.groups) {
        for (final field in group.fields) {
          expect(
            names,
            contains(field.name),
            reason: '${group.id} invented ${field.name}',
          );
        }
        for (final opaque in group.opaqueFields) {
          final definition = schema.byHashOnDisk(opaque.hash);
          expect(definition, isNotNull, reason: group.id);
          expect(
            definition!.name,
            isNull,
            reason: 'opaque ${opaque.hashHex} must not have a name',
          );
        }
      }
    });

    test('every tab has groups and every tab but settings has counts', () {
      for (final tab in EditorTabGroup.values) {
        final groups = catalogue.forTab(tab);
        final stats = catalogue.stats.forTab(tab);
        expect(groups, isNotEmpty, reason: tab.id);
        expect(stats.groups, groups.length, reason: tab.id);
        if (tab == EditorTabGroup.settings) {
          expect(stats.named, 0);
          expect(stats.unnamed, 0);
          expect(groups.single.fields, isEmpty);
          expect(groups.single.unnamedCount, 0);
          expect(stats.caveat, contains('No progress.sav fields'));
          expect(groups.single.caveat, isNotNull);
        } else {
          expect(
            stats.named + stats.unnamed,
            greaterThan(0),
            reason: '${tab.id} must expose at least one field or count',
          );
        }
      }
    });

    test('overview contains the documented headline scalars', () {
      final group = catalogue.groupById('overview.headline');
      expect(group, isNotNull);
      expect(group!.provenance, FieldProvenance.observed);
      final names = group.fields.map((field) => field.name).toSet();
      expect(
        names,
        containsAll(<String>[
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
        ]),
      );
    });

    test('search is case- and diacritic-insensitive and finds hashes', () {
      final life = catalogue.search('life').map((field) => field.name).toSet();
      expect(life, contains('PlayerStatus.Life'));
      expect(life, contains('PlayerStatus.MaxLife'));
      expect(
        catalogue.search('LIFE').map((field) => field.name),
        orderedEquals(catalogue.search('life').map((field) => field.name)),
      );
      expect(
        catalogue.search('Ōcarina').map((field) => field.name),
        orderedEquals(catalogue.search('ocarina').map((field) => field.name)),
      );

      final byHash = catalogue.search('0x31ab5580');
      expect(byHash, hasLength(1));
      expect(byHash.single.name, 'PlayerStatus.Life');
      expect(byHash.single.hashHex, '0x31ab5580');
      expect(catalogue.search('0x31AB5580').single.name, 'PlayerStatus.Life');
      expect(catalogue.search('31ab5580').single.name, 'PlayerStatus.Life');
      expect(catalogue.search('bottleinfo'), isNotEmpty);
      expect(catalogue.search('   '), isEmpty);
    });

    test('bottle group has all five contents and the 13-member enum', () {
      final group = catalogue.groupById('inventory.bottles');
      expect(group, isNotNull);
      final contents = group!.fields
          .where((field) => field.name.endsWith('.BottleItem'))
          .toList();
      final valid = group.fields
          .where((field) => field.name.endsWith('.IsValid'))
          .toList();
      expect(contents, hasLength(5));
      expect(valid, hasLength(5));
      for (final field in contents) {
        final definition = schema.byHashOnDisk(field.hash)!;
        expect(definition.type, SaveType.enumeration, reason: field.name);
        final table = definition.enumTable;
        expect(table, isNotNull, reason: field.name);
        expect(table!.members, hasLength(13), reason: field.name);
        expect(
          table.members.map((member) => member.name),
          containsAll(<String>[
            'Empty',
            'RedPotion',
            'GreenPotion',
            'BluePotion',
            'BlueFire',
            'Fish',
            'Letter',
            'BigPoe',
            'Poe',
            'Bug',
            'Fairy',
            'MaxMilk',
            'HalfMilk',
          ]),
        );
      }
    });

    test('dungeon groups match every dungeon with DungeonInfo entries', () {
      final expected = <String>{};
      final pattern = RegExp(r'^DungeonInfo\.([^.]+)\.');
      for (final field in schema.namedFields) {
        final match = pattern.firstMatch(field.name!);
        if (match != null) {
          expected.add(match.group(1)!);
        }
      }
      expect(expected, <String>{'DodongoCavern', 'FireTemple', 'WaterTemple'});
      final infoGroups = catalogue
          .forTab(EditorTabGroup.dungeons)
          .where((group) => group.id.startsWith('dungeons.info.'))
          .toList();
      expect(infoGroups, hasLength(expected.length));
      final actual = infoGroups
          .map((group) => group.id.substring('dungeons.info.'.length))
          .toSet();
      expect(actual, expected);
      for (final group in infoGroups) {
        final dungeon = group.id.substring('dungeons.info.'.length);
        expect(group.fields, isNotEmpty, reason: group.id);
        for (final field in group.fields) {
          expect(field.name, startsWith('DungeonInfo.$dungeon.'));
        }
      }
      final fire = catalogue.groupById('dungeons.info.FireTemple')!;
      expect(
        fire.fields.map((field) => field.name),
        containsAll(<String>[
          'DungeonInfo.FireTemple.IsGetMap',
          'DungeonInfo.FireTemple.IsGetCompass',
          'DungeonInfo.FireTemple.IsGetBossKey',
        ]),
      );
    });

    test('inventory membership is justified by schema names', () {
      final acquisition = catalogue.groupById('inventory.acquisition')!;
      final expectedAcquisition = schema.namedFields
          .where(
            (field) =>
                RegExp(r'^IsGet\.(Item_|Weapon_|Armor_|Pouch_)')
                    .hasMatch(field.name!),
          )
          .map((field) => field.name)
          .toSet();
      expect(
        acquisition.fields.map((field) => field.name).toSet(),
        expectedAcquisition,
      );
      expect(expectedAcquisition, hasLength(47));

      final bottles = catalogue.groupById('inventory.bottles')!;
      for (final field in bottles.fields) {
        expect(
          RegExp(
            r'^PlayerStatus\.AssignableItem\.BottleInfo\..*'
            r'\.(BottleItem|IsValid)$',
          ).hasMatch(field.name),
          isTrue,
          reason: field.name,
        );
      }

      final pouch = catalogue.groupById('inventory.pouch')!;
      expect(pouch.fields.map((field) => field.name).toSet(), <String>{
        'PouchData.Item_Token_Gold.StockNum',
        'PlayerStatus.AssignableItem.Adult',
        'PlayerStatus.AssignableItem.Child',
      });

      final ammo = catalogue.groupById('inventory.ammoCapacity')!;
      for (final field in ammo.fields) {
        final allowed =
            RegExp(
              r'(Quiver|BulletBag|BombBag|DekuNutsPouch|DekuStickPouch|'
              r'ScrubBusinessSeed|GoldScale|ShilverScale)',
            ).hasMatch(field.name) ||
            field.name == 'Get_MagicBeans' ||
            field.name == 'PlayerStatus.WeaponSwordGiantLife';
        expect(allowed, isTrue, reason: field.name);
      }
    });

    test('unnamed counts match the schema totals', () {
      final advanced = catalogue.forTab(EditorTabGroup.advanced).single;
      expect(schema.counts['unnamedFields'], 8317);
      expect(advanced.unnamedCount, 8317);
      expect(advanced.unnamedCount, schema.unnamedFields.length);
      expect(
        advanced.buckets.fold<int>(
          0,
          (total, bucket) => total + bucket.unnamedCount,
        ),
        8317,
      );
      expect(catalogue.stats.forTab(EditorTabGroup.advanced).unnamed, 8317);

      final unnamedBool = schema.fields
          .where(
            (field) => field.type == SaveType.boolean && field.name == null,
          )
          .length;
      final flags = catalogue.forTab(EditorTabGroup.flags).single;
      expect(unnamedBool, 6769);
      expect(flags.unnamedCount, unnamedBool);
      expect(catalogue.unnamedBoolCount, unnamedBool);
      final totalBool = schema.fields
          .where((field) => field.type == SaveType.boolean)
          .length;
      expect(flags.fields.length, 3443);
      expect(flags.fields.length + flags.unnamedCount, totalBool);
      expect(
        flags.buckets.fold<int>(
          0,
          (total, bucket) => total + bucket.totalCount,
        ),
        totalBool,
      );
      expect(
        catalogue.flagBucket('HavePlayedNaviBalloonMessage')!.namedCount,
        512,
      );
      expect(
        catalogue.flagFieldsUnder('HavePlayedNaviBalloonMessage'),
        hasLength(512),
      );
    });

    test('advanced lists only opaque hashes as unnamed records', () {
      final advanced = catalogue.forTab(EditorTabGroup.advanced).single;
      expect(advanced.opaqueFields, hasLength(7));
      final byType = <String, int>{};
      for (final opaque in advanced.opaqueFields) {
        byType.update(opaque.type, (count) => count + 1, ifAbsent: () => 1);
        final definition = schema.byHashOnDisk(opaque.hash);
        expect(definition, isNotNull);
        expect(definition!.name, isNull);
        expect(<String>{
          'Binary',
          'BinaryArray',
          'WString16Array',
        }, contains(opaque.type));
      }
      expect(byType, <String, int>{
        'Binary': 3,
        'BinaryArray': 2,
        'WString16Array': 2,
      });
    });

    test('generator output is deterministic and matches the asset', () async {
      final first = generator.buildFieldGroupsJson(schema);
      final second = generator.buildFieldGroupsJson(schema);
      expect(first, second);
      expect(
        await File('assets/fields/groups.json').readAsString(),
        first,
        reason: 'checked-in groups.json is stale; rerun the generator',
      );

      final temp = await Directory.systemTemp.createTemp('field-groups-');
      addTearDown(() async {
        if (temp.existsSync()) {
          await temp.delete(recursive: true);
        }
      });
      final outputA = File('${temp.path}/a/groups.json');
      final outputB = File('${temp.path}/b/groups.json');
      final runA = await Process.run('dart', <String>[
        'run',
        'tool/gen_field_groups.dart',
        'assets/schema/gamedata_110.json',
        outputA.path,
      ], workingDirectory: Directory.current.path);
      final runB = await Process.run('dart', <String>[
        'run',
        'tool/gen_field_groups.dart',
        'assets/schema/gamedata_110.json',
        outputB.path,
      ], workingDirectory: Directory.current.path);
      expect(runA.exitCode, 0, reason: '${runA.stdout}\n${runA.stderr}');
      expect(runB.exitCode, 0, reason: '${runB.stdout}\n${runB.stderr}');
      final bytesA = await outputA.readAsBytes();
      final bytesB = await outputB.readAsBytes();
      expect(bytesA, orderedEquals(bytesB));
      expect(bytesA, orderedEquals(utf8.encode(first)));
    });
  });
}
