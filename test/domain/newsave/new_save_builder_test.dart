import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/codec/caption_codec.dart';
import 'package:bomb_flower/data/codec/progress_codec.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/engine/engine.dart';
import 'package:bomb_flower/domain/newsave/new_save_builder.dart';
import 'package:bomb_flower/domain/newsave/new_save_spec.dart';
import 'package:bomb_flower/domain/save/models/caption_save.dart';
import 'package:bomb_flower/domain/save/models/progress_save.dart';
import 'package:bomb_flower/domain/save/progress_layout.dart' as layout;
import 'package:bomb_flower/domain/save/progress_record.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:flutter_test/flutter_test.dart';

// Verified numbers. These are asserted verbatim; they are not re-derived here.
const int _recordCount = 11958;
const int _fieldCount = 11925;
const int _sentinelCount = 32;
const int _dataOffset = 0x175D8; // 95704 == 0x28 + 8 * 11958.
const int _progressLength = 120164;
const int _tailLength = 24460;
const int _captionLength = 2029;
const int _noScreenshotCaptionLength = 1400;
const int _captionJpegOffset = 1396;
const int _footerIndex = 11957;
const int _footerKey = 0xA3DB7114;
const int _footerValue = 0x1D6F4;
const int _footerGapPastEof = 400;

const int _lifeKey = 0x31AB5580;
const int _positionKey = 0x960AD56A;
const int _string64Key = 0x1D6189DA;
const int _string32Hash = 1248582525;
const int _string64ForOverflowHash = 9273100; // PlayerStatus.EquipArmor.
const int _emptyItemEnumHash = 3194609225;

const Map<int, int> _sectionCounts = <int, int>{
  1: 10212,
  2: 6,
  3: 1144,
  4: 155,
  5: 76,
  6: 3,
  7: 101,
  8: 14,
  11: 16,
  15: 1,
  17: 30,
  18: 3,
  19: 3,
  20: 2,
  21: 87,
  22: 33,
  23: 28,
  25: 5,
  26: 4,
  28: 2,
};

const List<int> _emptySectionIds = <int>[
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
];

