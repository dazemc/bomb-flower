import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bomb_flower/data/codec/progress_codec.dart';
import 'package:bomb_flower/domain/save/models/progress_save.dart';
import 'package:bomb_flower/domain/save/progress_layout.dart';
import 'package:bomb_flower/domain/save/progress_record.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/byte_assert.dart';
import '../support/synthetic_progress.dart';

const int _boolKey = 0xCEA220D3;
const int _lifeKey = 0x31AB5580;
const int _maxLifeKey = 0xFBE01DA1;
const int _rupeeKey = 0xA77921D7;
const int _rotKey = 0xA4AEE8CD;
const int _posKey = 0x960AD56A;
const int _bancKey = 0x1D6189DA;
const int _stringKey = 0x0A0A0A0A;
const int _intArrayKey = 0x04040404;
const int _stringArrayKey = 0x0B0B0B0B;
const int _binaryKey = 0x0C0C0C0C;
const int _uintKey = 0x0E0E0E0E;
const int _enumKey = 0x07070707;
const int _int64Key = 0x10101010;
const int _uint64Key = 0x11111111;

const List<String> _sampleNames = <String>[
  'kokiri-start',
  'castle-gate',
  'market-entrance',
];

const Map<SaveType, int> _sampleCounts = <SaveType, int>{
  SaveType.boolValue: 10212,
  SaveType.boolArray: 6,
  SaveType.intValue: 1144,
  SaveType.intArray: 155,
  SaveType.floatValue: 76,
  SaveType.floatArray: 3,
  SaveType.enumValue: 101,
  SaveType.enumArray: 14,
  SaveType.vector3: 16,
  SaveType.string32: 1,
  SaveType.string64: 30,
  SaveType.string64Array: 3,
  SaveType.binary: 3,
  SaveType.binaryArray: 2,
  SaveType.uintValue: 87,
  SaveType.uintArray: 33,
  SaveType.int64: 28,
  SaveType.uint64: 5,
  SaveType.uint64Array: 4,
  SaveType.wstring16Array: 2,
};

