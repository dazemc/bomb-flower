import 'dart:typed_data';

import 'package:bomb_flower/domain/save/progress_layout.dart';

/// Builds a small, valid synthetic `progress.sav` in memory.
///
/// The defaults cover every populated section, including one field for each
/// verified name and one opaque record per unverified type. Tail data is laid
/// out in section order, so every pointer is unique and increasing. Individual
/// arguments can spoil one header field or the sentinel order without touching
/// the record layout; tests mutate the returned bytes to spoil pointer, string
/// and count details. [tailGaps] inserts unparsed zero bytes after a field's
/// tail data, which exercises gap preservation.
///
/// The i64/u64/f32 helpers write the same little-endian shapes the codec reads;
/// no bytes are copied from the game or from a `.sav` file.
Uint8List buildSyntheticProgress({
  int magic = ProgressLayout.magicValue,
  int revision = ProgressLayout.revision,
  int? dataOffsetOverride,
  int footerKey = ProgressLayout.footerKey,
  int footerValue = ProgressLayout.footerValue,
  List<int>? sentinelTypes,
  bool includeFields = true,
  int? reservedByteOffset,
  Map<int, int>? tailGaps,
}) {
  final fields = includeFields ? _standardFields() : <_FieldSpec>[];
  _checkKeys(fields);
  final sentinels = sentinelTypes ?? <int>[for (var i = 1; i <= 32; i++) i];
  if (sentinels.length != ProgressLayout.sentinelCount) {
    throw ArgumentError.value(
      sentinels.length,
      'sentinelTypes',
      'must hold exactly ${ProgressLayout.sentinelCount} type ids',
    );
  }

  final ordered = <_FieldSpec>[
    for (final type in SaveType.values)
      ...fields.where((field) => field.type == type),
  ];
  final recordCount = ProgressLayout.sentinelCount + ordered.length + 1;
  final dataOffset =
      ProgressLayout.recordStart + recordCount * ProgressLayout.recordSize;

  final tailOffsets = <_FieldSpec, int>{};
  var cursor = dataOffset;
  for (final field in ordered) {
    final tail = field.tail;
    if (tail != null) {
      final gap = tailGaps?[field.key] ?? 0;
      if (gap < 0) {
        throw ArgumentError.value(gap, 'tailGaps', 'gap must not be negative');
      }
      tailOffsets[field] = cursor;
      cursor += tail.length + gap;
    }
  }

  final out = Uint8List(cursor);
  _writeU32(out, ProgressLayout.magicOffset, magic);
  _writeU32(out, ProgressLayout.revisionOffset, revision);
  _writeU32(
    out,
    ProgressLayout.dataOffsetFieldOffset,
    dataOffsetOverride ?? dataOffset,
  );
  if (reservedByteOffset != null) {
    out[reservedByteOffset] = 0xff;
  }

  var recordIndex = 0;
  var fieldIndex = 0;
  for (final type in SaveType.values) {
    while (fieldIndex < ordered.length && ordered[fieldIndex].type == type) {
      final field = ordered[fieldIndex];
      final value = field.inline ?? tailOffsets[field]!;
      _writeRecord(out, recordIndex, field.key, value);
      recordIndex++;
      fieldIndex++;
    }
    _writeRecord(out, recordIndex, 0, sentinels[type.index]);
    recordIndex++;
  }
  _writeRecord(out, recordIndex, footerKey, footerValue);

  for (final field in ordered) {
    final tail = field.tail;
    final offset = tailOffsets[field];
    if (tail != null && offset != null) {
      out.setRange(offset, offset + tail.length, tail);
    }
  }
  return out;
}

/// One field specification for [buildSyntheticProgress].
final class _FieldSpec {
  const _FieldSpec({
    required this.type,
    required this.key,
    this.inline,
    this.tail,
  });

  final SaveType type;
  final int key;
  final int? inline;
  final Uint8List? tail;
}

_FieldSpec _inline(SaveType type, int key, int value) =>
    _FieldSpec(type: type, key: key, inline: value);

_FieldSpec _fixed(SaveType type, int key, Uint8List tail) =>
    _FieldSpec(type: type, key: key, tail: tail);

_FieldSpec _counted(SaveType type, int key, Uint8List tail) =>
    _FieldSpec(type: type, key: key, tail: tail);

_FieldSpec _opaque(SaveType type, int key, List<int> bytes) =>
    _FieldSpec(type: type, key: key, tail: Uint8List.fromList(bytes));

