import 'dart:typed_data';

import '../../domain/save/models/progress_save.dart';
import '../../domain/save/progress_layout.dart';
import '../../domain/save/progress_record.dart';
import 'byte_reader.dart';

/// The result of decoding a `progress.sav`.
sealed class ProgressDecodeResult {
  const ProgressDecodeResult();
}

/// The bytes are a layout this codec understands.
final class ProgressDecodeOk extends ProgressDecodeResult {
  const ProgressDecodeOk(this.save);

  final ProgressSave save;

  @override
  String toString() => 'ProgressDecodeOk($save)';
}

/// A well-formed container this codec does not support.
sealed class ProgressDecodeUnsupported extends ProgressDecodeResult {
  const ProgressDecodeUnsupported();

  /// Why the file is unsupported.
  String get message;
}

/// The magic is not the `04 03 02 01` of a `progress.sav`.
final class ProgressBadMagic extends ProgressDecodeUnsupported {
  const ProgressBadMagic({required this.magic});

  /// The first four bytes read as a little-endian integer.
  final int magic;

  /// [magic] as `0x` plus eight lower-case hex digits.
  String get magicHex => ProgressLayout.keyHex(magic);

  @override
  String get message => 'expected the magic 04 03 02 01';

  @override
  String toString() => 'ProgressBadMagic(magic: $magicHex)';
}

/// The magic is right but the schema revision is not [ProgressLayout.revision].
final class ProgressRevisionMismatch extends ProgressDecodeUnsupported {
  const ProgressRevisionMismatch({
    required this.revision,
    required this.expected,
  });

  /// The revision stored at [ProgressLayout.revisionOffset].
  final int revision;

  /// [ProgressLayout.revision].
  final int expected;

  @override
  String get message =>
      'expected revision $expected; the file stores $revision';

  @override
  String toString() =>
      'ProgressRevisionMismatch(revision: $revision, expected: $expected)';
}

/// The magic matched but a structural rule did not.
final class ProgressDecodeCorrupt extends ProgressDecodeResult {
  const ProgressDecodeCorrupt(this.reason, {required this.offset});

  /// What is wrong.
  final String reason;

  /// The exact byte offset the failure was detected at.
  final int offset;

  /// [offset] as `0x` plus eight lower-case hex digits.
  String get offsetHex => ProgressLayout.keyHex(offset);

  @override
  String toString() =>
      'ProgressDecodeCorrupt(offset: $offsetHex, reason: $reason)';
}

/// The buffer ends before a complete layout can be read.
final class ProgressDecodeTruncated extends ProgressDecodeResult {
  const ProgressDecodeTruncated({
    required this.length,
    required this.minimumLength,
    required this.reason,
  });

  /// The buffer's actual length.
  final int length;

  /// The shortest length needed for the requested read.
  final int minimumLength;

  /// Why the buffer was rejected as short.
  final String reason;

  @override
  String toString() =>
      'ProgressDecodeTruncated(length: $length, '
      'minimumLength: $minimumLength, reason: $reason)';
}

