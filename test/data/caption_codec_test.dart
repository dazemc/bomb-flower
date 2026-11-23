import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/codec/byte_reader.dart';
import 'package:bomb_flower/data/codec/caption_codec.dart';
import 'package:bomb_flower/domain/save/caption_layout.dart';
import 'package:bomb_flower/domain/save/models/caption_save.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/synthetic_caption.dart';

void main() {
  group('ByteReader', () {
    final bytes = Uint8List.fromList(<int>[0x01, 0x02, 0x03, 0x04, 0xff]);

    test('reads little- and big-endian integers explicitly', () {
      final reader = ByteReader(bytes, label: 'test');
      expect(reader.u8(4), 0xff);
      expect(reader.u16le(0), 0x0201);
      expect(reader.u16be(0), 0x0102);
      expect(reader.u32le(0), 0x04030201);
      expect(reader.u32be(0), 0x01020304);
      expect(reader.copyRange(1, 2), <int>[0x02, 0x03]);
    });

    test('rejects a read outside the buffer', () {
      final reader = ByteReader(bytes, label: 'test');
      expect(() => reader.u8(5), throwsA(isA<ByteReaderRangeError>()));
      expect(() => reader.u16le(4), throwsA(isA<ByteReaderRangeError>()));
      expect(() => reader.u32le(2), throwsA(isA<ByteReaderRangeError>()));
      expect(() => reader.u8(-1), throwsA(isA<ByteReaderRangeError>()));
      expect(
        () => reader.copyRange(4, 2),
        throwsA(isA<ByteReaderRangeError>()),
      );
    });
  });

  group('synthetic caption decode', () {
    test('reads the verified fields', () {
      final bytes = buildSyntheticCaption();
      final save = _decodeOk(bytes);

      expect(save.magic, CaptionLayout.magicValue);
      expect(save.sceneName, 'TestScene');
      expect(save.mapPath, 'TestScene/Room_1');
      expect(save.mapName, 'Room_1');
      expect(save.jpegLength, syntheticJpegBytes.length);
      expect(save.jpegBytes, syntheticJpegBytes);
      expect(
        save.savedAt,
        const CaptionSavedAt(
          year: 2026,
          month: 1,
          day: 1,
          hour: 0,
          minute: 0,
          second: 0,
        ),
      );
    });

    test('accepts a full 64-byte name with no NUL', () {
      final name = 'A' * CaptionLayout.nameLength;
      final bytes = buildSyntheticCaption(sceneName: name);
      final save = _decodeOk(bytes);
      expect(save.sceneName, name);
      expect(save.sceneName.length, CaptionLayout.nameLength);
      expect(CaptionCodec.encode(save), bytes);
    });

    test('keeps bytes after a name NUL', () {
      final bytes = buildSyntheticCaption(
        sceneName: 'Market',
        sceneTrailer: 'ield'.codeUnits,
        mapPath: 'Market/Market_Child',
        mapTrailer: 'eld_Child\u0000d'.codeUnits,
      );
      final save = _decodeOk(bytes);
      expect(save.sceneName, 'Market');
      expect(save.mapPath, 'Market/Market_Child');
      expect(CaptionCodec.encode(save), bytes);
    });

    test('wrong magic is unsupported', () {
      final bytes = buildSyntheticCaption()..[0] = 0x00;
      final result = CaptionCodec.decode(bytes);
      expect(result, isA<CaptionDecodeUnsupported>());
      expect((result as CaptionDecodeUnsupported).magicHex, '0x01020300');
    });

    test('a layout-marker mismatch is corrupt', () {
      final bytes = buildSyntheticCaption();
      _putU32Le(bytes, CaptionLayout.layoutCheckOffset, 1000);
      final result = CaptionCodec.decode(bytes);
      expect(result, isA<CaptionDecodeCorrupt>());
      expect((result as CaptionDecodeCorrupt).offset, 540);
    });

    test('a JPEG length beyond the buffer is corrupt', () {
      final bytes = buildSyntheticCaption(
        jpegLength: syntheticJpegBytes.length + 100,
      );
      final result = CaptionCodec.decode(bytes);
      expect(result, isA<CaptionDecodeCorrupt>());
      expect((result as CaptionDecodeCorrupt).offset, 1392);
    });

    test('a JPEG length that does not reach the end is corrupt', () {
      final bytes = buildSyntheticCaption(
        jpegLength: syntheticJpegBytes.length - 2,
      );
      expect(CaptionCodec.decode(bytes), isA<CaptionDecodeCorrupt>());
    });

    test('a JPEG shorter than its markers is corrupt', () {
      final bytes = buildSyntheticCaption(jpegLength: 2);
      expect(CaptionCodec.decode(bytes), isA<CaptionDecodeCorrupt>());
    });

    test('a missing JPEG end marker is corrupt', () {
      final bytes = buildSyntheticCaption();
      bytes[bytes.length - 1] = 0x00;
      expect(CaptionCodec.decode(bytes), isA<CaptionDecodeCorrupt>());
    });

    test('a non-printable name byte is corrupt', () {
      final bytes = buildSyntheticCaption();
      bytes[CaptionLayout.sceneNameOffset] = 0x01;
      final result = CaptionCodec.decode(bytes);
      expect(result, isA<CaptionDecodeCorrupt>());
      expect((result as CaptionDecodeCorrupt).offset, 684);
    });

    test('a missing date key is corrupt', () {
      final offsets = <CaptionDateField, int>{
        for (final descriptor in CaptionLayout.dateFields)
          if (descriptor.field != CaptionDateField.year)
            descriptor.field: descriptor.sampleOffset,
      };
      final bytes = buildSyntheticCaption(dateOffsets: offsets);
      expect(CaptionCodec.decode(bytes), isA<CaptionDecodeCorrupt>());
    });

    test('date entries not on one 8-byte grid are corrupt', () {
      final bytes = buildSyntheticCaption(
        dateOffsets: <CaptionDateField, int>{
          for (final descriptor in CaptionLayout.dateFields)
            descriptor.field: descriptor.sampleOffset,
          CaptionDateField.year: 361,
        },
      );
      expect(CaptionCodec.decode(bytes), isA<CaptionDecodeCorrupt>());
    });

    test('a buffer shorter than the fixed layout is truncated', () {
      final bytes = buildSyntheticCaption().sublist(0, 1000);
      final result = CaptionCodec.decode(bytes);
      expect(result, isA<CaptionDecodeTruncated>());
      expect((result as CaptionDecodeTruncated).length, 1000);
      expect(result.minimumLength, CaptionLayout.minimumFileLength);
    });
  });

  group('synthetic caption encode', () {
    test('an unedited decode re-encodes byte-identically', () {
      final bytes = buildSyntheticCaption();
      final save = _decodeOk(bytes);
      expect(CaptionCodec.encode(save), bytes);
    });

    test('editing sceneName changes only the 64-byte scene span', () {
      final bytes = buildSyntheticCaption();
      final save = _decodeOk(bytes);
      final out = CaptionCodec.encode(save.copyWith(sceneName: 'LostWoods'));

      expect(out.length, bytes.length);
      final changed = _changedOffsets(bytes, out);
      expect(changed, isNotEmpty);
      expect(
        changed.every(
          (offset) =>
              offset >= CaptionLayout.sceneNameOffset &&
              offset < CaptionLayout.sceneNameOffset + CaptionLayout.nameLength,
        ),
        isTrue,
        reason: 'changed offsets: $changed',
      );
      expect(
        out.sublist(CaptionLayout.jpegOffset),
        bytes.sublist(CaptionLayout.jpegOffset),
      );
      expect(_decodeOk(out).sceneName, 'LostWoods');
    });

    test('editing mapPath changes only the 64-byte map-path span', () {
      final bytes = buildSyntheticCaption();
      final save = _decodeOk(bytes);
      final out = CaptionCodec.encode(
        save.copyWith(mapPath: 'TestScene/Room_2'),
      );

      expect(out.length, bytes.length);
      final changed = _changedOffsets(bytes, out);
      expect(changed, isNotEmpty);
      expect(
        changed.every(
          (offset) =>
              offset >= CaptionLayout.mapPathOffset &&
              offset < CaptionLayout.mapPathOffset + CaptionLayout.nameLength,
        ),
        isTrue,
        reason: 'changed offsets: $changed',
      );
      expect(
        out.sublist(CaptionLayout.jpegOffset),
        bytes.sublist(CaptionLayout.jpegOffset),
      );
      expect(_decodeOk(out).mapPath, 'TestScene/Room_2');
    });

    test('editing the date changes only the six value words', () {
      final bytes = buildSyntheticCaption();
      final save = _decodeOk(bytes);
      const changedDate = CaptionSavedAt(
        year: 1998,
        month: 11,
        day: 21,
        hour: 23,
        minute: 59,
        second: 58,
      );
      final out = CaptionCodec.encode(save.copyWith(savedAt: changedDate));

      final allowed = <int>{};
      for (final descriptor in CaptionLayout.dateFields) {
        final at = descriptor.sampleOffset + 4;
        allowed.addAll(<int>[at, at + 1, at + 2, at + 3]);
      }
      final changed = _changedOffsets(bytes, out);
      expect(changed, isNotEmpty);
      expect(
        changed.every(allowed.contains),
        isTrue,
        reason: 'changed offsets: $changed',
      );
      expect(_decodeOk(out).savedAt, changedDate);
      expect(
        out.sublist(CaptionLayout.jpegOffset),
        bytes.sublist(CaptionLayout.jpegOffset),
      );
    });

    test('replacing the JPEG at the same length changes only the picture', () {
      final bytes = buildSyntheticCaption();
      final save = _decodeOk(bytes);
      final replacement = <int>[
        ...syntheticJpegBytes.take(syntheticJpegBytes.length - 4),
        0xaa,
        0xbb,
        0xff,
        0xd9,
      ];
      final out = CaptionCodec.encode(
        save.copyWith(jpegBytes: Uint8List.fromList(replacement)),
      );

      expect(out.length, bytes.length);
      expect(
        out.sublist(0, CaptionLayout.jpegOffset),
        bytes.sublist(0, CaptionLayout.jpegOffset),
      );
      expect(out.sublist(CaptionLayout.jpegOffset), replacement);
    });

    test('a longer JPEG rewrites only the length word and the picture', () {
      final bytes = buildSyntheticCaption();
      final save = _decodeOk(bytes);
      final replacement = <int>[
        ...syntheticJpegBytes.take(syntheticJpegBytes.length - 2),
        0xde,
        0xad,
        0xbe,
        0xef,
        0xff,
        0xd9,
      ];
      final out = CaptionCodec.encode(
        save.copyWith(jpegBytes: Uint8List.fromList(replacement)),
      );

      expect(out.length, CaptionLayout.jpegOffset + replacement.length);
      expect(
        out.sublist(0, CaptionLayout.jpegLengthOffset),
        bytes.sublist(0, CaptionLayout.jpegLengthOffset),
      );
      expect(
        _readU32Le(out, CaptionLayout.jpegLengthOffset),
        replacement.length,
      );
      expect(out.sublist(CaptionLayout.jpegOffset), replacement);
    });

    test('editing a name clears stale bytes after the old NUL', () {
      final bytes = buildSyntheticCaption(
        sceneName: 'Market',
        sceneTrailer: 'ield'.codeUnits,
        mapPath: 'Market/Market_Child',
        mapTrailer: 'eld_Child\u0000d'.codeUnits,
      );
      final save = _decodeOk(bytes);
      final out = CaptionCodec.encode(save.copyWith(sceneName: 'Market2'));

      expect(
        out.sublist(
          CaptionLayout.sceneNameOffset,
          CaptionLayout.sceneNameOffset + 7,
        ),
        'Market2'.codeUnits,
      );
      expect(
        out.sublist(
          CaptionLayout.sceneNameOffset + 7,
          CaptionLayout.sceneNameOffset + CaptionLayout.nameLength,
        ),
        everyElement(0),
      );
      expect(
        out.sublist(CaptionLayout.mapPathOffset),
        bytes.sublist(CaptionLayout.mapPathOffset),
      );
    });

    test('rejects a name longer than 64 characters', () {
      final save = _decodeOk(buildSyntheticCaption());
      expect(
        () => CaptionCodec.encode(save.copyWith(sceneName: 'A' * 65)),
        throwsArgumentError,
      );
    });

    test('rejects a name outside printable ASCII', () {
      final save = _decodeOk(buildSyntheticCaption());
      expect(
        () => CaptionCodec.encode(save.copyWith(mapPath: 'TestScène/Room_1')),
        throwsArgumentError,
      );
    });

    test('rejects a payload without JPEG markers', () {
      final save = _decodeOk(buildSyntheticCaption());
      expect(
        () => CaptionCodec.encode(
          save.copyWith(
            jpegBytes: Uint8List.fromList(<int>[0xff, 0xd8, 0x00, 0x00]),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Longshot repository samples', () {
    final root = Directory('../Longshot/assets/saves');
    const samples = <String, ({String scene, String map})>{
      'kokiri-start': (
        scene: 'KokiriForest',
        map: 'KokiriForest/KokiriForest_Child',
      ),
      'castle-gate': (
        scene: 'HyruleField',
        map: 'HyruleField/HyruleField_Child',
      ),
      'market-entrance': (scene: 'Market', map: 'Market/Market_Child'),
    };
    for (final entry in samples.entries) {
      final file = File('${root.path}/${entry.key}/slot_00/caption.sav');
      final skipReason = file.existsSync()
          ? false
          : 'Longshot sample saves not present';

      test('${entry.key}: decodes the verified values', () {
        final bytes = file.readAsBytesSync();
        expect(bytes.length, 4741);
        final save = _decodeOk(bytes);

        expect(save.sceneName, entry.value.scene);
        expect(save.mapPath, entry.value.map);
        expect(save.jpegLength, 3345);
        expect(save.jpegBytes.sublist(0, 2), <int>[0xff, 0xd8]);
        expect(save.jpegBytes.sublist(save.jpegLength - 2), <int>[0xff, 0xd9]);
        expect(
          save.savedAt,
          const CaptionSavedAt(
            year: 2026,
            month: 1,
            day: 1,
            hour: 0,
            minute: 0,
            second: 0,
          ),
        );
      }, skip: skipReason);

      test('${entry.key}: round-trips byte-identically', () {
        final bytes = file.readAsBytesSync();
        final save = _decodeOk(bytes);
        expect(CaptionCodec.encode(save), bytes);
      }, skip: skipReason);
    }
  });
}

CaptionSave _decodeOk(Uint8List bytes) {
  final result = CaptionCodec.decode(bytes);
  expect(result, isA<CaptionDecodeOk>(), reason: '$result');
  return (result as CaptionDecodeOk).save;
}

List<int> _changedOffsets(Uint8List before, Uint8List after) {
  expect(after.length, before.length);
  return <int>[
    for (var i = 0; i < before.length; i++)
      if (before[i] != after[i]) i,
  ];
}

int _readU32Le(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

void _putU32Le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
  bytes[offset + 3] = (value >> 24) & 0xff;
}