void main() {
  group('ProgressLayout', () {
    test('descriptors are the 32 sentinels in type order', () {
      expect(ProgressLayout.sections.length, 32);
      for (var i = 0; i < ProgressLayout.sections.length; i++) {
        final descriptor = ProgressLayout.sections[i];
        expect(descriptor.typeId, i + 1);
        expect(descriptor.name, isNotEmpty);
        expect(ProgressLayout.sectionFor(descriptor.type), descriptor);
      }
      expect(ProgressLayout.sections.first.sampleCount, 10212);
      expect(ProgressLayout.sections.last.sampleCount, 0);
      expect(ProgressLayout.sectionFor(SaveType.wstring16Array).sampleCount, 2);
    });

    test('keeps the verified sample constants', () {
      expect(ProgressLayout.magicValue, 0x01020304);
      expect(ProgressLayout.revision, 2982123);
      expect(ProgressLayout.sampleDataOffset, 0x175D8);
      expect(ProgressLayout.sampleRecordCount, 11958);
      expect(ProgressLayout.sampleFieldCount, 11925);
      expect(ProgressLayout.sampleFileLength, 120572);
      expect(
        ProgressLayout.recordStart +
            ProgressLayout.sampleRecordCount * ProgressLayout.recordSize,
        ProgressLayout.sampleDataOffset,
      );
      expect(ProgressLayout.minimumFileLength, 304);
    });

    test('has exactly the seven verified names', () {
      expect(ProgressLayout.verifiedFieldNames.length, 7);
      expect(
        ProgressLayout.verifiedFieldNames[_bancKey],
        'Sequence_CurrentBanc',
      );
      expect(ProgressLayout.verifiedFieldNames[_lifeKey], 'PlayerStatus.Life');
      expect(
        ProgressLayout.verifiedFieldNames.containsKey(0x01010101),
        isFalse,
      );
    });
  });

  group('real .local-fixtures samples', () {
    for (final name in _sampleNames) {
      final file = File('.local-fixtures/$name/slot_00/progress.sav');
      final skipReason = file.existsSync()
          ? false
          : 'No ${file.path}; run `dart run tool/make_fixtures.dart` to '
                'populate the gitignored .local-fixtures/ directory.';

      test(
        '$name: decodes the verified walk and round-trips byte-identically',
        () {
          final bytes = Uint8List.fromList(file.readAsBytesSync());
          final save = _ok(bytes);

          expect(save.revision, ProgressLayout.revision);
          expect(save.dataOffset, ProgressLayout.sampleDataOffset);
          expect(save.recordCount, ProgressLayout.sampleRecordCount);
          expect(save.fieldCount, ProgressLayout.sampleFieldCount);
          expect(save.sentinels.length, ProgressLayout.sentinelCount);
          expect(
            <int>[for (final sentinel in save.sentinels) sentinel.rawValue],
            <int>[for (var i = 1; i <= 32; i++) i],
          );
          expect(save.footer.key, ProgressLayout.footerKey);
          expect(save.footer.rawValue, ProgressLayout.footerValue);
          expect(save.footer.index, save.recordCount - 1);
          expect(save.sections.length, 32);

          for (final entry in _sampleCounts.entries) {
            expect(
              save.sectionFor(entry.key).records.length,
              entry.value,
              reason: entry.key.label,
            );
          }

          expect(save.encode(), bytes);
          expect(ProgressCodec.encode(save), bytes);

          if (name == 'kokiri-start') {
            expect(
              save.recordByHash(_bancKey)!.asString(),
              'KokiriForest_Child',
            );
            expect(save.recordByHash(_boolKey)!.asBool(), isTrue);
            expect(save.recordByHash(_lifeKey)!.asInt(), 12);
            expect(save.recordByHash(_maxLifeKey)!.asInt(), 12);
            expect(save.recordByHash(_rupeeKey)!.asInt(), 0);
            expect(
              save.recordByHash(_rotKey)!.asFloat(),
              closeTo(-71.43298, 0.0001),
            );
            final position = save.recordByHash(_posKey)!.asVector3();
            expect(position.x, closeTo(-46.08690, 0.0001));
            expect(position.y, closeTo(118.43888, 0.0001));
            expect(position.z, closeTo(15.39390, 0.0001));
          }
        },
        skip: skipReason,
      );

      test('$name: a setInt edit changes exactly four bytes', () {
        final bytes = Uint8List.fromList(file.readAsBytesSync());
        final save = _ok(bytes);
        final life = save.recordByHash(_lifeKey)!;
        final edited = save.setInt(_lifeKey, life.asInt() + 1).encode();

        expectOnlyRegionsChanged(bytes, edited, <ByteRegion>[
          ByteRegion(
            life.valueOffset,
            life.valueOffset + 4,
            'PlayerStatus.Life value',
          ),
        ]);
        expect(_ok(edited).recordByHash(_lifeKey)!.asInt(), life.asInt() + 1);
      }, skip: skipReason);
    }
  });

  group('synthetic decode', () {
    late Uint8List synthetic;
    late ProgressSave save;

    setUp(() {
      synthetic = buildSyntheticProgress();
      save = _ok(synthetic);
    });

    test('reads the header, all 32 sections and the footer', () {
      expect(save.magic, ProgressLayout.magicValue);
      expect(save.revision, ProgressLayout.revision);
      expect(save.dataOffset, 40 + 8 * save.recordCount);
      expect(save.fieldCount, 26);
      expect(save.recordCount, 26 + 32 + 1);
      expect(save.sentinels.first.rawValue, 1);
      expect(save.sentinels.last.rawValue, 32);
      expect(save.footer.key, ProgressLayout.footerKey);
      expect(save.footer.rawValue, ProgressLayout.footerValue);
      expect(save.sections.length, 32);
      expect(save.sectionFor(SaveType.boolValue).records.length, 2);
      expect(save.sectionFor(SaveType.reserved9).records, isEmpty);
      expect(save.sectionFor(SaveType.reserved9).sentinel.rawValue, 9);
      expect(save.recordByHash(_lifeKey), isNotNull);
      expect(save.recordsByHash(_lifeKey).length, 1);
    });

    test('encodes an untouched save byte-identically', () {
      expect(save.encode(), synthetic);
      expect(ProgressCodec.encode(save), synthetic);
      expect(save.isEdited, isFalse);
      expect(save.originalBytes, synthetic);
    });

    test('a save with only sentinels and the footer is valid', () {
      final bytes = buildSyntheticProgress(includeFields: false);
      final empty = _ok(bytes);
      expect(empty.fieldCount, 0);
      expect(empty.recordCount, 33);
      expect(empty.dataOffset, 304);
      expect(empty.records, isEmpty);
      expect(empty.sections.length, 32);
      expect(empty.encode(), bytes);
    });

    test('keeps sentinels, footer, tail and opaque bytes on a zero-edit round trip', () {
      final out = save.encode();
      for (final sentinel in save.sentinels) {
        expect(_u32(out, sentinel.recordOffset), 0);
        expect(_u32(out, sentinel.valueOffset), sentinel.rawValue);
        expect(out[sentinel.recordOffset], 0);
      }
      expect(_u32(out, save.footer.recordOffset), save.footer.key);
      expect(_u32(out, save.footer.valueOffset), save.footer.rawValue);
      expect(save.tailBytes, synthetic.sublist(save.dataOffset));

      final binary = save.recordByHash(_binaryKey)!;
      expect(binary.type, SaveType.binary);
      expect(binary.dataLength, 4);
      expect(binary.copyDataBytes(), <int>[0xDE, 0xAD, 0xBE, 0xEF]);
      expect(
        out.sublist(binary.dataOffset!, binary.dataOffset! + binary.dataLength),
        binary.copyDataBytes(),
      );
    });

    test('a single-field edit leaves sentinels, footer and opaque bytes byte-identically', () {
      final life = save.recordByHash(_lifeKey)!;
      final edited = save.setInt(_lifeKey, 99).encode();
      expectOnlyRegionsChanged(synthetic, edited, <ByteRegion>[
        ByteRegion(life.valueOffset, life.valueOffset + 4, 'Life value'),
      ]);

      for (final sentinel in save.sentinels) {
        expect(
          _u32(edited, sentinel.recordOffset),
          _u32(synthetic, sentinel.recordOffset),
        );
        expect(
          _u32(edited, sentinel.valueOffset),
          _u32(synthetic, sentinel.valueOffset),
        );
      }
      expect(
        _u32(edited, save.footer.recordOffset),
        _u32(synthetic, save.footer.recordOffset),
      );
      expect(
        _u32(edited, save.footer.valueOffset),
        _u32(synthetic, save.footer.valueOffset),
      );

      final binary = save.recordByHash(_binaryKey)!;
      final start = binary.dataOffset!;
      final end = start + binary.dataLength;
      expect(edited.sublist(start, end), synthetic.sublist(start, end));
    });

    test('preserves an unparsed tail gap between known records', () {
      final bytes = buildSyntheticProgress(tailGaps: <int, int>{_int64Key: 5});
      final gapSave = _ok(bytes);
      final record = gapSave.recordByHash(_int64Key)!;
      expect(record.dataLength, 8);
      expect(gapSave.encode(), bytes);

      final edited = gapSave.setInt64(_int64Key, 123).encode();
      expectOnlyRegionsChanged(bytes, edited, <ByteRegion>[
        ByteRegion(record.dataOffset!, record.dataOffset! + 8, 'Int64 data'),
      ]);
      expect(
        edited.sublist(record.dataOffset! + 8, record.dataOffset! + 13),
        <int>[0, 0, 0, 0, 0],
      );
    });
  });

  group('validation', () {
    late Uint8List synthetic;
    late ProgressSave save;

    setUp(() {
      synthetic = buildSyntheticProgress();
      save = _ok(synthetic);
    });

    test('rejects a wrong magic as unsupported', () {
      final bytes = _copy(synthetic);
      _putU32(bytes, 0, 0x01020305);
      final result = ProgressCodec.decode(bytes);
      expect(result, isA<ProgressBadMagic>());
      expect((result as ProgressBadMagic).magic, 0x01020305);
      expect(result.magicHex, '0x01020305');
      expect(result, isA<ProgressDecodeUnsupported>());
    });

    test('rejects a wrong revision as unsupported', () {
      final bytes = _copy(synthetic);
      _putU32(bytes, 4, 2982122);
      final result = ProgressCodec.decode(bytes);
      expect(result, isA<ProgressRevisionMismatch>());
      final mismatch = result as ProgressRevisionMismatch;
      expect(mismatch.revision, 2982122);
      expect(mismatch.expected, 2982123);
      expect(mismatch, isA<ProgressDecodeUnsupported>());
    });

    test('rejects a misaligned data offset at offset 8', () {
      final bytes = _copy(synthetic);
      _putU32(bytes, 8, save.dataOffset + 1);
      final corrupt = _corrupt(bytes);
      expect(corrupt.offset, 8);
      expect(corrupt.reason, contains('0x28 + 8*N'));
    });

    test('rejects a data offset with too few records at offset 8', () {
      final bytes = _copy(synthetic);
      _putU32(bytes, 8, ProgressLayout.recordStart);
      final corrupt = _corrupt(bytes);
      expect(corrupt.offset, 8);
      expect(corrupt.reason, contains('at least 33'));
    });

    test('reports a data offset past EOF as truncated', () {
      final bytes = _copy(synthetic);
      final beyond = save.dataOffset + 8 * 100;
      _putU32(bytes, 8, beyond);
      final result = ProgressCodec.decode(bytes);
      expect(result, isA<ProgressDecodeTruncated>());
      final truncated = result as ProgressDecodeTruncated;
      expect(truncated.length, bytes.length);
      expect(truncated.minimumLength, beyond);
    });

    test('reports every truncation point as truncated', () {
      final lengths = <int>[0, 3, 4, 7, 8, 11, 12, 40, save.dataOffset - 1];
      for (final length in lengths) {
        final result = ProgressCodec.decode(
          Uint8List.fromList(synthetic.sublist(0, length)),
        );
        expect(
          result,
          isA<ProgressDecodeTruncated>(),
          reason: 'length $length returned $result',
        );
      }
    });

    test(
      'accepts a buffer cut exactly at the data offset when it has no tail',
      () {
        final bytes = buildSyntheticProgress(includeFields: false);
        final empty = _ok(bytes);
        final cut = Uint8List.fromList(bytes.sublist(0, empty.dataOffset));
        expect(cut.length, 304);
        final decoded = _ok(cut);
        expect(decoded.fieldCount, 0);
        expect(decoded.encode(), cut);
      },
    );

    test('rejects a sentinel out of order at its value word', () {
      final bytes = _copy(synthetic);
      final sentinel = save.sentinels[1];
      _putU32(bytes, sentinel.valueOffset, 3);
      final corrupt = _corrupt(bytes);
      expect(corrupt.offset, sentinel.valueOffset);
      expect(corrupt.reason, contains('expected 2'));
    });

    test('rejects a duplicate sentinel at its value word', () {
      final bytes = _copy(synthetic);
      final sentinel = save.sentinels[1];
      _putU32(bytes, sentinel.valueOffset, 1);
      final corrupt = _corrupt(bytes);
      expect(corrupt.offset, sentinel.valueOffset);
      expect(corrupt.reason, contains('expected 2'));
    });

    test('rejects a wrong footer key at the footer record', () {
      final bytes = _copy(synthetic);
      _putU32(bytes, save.footer.recordOffset, 0);
      final corrupt = _corrupt(bytes);
      expect(corrupt.offset, save.footer.recordOffset);
      expect(corrupt.reason, contains('footer'));
    });

    test('rejects a non-zero reserved header byte at its offset', () {
      final bytes = _copy(synthetic);
      bytes[ProgressLayout.reservedOffset] = 0xff;
      final corrupt = _corrupt(bytes);
      expect(corrupt.offset, ProgressLayout.reservedOffset);
      expect(corrupt.reason, contains('reserved'));
    });

    test('rejects a pointer outside the tail at its value word', () {
      final bytes = _copy(synthetic);
      final vector = save.recordByHash(_posKey)!;
      _putU32(bytes, vector.valueOffset, bytes.length + 4);
      final corrupt = _corrupt(bytes);
      expect(corrupt.offset, vector.valueOffset);
      expect(corrupt.reason, contains('must lie in'));
    });

    test('rejects a pointer below the data offset', () {
      final bytes = _copy(synthetic);
      final vector = save.recordByHash(_posKey)!;
      _putU32(bytes, vector.valueOffset, save.dataOffset - 1);
      final corrupt = _corrupt(bytes);
      expect(corrupt.offset, vector.valueOffset);
    });

    test('rejects a string slot without a NUL at the slot start', () {
      final bytes = _copy(synthetic);
      final string = save.recordByHash(_bancKey)!;
      _fill(bytes, string.dataOffset!, string.dataLength, 0x41);
      final corrupt = _corrupt(bytes);
      expect(corrupt.offset, string.dataOffset);
      expect(corrupt.reason, contains('no NUL'));
    });

    test('rejects a String64Array element without a NUL at its start', () {
      final bytes = _copy(synthetic);
      final array = save.recordByHash(_stringArrayKey)!;
      final elementStart = array.dataOffset! + 4 + 64;
      _fill(bytes, elementStart, 64, 0x42);
      final corrupt = _corrupt(bytes);
      expect(corrupt.offset, elementStart);
      expect(corrupt.reason, contains('no NUL'));
    });

    test('rejects an array count that does not fit at the count word', () {
      final bytes = _copy(synthetic);
      final array = save.recordByHash(_intArrayKey)!;
      _putU32(bytes, array.dataOffset!, 0xFFFFFFFF);
      final corrupt = _corrupt(bytes);
      expect(corrupt.offset, array.dataOffset);
      expect(corrupt.reason, contains('count'));
    });

    test('rejects a Bool value other than 0 or 1 at its value word', () {
      final bytes = _copy(synthetic);
      final boolean = save.recordByHash(_boolKey)!;
      _putU32(bytes, boolean.valueOffset, 2);
      final corrupt = _corrupt(bytes);
      expect(corrupt.offset, boolean.valueOffset);
      expect(corrupt.reason, contains('Bool'));
    });

    test('rejects overlapping tail regions at the later value word', () {
      final bytes = _copy(synthetic);
      final first = save.recordByHash(_bancKey)!;
      final second = save.recordByHash(_stringKey)!;
      _putU32(bytes, second.valueOffset, first.dataOffset!);
      final corrupt = _corrupt(bytes);
      expect(corrupt.offset, second.valueOffset);
      expect(corrupt.reason, contains('overlaps'));
    });

    test('never throws on arbitrary short buffers', () {
      final random = math.Random(20261122);
      for (var length = 0; length < 400; length += 7) {
        final bytes = Uint8List.fromList(<int>[
          for (var i = 0; i < length; i++) random.nextInt(256),
        ]);
        expect(
          () => ProgressCodec.decode(bytes),
          returnsNormally,
          reason: 'length $length',
        );
      }
    });

    test('does not allocate from an absurd data offset', () {
      final bytes = _copy(synthetic);
      _putU32(bytes, 8, 0xFFFFFFF8);
      final result = ProgressCodec.decode(bytes);
      expect(result, isA<ProgressDecodeTruncated>());
      expect((result as ProgressDecodeTruncated).minimumLength, 0xFFFFFFF8);
    });
  });

  group('typed accessors', () {
    late ProgressSave save;

    setUp(() {
      save = _ok(buildSyntheticProgress());
    });

    test('read every inline and tail type', () {
      expect(save.recordByHash(_lifeKey)!.asInt(), 20);
      expect(save.recordByHash(0x03030303)!.asInt(), -7);
      expect(save.recordByHash(_uintKey)!.asUInt(), 0xFFFFFFF0);
      expect(save.recordByHash(_rotKey)!.asFloat(), 1.5);
      expect(save.recordByHash(0x05050505)!.asFloat(), -2.25);
      expect(save.recordByHash(_boolKey)!.asBool(), isTrue);
      expect(save.recordByHash(0x01010101)!.asBool(), isFalse);
      expect(save.recordByHash(_enumKey)!.asEnumHash(), 0xDEADBEEF);
      expect(save.recordByHash(_bancKey)!.asString(), 'KokiriForest_Child');
      expect(save.recordByHash(0x09090909)!.asString(), 'Short');
      expect(
        save.recordByHash(_posKey)!.asVector3(),
        const ProgressVector3(1.0, -2.0, 3.5),
      );
      expect(save.recordByHash(_int64Key)!.asInt64(), -5);
      expect(save.recordByHash(_uint64Key)!.asUInt64(), 9);
      expect(save.recordByHash(_binaryKey)!.copyDataBytes(), <int>[
        0xDE,
        0xAD,
        0xBE,
        0xEF,
      ]);
    });

    test('rejects the wrong type with FormatException', () {
      expect(
        () => save.recordByHash(_lifeKey)!.asBool(),
        throwsFormatException,
      );
      expect(() => save.recordByHash(_boolKey)!.asInt(), throwsFormatException);
      expect(
        () => save.recordByHash(_bancKey)!.asVector3(),
        throwsFormatException,
      );
      expect(() => save.sentinels.first.asBool(), throwsFormatException);
      expect(
        () => save.recordByHash(_bancKey)!.asInt64(),
        throwsFormatException,
      );
    });

    test('throws RangeError when a record data span is outside its buffer', () {
      final short = Uint8List(4);
      final record = ProgressRecord(
        bytes: short,
        key: 0x12345678,
        rawValue: 0,
        index: 0,
        type: SaveType.intValue,
        valueOffset: 8,
        dataOffset: null,
        dataLength: 4,
      );
      expect(() => record.asInt(), throwsRangeError);
      expect(() => record.copyDataBytes(), throwsRangeError);
    });

    test(
      'throws FormatException for a manually built string without a NUL',
      () {
        final bytes = Uint8List.fromList(<int>[0x41, 0x42, 0x43, 0x44]);
        final record = ProgressRecord(
          bytes: bytes,
          key: 0x12345678,
          rawValue: 0,
          index: 0,
          type: SaveType.string64,
          valueOffset: 4,
          dataOffset: 0,
          dataLength: 4,
        );
        expect(() => record.asString(), throwsFormatException);
      },
    );

    test('exposes record offsets and key hex', () {
      final life = save.recordByHash(_lifeKey)!;
      expect(life.recordOffset, 40 + 8 * life.index);
      expect(life.valueOffset, life.recordOffset + 4);
      expect(life.keyHex, '0x31ab5580');
      expect(save.footer.keyHex, '0xa3db7114');
    });
  });

  group('in-place edits', () {
    late Uint8List before;
    late ProgressSave save;

    setUp(() {
      before = buildSyntheticProgress();
      save = _ok(before);
    });

    test('setInt changes exactly its four value bytes', () {
      final life = save.recordByHash(_lifeKey)!;
      final after = save.setInt(_lifeKey, 99);
      final edited = after.encode();

      expect(edited.length, before.length);
      expectOnlyRegionsChanged(before, edited, <ByteRegion>[
        ByteRegion(life.valueOffset, life.valueOffset + 4, 'Life value'),
      ]);
      expect(_u32(edited, life.valueOffset), 99);
      expect(after.recordByHash(_lifeKey)!.asInt(), 99);
      expect(after.recordByHash(_lifeKey)!.rawValue, 99);
      expect(after.isEdited, isTrue);
      expect(save.encode(), before);

      final reread = _ok(edited);
      expect(reread.recordByHash(_lifeKey)!.asInt(), 99);
      _expectOnlyRecordChanged(save, reread, life);
    });

    test('setInt accepts the signed 32-bit boundaries', () {
      final min = save.setInt(_lifeKey, -0x80000000);
      final max = save.setInt(_lifeKey, 0x7fffffff);
      expect(min.recordByHash(_lifeKey)!.asInt(), -0x80000000);
      expect(max.recordByHash(_lifeKey)!.asInt(), 0x7fffffff);
      expect(min.recordByHash(_lifeKey)!.rawValue, 0x80000000);
    });

    test('setUInt changes exactly its four value bytes', () {
      final record = save.recordByHash(_uintKey)!;
      final after = save.setUInt(_uintKey, 0x12345678);
      expectOnlyRegionsChanged(before, after.encode(), <ByteRegion>[
        ByteRegion(record.valueOffset, record.valueOffset + 4, 'UInt value'),
      ]);
      expect(after.recordByHash(_uintKey)!.asUInt(), 0x12345678);
    });

    test('setFloat changes exactly its four value bytes', () {
      final record = save.recordByHash(_rotKey)!;
      final after = save.setFloat(_rotKey, -3.75);
      expectOnlyRegionsChanged(before, after.encode(), <ByteRegion>[
        ByteRegion(record.valueOffset, record.valueOffset + 4, 'Float value'),
      ]);
      expect(after.recordByHash(_rotKey)!.asFloat(), -3.75);
    });

    test('setBool changes exactly its four value bytes', () {
      final record = save.recordByHash(_boolKey)!;
      final after = save.setBool(_boolKey, 0);
      expectOnlyRegionsChanged(before, after.encode(), <ByteRegion>[
        ByteRegion(record.valueOffset, record.valueOffset + 4, 'Bool value'),
      ]);
      expect(after.recordByHash(_boolKey)!.asBool(), isFalse);
      expect(after.recordByHash(_boolKey)!.rawValue, 0);
    });

    test('setEnumHash changes exactly its four value bytes', () {
      final record = save.recordByHash(_enumKey)!;
      final after = save.setEnumHash(_enumKey, 0xCAFEBABE);
      expectOnlyRegionsChanged(before, after.encode(), <ByteRegion>[
        ByteRegion(record.valueOffset, record.valueOffset + 4, 'Enum hash'),
      ]);
      expect(after.recordByHash(_enumKey)!.asEnumHash(), 0xCAFEBABE);
    });

    test(
      'setString changes exactly its slot, NUL-terminates and zero-fills',
      () {
        final stale = _copy(before);
        final slot = save.recordByHash(_stringKey)!;
        stale.setRange(
          slot.dataOffset! + 19,
          slot.dataOffset! + slot.dataLength,
          List<int>.filled(slot.dataLength - 19, 0x5A),
        );
        final staleSave = _ok(stale);
        expect(
          staleSave.recordByHash(_stringKey)!.asString(),
          'OldValueThatIsLong',
        );

        final after = staleSave.setString(_stringKey, 'New');
        final edited = after.encode();
        expectOnlyRegionsChanged(stale, edited, <ByteRegion>[
          ByteRegion(
            slot.dataOffset!,
            slot.dataOffset! + slot.dataLength,
            'String64 slot',
          ),
        ]);
        expect(after.recordByHash(_stringKey)!.asString(), 'New');
        for (var i = 3; i < slot.dataLength; i++) {
          expect(
            edited[slot.dataOffset! + i],
            0,
            reason: 'byte $i of the slot should be zero-filled',
          );
        }
      },
    );

    test('setString fills a slot to one byte short of overflow', () {
      final value = 'A' * 63;
      final after = save.setString(_stringKey, value);
      final edited = after.encode();
      final slot = save.recordByHash(_stringKey)!;
      expect(after.recordByHash(_stringKey)!.asString(), value);
      expect(edited[slot.dataOffset! + 63], 0);
    });

    test('setString refuses overflow and leaves bytes unchanged', () {
      final slot = save.recordByHash(_stringKey)!;
      expect(
        () => save.setString(_stringKey, 'A' * slot.dataLength),
        throwsArgumentError,
      );
      expect(save.encode(), before);
    });

    test(
      'setString rejects non-printable ASCII and leaves bytes unchanged',
      () {
        expect(
          () => save.setString(_stringKey, 'A\u0001'),
          throwsArgumentError,
        );
        expect(save.encode(), before);
      },
    );

    test('setVector3 changes exactly its twelve data bytes', () {
      final record = save.recordByHash(_posKey)!;
      final after = save.setVector3(_posKey, 9.5, -8.25, 7.0);
      expectOnlyRegionsChanged(before, after.encode(), <ByteRegion>[
        ByteRegion(record.dataOffset!, record.dataOffset! + 12, 'Vector3 data'),
      ]);
      expect(
        after.recordByHash(_posKey)!.asVector3(),
        const ProgressVector3(9.5, -8.25, 7.0),
      );
    });

    test('setInt64 changes exactly its eight data bytes', () {
      final record = save.recordByHash(_int64Key)!;
      final after = save.setInt64(_int64Key, -0x123456789);
      expectOnlyRegionsChanged(before, after.encode(), <ByteRegion>[
        ByteRegion(record.dataOffset!, record.dataOffset! + 8, 'Int64 data'),
      ]);
      expect(after.recordByHash(_int64Key)!.asInt64(), -0x123456789);
    });

    test('setUInt64 changes exactly its eight data bytes', () {
      final record = save.recordByHash(_uint64Key)!;
      final after = save.setUInt64(_uint64Key, 0x1122334455667788);
      expectOnlyRegionsChanged(before, after.encode(), <ByteRegion>[
        ByteRegion(record.dataOffset!, record.dataOffset! + 8, 'UInt64 data'),
      ]);
      expect(after.recordByHash(_uint64Key)!.asUInt64(), 0x1122334455667788);
    });

    test('setRawBytes replaces exactly an opaque Binary span', () {
      final record = save.recordByHash(_binaryKey)!;
      final after = save.setRawBytes(_binaryKey, <int>[1, 2, 3, 4]);
      expectOnlyRegionsChanged(before, after.encode(), <ByteRegion>[
        ByteRegion(
          record.dataOffset!,
          record.dataOffset! + record.dataLength,
          'Binary data',
        ),
      ]);
      expect(after.recordByHash(_binaryKey)!.copyDataBytes(), <int>[
        1,
        2,
        3,
        4,
      ]);
    });

    test('setRawBytes refuses a length change and leaves bytes unchanged', () {
      expect(
        () => save.setRawBytes(_binaryKey, <int>[1, 2, 3]),
        throwsArgumentError,
      );
      expect(save.encode(), before);
    });

    test('rejects a value edit on the wrong record type', () {
      expect(() => save.setInt(_boolKey, 1), throwsArgumentError);
      expect(() => save.setBool(_lifeKey, 1), throwsArgumentError);
      expect(() => save.setString(_lifeKey, 'x'), throwsArgumentError);
      expect(() => save.setRawBytes(_lifeKey, <int>[1]), throwsArgumentError);
      expect(() => save.setVector3(_lifeKey, 1, 2, 3), throwsArgumentError);
      expect(save.encode(), before);
    });

    test('rejects out-of-range values before changing anything', () {
      expect(() => save.setBool(_boolKey, 2), throwsArgumentError);
      expect(() => save.setBool(_boolKey, -1), throwsArgumentError);
      expect(() => save.setInt(_lifeKey, 0x80000000), throwsArgumentError);
      expect(() => save.setInt(_lifeKey, -0x80000001), throwsArgumentError);
      expect(() => save.setUInt(_uintKey, -1), throwsArgumentError);
      expect(() => save.setUInt(_uintKey, 0x100000000), throwsArgumentError);
      expect(
        () => save.setEnumHash(_enumKey, 0x100000000),
        throwsArgumentError,
      );
      expect(() => save.setFloat(_rotKey, double.nan), throwsArgumentError);
      expect(() => save.setFloat(_rotKey, 1e300), throwsArgumentError);
      expect(() => save.setUInt64(_uint64Key, -1), throwsArgumentError);
      expect(save.encode(), before);
    });

    test('applies several valid edits atomically', () {
      final life = save.recordByHash(_lifeKey)!;
      final slot = save.recordByHash(_stringKey)!;
      final after = save.applyEdits(<ProgressEdit>[
        const ProgressSetInt(key: _lifeKey, value: 25),
        const ProgressSetString(key: _stringKey, value: 'Atomic'),
      ]);
      final edited = after.encode();
      expectOnlyRegionsChanged(before, edited, <ByteRegion>[
        ByteRegion(life.valueOffset, life.valueOffset + 4, 'Life value'),
        ByteRegion(
          slot.dataOffset!,
          slot.dataOffset! + slot.dataLength,
          'String64 slot',
        ),
      ]);
      expect(after.recordByHash(_lifeKey)!.asInt(), 25);
      expect(after.recordByHash(_stringKey)!.asString(), 'Atomic');
    });

    test('rolls back every edit when a later edit is invalid', () {
      expect(
        () => save.applyEdits(<ProgressEdit>[
          const ProgressSetInt(key: _lifeKey, value: 25),
          const ProgressSetString(
            key: _stringKey,
            value: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          ),
        ]),
        throwsArgumentError,
      );
      expect(save.encode(), before);
      expect(save.recordByHash(_lifeKey)!.asInt(), 20);
      expect(save.recordByHash(_stringKey)!.asString(), 'OldValueThatIsLong');
    });

    test('rolls back when the second edit has the wrong type', () {
      expect(
        () => save.applyEdits(<ProgressEdit>[
          const ProgressSetInt(key: _lifeKey, value: 25),
          const ProgressSetBool(key: _lifeKey, value: 1),
        ]),
        throwsArgumentError,
      );
      expect(save.encode(), before);
    });

    test('an edit cannot change another record value or any key', () {
      final life = save.recordByHash(_lifeKey)!;
      final after = save.setInt(_lifeKey, 77);
      final reread = _ok(after.encode());

      expect(reread.records.length, save.records.length);
      for (var i = 0; i < save.records.length; i++) {
        final original = save.records[i];
        final updated = reread.records[i];
        expect(updated.key, original.key);
        expect(updated.type, original.type);
        expect(updated.valueOffset, original.valueOffset);
        if (original.index != life.index) {
          expect(updated.rawValue, original.rawValue);
          expect(updated.dataOffset, original.dataOffset);
          expect(updated.dataLength, original.dataLength);
        }
      }
      expect(
        <int>[for (final sentinel in reread.sentinels) sentinel.rawValue],
        <int>[for (final sentinel in save.sentinels) sentinel.rawValue],
      );
      expect(reread.footer, save.footer);
    });
  });

  group('lookups and names', () {
    late ProgressSave save;

    setUp(() {
      save = _ok(buildSyntheticProgress());
    });

    test(
      'fieldsByHash returns the field records, not sentinels or the footer',
      () {
        expect(
          save.fieldsByHash[_lifeKey]!.single,
          same(save.recordByHash(_lifeKey)),
        );
        expect(save.fieldsByHash.containsKey(0), isFalse);
        expect(
          save.fieldsByHash.containsKey(ProgressLayout.footerKey),
          isFalse,
        );
        expect(save.recordsByHash(0xDEADBEEF), isEmpty);
        expect(save.recordByHash(0xDEADBEEF), isNull);
      },
    );

    test('search matches names, hex and decimal key forms', () {
      expect(<int>[
        for (final record in save.search('Life')) record.key,
      ], containsAll(<int>[_lifeKey, _maxLifeKey]));
      expect(save.search('PlayerStatus').length, 3);
      expect(save.search('0x31ab5580').single.key, _lifeKey);
      expect(save.search('31AB5580').single.key, _lifeKey);
      expect(save.search('CurrentRupee').single.key, _rupeeKey);
      expect(save.search('nothing'), isEmpty);
      expect(save.search(''), isEmpty);
    });

    test(
      'nameFor returns verified names, then null, unless names are injected',
      () {
        expect(save.nameFor(_lifeKey), 'PlayerStatus.Life');
        expect(save.nameFor(_bancKey), 'Sequence_CurrentBanc');
        expect(save.nameFor(0x01010101), isNull);

        final named = save.withNames(<int, String>{
          0x01010101: 'Synthetic Bool',
          _lifeKey: 'HP',
        });
        expect(named.nameFor(0x01010101), 'Synthetic Bool');
        expect(named.nameFor(_lifeKey), 'HP');
        expect(named.nameFor(_maxLifeKey), 'PlayerStatus.MaxLife');
        expect(named.search('Synthetic').single.key, 0x01010101);
        expect(named.search('HP').single.key, _lifeKey);

        expect(save.nameFor(_lifeKey), 'PlayerStatus.Life');
      },
    );

    test('decode accepts an injected name map without touching bytes', () {
      final bytes = buildSyntheticProgress();
      final result = ProgressCodec.decode(
        bytes,
        names: <int, String>{0x01010101: 'Injected'},
      );
      expect(result, isA<ProgressDecodeOk>());
      final named = (result as ProgressDecodeOk).save;
      expect(named.nameFor(0x01010101), 'Injected');
      expect(named.encode(), bytes);
    });
  });
}

