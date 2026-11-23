import 'dart:typed_data';

import 'progress_layout.dart';

/// One **field** record, or one section sentinel, of a `progress.sav`.
///
/// A record is immutable. [rawValue] is the 32-bit little-endian word stored at
/// [valueOffset] and is kept verbatim so an untouched record can always be
/// written back. For inline types it *is* the value; for tail types it is the
/// absolute offset of the data ([dataOffset]).
///
/// The record keeps a reference to the buffer it was decoded from so the typed
/// accessors can read tail data. The buffer is owned by [ProgressSave] and is
/// never mutated in place; edits build a new record and a new buffer.
final class ProgressRecord {
  const ProgressRecord._({
    required this._bytes,
    required this.key,
    required this.rawValue,
    required this.index,
    required this.type,
    required this.valueOffset,
    required this.dataOffset,
    required this.dataLength,
    this.isSentinel = false,
  });

  /// Builds a record over [bytes].
  ///
  /// The buffer is not copied; it is owned by the enclosing save and is never
  /// mutated in place. A standalone record may carry a short buffer so callers
  /// can exercise the accessors' range checks.
  factory ProgressRecord({
    required Uint8List bytes,
    required int key,
    required int rawValue,
    required int index,
    required SaveType type,
    required int valueOffset,
    required int? dataOffset,
    required int dataLength,
    bool isSentinel = false,
  }) => ProgressRecord._(
    bytes: bytes,
    key: key,
    rawValue: rawValue,
    index: index,
    type: type,
    valueOffset: valueOffset,
    dataOffset: dataOffset,
    dataLength: dataLength,
    isSentinel: isSentinel,
  );

  final Uint8List _bytes;

  /// The field's 32-bit hash, or 0 for a sentinel.
  final int key;

  /// The value word, exactly as stored at [valueOffset].
  final int rawValue;

  /// Zero-based index in the record stream (sentinels and footer included).
  final int index;

  /// The typed section this record belongs to.
  final SaveType type;

  /// Absolute offset of the record's 4-byte value word.
  final int valueOffset;

  /// Absolute offset of tail data, or `null` for an inline scalar.
  final int? dataOffset;

  /// Length of the data in bytes.
  ///
  /// For an inline scalar this is [ProgressLayout.valueWordSize] (the value
  /// word itself). For a tail record it is the span at [dataOffset]; opaque
  /// types use the distance to the next tail pointer (or EOF).
  final int dataLength;

  /// Whether this is a section sentinel rather than a field.
  final bool isSentinel;

  /// Absolute offset of the record's 8-byte entry.
  int get recordOffset =>
      ProgressLayout.recordStart + index * ProgressLayout.recordSize;

  /// [key] as `0x` plus eight lower-case hex digits.
  String get keyHex => ProgressLayout.keyHex(key);

  /// The signed 32-bit value of an `Int` record.
  int asInt() {
    _requireType(SaveType.intValue, 'asInt');
    return _readU32(valueOffset).toSigned(32);
  }

  /// The unsigned 32-bit value of a `UInt` record.
  int asUInt() {
    _requireType(SaveType.uintValue, 'asUInt');
    return _readU32(valueOffset);
  }

  /// The binary32 value of a `Float` record.
  double asFloat() {
    _requireType(SaveType.floatValue, 'asFloat');
    return _readF32(valueOffset);
  }

  /// The boolean value of a `Bool` record.
  ///
  /// Only 0 and 1 are accepted; the codec rejects any other stored value.
  bool asBool() {
    _requireType(SaveType.boolValue, 'asBool');
    return switch (_readU32(valueOffset)) {
      0 => false,
      1 => true,
      final value => throw FormatException(
        'record $keyHex stores $value in a Bool field; expected 0 or 1',
      ),
    };
  }

  /// The 32-bit hash of an `Enum` record.
  int asEnumHash() {
    _requireType(SaveType.enumValue, 'asEnumHash');
    return _readU32(valueOffset);
  }

  /// The printable-ASCII value of a `String32` or `String64` record.
  ///
  /// Bytes after the first NUL are not part of the value.
  String asString() {
    _requireAnyType(<SaveType>[
      SaveType.string32,
      SaveType.string64,
    ], 'asString');
    final start = _tailStart(dataLength);
    final end = _firstNul(start, dataLength);
    if (end == null) {
      throw FormatException(
        'record $keyHex has no NUL in its $dataLength-byte string slot',
      );
    }
    return String.fromCharCodes(_bytes, start, start + end);
  }

  /// The three binary32 components of a `Vector3` record.
  ProgressVector3 asVector3() {
    _requireType(SaveType.vector3, 'asVector3');
    final start = _tailStart(12);
    return ProgressVector3(
      _readF32(start),
      _readF32(start + 4),
      _readF32(start + 8),
    );
  }

  /// The signed 64-bit value of an `Int64` record.
  int asInt64() {
    _requireType(SaveType.int64, 'asInt64');
    final start = _tailStart(8);
    return _readU64(start).toSigned(64);
  }

  /// The 64-bit value of a `UInt64` record.
  ///
  /// Dart's native `int` is signed 64-bit, so values with bit 63 set come back
  /// negative. The raw bytes are still exact; use [copyDataBytes] when the
  /// unsigned bit pattern matters.
  int asUInt64() {
    _requireType(SaveType.uint64, 'asUInt64');
    final start = _tailStart(8);
    return _readU64(start);
  }

