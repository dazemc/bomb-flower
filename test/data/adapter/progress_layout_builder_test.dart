import 'dart:typed_data';

import 'package:bomb_flower/data/adapter/progress_field_id.dart';
import 'package:bomb_flower/data/adapter/progress_layout_builder.dart';
import 'package:bomb_flower/data/codec/progress_codec.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/engine/engine.dart';
import 'package:bomb_flower/domain/save/caption_layout.dart';
import 'package:bomb_flower/domain/save/models/caption_save.dart';
import 'package:bomb_flower/domain/save/models/progress_save.dart';
import 'package:bomb_flower/domain/save/progress_record.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:bomb_flower/domain/schema/murmur3.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/synthetic_progress.dart';

/// The name declared for the synthetic `IntArray` record.
const String _arrayName = 'Test_StructArray';

/// The only citation strings a progress descriptor may carry.
const Set<String> _progressSources = <String>{
  'schema:struct',
  'schema:string',
  'schema:prefix',
  'host:oot_state_tap.c',
  'unverified',
};

void main() {
  late GameDataSchema schema;

  setUpAll(() async {
    schema = await _loadSchema();
  });

  group('buildProgressSlotLayout', () {
    test('describes every record in order with the record spans', () {
      final save = _save();
      final layout = ProgressLayoutBuilder(schema)
          .buildProgressSlotLayout(save);

      expect(layout.id.value, 'slot_00');
      expect(layout.relativePath, 'slot_00/progress.sav');
      expect(layout.expectedLength, save.length);
      expect(layout.fields.length, save.records.length);
      expect(layout.fields.length, save.fieldCount);

      for (var i = 0; i < save.records.length; i++) {
        final record = save.records[i];
        final descriptor = layout.fields[i];
        expect(descriptor.id, progressFieldId(record), reason: 'record $i');
        expect(descriptor.slot, SaveSlotId.progress(0));
        final expectedSpan = record.dataOffset == null
            ? ByteSpan(record.valueOffset, 4)
            : ByteSpan(record.dataOffset!, record.dataLength);
        expect(descriptor.span, expectedSpan, reason: 'record $i');
        expect(_progressSources, contains(descriptor.source));
      }
    });

    test('classifies struct, host, prefix and unnamed evidence', () {
      final save = _save();
      final layout = ProgressLayoutBuilder(schema)
          .buildProgressSlotLayout(save);

      FieldDescriptor descriptorFor(int key) {
        final record = save.recordByHash(key);
        expect(record, isNotNull, reason: 'synthetic key $key');
        return layout.field(progressFieldId(record!))!;
      }

      final structInt = descriptorFor(0x31AB5580);
      expect(structInt.id.value, 'progress.31ab5580');
      expect(isProgressFieldId(structInt.id), isTrue);
      expect(structInt.label, 'PlayerStatus.Life');
      expect(structInt.kind, FieldKind.integer);
      expect(structInt.confidence, FieldConfidence.verified);
      expect(structInt.source, 'schema:struct');
      expect(structInt.min, -2147483648);
      expect(structInt.max, 2147483647);
      expect(structInt.readOnly, isFalse);
      expect(structInt.isEditable, isTrue);

      final structArray = descriptorFor(murmur3X86_32(_arrayName));
      expect(structArray.label, 'Test_StructArray');
      expect(structArray.kind, FieldKind.list);
      expect(structArray.confidence, FieldConfidence.verified);
      expect(structArray.source, 'schema:struct');
      expect(structArray.readOnly, isTrue);
      expect(structArray.isEditable, isFalse);

      final prefix = descriptorFor(0x1D6189DA);
      expect(prefix.label, 'Sequence_CurrentBanc');
      expect(prefix.kind, FieldKind.string);
      expect(prefix.confidence, FieldConfidence.inferred);
      expect(prefix.source, 'schema:prefix');
      expect(prefix.readOnly, isTrue);
      expect(prefix.isEditable, isFalse);

      final unnamed = descriptorFor(0x03030303);
      expect(unnamed.label, 'Unnamed 0x03030303');
      expect(unnamed.confidence, FieldConfidence.unverified);
      expect(unnamed.source, 'unverified');
      expect(unnamed.readOnly, isTrue);

      final host = descriptorFor(0xCEA220D3);
      expect(host.label, 'Sequence_IsChildhood');
      expect(host.kind, FieldKind.boolean);
      expect(host.confidence, FieldConfidence.verified);
      expect(host.source, 'host:oot_state_tap.c');
      expect(host.readOnly, isFalse);
    });

    test('carries float and uint as unsigned 32-bit raw patterns', () {
      final save = _save();
      final layout = ProgressLayoutBuilder(schema)
          .buildProgressSlotLayout(save);

      for (final key in <int>[0xA4AEE8CD, 0x0E0E0E0E]) {
        final record = save.recordByHash(key)!;
        final descriptor = layout.field(progressFieldId(record))!;
        expect(descriptor.kind, FieldKind.integer, reason: 'key $key');
        expect(descriptor.min, 0, reason: 'key $key');
        expect(descriptor.max, 4294967295, reason: 'key $key');
      }
    });

    test('uses the supplied slot for every id and the relative path', () {
      final save = _save();
      const slot = SaveSlotId('slot_07');
      final layout = ProgressLayoutBuilder(schema)
          .buildProgressSlotLayout(save, slot: slot);

      expect(layout.id, slot);
      expect(layout.relativePath, 'slot_07/progress.sav');
      expect(layout.fields.every((field) => field.slot == slot), isTrue);
    });
  });

  group('buildCaptionSlotLayout', () {
    test('uses a caption slot id that is not a progress slot id', () {
      final caption = _caption();
      final layout = ProgressLayoutBuilder(schema)
          .buildCaptionSlotLayout(caption);

      expect(layout.id.value, 'slot_00.caption');
      expect(RegExp(r'^slot_\d+$').hasMatch(layout.id.value), isFalse);
      expect(layout.relativePath, 'slot_00.caption/caption.sav');
      expect(layout.expectedLength, CaptionLayout.minimumFileLength);

      final custom = ProgressLayoutBuilder(
        schema,
      ).buildCaptionSlotLayout(caption, progressSlot: SaveSlotId.progress(3));
      expect(custom.id.value, 'slot_03.caption');
      expect(RegExp(r'^slot_\d+$').hasMatch(custom.id.value), isFalse);
      expect(custom.relativePath, 'slot_03.caption/caption.sav');
    });

    test('cites scene and map as editable 64-byte strings', () {
      final caption = _caption();
      final layout = ProgressLayoutBuilder(schema)
          .buildCaptionSlotLayout(caption);

      expect(
        layout.fields.length,
        CaptionLayout.fields.length + CaptionLayout.dateFields.length,
      );

      final scene = layout.fields.singleWhere(
        (field) => field.label == 'sceneName',
      );
      expect(scene.kind, FieldKind.string);
      expect(
        scene.span,
        ByteSpan(CaptionLayout.sceneNameOffset, CaptionLayout.nameLength),
      );
      expect(scene.confidence, FieldConfidence.verified);
      expect(scene.source, 'caption:control.c:1885');
      expect(scene.readOnly, isFalse);
      expect(scene.isEditable, isTrue);

      final map = layout.fields.singleWhere(
        (field) => field.label == 'mapPath',
      );
      expect(map.kind, FieldKind.string);
      expect(
        map.span,
        ByteSpan(CaptionLayout.mapPathOffset, CaptionLayout.nameLength),
      );
      expect(map.confidence, FieldConfidence.verified);
      expect(map.source, 'caption:control.c:1885');
      expect(map.readOnly, isFalse);
      expect(map.isEditable, isTrue);
    });

    test('keeps header and date fields read-only', () {
      final caption = _caption();
      final layout = ProgressLayoutBuilder(schema)
          .buildCaptionSlotLayout(caption);

      expect(layout.fields.length, 12);
      for (final descriptor in layout.fields) {
        expect(descriptor.slot, layout.id);
        expect(descriptor.source, startsWith('caption:'));
        expect(descriptor.source.length, greaterThan('caption:'.length));
      }

      final magic = layout.fields.singleWhere(
        (field) => field.label == 'magic',
      );
      expect(magic.confidence, FieldConfidence.inferred);
      expect(magic.readOnly, isTrue);

      final layoutCheck = layout.fields.singleWhere(
        (field) => field.label == 'layoutCheck',
      );
      expect(layoutCheck.readOnly, isTrue);

      final jpegLength = layout.fields.singleWhere(
        (field) => field.label == 'jpegLength',
      );
      expect(jpegLength.kind, FieldKind.integer);
      expect(jpegLength.span, ByteSpan(CaptionLayout.jpegLengthOffset, 4));
      expect(jpegLength.confidence, FieldConfidence.verified);
      expect(jpegLength.source, 'caption:control.c:1894');
      expect(jpegLength.readOnly, isTrue);
      expect(jpegLength.isEditable, isFalse);

      final jpeg = layout.fields.singleWhere((field) => field.label == 'jpeg');
      expect(jpeg.kind, FieldKind.list);
      expect(jpeg.span, ByteSpan(CaptionLayout.jpegOffset, caption.jpegLength));
      expect(jpeg.span.end, caption.jpegLength + CaptionLayout.jpegOffset);
      expect(jpeg.confidence, FieldConfidence.inferred);
      expect(jpeg.readOnly, isTrue);

      for (final date in CaptionLayout.dateFields) {
        final descriptor = layout.fields.singleWhere(
          (field) => field.id.value == 'caption.savedAt.${date.field.name}',
        );
        expect(descriptor.kind, FieldKind.integer);
        expect(descriptor.span, ByteSpan(date.sampleOffset + 4, 4));
        expect(descriptor.confidence, FieldConfidence.verified);
        expect(descriptor.source, 'caption:docs/SAVE-FORMAT.md');
        // sampleOffset is an observation; the codec finds entries by key.
        expect(descriptor.readOnly, isTrue);
        expect(descriptor.isEditable, isFalse);
      }
    });
  });

  group('endianness', () {
    test('every progress and caption descriptor is little-endian', () {
      final save = _save();
      final progress = ProgressLayoutBuilder(schema)
          .buildProgressSlotLayout(save);
      final caption = ProgressLayoutBuilder(schema)
          .buildCaptionSlotLayout(_caption());
      final descriptors = <FieldDescriptor>[
        ...progress.fields,
        ...caption.fields,
      ];

      expect(descriptors, isNotEmpty);
      for (final descriptor in descriptors) {
        expect(
          descriptor.endianness,
          Endian.little,
          reason: descriptor.id.value,
        );
      }
    });

    test(
      'SetScalar writes PlayerStatus.Life little-endian and reads back',
      () async {
        final save = _save();
        final slotLayout = ProgressLayoutBuilder(schema)
            .buildProgressSlotLayout(save);
        final id = const FieldId('progress.31ab5580');
        final descriptor = slotLayout.field(id)!;
        final record = save.recordByHash(0x31AB5580)!;

        expect(descriptor.endianness, Endian.little);
        expect(descriptor.span, ByteSpan(record.valueOffset, 4));
        // The synthetic stream puts this record at index 5 (0x28 + 5*8 + 4).
        expect(descriptor.span.offset, 84);
        expect(descriptor.isEditable, isTrue);

        final layout = LayoutDescriptor(
          'synthetic.progress',
          1,
          <SaveSlotLayout>[slotLayout],
        );
        final format = SaveFormat('synthetic', 'Synthetic', <LayoutDescriptor>[
          layout,
        ]);
        final engine = SaveEngine(format);
        final source = _MemorySlotSource(<SaveSlotId, Uint8List>{
          slotLayout.id: save.encode(),
        });
        final originals = _MemoryOriginalStore();

        Future<SaveProject> openProject() async {
          final result = await engine.open(
            rootPath: '/save',
            source: source,
            layout: layout,
            detectedVersion: 1,
          );
          return switch (result) {
            ParseOk(:final project) ||
            ParseUnverified(:final project) => project,
            _ => fail('open failed: $result'),
          };
        }

        final project = await openProject();
        final edited = engine.apply(project, SetScalar(id, 0x12345678));
        final plan = engine.planExport(
          edited,
          destinationRoot: '/save',
          mode: ExportMode.saveInPlace,
        );
        final result = await engine.export(
          plan,
          source: source,
          originals: originals,
        );
        expect(result.succeeded, isTrue, reason: '${result.issues}');

        final written = source.files[slotLayout.id]!;
        expect(
          written.sublist(descriptor.span.offset, descriptor.span.end),
          <int>[0x78, 0x56, 0x34, 0x12],
        );

        final reopened = await openProject();
        final field = reopened.documents[slotLayout.id]!.field(id);
        expect(field, isNotNull);
        expect(field!.value, const IntValue(0x12345678));
      },
    );
  });
}