void main() {
  late String schemaJson;
  late GameDataSchema schema;
  late NewSaveBuild build;
  late ProgressDecodeResult decodeResult;
  late ProgressSave save;

  setUpAll(() async {
    schemaJson = await File('assets/schema/gamedata_110.json').readAsString();
    schema = GameDataSchema.fromJsonString(schemaJson);
    build = NewSaveBuilder.build(
      schema: schema,
      spec: NewSaveSpec.preset(NewSavePreset.schemaDefaults),
    );
    decodeResult = ProgressCodec.decode(build.progressBytes);
    expect(decodeResult, isA<ProgressDecodeOk>());
    save = (decodeResult as ProgressDecodeOk).save;
  });

  group('default build', () {
    test('decodes as ProgressDecodeOk with the verified counts', () {
      expect(decodeResult, isA<ProgressDecodeOk>());
      expect(decodeResult, isNot(isA<ProgressDecodeCorrupt>()));
      expect(decodeResult, isNot(isA<ProgressDecodeUnsupported>()));
      expect(build.fieldCount, _fieldCount);
      expect(build.recordCount, _recordCount);
      expect(build.sentinelCount, _sentinelCount);
      expect(save.fieldCount, _fieldCount);
      expect(save.recordCount, _recordCount);
    });

    test('has the exact verified record, section and file geometry', () {
      expect(build.recordCount, _recordCount);
      expect(build.fieldCount, _fieldCount);
      expect(build.sentinelCount, _sentinelCount);
      expect(build.dataOffset, 0x28 + 8 * _recordCount);
      expect(build.dataOffset, _dataOffset);
      expect(save.dataOffset, _dataOffset);

      expect(save.records.length, _fieldCount);
      expect(build.progressBytes.length, _progressLength);
      expect(save.length, _progressLength);

      for (final entry in _sectionCounts.entries) {
        final type = layout.SaveType.forTypeId(entry.key)!;
        final section = schema.section(entry.key);
        expect(section, isNotNull, reason: 'section ${entry.key} is populated');
        expect(
          save.sectionFor(type).records.length,
          section!.count,
          reason: 'decoded section ${entry.key} must match the schema',
        );
        expect(
          save.sectionFor(type).records.length,
          entry.value,
          reason: 'decoded section ${entry.key} must match the verified count',
        );
        expect(
          build.sectionCounts[entry.key],
          entry.value,
          reason: 'build sectionCounts[${entry.key}]',
        );
      }
      expect(build.sectionCounts.length, _sentinelCount);

      for (final typeId in _emptySectionIds) {
        final type = layout.SaveType.forTypeId(typeId)!;
        expect(schema.section(typeId), isNull);
        expect(save.sectionFor(type).records, isEmpty);
        expect(build.sectionCounts[typeId], 0);
      }
    });

    test('record order follows the schema and sentinels close every section', () {
      final byIndex = <int, ProgressRecord>{
        for (final record in save.records) record.index: record,
      };

      final fieldIndices = <int>{};
      for (final field in schema.fields) {
        final index = field.recordIndex;
        expect(
          index,
          isNotNull,
          reason: '${field.displayName} has no recordIndex',
        );
        expect(
          fieldIndices.add(index!),
          isTrue,
          reason: '${field.displayName} repeats recordIndex $index',
        );
      }
      expect(fieldIndices.length, _fieldCount);

      final mismatched = schema.fields
          .where((field) => byIndex[field.recordIndex]?.key != field.hash)
          .toList(growable: false);
      expect(
        mismatched.length,
        0,
        reason: mismatched
            .take(3)
            .map((field) => '${field.displayName}@${field.recordIndex}')
            .join(', '),
      );

      final sentinelIndices = <int>{
        for (final sentinel in save.sentinels) sentinel.index,
      };
      final nonFieldIndices = <int>{
        for (var i = 0; i < build.recordCount; i++)
          if (i != save.footer.index && !sentinelIndices.contains(i)) i,
      };
      expect(fieldIndices, nonFieldIndices);
      expect(<int>{
        for (final record in save.records) record.index,
      }, nonFieldIndices);

      expect(save.sentinels.length, _sentinelCount);
      var previousSentinelIndex = -1;
      for (var i = 0; i < save.sentinels.length; i++) {
        final sentinel = save.sentinels[i];
        final typeId = i + 1;
        expect(sentinel.type.typeId, typeId);
        expect(sentinel.key, 0);
        expect(sentinel.rawValue, typeId);
        expect(sentinel.isSentinel, isTrue);
        expect(sentinel.index, greaterThan(previousSentinelIndex));
        final section = schema.section(typeId);
        if (section == null) {
          // Empty sections have no schema SectionDef, so the sentinel is the
          // bare record immediately after the previous section's sentinel.
          expect(sentinel.index, previousSentinelIndex + 1);
        } else {
          expect(sentinel.index, section.sentinelRecordIndex);
        }
        previousSentinelIndex = sentinel.index;
      }

      expect(save.footer.index, _footerIndex);
      expect(save.footer.key, _footerKey);
      // The opaque footer value stays verbatim. In this build the tail ends
      // 400 bytes before it: the samples' three Binary spans are the 400 bytes
      // the builder deliberately does not invent.
      expect(save.footer.rawValue, _footerValue);
      expect(
        save.footer.rawValue - build.progressBytes.length,
        _footerGapPastEof,
      );
      expect(save.footer.index, save.recordCount - 1);
    });

    test('tail spans are contiguous from dataOffset to EOF', () {
      final tailRecords = save.records
          .where((record) => record.type.isTail)
          .toList(growable: false);

      // The codec computes dataLength for a tail record, so this uses the
      // codec's own span logic rather than re-deriving lengths here.
      for (final record in tailRecords) {
        expect(
          record.dataOffset,
          isNotNull,
          reason: '${record.keyHex} ${record.type.label} has no tail data',
        );
      }
      expect(tailRecords, isNotEmpty);

      final sorted = <ProgressRecord>[...tailRecords]
        ..sort((a, b) => a.dataOffset!.compareTo(b.dataOffset!));

      var previousEnd = build.dataOffset;
      for (final record in sorted) {
        final start = record.dataOffset!;
        expect(
          start,
          previousEnd,
          reason: '${record.keyHex} ${record.type.label} is not contiguous',
        );
        final end = start + record.dataLength;
        expect(end, lessThanOrEqualTo(build.progressBytes.length));
        previousEnd = end;
      }
      expect(previousEnd, build.progressBytes.length);
      expect(build.dataOffset + _tailLength, build.progressBytes.length);
      expect(save.tailBytes.length, _tailLength);
    });

    test('an unedited decode re-encodes byte-for-byte', () {
      expect(ProgressCodec.encode(save), equals(build.progressBytes));
    });
  });

  group('edits', () {
    test('survive encode and decode without changing the file length', () {
      final edited = save
          .setInt(_lifeKey, 20)
          .setString(_string64Key, 'Kokiri');
      final bytes = ProgressCodec.encode(edited);

      expect(edited.length, save.length);
      expect(bytes.length, build.progressBytes.length);

      final result = ProgressCodec.decode(bytes);
      expect(result, isA<ProgressDecodeOk>());
      final roundTrip = (result as ProgressDecodeOk).save;
      expect(roundTrip.length, build.progressBytes.length);
      expect(roundTrip.recordByHash(_lifeKey)!.asInt(), 20);
      expect(roundTrip.recordByHash(_string64Key)!.asString(), 'Kokiri');
    });
  });

  group('engine', () {
    test('accepts the built bytes under a test-local container layout', () {
      // Test-local container metadata only: the two slots declare their
      // relative paths and expected lengths so the engine can accept the
      // bytes. This layout invents no field offsets for the save; the domain
      // builder and codecs remain the authority on the byte layout.
      final descriptor = LayoutDescriptor('newsave-test', 1, <SaveSlotLayout>[
        SaveSlotLayout(
          SaveSlotId.progress(0),
          'slot_00/progress.sav',
          const <FieldDescriptor>[],
          expectedLength: build.progressBytes.length,
        ),
        SaveSlotLayout(
          SaveSlotId('slot_00.caption'),
          'slot_00/caption.sav',
          const <FieldDescriptor>[],
          expectedLength: build.captionBytes.length,
        ),
      ]);
      final engine = SaveEngine(
        SaveFormat('newsave-test', 'New save test', <LayoutDescriptor>[
          descriptor,
        ]),
      );

      final result = engine.parse(
        rootPath: '/newsave',
        files: <SaveSlotId, ByteRegion>{
          SaveSlotId.progress(0): ByteRegion.fromBytes(build.progressBytes),
          SaveSlotId('slot_00.caption'): ByteRegion.fromBytes(
            build.captionBytes,
          ),
        },
        detectedVersion: 1,
        backupPath: '/newsave-backup',
      );

      expect(result, isA<ParseOk>());
      final project = (result as ParseOk).project;
      expect(
        engine
            .validateResult(project)
            .issues
            .where((issue) => issue.isBlocking),
        isEmpty,
      );
    });
  });

  group('schema default rejection', () {
    test('rejects a 32-character String32 default', () {
      final broken = _schemaWithDefault(schemaJson, _string32Hash, 'x' * 32);
      expect(
        () => NewSaveBuilder.build(
          schema: broken,
          spec: NewSaveSpec.preset(NewSavePreset.schemaDefaults),
        ),
        throwsA(
          isA<NewSaveBuildException>().having(
            (error) => error.code,
            'code',
            'string_too_long',
          ),
        ),
      );
    });

    test('rejects a 64-character String64 default', () {
      final broken = _schemaWithDefault(
        schemaJson,
        _string64ForOverflowHash,
        'y' * 64,
      );
      expect(
        () => NewSaveBuilder.build(
          schema: broken,
          spec: NewSaveSpec.preset(NewSavePreset.schemaDefaults),
        ),
        throwsA(
          isA<NewSaveBuildException>().having(
            (error) => error.code,
            'code',
            'string_too_long',
          ),
        ),
      );
    });

    test('accepts a 31-character String32 default at the boundary', () {
      const value = '0123456789abcdefghijklmnopqrstu';
      expect(value.length, 31);
      final boundary = _schemaWithDefault(schemaJson, _string32Hash, value);

      final result = NewSaveBuilder.build(
        schema: boundary,
        spec: NewSaveSpec.preset(NewSavePreset.schemaDefaults),
      );
      expect(result.progressBytes.length, _progressLength);

      final decoded = ProgressCodec.decode(result.progressBytes);
      expect(decoded, isA<ProgressDecodeOk>());
      final roundTrip = (decoded as ProgressDecodeOk).save;
      expect(roundTrip.recordByHash(_string32Hash)!.asString(), value);
    });
  });

  group('enum defaults', () {
    test('are member hashes rather than member indices', () {
      final child = schema.byNameOnDisk('PlayerStatus.AssignableItem.Child')!;
      expect(child.defaultValue, _emptyItemEnumHash);
      expect(child.recordIndex, 11667);
      expect(child.enumTable!.member(_emptyItemEnumHash), isNotNull);

      final record = save.recordByHash(child.hash)!;
      expect(record.asEnumHash(), _emptyItemEnumHash);

      final adult = schema.byNameOnDisk('PlayerStatus.AssignableItem.Adult')!;
      expect(adult.defaultValue, _emptyItemEnumHash);
      expect(save.recordByHash(adult.hash)!.asEnumHash(), _emptyItemEnumHash);
    });
  });

  group('string defaults', () {
    test('are NUL-terminated and zero-filled', () {
      final field = schema.byHashOnDisk(_string64Key)!;
      expect(field.type, SaveType.string64);

      final record = save.recordByHash(_string64Key)!;
      expect(record.type, layout.SaveType.string64);
      expect(record.dataLength, 64);

      final Uint8List bytes = record.copyDataBytes();
      expect(bytes.length, 64);
      expect(bytes.every((byte) => byte == 0), isTrue);
      expect(record.asString(), '');
    });
  });

  group('spec overrides', () {
    test('start position replaces the default origin', () {
      final overridden = NewSaveBuilder.build(
        schema: schema,
        spec: NewSaveSpec.preset(
          NewSavePreset.schemaDefaults,
          startPosition: const SavePosition(x: 1.5, y: -2.25, z: 3.75),
        ),
      );
      final decoded = ProgressCodec.decode(overridden.progressBytes);
      expect(decoded, isA<ProgressDecodeOk>());
      final position = (decoded as ProgressDecodeOk).save
          .recordByHash(_positionKey)!
          .asVector3();
      expect(position.x, 1.5);
      expect(position.y, -2.25);
      expect(position.z, 3.75);

      final origin = save.recordByHash(_positionKey)!.asVector3();
      expect(origin.x, 0);
      expect(origin.y, 0);
      expect(origin.z, 0);
    });

    test('a profile name is rejected, never ignored', () {
      expect(
        () => NewSaveBuilder.build(
          schema: schema,
          spec: NewSaveSpec.preset(
            NewSavePreset.schemaDefaults,
            profileName: 'Link',
          ),
        ),
        throwsA(
          isA<NewSaveBuildException>().having(
            (error) => error.code,
            'code',
            'profile_name_unavailable',
          ),
        ),
      );
    });

    test('a non-finite start position is rejected', () {
      for (final value in <double>[double.nan, double.infinity]) {
        expect(
          () => NewSaveBuilder.build(
            schema: schema,
            spec: NewSaveSpec.preset(
              NewSavePreset.schemaDefaults,
              startPosition: SavePosition(x: value, y: 0, z: 0),
            ),
          ),
          throwsA(
            isA<NewSaveBuildException>().having(
              (error) => error.code,
              'code',
              'start_position_unavailable',
            ),
          ),
          reason: 'x = $value',
        );
      }
    });

    test('caption names must be printable ASCII of at most 63 code units', () {
      for (final scene in <String>['a' * 64, 'Kokiri\nForest']) {
        expect(
          () => NewSaveBuilder.build(
            schema: schema,
            spec: NewSaveSpec(
              scene: scene,
              mapPath: 'KokiriForest/KokiriForest_Child',
            ),
          ),
          throwsA(
            isA<NewSaveBuildException>().having(
              (error) => error.code,
              'code',
              'caption_name_invalid',
            ),
          ),
          reason: 'scene = ${jsonEncode(scene)}',
        );
      }
    });
  });

  group('caption', () {
    test('embeds the default JPEG and round-trips byte-for-byte', () {
      const preset = NewSaveSpec(
        scene: 'KokiriForest',
        mapPath: 'KokiriForest/KokiriForest_Child',
      );

      final result = CaptionCodec.decode(build.captionBytes);
      expect(result, isA<CaptionDecodeOk>());
      final caption = (result as CaptionDecodeOk).save;

      expect(caption.sceneName, preset.scene);
      expect(caption.mapPath, preset.mapPath);
      expect(
        caption.savedAt,
        const CaptionSavedAt(
          year: 2026,
          month: 1,
          day: 1,
          hour: 0,
          minute: 0,
          second: 0,
        ),
      );
      expect(build.captionBytes.length, _captionLength);
      expect(caption.jpegLength, _captionLength - _captionJpegOffset);
      expect(
        _captionJpegOffset + caption.jpegLength,
        build.captionBytes.length,
      );
      expect(CaptionCodec.encode(caption), equals(build.captionBytes));
    });

    test('can omit the screenshot and write the FF D8 FF D9 marker pair', () {
      const spec = NewSaveSpec(
        scene: 'KokiriForest',
        mapPath: 'KokiriForest/KokiriForest_Child',
        createCaptionScreenshot: false,
      );
      final noScreenshot = NewSaveBuilder.build(schema: schema, spec: spec);

      expect(noScreenshot.captionBytes.length, _noScreenshotCaptionLength);
      final result = CaptionCodec.decode(noScreenshot.captionBytes);
      expect(result, isA<CaptionDecodeOk>());
      final caption = (result as CaptionDecodeOk).save;
      expect(caption.jpegLength, 4);
      expect(caption.jpegBytes, <int>[0xFF, 0xD8, 0xFF, 0xD9]);
      expect(CaptionCodec.encode(caption), equals(noScreenshot.captionBytes));
    });
  });
}

/// Returns [schemaJson] re-parsed with one field's `default` replaced.
GameDataSchema _schemaWithDefault(String schemaJson, int hash, Object value) {
  final root = jsonDecode(schemaJson) as Map<String, dynamic>;
  final fields = (root['fields'] as List<dynamic>).cast<Map<String, dynamic>>();
  final field = fields.firstWhere((entry) => entry['hash'] == hash);
  field['default'] = value;
  return GameDataSchema.fromJsonString(jsonEncode(root));
}