/// Decodes and encodes the verified `progress.sav` container.
///
/// Decoding never throws for user data: a wrong magic or revision is
/// [ProgressDecodeUnsupported], a malformed container is
/// [ProgressDecodeCorrupt] with the exact offset, and a short buffer is
/// [ProgressDecodeTruncated].
///
/// Encoding starts from the save's current buffer. Edits patch only their own
/// spans, and an unedited decode re-encodes byte-for-byte.
abstract final class ProgressCodec {
  /// Parses [bytes].
  ///
  /// [names] is an optional display-name map; it never affects the bytes.
  static ProgressDecodeResult decode(
    Uint8List bytes, {
    Map<int, String> names = const <int, String>{},
  }) {
    if (bytes.length < ProgressLayout.valueWordSize) {
      return ProgressDecodeTruncated(
        length: bytes.length,
        minimumLength: ProgressLayout.valueWordSize,
        reason: 'a progress.sav needs at least 4 bytes for the magic',
      );
    }

    final magic = _readU32(bytes, ProgressLayout.magicOffset);
    if (magic != ProgressLayout.magicValue) {
      return ProgressBadMagic(magic: magic);
    }

    if (bytes.length < ProgressLayout.revisionOffset + 4) {
      return ProgressDecodeTruncated(
        length: bytes.length,
        minimumLength: ProgressLayout.revisionOffset + 4,
        reason: 'the magic is present but the revision is not',
      );
    }
    final revision = _readU32(bytes, ProgressLayout.revisionOffset);
    if (revision != ProgressLayout.revision) {
      return ProgressRevisionMismatch(
        revision: revision,
        expected: ProgressLayout.revision,
      );
    }

    if (bytes.length < ProgressLayout.dataOffsetFieldOffset + 4) {
      return ProgressDecodeTruncated(
        length: bytes.length,
        minimumLength: ProgressLayout.dataOffsetFieldOffset + 4,
        reason: 'the revision is present but the data offset is not',
      );
    }
    final dataOffset = _readU32(bytes, ProgressLayout.dataOffsetFieldOffset);
    if (dataOffset < ProgressLayout.recordStart ||
        (dataOffset - ProgressLayout.recordStart) % ProgressLayout.recordSize !=
            0) {
      return ProgressDecodeCorrupt(
        'the data offset $dataOffset is not 0x28 + 8*N',
        offset: ProgressLayout.dataOffsetFieldOffset,
      );
    }
    if (dataOffset > bytes.length) {
      return ProgressDecodeTruncated(
        length: bytes.length,
        minimumLength: dataOffset,
        reason:
            'the data offset $dataOffset points past the end of the '
            '${bytes.length}-byte buffer',
      );
    }

    final recordCount =
        (dataOffset - ProgressLayout.recordStart) ~/ ProgressLayout.recordSize;
    if (recordCount < ProgressLayout.minimumRecordCount) {
      return ProgressDecodeCorrupt(
        'the data offset $dataOffset leaves $recordCount record(s); '
        'at least ${ProgressLayout.minimumRecordCount} are needed for '
        '32 sentinels and the footer',
        offset: ProgressLayout.dataOffsetFieldOffset,
      );
    }

    for (var i = 0; i < ProgressLayout.reservedLength; i++) {
      final offset = ProgressLayout.reservedOffset + i;
      if (bytes[offset] != 0) {
        return ProgressDecodeCorrupt(
          'the reserved byte at 0x${offset.toRadixString(16)} is '
          '0x${bytes[offset].toRadixString(16)}; expected zero',
          offset: offset,
        );
      }
    }

    final source = Uint8List.fromList(bytes);
    try {
      return _parse(source, dataOffset, recordCount, names);
    } on _ProgressCorrupt catch (error) {
      return ProgressDecodeCorrupt(error.reason, offset: error.offset);
    } on ByteReaderRangeError catch (error) {
      return ProgressDecodeCorrupt('short read: $error', offset: error.offset);
    } on ArgumentError catch (error) {
      return ProgressDecodeCorrupt(
        'the parsed values were rejected: ${error.message}',
        offset: 0,
      );
    } on FormatException catch (error) {
      return ProgressDecodeCorrupt(
        'the parsed values were rejected: ${error.message}',
        offset: 0,
      );
    } on Object catch (error) {
      // The codec's contract is "never throw for user data". Any unexpected
      // failure still becomes a typed result so a caller cannot crash on a
      // crafted file.
      return ProgressDecodeCorrupt(
        'unexpected parse failure: $error',
        offset: 0,
      );
    }
  }

  /// Serialises [save]. With no edits this is the decoded buffer verbatim.
  static Uint8List encode(ProgressSave save) => save.encode();