ProgressSave _save() {
  final result = ProgressCodec.decode(buildSyntheticProgress());
  expect(result, isA<ProgressDecodeOk>(), reason: '$result');
  final base = (result as ProgressDecodeOk).save;
  const sourceKey = 0x04040404;
  final targetKey = murmur3X86_32(_arrayName);
  final bytes = base.encode();
  return ProgressSave.fromDecodedBytes(
    bytes: bytes,
    revision: base.revision,
    dataOffset: base.dataOffset,
    records: <ProgressRecord>[
      for (final record in base.records)
        if (record.key == sourceKey)
          ProgressRecord(
            bytes: bytes,
            key: targetKey,
            rawValue: record.rawValue,
            index: record.index,
            type: record.type,
            valueOffset: record.valueOffset,
            dataOffset: record.dataOffset,
            dataLength: record.dataLength,
          )
        else
          record,
    ],
    sentinels: base.sentinels,
    footer: base.footer,
  );
}

CaptionSave _caption() {
  final original = Uint8List(CaptionLayout.minimumFileLength);
  original.setRange(
    0,
    CaptionLayout.magicBytes.length,
    CaptionLayout.magicBytes,
  );
  return CaptionSave(
    originalBytes: original,
    sceneName: 'KokiriForest',
    mapPath: 'KokiriForest/KokiriForest_Child',
    jpegBytes: Uint8List.fromList(<int>[0xff, 0xd8, 0x00, 0xff, 0xd9]),
    savedAt: const CaptionSavedAt(
      year: 2026,
      month: 1,
      day: 2,
      hour: 3,
      minute: 4,
      second: 5,
    ),
  );
}

