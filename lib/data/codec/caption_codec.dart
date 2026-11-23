import 'dart:typed_data';

import '../../domain/save/caption_layout.dart';
import '../../domain/save/models/caption_save.dart';
import 'byte_reader.dart';

/// The result of decoding a `caption.sav`.
sealed class CaptionDecodeResult {
  const CaptionDecodeResult();
}

/// The bytes are a layout this codec understands.
final class CaptionDecodeOk extends CaptionDecodeResult {
  const CaptionDecodeOk(this.save);

  final CaptionSave save;

  @override
  String toString() => 'CaptionDecodeOk($save)';
}

/// The magic is not `04 03 02 01`, so this is not a `caption.sav` layout this
/// codec understands.
final class CaptionDecodeUnsupported extends CaptionDecodeResult {
  const CaptionDecodeUnsupported({required this.magic, required this.message});

  /// The first four bytes read as a little-endian integer.
  final int magic;

  /// Why the file is unsupported.
  final String message;

  /// [magic] as `0x` plus eight lower-case hex digits.
  String get magicHex => '0x${magic.toRadixString(16).padLeft(8, '0')}';

  @override
  String toString() =>
      'CaptionDecodeUnsupported(magic: $magicHex, message: $message)';
}

/// The magic matched but a structural rule did not.
final class CaptionDecodeCorrupt extends CaptionDecodeResult {
  const CaptionDecodeCorrupt(this.reason, {this.offset});

  /// What is wrong.
  final String reason;

  /// The field or byte the failure was detected at, when known.
  final int? offset;

  @override
  String toString() => 'CaptionDecodeCorrupt(offset: $offset, reason: $reason)';
}

/// The buffer ends before the fixed part of the layout can be read.
final class CaptionDecodeTruncated extends CaptionDecodeResult {
  const CaptionDecodeTruncated({
    required this.length,
    required this.minimumLength,
    required this.reason,
  });

  /// The buffer's actual length.
  final int length;

  /// The shortest length this codec can read.
  final int minimumLength;

  /// Why the buffer was rejected as short.
  final String reason;

  @override
  String toString() =>
      'CaptionDecodeTruncated(length: $length, '
      'minimumLength: $minimumLength, reason: $reason)';
}

/// Decodes and encodes the verified `caption.sav` layout.
///
/// Decoding never throws for user data: wrong magic is
/// [CaptionDecodeUnsupported], a structural violation (including a JPEG length
/// that does not fit the buffer) is [CaptionDecodeCorrupt], and a buffer too
/// short for the fixed layout is [CaptionDecodeTruncated].
///
/// Encoding starts from the save's original bytes and patches only the fields
/// whose values differ. An unedited decode therefore re-encodes identically.
abstract final class CaptionCodec {
  /// Parses [bytes].
  static CaptionDecodeResult decode(Uint8List bytes) {
    if (bytes.length < CaptionLayout.minimumFileLength) {
      return CaptionDecodeTruncated(
        length: bytes.length,
        minimumLength: CaptionLayout.minimumFileLength,
        reason:
            'a caption.sav needs at least '
            '${CaptionLayout.minimumFileLength} bytes for the header, '
            'the JPEG length and a FF D8 FF D9 JPEG',
      );
    }

    final reader = ByteReader(bytes, label: 'caption.sav');
    if (!CaptionSave.hasMagic(bytes)) {
      return CaptionDecodeUnsupported(
        magic: reader.u32le(CaptionLayout.magicOffset),
        message: 'expected 04 03 02 01',
      );
    }

    try {
      final layoutCheck = reader.u32le(CaptionLayout.layoutCheckOffset);
      if (layoutCheck != CaptionLayout.layoutCheckValue) {
        throw _CaptionCorrupt(
          'the marker at ${CaptionLayout.layoutCheckOffset} is $layoutCheck, '
          'not ${CaptionLayout.layoutCheckValue}',
          offset: CaptionLayout.layoutCheckOffset,
        );
      }

      final jpegLength = reader.u32le(CaptionLayout.jpegLengthOffset);
      final available = bytes.length - CaptionLayout.jpegOffset;
      if (jpegLength > available) {
        throw const _CaptionCorrupt(
          'the JPEG length at ${CaptionLayout.jpegLengthOffset} points past '
          'the end of the buffer',
          offset: CaptionLayout.jpegLengthOffset,
        );
      }
      if (jpegLength < CaptionLayout.minimumJpegLength) {
        throw _CaptionCorrupt(
          'the JPEG length at ${CaptionLayout.jpegLengthOffset} is '
          '$jpegLength, shorter than FF D8 FF D9',
          offset: CaptionLayout.jpegLengthOffset,
        );
      }
      if (CaptionLayout.jpegOffset + jpegLength != bytes.length) {
        throw _CaptionCorrupt(
          'the JPEG length at ${CaptionLayout.jpegLengthOffset} '
          '($jpegLength) does not reach the end of the buffer '
          '($available bytes after ${CaptionLayout.jpegOffset})',
          offset: CaptionLayout.jpegLengthOffset,
        );
      }

      final jpeg = reader.copyRange(CaptionLayout.jpegOffset, jpegLength);
      if (!CaptionSave.hasJpegMarkers(jpeg)) {
        throw const _CaptionCorrupt(
          'the bytes at ${CaptionLayout.jpegOffset} are not a JPEG '
          '(expected FF D8 at the start and FF D9 at the end)',
          offset: CaptionLayout.jpegOffset,
        );
      }

      final sceneName = _readName(
        reader,
        CaptionLayout.sceneNameOffset,
        'sceneName',
      );
      final mapPath = _readName(reader, CaptionLayout.mapPathOffset, 'mapPath');
      final entries = _findDateEntries(reader);
      final savedAt = CaptionSavedAt(
        year: reader.u32le(entries[CaptionDateField.year]! + 4),
        month: reader.u32le(entries[CaptionDateField.month]! + 4),
        day: reader.u32le(entries[CaptionDateField.day]! + 4),
        hour: reader.u32le(entries[CaptionDateField.hour]! + 4),
        minute: reader.u32le(entries[CaptionDateField.minute]! + 4),
        second: reader.u32le(entries[CaptionDateField.second]! + 4),
      );

      return CaptionDecodeOk(
        CaptionSave(
          originalBytes: bytes,
          sceneName: sceneName,
          mapPath: mapPath,
          jpegBytes: jpeg,
          savedAt: savedAt,
        ),
      );
    } on _CaptionCorrupt catch (error) {
      return CaptionDecodeCorrupt(error.reason, offset: error.offset);
    } on ByteReaderRangeError catch (error) {
      return CaptionDecodeCorrupt('short read: $error');
    } on ArgumentError catch (error) {
      return CaptionDecodeCorrupt(
        'the parsed values were rejected: ${error.message}',
      );
    }
  }