ProgressSave _ok(Uint8List bytes) {
  final result = ProgressCodec.decode(bytes);
  expect(result, isA<ProgressDecodeOk>(), reason: '$result');
  return (result as ProgressDecodeOk).save;
}

ProgressDecodeCorrupt _corrupt(Uint8List bytes) {
  final result = ProgressCodec.decode(bytes);
  expect(result, isA<ProgressDecodeCorrupt>(), reason: '$result');
  return result as ProgressDecodeCorrupt;
}

void _expectOnlyRecordChanged(
  ProgressSave before,
  ProgressSave after,
  ProgressRecord changed,
) {
  expect(after.fieldCount, before.fieldCount);
  for (var i = 0; i < before.records.length; i++) {
    final original = before.records[i];
    final updated = after.records[i];
    expect(updated.key, original.key);
    expect(updated.type, original.type);
    expect(updated.valueOffset, original.valueOffset);
    if (original.index != changed.index) {
      expect(updated.rawValue, original.rawValue);
      expect(updated.dataOffset, original.dataOffset);
      expect(updated.dataLength, original.dataLength);
    }
  }
}

Uint8List _copy(Uint8List bytes) => Uint8List.fromList(bytes);

void _fill(Uint8List bytes, int offset, int length, int value) {
  bytes.fillRange(offset, offset + length, value);
}

void _putU32(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
  bytes[offset + 3] = (value >> 24) & 0xff;
}

int _u32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);