Future<GameDataSchema> _loadSchema() {
  const structIntName = 'PlayerStatus.Life';
  const hostBoolName = 'Sequence_IsChildhood';
  const prefixName = 'Sequence_CurrentBanc';
  final arrayHash = murmur3X86_32(_arrayName);
  final json =
      '''
{
  "schemaRevision": 2982123,
  "schemaRevisionHex": "0x2d80eb",
  "game": "synthetic-test",
  "provenance": {},
  "counts": {
    "onDiskFields": 5,
    "absentBool64bitKey": 0,
    "declaredNotSaved": 0,
    "sections": 4
  },
  "sections": [
    {"typeId": 1, "typeName": "Bool", "count": 1, "sentinelValue": 1,
     "recordStart": 0, "recordEnd": 0, "sentinelRecordIndex": 1},
    {"typeId": 3, "typeName": "Int", "count": 2, "sentinelValue": 3,
     "recordStart": 2, "recordEnd": 3, "sentinelRecordIndex": 4},
    {"typeId": 4, "typeName": "IntArray", "count": 1, "sentinelValue": 4,
     "recordStart": 5, "recordEnd": 5, "sentinelRecordIndex": 6},
    {"typeId": 17, "typeName": "String64", "count": 1, "sentinelValue": 17,
     "recordStart": 7, "recordEnd": 7, "sentinelRecordIndex": 8}
  ],
  "emptySectionIds": [],
  "fields": [
    {"id": 0, "hash": ${0xCEA220D3}, "type": "Bool", "section": 1,
     "presentOnDisk": true, "verified": true, "saveFileIndex": 0,
     "name": "$hostBoolName", "nameSource": "host-code"},
    {"id": 1, "hash": ${0x31AB5580}, "type": "Int", "section": 3,
     "presentOnDisk": true, "verified": true, "saveFileIndex": 0,
     "name": "$structIntName", "nameSource": "struct-default"},
    {"id": 2, "hash": $arrayHash, "type": "IntArray", "section": 4,
     "presentOnDisk": true, "verified": true, "saveFileIndex": 0,
     "name": "$_arrayName", "nameSource": "struct-default"},
    {"id": 3, "hash": ${0x1D6189DA}, "type": "String64", "section": 17,
     "presentOnDisk": true, "verified": true, "saveFileIndex": 0,
     "name": "$prefixName", "nameSource": "prefix-search"},
    {"id": 4, "hash": ${0x12345678}, "type": "Int", "section": 3,
     "presentOnDisk": true, "verified": true, "saveFileIndex": 0,
     "name": null, "nameSource": null}
  ],
  "absentFields": [],
  "declaredNotSaved": [],
  "enums": {},
  "unresolved": []
}
''';
  return GameDataSchema.load(() async => json);
}