List<_FieldSpec> _standardFields() => <_FieldSpec>[
  _inline(SaveType.boolValue, 0xCEA220D3, 1),
  _inline(SaveType.boolValue, 0x01010101, 0),
  _fixed(SaveType.boolArray, 0x02020202, _boolArray(3, 0x5)),
  _inline(SaveType.intValue, 0x31AB5580, 20),
  _inline(SaveType.intValue, 0xFBE01DA1, 30),
  _inline(SaveType.intValue, 0xA77921D7, 50),
  _inline(SaveType.intValue, 0x03030303, -7),
  _counted(SaveType.intArray, 0x04040404, _u32Array(<int>[1, -2, 3])),
  _inline(SaveType.floatValue, 0xA4AEE8CD, _f32Bits(1.5)),
  _inline(SaveType.floatValue, 0x05050505, _f32Bits(-2.25)),
  _counted(
    SaveType.floatArray,
    0x06060606,
    _f32Array(<double>[1.5, -2.5, 0.0]),
  ),
  _inline(SaveType.enumValue, 0x07070707, 0xDEADBEEF),
  _counted(SaveType.enumArray, 0x08080808, _u32Array(<int>[0xA, 0xB])),
  _fixed(SaveType.vector3, 0x960AD56A, _vector3Bytes(1.0, -2.0, 3.5)),
  _fixed(SaveType.string32, 0x09090909, _stringSlot('Short', 32)),
  _fixed(SaveType.string64, 0x1D6189DA, _stringSlot('KokiriForest_Child', 64)),
  _fixed(SaveType.string64, 0x0A0A0A0A, _stringSlot('OldValueThatIsLong', 64)),
  _counted(
    SaveType.string64Array,
    0x0B0B0B0B,
    _stringArray(<String>['First', 'Second']),
  ),
  _opaque(SaveType.binary, 0x0C0C0C0C, <int>[0xDE, 0xAD, 0xBE, 0xEF]),
  _opaque(SaveType.binaryArray, 0x0D0D0D0D, <int>[1, 2, 3, 4, 5, 6, 7, 8]),
  _inline(SaveType.uintValue, 0x0E0E0E0E, 0xFFFFFFF0),
  _counted(SaveType.uintArray, 0x0F0F0F0F, _u32Array(<int>[1, 2, 3, 4])),
  _fixed(SaveType.int64, 0x10101010, _u64Bytes(-5)),
  _fixed(SaveType.uint64, 0x11111111, _u64Bytes(9)),
  _counted(SaveType.uint64Array, 0x12121212, _u64Array(<int>[3, 4])),
  _opaque(SaveType.wstring16Array, 0x13131313, <int>[
    0x41,
    0,
    0x42,
    0,
    0x43,
    0,
    0x44,
    0,
  ]),
];

void _checkKeys(List<_FieldSpec> fields) {
  final seen = <int>{};
  for (final field in fields) {
    if (field.key == 0) {
      throw ArgumentError.value(field.key, 'key', 'a field key cannot be 0');
    }
    if (field.key == ProgressLayout.footerKey) {
      throw ArgumentError.value(
        field.key,
        'key',
        'collides with the footer key',
      );
    }
    if (!seen.add(field.key)) {
      throw ArgumentError.value(field.key, 'key', 'duplicate synthetic key');
    }
  }
}

Uint8List _boolArray(int bitCount, int bits) {
  if (bitCount < 0 || bitCount > 32) {
    throw ArgumentError.value(bitCount, 'bitCount', 'must be 0..32');
  }
  final out = Uint8List(8);
  _writeU32(out, 0, bitCount);
  _writeU32(out, 4, bits);
  return out;
}

Uint8List _u32Array(List<int> values) {
  final out = Uint8List(4 + values.length * 4);
  _writeU32(out, 0, values.length);
  for (var i = 0; i < values.length; i++) {
    _writeU32(out, 4 + i * 4, values[i] & 0xffffffff);
  }
  return out;
}

Uint8List _f32Array(List<double> values) {
  final out = Uint8List(4 + values.length * 4);
  _writeU32(out, 0, values.length);
  final data = ByteData.sublistView(out);
  for (var i = 0; i < values.length; i++) {
    data.setFloat32(4 + i * 4, values[i], Endian.little);
  }
  return out;
}

Uint8List _u64Array(List<int> values) {
  final out = Uint8List(4 + values.length * 8);
  _writeU32(out, 0, values.length);
  for (var i = 0; i < values.length; i++) {
    final bytes = _u64Bytes(values[i]);
    out.setRange(4 + i * 8, 12 + i * 8, bytes);
  }
  return out;
}

Uint8List _stringSlot(String value, int size) {
  if (value.length > size - 1) {
    throw ArgumentError.value(
      value,
      'value',
      'does not fit a $size-byte NUL-terminated slot',
    );
  }
  final out = Uint8List(size);
  out.setRange(0, value.length, value.codeUnits);
  return out;
}

Uint8List _stringArray(List<String> values) {
  final out = Uint8List(4 + values.length * 64);
  _writeU32(out, 0, values.length);
  for (var i = 0; i < values.length; i++) {
    final slot = _stringSlot(values[i], 64);
    out.setRange(4 + i * 64, 4 + (i + 1) * 64, slot);
  }
  return out;
}

Uint8List _vector3Bytes(double x, double y, double z) {
  final out = Uint8List(12);
  final data = ByteData.sublistView(out);
  data.setFloat32(0, x, Endian.little);
  data.setFloat32(4, y, Endian.little);
  data.setFloat32(8, z, Endian.little);
  return out;
}

Uint8List _u64Bytes(int value) {
  final out = Uint8List(8);
  for (var i = 0; i < 8; i++) {
    out[i] = (value >> (8 * i)) & 0xff;
  }
  return out;
}

int _f32Bits(double value) {
  final bytes = Uint8List(4);
  ByteData.sublistView(bytes).setFloat32(0, value, Endian.little);
  return _readU32(bytes, 0);
}

void _writeRecord(Uint8List out, int index, int key, int value) {
  final offset = ProgressLayout.recordStart + index * ProgressLayout.recordSize;
  _writeU32(out, offset, key);
  _writeU32(out, offset + 4, value);
}

void _writeU32(Uint8List out, int offset, int value) {
  out[offset] = value & 0xff;
  out[offset + 1] = (value >> 8) & 0xff;
  out[offset + 2] = (value >> 16) & 0xff;
  out[offset + 3] = (value >> 24) & 0xff;
}

int _readU32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);