  static ProgressDecodeResult _parse(
    Uint8List source,
    int dataOffset,
    int recordCount,
    Map<int, String> names,
  ) {
    final reader = ByteReader(source, label: 'progress.sav');
    final fields = <ProgressRecord>[];
    final sentinels = <ProgressRecord>[];
    ProgressFooter? footer;
    var expectedTypeId = 1;

    for (var i = 0; i < recordCount; i++) {
      final recordOffset =
          ProgressLayout.recordStart + i * ProgressLayout.recordSize;
      final key = reader.u32le(recordOffset);
      final value = reader.u32le(recordOffset + 4);

      if (i == recordCount - 1) {
        if (key != ProgressLayout.footerKey) {
          throw _ProgressCorrupt(
            'the last record at 0x${_hex(recordOffset)} has key '
            '${_hex(key)}; expected the footer ${_hex(ProgressLayout.footerKey)}',
            offset: recordOffset,
          );
        }
        footer = ProgressFooter(
          key: key,
          rawValue: value,
          index: i,
          valueOffset: recordOffset + 4,
        );
        continue;
      }

      if (key == 0) {
        if (sentinels.length >= ProgressLayout.sentinelCount) {
          throw _ProgressCorrupt(
            'more than ${ProgressLayout.sentinelCount} sentinels before the '
            'footer',
            offset: recordOffset,
          );
        }
        if (value != expectedTypeId) {
          throw _ProgressCorrupt(
            'the sentinel at 0x${_hex(recordOffset)} carries type $value; '
            'expected $expectedTypeId',
            offset: recordOffset + 4,
          );
        }
        final type = SaveType.forTypeId(value);
        if (type == null) {
          throw _ProgressCorrupt(
            'the sentinel at 0x${_hex(recordOffset)} carries unknown type '
            '$value',
            offset: recordOffset + 4,
          );
        }
        sentinels.add(
          ProgressRecord(
            bytes: source,
            key: 0,
            rawValue: value,
            index: i,
            type: type,
            valueOffset: recordOffset + 4,
            dataOffset: null,
            dataLength: ProgressLayout.valueWordSize,
            isSentinel: true,
          ),
        );
        expectedTypeId++;
        continue;
      }

      if (expectedTypeId > ProgressLayout.sentinelCount) {
        throw _ProgressCorrupt(
          'the field ${_hex(key)} at 0x${_hex(recordOffset)} follows the '
          'last sentinel',
          offset: recordOffset,
        );
      }
      final type = SaveType.forTypeId(expectedTypeId)!;
      if (!type.isKnown) {
        throw _ProgressCorrupt(
          'the field ${_hex(key)} at 0x${_hex(recordOffset)} lies in reserved '
          'section ${type.typeId}, whose layout is unverified',
          offset: recordOffset,
        );
      }

      final inline = type.isInline;
      if (inline && type == SaveType.boolValue && value > 1) {
        throw _ProgressCorrupt(
          'the Bool field ${_hex(key)} stores $value; expected 0 or 1',
          offset: recordOffset + 4,
        );
      }
      fields.add(
        ProgressRecord(
          bytes: source,
          key: key,
          rawValue: value,
          index: i,
          type: type,
          valueOffset: recordOffset + 4,
          dataOffset: inline ? null : value,
          dataLength: inline ? ProgressLayout.valueWordSize : 0,
        ),
      );
    }

    final verifiedFooter = footer;
    if (verifiedFooter == null) {
      throw _ProgressCorrupt(
        'the footer is missing',
        offset: dataOffset - ProgressLayout.recordSize,
      );
    }
    if (expectedTypeId != ProgressLayout.sentinelCount + 1) {
      throw _ProgressCorrupt(
        'the record stream ends after ${sentinels.length} sentinel(s); '
        'expected ${ProgressLayout.sentinelCount}',
        offset: verifiedFooter.recordOffset,
      );
    }

    final targets = <int>{};
    for (final record in fields) {
      if (!record.type.isTail) {
        continue;
      }
      final target = record.dataOffset!;
      if (target < dataOffset || target >= source.length) {
        throw _ProgressCorrupt(
          'the pointer for ${record.keyHex} (${record.type.label}) is '
          '0x${_hex(target)}; it must lie in '
          '[0x${_hex(dataOffset)}, 0x${_hex(source.length)})',
          offset: record.valueOffset,
        );
      }
      targets.add(target);
    }
    final sortedTargets = targets.toList()..sort();
    final nextTarget = <int, int>{};
    for (var i = 0; i < sortedTargets.length; i++) {
      nextTarget[sortedTargets[i]] = i + 1 < sortedTargets.length
          ? sortedTargets[i + 1]
          : source.length;
    }

    final resolved = <ProgressRecord>[];
    final intervals = <_TailInterval>[];
    for (final record in fields) {
      if (!record.type.isTail) {
        resolved.add(record);
        continue;
      }
      final target = record.dataOffset!;
      final length = _tailLength(
        reader,
        record,
        target,
        source.length,
        nextTarget[target]!,
      );
      final updated = ProgressRecord(
        bytes: source,
        key: record.key,
        rawValue: record.rawValue,
        index: record.index,
        type: record.type,
        valueOffset: record.valueOffset,
        dataOffset: target,
        dataLength: length,
      );
      resolved.add(updated);
      intervals.add(_TailInterval(target, target + length, updated));
    }

    intervals.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.record.index.compareTo(b.record.index);
    });
    for (var i = 1; i < intervals.length; i++) {
      if (intervals[i].start < intervals[i - 1].end) {
        throw _ProgressCorrupt(
          'the tail region for ${intervals[i].record.keyHex} at '
          '0x${_hex(intervals[i].start)} overlaps the region for '
          '${intervals[i - 1].record.keyHex} ending at '
          '0x${_hex(intervals[i - 1].end)}',
          offset: intervals[i].record.valueOffset,
        );
      }
    }

    return ProgressDecodeOk(
      ProgressSave.fromDecodedBytes(
        bytes: source,
        revision: ProgressLayout.revision,
        dataOffset: dataOffset,
        records: resolved,
        sentinels: sentinels,
        footer: verifiedFooter,
        names: names,
      ),
    );
  }

  static int _tailLength(
    ByteReader reader,
    ProgressRecord record,
    int target,
    int fileLength,
    int nextTarget,
  ) {
    switch (record.type.kind) {
      case SaveRecordKind.tailFixed:
        final length = record.type.fixedLength!;
        _requireFits(record, target, length, fileLength);
        if (record.type == SaveType.boolArray) {
          if (target + ProgressLayout.valueWordSize > fileLength) {
            throw _ProgressCorrupt(
              'the BoolArray ${record.keyHex} has no bit-count word at '
              '0x${_hex(target)}',
              offset: record.valueOffset,
            );
          }
          final bitCount = reader.u32le(target);
          if (bitCount > 32) {
            throw _ProgressCorrupt(
              'the BoolArray ${record.keyHex} has bitCount $bitCount; its '
              '32-bit bits word holds at most 32',
              offset: target,
            );
          }
        } else if (record.type == SaveType.string32 ||
            record.type == SaveType.string64) {
          _requireNul(reader, target, length, record, target);
        }
        return length;
      case SaveRecordKind.tailCounted:
        if (target + ProgressLayout.valueWordSize > fileLength) {
          throw _ProgressCorrupt(
            'the ${record.type.label} ${record.keyHex} has no count word at '
            '0x${_hex(target)}',
            offset: record.valueOffset,
          );
        }
        final count = reader.u32le(target);
        final elementSize = record.type.elementSize!;
        final available = fileLength - target - ProgressLayout.valueWordSize;
        if (count > available ~/ elementSize) {
          throw _ProgressCorrupt(
            'the ${record.type.label} ${record.keyHex} count $count needs '
            '${count * elementSize} byte(s) after 0x${_hex(target + 4)}; only '
            '$available remain',
            offset: target,
          );
        }
        final length = ProgressLayout.valueWordSize + count * elementSize;
        _requireFits(record, target, length, fileLength);
        if (record.type == SaveType.string64Array) {
          for (var i = 0; i < count; i++) {
            final elementStart =
                target + ProgressLayout.valueWordSize + i * elementSize;
            _requireNul(
              reader,
              elementStart,
              elementSize,
              record,
              elementStart,
            );
          }
        }
        return length;
      case SaveRecordKind.tailOpaque:
        final length = nextTarget - target;
        _requireFits(record, target, length, fileLength);
        return length;
      case SaveRecordKind.inlineScalar:
      case SaveRecordKind.unknown:
        throw StateError(
          '${record.type.label} at ${record.keyHex} is not a tail type',
        );
    }
  }

  static void _requireFits(
    ProgressRecord record,
    int target,
    int length,
    int fileLength,
  ) {
    if (target < 0 || length < 0 || target > fileLength - length) {
      throw _ProgressCorrupt(
        'the ${record.type.label} ${record.keyHex} needs $length byte(s) at '
        '0x${_hex(target)}; the file is 0x${_hex(fileLength)} byte(s) long',
        offset: record.valueOffset,
      );
    }
  }

  static void _requireNul(
    ByteReader reader,
    int start,
    int length,
    ProgressRecord record,
    int failureOffset,
  ) {
    for (var i = 0; i < length; i++) {
      if (reader.u8(start + i) == 0) {
        return;
      }
    }
    throw _ProgressCorrupt(
      'the ${record.type.label} ${record.keyHex} has no NUL in its '
      '$length-byte slot at 0x${_hex(start)}',
      offset: failureOffset,
    );
  }

  static int _readU32(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  static String _hex(int value) =>
      '0x${value.toRadixString(16).padLeft(8, '0')}';
}

/// A coalesced tail span used for the overlap check.
final class _TailInterval {
  const _TailInterval(this.start, this.end, this.record);

  final int start;
  final int end;
  final ProgressRecord record;
}

/// Internal structural failure, turned into [ProgressDecodeCorrupt] at the API.
final class _ProgressCorrupt implements Exception {
  const _ProgressCorrupt(this.reason, {required this.offset});

  final String reason;
  final int offset;

  @override
  String toString() => '_ProgressCorrupt($reason @ $offset)';
}