  /// A copy of this record's data bytes.
  ///
  /// Used for opaque `Binary`, `BinaryArray` and `WString16Array` ranges. For an
  /// inline scalar this is the 4-byte value word.
  Uint8List copyDataBytes() {
    if (isSentinel) {
      throw FormatException('record $keyHex is a sentinel, not a field');
    }
    if (dataOffset case final start?) {
      _requireRange(start, dataLength);
      return Uint8List.fromList(_bytes.sublist(start, start + dataLength));
    }
    _requireRange(valueOffset, ProgressLayout.valueWordSize);
    return Uint8List.fromList(
      _bytes.sublist(valueOffset, valueOffset + ProgressLayout.valueWordSize),
    );
  }

  void _requireType(SaveType expected, String accessor) {
    if (isSentinel) {
      throw FormatException('$accessor cannot read sentinel record $keyHex');
    }
    if (type != expected) {
      throw FormatException(
        '$accessor needs a ${expected.label} record; '
        'record $keyHex is ${type.label}',
      );
    }
  }

  void _requireAnyType(List<SaveType> allowed, String accessor) {
    if (isSentinel) {
      throw FormatException('$accessor cannot read sentinel record $keyHex');
    }
    if (!allowed.contains(type)) {
      final names = allowed.map((type) => type.label).join(' or ');
      throw FormatException(
        '$accessor needs a $names record; '
        'record $keyHex is ${type.label}',
      );
    }
  }

  int _tailStart(int minimumLength) {
    if (isSentinel) {
      throw FormatException('record $keyHex is a sentinel, not a field');
    }
    final start = dataOffset;
    if (start == null) {
      throw FormatException('record $keyHex has no tail data');
    }
    if (dataLength < minimumLength) {
      throw FormatException(
        'record $keyHex declares $dataLength byte(s); '
        '$minimumLength are needed',
      );
    }
    _requireRange(start, minimumLength);
    return start;
  }

  int? _firstNul(int start, int length) {
    for (var i = 0; i < length; i++) {
      if (_bytes[start + i] == 0) {
        return i;
      }
    }
    return null;
  }

  void _requireRange(int offset, int size) {
    if (size < 0 || offset < 0 || offset > _bytes.length - size) {
      throw RangeError(
        'record $keyHex needs $size byte(s) at $offset; '
        'the buffer is ${_bytes.length} byte(s) long',
      );
    }
  }

  int _readU32(int offset) {
    _requireRange(offset, 4);
    return _bytes[offset] |
        (_bytes[offset + 1] << 8) |
        (_bytes[offset + 2] << 16) |
        (_bytes[offset + 3] << 24);
  }

  int _readU64(int offset) {
    _requireRange(offset, 8);
    var value = 0;
    for (var i = 7; i >= 0; i--) {
      value = (value << 8) | _bytes[offset + i];
    }
    return value;
  }

  double _readF32(int offset) {
    _requireRange(offset, 4);
    return ByteData.sublistView(
      _bytes,
      offset,
      offset + 4,
    ).getFloat32(0, Endian.little);
  }

  @override
  bool operator ==(Object other) =>
      other is ProgressRecord &&
      other.key == key &&
      other.rawValue == rawValue &&
      other.index == index &&
      other.type == type &&
      other.valueOffset == valueOffset &&
      other.dataOffset == dataOffset &&
      other.dataLength == dataLength &&
      other.isSentinel == isSentinel;

  @override
  int get hashCode => Object.hash(
    key,
    rawValue,
    index,
    type,
    valueOffset,
    dataOffset,
    dataLength,
    isSentinel,
  );

  @override
  String toString() =>
      'ProgressRecord($keyHex, ${type.label}, index: $index, '
      'raw: 0x${rawValue.toRadixString(16)}, data: $dataOffset, '
      'length: $dataLength${isSentinel ? ', sentinel' : ''})';
}

/// A three-component vector stored as three little-endian binary32 values.
final class ProgressVector3 {
  const ProgressVector3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  @override
  bool operator ==(Object other) =>
      other is ProgressVector3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'ProgressVector3($x, $y, $z)';
}

/// The opaque footer record immediately before the tail.
///
/// Its key and value are preserved verbatim. No meaning is assigned to
/// [rawValue]; the samples happen to carry `0x1D6F4`, which is the file length
/// minus eight, but that relationship is not relied on.
final class ProgressFooter {
  const ProgressFooter({
    required this.key,
    required this.rawValue,
    required this.index,
    required this.valueOffset,
  });

  /// The footer's 32-bit key.
  final int key;

  /// The footer's 32-bit value, opaque.
  final int rawValue;

  /// Zero-based index in the record stream.
  final int index;

  /// Absolute offset of the 4-byte value word.
  final int valueOffset;

  /// Absolute offset of the 8-byte footer entry.
  int get recordOffset => valueOffset - 4;

  /// [key] as `0x` plus eight lower-case hex digits.
  String get keyHex => ProgressLayout.keyHex(key);

  @override
  bool operator ==(Object other) =>
      other is ProgressFooter &&
      other.key == key &&
      other.rawValue == rawValue &&
      other.index == index &&
      other.valueOffset == valueOffset;

  @override
  int get hashCode => Object.hash(key, rawValue, index, valueOffset);

  @override
  String toString() =>
      'ProgressFooter($keyHex, value: 0x${rawValue.toRadixString(16)}, '
      'index: $index)';
}
