import 'dart:io';

import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:bomb_flower/domain/schema/murmur3.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Murmur3_x86_32', () {
    test('matches the game-known name hashes', () {
      const vectors = <String, int>{
        'Sequence_CurrentBanc': 0x1D6189DA,
        'Sequence_IsChildhood': 0xCEA220D3,
        'PlayerStatus.Life': 0x31AB5580,
        'PlayerStatus.MaxLife': 0xFBE01DA1,
        'PlayerStatus.CurrentRupee': 0xA77921D7,
        'Player_Rot_For_Map': 0xA4AEE8CD,
        'Sequence_IsLoadingBanc': 0xEF2B60C2,
      };
      for (final entry in vectors.entries) {
        expect(
          murmur3X86_32(entry.key),
          entry.value,
          reason: 'Murmur3(${entry.key})',
        );
      }
    });

    test('hashes the empty string to zero', () {
      expect(murmur3X86_32(''), 0);
    });

    test('documents the hash of a name that is not a field', () {
      // The brief said "PlayerStatus.MaxRupee if present". It is not: no byml
      // entry and no name preimage with that spelling appear in revision
      // 2982123. The hash is recorded only so the negative lookup is explicit.
      expect(murmur3X86_32('PlayerStatus.MaxRupee'), 0xB128B5A9);
    });
  });

  group('GameDataSchema', () {
    late GameDataSchema schema;

    setUpAll(() async {
      final text = await File('assets/schema/gamedata_110.json').readAsString();
      schema = GameDataSchema.fromJsonString(text);
    });

    test('loads through an injected reader', () async {
      final loaded = await GameDataSchema.load(
        () => File('assets/schema/gamedata_110.json').readAsString(),
      );
      expect(loaded.schemaRevision, gamedataSchemaRevision);
      expect(loaded.fields.length, schema.fields.length);
    });

    test('schema revision is 2982123', () {
      expect(schema.schemaRevision, 2982123);
      expect(schema.schemaRevisionHex, '0x2d80eb');
      expect(schema.game, contains('v131072'));
    });

    test('has 11,925 on-disk fields and 11,657 absent Bool64bitKey', () {
      expect(schema.fields.length, 11925);
      expect(schema.absentFields.length, 11657);
      expect(schema.counts['onDiskFields'], 11925);
      expect(schema.counts['absentBool64bitKey'], 11657);
      expect(schema.declaredNotSaved, isNotEmpty);
    });

    test('every on-disk field hash is unique', () {
      final hashes = schema.fields.map((field) => field.hash).toSet();
      expect(hashes.length, schema.fields.length);
    });

    test('every on-disk field is present and verified', () {
      for (final field in schema.fields) {
        expect(field.presentOnDisk, isTrue, reason: field.displayName);
        expect(field.verified, isTrue, reason: field.displayName);
        expect(field.type, isNot(SaveType.bool64bitKey));
        expect(field.section, isNotNull, reason: field.displayName);
        expect(field.recordIndex, isNotNull, reason: field.displayName);
      }
    });

    test('section counts match the verified table', () {
      const expected = <String, int>{
        'Bool': 10212,
        'BoolArray': 6,
        'Int': 1144,
        'IntArray': 155,
        'Float': 76,
        'FloatArray': 3,
        'Enum': 101,
        'EnumArray': 14,
        'Vector3': 16,
        'String32': 1,
        'String64': 30,
        'String64Array': 3,
        'Binary': 3,
        'BinaryArray': 2,
        'UInt': 87,
        'UIntArray': 33,
        'Int64': 28,
        'UInt64': 5,
        'UInt64Array': 4,
        'WString16Array': 2,
      };
      final actual = <String, int>{
        for (final section in schema.sections)
          section.type.wireName: section.count,
      };
      expect(actual, expected);
      expect(
        schema.sections.fold<int>(0, (sum, section) => sum + section.count),
        11925,
      );
      expect(schema.emptySectionIds, <int>[
        9,
        10,
        12,
        13,
        14,
        16,
        24,
        27,
        29,
        30,
        31,
        32,
      ]);
    });

    test('spot-checks 20 fields against the independent CSV dump', () {
      // Source: /tmp/opencode/research/fields/progress_fields.csv, generated
      // from the same record stream but without any byml name lookup.
      const expected = <int, (String, int, Object?, int?)>{
        0x000D93CE: ('Bool', 1, false, null),
        0x0012B8C0: ('Int', 3, 0, null),
        0x003694B5: ('Enum', 7, 1471695344, null),
        0x00480C86: ('Bool', 1, true, null),
        0x008D7F0C: ('String64', 17, '', null),
        0x960AD56A: (
          'Vector3',
          11,
          <String, Object?>{'x': 0.0, 'y': 0.0, 'z': 0.0},
          null,
        ),
        0x1D6189DA: ('String64', 17, '', null),
        0x4CF1EC50: ('IntArray', 4, 0, 256),
        0x09B4C038: ('Float', 5, 216000.0, null),
        0x877F32F3: ('EnumArray', 8, 3069107721, 10),
        0x70D7C5CB: ('Binary', 19, 160000, null),
        0xBBF85FD5: ('BinaryArray', 20, 104, 10),
        0x9152EEF8: ('UInt64Array', 26, 0, 256),
        0xD2DDB868: ('WString16Array', 28, '', 10),
        0x3F31AD53: ('Int64', 23, 0, null),
        0xEE8002A0: ('UInt64', 25, 0, null),
        0xCFE1A634: ('UInt', 21, 0, null),
        0x8F76B998: ('FloatArray', 6, -1.0, 32),
        0x99BE8C0B: ('BoolArray', 2, false, 7),
        0x4A6BDB7D: ('String32', 15, '', null),
      };

      for (final entry in expected.entries) {
        final field = schema.byHashOnDisk(entry.key);
        expect(field, isNotNull, reason: hashHex(entry.key));
        expect(field!.type.wireName, entry.value.$1);
        expect(field.section, entry.value.$2);
        expect(field.defaultValue, entry.value.$3);
        expect(field.arrayLen, entry.value.$4);
      }
    });

    test('every enum table member hash is 32-bit and name-verified', () {
      var tables = 0;
      var members = 0;
      for (final table in schema.enums.values) {
        tables++;
        for (final member in table.members) {
          members++;
          expect(member.hash, inInclusiveRange(0, 0xFFFFFFFF));
          expect(murmur3X86_32(member.name), member.hash);
        }
      }
      expect(tables, 75);
      expect(members, 1257);
      expect(schema.counts['enumMemberUses'], 2499);
    });

    test('bottle contents have readable enum labels', () {
      final field = schema.byNameOnDisk(
        'PlayerStatus.AssignableItem.BottleInfo.BottleA.BottleItem',
      );
      expect(field, isNotNull);
      final table = field!.enumTable;
      expect(table, isNotNull);
      expect(table!.members.length, 13);
      expect(table.byHash[3194609225]?.name, 'Empty');
      expect(table.byName['RedPotion'], isNotNull);
      expect(field.defaultLabel, 'Empty');
    });

    test('byHash resolves the seven named host constants', () {
      const names = <int, String>{
        0x1D6189DA: 'Sequence_CurrentBanc',
        0xEF2B60C2: 'Sequence_IsLoadingBanc',
        0xCEA220D3: 'Sequence_IsChildhood',
        0xA4AEE8CD: 'Player_Rot_For_Map',
        0x31AB5580: 'PlayerStatus.Life',
        0xFBE01DA1: 'PlayerStatus.MaxLife',
        0xA77921D7: 'PlayerStatus.CurrentRupee',
      };
      for (final entry in names.entries) {
        final field = schema.byHash(entry.key);
        expect(field, isNotNull, reason: hashHex(entry.key));
        expect(field!.name, entry.value);
      }
      expect(schema.byHash(0xEF2B60C2)!.presentOnDisk, isFalse);
    });

    test('defaults and names for editor-critical player fields', () {
      final life = schema.byNameOnDisk('PlayerStatus.Life');
      expect(life, isNotNull);
      expect(life!.type, SaveType.integer);
      expect(life.defaultValue, 12);
      expect(life.hash, 833312128);

      final maxLife = schema.byNameOnDisk('PlayerStatus.MaxLife');
      expect(maxLife!.defaultValue, 12);

      final rupees = schema.byNameOnDisk('PlayerStatus.CurrentRupee');
      expect(rupees!.defaultValue, 0);

      final position = schema.byNameOnDisk('Player_Pos_For_Map');
      expect(position!.type, SaveType.vector3);
      expect(position.defaultValue, isA<Map<String, Object?>>());

      final rotation = schema.byNameOnDisk('Player_Rot_For_Map');
      expect(rotation!.type, SaveType.float32);
    });

    test('byName does not invent PlayerStatus.MaxRupee', () {
      expect(schema.byName('PlayerStatus.MaxRupee'), isNull);
    });

    test('version gate accepts 2982123 and rejects a mismatch', () {
      expect(schema.revisionMatches(2982123), isTrue);
      expect(() => schema.validateRevision(2982123), returnsNormally);
      expect(
        () => schema.validateRevision(2982122),
        throwsA(isA<SchemaRevisionMismatch>()),
      );
      expect(
        () => GameDataSchema.fromJsonString(
          File('assets/schema/gamedata_110.json').readAsStringSync(),
          fileRevision: 1,
        ),
        throwsA(isA<SchemaRevisionMismatch>()),
      );
    });
  });
}