  /// Serialises [save].
  ///
  /// The returned bytes are [CaptionSave.originalBytes] with only the edited
  /// fields patched: the scene span, the map-path span, the six date values,
  /// and the JPEG length plus JPEG when the picture changed. Everything else,
  /// including stale bytes after a name's NUL, stays as it was.
  static Uint8List encode(CaptionSave save) {
    final source = save.originalBytes;
    if (source.length < CaptionLayout.minimumFileLength) {
      throw ArgumentError.value(
        source.length,
        'originalBytes',
        'shorter than ${CaptionLayout.minimumFileLength} bytes',
      );
    }
    if (!CaptionSave.hasMagic(source)) {
      throw ArgumentError.value(
        source,
        'originalBytes',
        'does not start with 04 03 02 01',
      );
    }

    final jpeg = save.jpegBytes;
    if (!CaptionSave.hasJpegMarkers(jpeg)) {
      throw ArgumentError.value(
        jpeg,
        'jpegBytes',
        'is not a JPEG: expected FF D8 at the start and FF D9 at the end',
      );
    }

    final out = Uint8List.fromList(source);
    _patchName(out, CaptionLayout.sceneNameOffset, save.sceneName, 'sceneName');
    _patchName(out, CaptionLayout.mapPathOffset, save.mapPath, 'mapPath');

    final Map<CaptionDateField, int> entries;
    try {
      entries = _findDateEntries(ByteReader(out, label: 'caption.sav'));
    } on _CaptionCorrupt catch (error) {
      throw StateError('the original header cannot be edited: ${error.reason}');
    }
    for (final descriptor in CaptionLayout.dateFields) {
      final value = save.savedAt.valueOf(descriptor.field);
      if (value < 0 || value > 0xffffffff) {
        throw ArgumentError.value(
          value,
          descriptor.field.name,
          'does not fit in 32 bits',
        );
      }
      final at = entries[descriptor.field]! + 4;
      if (_readU32le(out, at) != value) {
        _writeU32le(out, at, value);
      }
    }

    final storedLength = _readU32le(out, CaptionLayout.jpegLengthOffset);
    final available = out.length - CaptionLayout.jpegOffset;
    if (storedLength != available) {
      throw ArgumentError(
        'originalBytes: the JPEG length at ${CaptionLayout.jpegLengthOffset} '
        'is $storedLength but $available bytes follow '
        '${CaptionLayout.jpegOffset}',
      );
    }

    final storedJpeg = Uint8List.sublistView(out, CaptionLayout.jpegOffset);
    if (storedLength != jpeg.length || !_bytesEqual(storedJpeg, jpeg)) {
      if (storedLength == jpeg.length) {
        out.setRange(
          CaptionLayout.jpegOffset,
          CaptionLayout.jpegOffset + jpeg.length,
          jpeg,
        );
      } else {
        final rebuilt = Uint8List(CaptionLayout.jpegOffset + jpeg.length);
        rebuilt.setRange(0, CaptionLayout.jpegOffset, out);
        _writeU32le(rebuilt, CaptionLayout.jpegLengthOffset, jpeg.length);
        rebuilt.setRange(CaptionLayout.jpegOffset, rebuilt.length, jpeg);
        return rebuilt;
      }
    }
    return out;
  }