final class _MemorySlotSource implements SlotSource {
  _MemorySlotSource(this.files);

  final Map<SaveSlotId, Uint8List> files;

  @override
  Future<Uint8List?> read(SaveSlotId slot) async => files[slot];

  @override
  Future<void> write(
    SaveSlotId slot,
    Uint8List bytes, {
    bool keepPreviousVersion = true,
  }) async {
    files[slot] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeAll(
    Map<SaveSlotId, Uint8List> writes, {
    bool keepPreviousVersion = true,
  }) async {
    for (final entry in writes.entries) {
      files[entry.key] = Uint8List.fromList(entry.value);
    }
  }

  @override
  String pathFor(SaveSlotId slot) => '/save/${slot.value}.sav';
}

final class _MemoryOriginalStore implements OriginalStore {
  final Map<SaveSlotId, Uint8List> stored = <SaveSlotId, Uint8List>{};

  @override
  String get rootPath => '/save.bombflower-original';

  @override
  Future<void> ensure(
    Map<SaveSlotId, ByteRegion> originals,
    BackupPolicy policy,
  ) async {
    for (final entry in originals.entries) {
      stored[entry.key] = entry.value.materialize();
    }
  }

  @override
  Future<Uint8List?> read(SaveSlotId slot) async => stored[slot];

  @override
  Future<bool> verify(Map<SaveSlotId, ByteRegion> originals) async {
    for (final entry in originals.entries) {
      final storedBytes = stored[entry.key];
      final expected = entry.value.materialize();
      if (storedBytes == null || storedBytes.length != expected.length) {
        return false;
      }
      for (var i = 0; i < storedBytes.length; i++) {
        if (storedBytes[i] != expected[i]) {
          return false;
        }
      }
    }
    return true;
  }
}