  /// Reads a 64-byte printable-ASCII span, stopping at the first NUL.
  ///
  /// Bytes after the first NUL are not part of the value and are not validated:
  /// the market sample proves they can be stale.
  static String _readName(ByteReader reader, int offset, String field) {
    var end = CaptionLayout.nameLength;
    for (var i = 0; i < CaptionLayout.nameLength; i++) {
      if (reader.u8(offset + i) == 0) {
        end = i;
        break;
      }
    }
    for (var i = 0; i < end; i++) {
      final byte = reader.u8(offset + i);
      if (byte < 0x20 || byte > 0x7e) {
        throw _CaptionCorrupt(
          '$field has a non-printable byte '
          '(0x${byte.toRadixString(16).padLeft(2, '0')}) at ${offset + i}',
          offset: offset + i,
        );
      }
    }
    return String.fromCharCodes(reader.bytes, offset, offset + end);
  }

  /// Finds the six date entries by key, requiring one each on one 8-byte grid.
  static Map<CaptionDateField, int> _findDateEntries(ByteReader reader) {
    final found = <CaptionDateField, int>{};
    for (final descriptor in CaptionLayout.dateFields) {
      int? at;
      for (var offset = 0; offset + 4 <= CaptionLayout.headerLength; offset++) {
        if (reader.u32le(offset) == descriptor.key) {
          if (at != null) {
            throw _CaptionCorrupt(
              'the ${descriptor.field.name} key ${descriptor.keyHex} occurs '
              'more than once in the header',
              offset: offset,
            );
          }
          at = offset;
        }
      }
      if (at == null) {
        throw _CaptionCorrupt(
          'the ${descriptor.field.name} key ${descriptor.keyHex} is not in '
          'the header',
        );
      }
      if (at + 8 > CaptionLayout.headerLength) {
        throw _CaptionCorrupt(
          'the ${descriptor.field.name} entry at $at is not whole',
          offset: at,
        );
      }
      found[descriptor.field] = at;
    }

    final grid = found.values.map((offset) => offset % 8).toSet();
    if (grid.length != 1) {
      throw const _CaptionCorrupt(
        'the six date entries are not on one 8-byte grid',
      );
    }
    return found;
  }

  /// Writes [value] into [out]'s name span only when the existing span does not
  /// already hold it.
  ///
  /// A match must include the NUL (when the value is shorter than 64 bytes).
  /// That is what preserves stale tail bytes in an unedited save: `Market\0ield`
  /// matches the value `Market` because byte 6 is NUL, and is left alone. A
  /// different value clears the whole span first, so no stale byte survives an
  /// edit.
  static void _patchName(
    Uint8List out,
    int offset,
    String value,
    String field,
  ) {
    final problem = CaptionSave.nameProblem(value);
    if (problem != null) {
      throw ArgumentError.value(value, field, problem);
    }
    final encoded = Uint8List(value.length);
    for (var i = 0; i < value.length; i++) {
      encoded[i] = value.codeUnitAt(i);
    }
    if (_nameMatches(out, offset, encoded)) {
      return;
    }
    out.fillRange(offset, offset + CaptionLayout.nameLength, 0);
    out.setRange(offset, offset + encoded.length, encoded);
  }

  static bool _nameMatches(Uint8List out, int offset, Uint8List encoded) {
    for (var i = 0; i < encoded.length; i++) {
      if (out[offset + i] != encoded[i]) {
        return false;
      }
    }
    return encoded.length == CaptionLayout.nameLength ||
        out[offset + encoded.length] == 0;
  }

  static int _readU32le(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  static void _writeU32le(Uint8List bytes, int offset, int value) {
    bytes[offset] = value & 0xff;
    bytes[offset + 1] = (value >> 8) & 0xff;
    bytes[offset + 2] = (value >> 16) & 0xff;
    bytes[offset + 3] = (value >> 24) & 0xff;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// Internal structural failure, turned into [CaptionDecodeCorrupt] at the API.
final class _CaptionCorrupt implements Exception {
  const _CaptionCorrupt(this.reason, {this.offset});

  final String reason;
  final int? offset;

  @override
  String toString() => '_CaptionCorrupt($reason)';
}
