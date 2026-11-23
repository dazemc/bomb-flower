import 'dart:typed_data';

import '../progress_layout.dart';
import '../progress_record.dart';

/// One typed section of a decoded save: its sentinel and its fields.
final class ProgressSection {
  ProgressSection({
    required this.type,
    required this.sentinel,
    required List<ProgressRecord> records,
  }) : records = List<ProgressRecord>.unmodifiable(records);

  /// The section's type.
  final SaveType type;

  /// The `{key 0, value typeId}` record that terminates the section.
  final ProgressRecord sentinel;

  /// The section's fields, in file order.
  final List<ProgressRecord> records;

  /// The section's type id (1..32).
  int get typeId => type.typeId;

  /// The type id carried by [sentinel]; equal to [typeId] in a valid save.
  int get sentinelTypeId => sentinel.rawValue;

  @override
  String toString() =>
      'ProgressSection($typeId ${type.label}, ${records.length} fields)';
}

/// A pending in-place edit.
///
/// Edits are value objects. [ProgressSave.applyEdits] validates every edit
/// before touching a byte, so a list is applied atomically. An edit never
/// changes the file's length or moves a record.
sealed class ProgressEdit {
  const ProgressEdit({required this.key});

  /// The hash of the record to edit.
  final int key;
}

/// Sets a `Bool` field; [value] must be 0 or 1.
final class ProgressSetBool extends ProgressEdit {
  const ProgressSetBool({required super.key, required this.value});

  final int value;
}

/// Sets an `Int` field; [value] must fit a signed 32-bit integer.
final class ProgressSetInt extends ProgressEdit {
  const ProgressSetInt({required super.key, required this.value});

  final int value;
}

/// Sets a `UInt` field; [value] must fit an unsigned 32-bit integer.
final class ProgressSetUInt extends ProgressEdit {
  const ProgressSetUInt({required super.key, required this.value});

  final int value;
}

/// Sets a `Float` field.
final class ProgressSetFloat extends ProgressEdit {
  const ProgressSetFloat({required super.key, required this.value});

  final double value;
}

/// Sets an `Enum` field's 32-bit hash.
final class ProgressSetEnumHash extends ProgressEdit {
  const ProgressSetEnumHash({required super.key, required this.value});

  final int value;
}

/// Sets a `String32` or `String64` field.
final class ProgressSetString extends ProgressEdit {
  const ProgressSetString({required super.key, required this.value});

  final String value;
}

/// Sets a `Vector3` field.
final class ProgressSetVector3 extends ProgressEdit {
  const ProgressSetVector3({
    required super.key,
    required this.x,
    required this.y,
    required this.z,
  });

  final double x;
  final double y;
  final double z;
}

/// Sets an `Int64` field.
final class ProgressSetInt64 extends ProgressEdit {
  const ProgressSetInt64({required super.key, required this.value});

  final int value;
}

/// Sets a `UInt64` field.
final class ProgressSetUInt64 extends ProgressEdit {
  const ProgressSetUInt64({required super.key, required this.value});

  final int value;
}

/// Replaces an opaque `Binary` field with bytes of exactly its stored length.
final class ProgressSetRawBytes extends ProgressEdit {
  ProgressSetRawBytes({required super.key, required List<int> bytes})
    : bytes = List<int>.unmodifiable(bytes);

  final List<int> bytes;
}

/// An immutable, typed view of one `progress.sav`.
///
/// The model keeps the exact bytes it was decoded from and a current buffer.
/// An unedited save's current buffer is the decoded buffer, so [encode] returns
/// the original bytes verbatim. Edits patch only the affected spans and build a
/// new save; the file never grows, shrinks, or moves a record.
final class ProgressSave {
  ProgressSave._({
    required this._initialBytes,
    required this._bytes,
    required this.revision,
    required this.dataOffset,
    required List<ProgressRecord> records,
    required List<ProgressRecord> sentinels,
    required this.footer,
    required Map<int, String> names,
    required this.isEdited,
  }) : _records = List<ProgressRecord>.unmodifiable(records),
       _sentinels = List<ProgressRecord>.unmodifiable(sentinels),
       _names = Map<int, String>.unmodifiable(names) {
    _sections = _buildSections();
    _fieldsByHash = _buildFieldsByHash();
  }

  /// Builds a save from verified parts.
  ///
  /// The codec calls this after validating a buffer. The save takes ownership
  /// of [bytes]; callers must not mutate it afterwards. Use [encode] or
  /// [originalBytes] for defensive copies.
  factory ProgressSave.fromDecodedBytes({
    required Uint8List bytes,
    required int revision,
    required int dataOffset,
    required List<ProgressRecord> records,
    required List<ProgressRecord> sentinels,
    required ProgressFooter footer,
    Map<int, String> names = const <int, String>{},
  }) => ProgressSave._(
    initialBytes: bytes,
    bytes: bytes,
    revision: revision,
    dataOffset: dataOffset,
    records: records,
    sentinels: sentinels,
    footer: footer,
    names: names,
    isEdited: false,
  );

  /// The exact buffer the save was decoded from.
  final Uint8List _initialBytes;

  /// The current buffer: the decoded buffer until an edit replaces it.
  final Uint8List _bytes;

  /// The schema revision (always [ProgressLayout.revision] after decoding).
  final int revision;

  /// Absolute offset of the tail.
  final int dataOffset;

  final List<ProgressRecord> _records;
  final List<ProgressRecord> _sentinels;
  final Map<int, String> _names;

  /// Whether an edit has replaced the decoded buffer.
  final bool isEdited;

  late final Map<SaveType, ProgressSection> _sections;
  late final Map<int, List<ProgressRecord>> _fieldsByHash;

  /// The magic, as a little-endian integer.
  int get magic => ProgressLayout.magicValue;

  /// The current file length in bytes.
  int get length => _bytes.length;

  /// Total records: fields, sentinels and the footer.
  int get recordCount => _records.length + _sentinels.length + 1;

  /// Field records only.
  int get fieldCount => _records.length;

  /// The field records, in file order.
  List<ProgressRecord> get records => _records;

  /// The 32 section sentinels, in file order.
  List<ProgressRecord> get sentinels => _sentinels;

  /// The opaque footer.
  final ProgressFooter footer;

  /// The 32 sections keyed by type. Empty sections are present.
  Map<SaveType, ProgressSection> get sections => _sections;

  /// Field records keyed by hash. Keys are unique in every sample; the lists
  /// keep duplicates observable rather than silently dropping one.
  Map<int, List<ProgressRecord>> get fieldsByHash => _fieldsByHash;

  /// Injected display names, without the verified fallback table.
  Map<int, String> get names => _names;

  /// A defensive copy of the exact decoded bytes.
  Uint8List get originalBytes => Uint8List.fromList(_initialBytes);

  /// A defensive copy of the current tail (`dataOffset..EOF`).
  Uint8List get tailBytes => Uint8List.fromList(_bytes.sublist(dataOffset));

  /// The current bytes, including any edits.
  ///
  /// Edits patch only their spans, so every unedited byte is still the decoded
  /// byte. With no edits this is byte-identical to the decoded input.
  Uint8List encode() => Uint8List.fromList(_bytes);

  /// The section for [type].
  ProgressSection sectionFor(SaveType type) => _sections[type]!;

  /// The first field with [key], or `null` when there is none.
  ProgressRecord? recordByHash(int key) {
    final matches = _fieldsByHash[key];
    if (matches == null || matches.isEmpty) {
      return null;
    }
    return matches.first;
  }

  /// Every field with [key]; empty when there is none.
  List<ProgressRecord> recordsByHash(int key) =>
      _fieldsByHash[key] ?? const <ProgressRecord>[];

  /// The display name for [key].
  ///
  /// An injected name wins. Otherwise only the seven names in
  /// [ProgressLayout.verifiedFieldNames] are known; every other key returns
  /// `null`. This is deliberately not a guess.
  String? nameFor(int key) =>
      _names[key] ?? ProgressLayout.verifiedFieldNames[key];

  /// Fields whose name contains [query], or whose key matches its hex/decimal
  /// form. Matching is case-insensitive and returns file order.
  List<ProgressRecord> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return const <ProgressRecord>[];
    }
    final hexNeedle = needle.startsWith('0x') ? needle.substring(2) : needle;
    final results = <ProgressRecord>[];
    for (final record in _records) {
      final name = nameFor(record.key)?.toLowerCase();
      final hex = record.key.toRadixString(16).padLeft(8, '0');
      final nameMatches = name != null && name.contains(needle);
      final hexMatches = hexNeedle.isNotEmpty && hex.contains(hexNeedle);
      if (nameMatches || hexMatches || record.key.toString() == needle) {
        results.add(record);
      }
    }
    return List<ProgressRecord>.unmodifiable(results);
  }

  /// A copy with [names] injected. Bytes and edits are unchanged.
  ProgressSave withNames(Map<int, String> names) => ProgressSave._(
    initialBytes: _initialBytes,
    bytes: _bytes,
    revision: revision,
    dataOffset: dataOffset,
    records: _records,
    sentinels: _sentinels,
    footer: footer,
    names: names,
    isEdited: isEdited,
  );

  /// Sets an `Int` field.
  ProgressSave setInt(int key, int value) =>
      applyEdits(<ProgressEdit>[ProgressSetInt(key: key, value: value)]);

  /// Sets a `UInt` field.
  ProgressSave setUInt(int key, int value) =>
      applyEdits(<ProgressEdit>[ProgressSetUInt(key: key, value: value)]);

  /// Sets a `Float` field.
  ProgressSave setFloat(int key, double value) =>
      applyEdits(<ProgressEdit>[ProgressSetFloat(key: key, value: value)]);

  /// Sets a `Bool` field to 0 or 1.
  ProgressSave setBool(int key, int value) =>
      applyEdits(<ProgressEdit>[ProgressSetBool(key: key, value: value)]);

  /// Sets an `Enum` field's 32-bit hash.
  ProgressSave setEnumHash(int key, int value) =>
      applyEdits(<ProgressEdit>[ProgressSetEnumHash(key: key, value: value)]);

  /// Sets a `String32` or `String64` field.
  ProgressSave setString(int key, String value) =>
      applyEdits(<ProgressEdit>[ProgressSetString(key: key, value: value)]);

  /// Sets a `Vector3` field.
  ProgressSave setVector3(int key, double x, double y, double z) => applyEdits(
    <ProgressEdit>[ProgressSetVector3(key: key, x: x, y: y, z: z)],
  );

  /// Sets an `Int64` field.
  ProgressSave setInt64(int key, int value) =>
      applyEdits(<ProgressEdit>[ProgressSetInt64(key: key, value: value)]);

  /// Sets a `UInt64` field.
  ProgressSave setUInt64(int key, int value) =>
      applyEdits(<ProgressEdit>[ProgressSetUInt64(key: key, value: value)]);

  /// Replaces an opaque `Binary` field; [bytes] must match its stored length.
  ProgressSave setRawBytes(int key, List<int> bytes) =>
      applyEdits(<ProgressEdit>[ProgressSetRawBytes(key: key, bytes: bytes)]);

  /// Applies [edits] atomically.
  ///
  /// Every edit is resolved against the current records first. If any edit is
  /// rejected, no byte is changed and this save is returned unchanged by
  /// throwing before the patch buffer is created.
  ProgressSave applyEdits(Iterable<ProgressEdit> edits) {
    final pending = edits.toList(growable: false);
    if (pending.isEmpty) {
      return this;
    }

    final resolved = <_ResolvedEdit>[];
    for (final edit in pending) {
      resolved.add(_resolve(edit));
    }
    for (final edit in resolved) {
      if (edit.offset < 0 || edit.offset > _bytes.length - edit.bytes.length) {
        throw RangeError(
          'edit ${edit.record.keyHex} would write ${edit.bytes.length} '
          'byte(s) at ${edit.offset}; the buffer is ${_bytes.length} '
          'byte(s) long',
        );
      }
    }

    final patched = Uint8List.fromList(_bytes);
    final inlineValues = <int, int>{};
    for (final edit in resolved) {
      patched.setRange(
        edit.offset,
        edit.offset + edit.bytes.length,
        edit.bytes,
      );
      final rawValue = edit.inlineRawValue;
      if (rawValue != null) {
        inlineValues[edit.record.index] = rawValue;
      }
    }

    final records = <ProgressRecord>[
      for (final record in _records)
        _copyRecord(record, patched, inlineValues[record.index]),
    ];
    final sentinels = <ProgressRecord>[
      for (final sentinel in _sentinels) _copyRecord(sentinel, patched, null),
    ];

    return ProgressSave._(
      initialBytes: _initialBytes,
      bytes: patched,
      revision: revision,
      dataOffset: dataOffset,
      records: records,
      sentinels: sentinels,
      footer: footer,
      names: _names,
      isEdited: true,
    );
  }

  _ResolvedEdit _resolve(ProgressEdit edit) => switch (edit) {
    ProgressSetBool(:final key, :final value) => _resolveInline(
      key,
      SaveType.boolValue,
      value,
      0,
      1,
      'setBool',
    ),
    ProgressSetInt(:final key, :final value) => _resolveInline(
      key,
      SaveType.intValue,
      value,
      -0x80000000,
      0x7fffffff,
      'setInt',
    ),
    ProgressSetUInt(:final key, :final value) => _resolveInline(
      key,
      SaveType.uintValue,
      value,
      0,
      0xffffffff,
      'setUInt',
    ),
    ProgressSetEnumHash(:final key, :final value) => _resolveInline(
      key,
      SaveType.enumValue,
      value,
      0,
      0xffffffff,
      'setEnumHash',
    ),
    ProgressSetFloat(:final key, :final value) => _resolveFloat(key, value),
    ProgressSetString(:final key, :final value) => _resolveString(key, value),
    ProgressSetVector3(:final key, :final x, :final y, :final z) =>
      _resolveVector3(key, x, y, z),
    ProgressSetInt64(:final key, :final value) => _resolveInt64(key, value),
    ProgressSetUInt64(:final key, :final value) => _resolveUInt64(key, value),
    ProgressSetRawBytes(:final key, :final bytes) => _resolveRawBytes(
      key,
      bytes,
    ),
  };

  _ResolvedEdit _resolveInline(
    int key,
    SaveType expected,
    int value,
    int minimum,
    int maximum,
    String operation,
  ) {
    final record = _uniqueRecord(key, operation);
    _requireType(record, expected, operation);
    if (value < minimum || value > maximum) {
      throw RangeError.range(
        value,
        minimum,
        maximum,
        'value',
        '$operation value does not fit ${expected.label}',
      );
    }
    final bytes = _encodeU32(value & 0xffffffff);
    return _ResolvedEdit(
      record: record,
      offset: record.valueOffset,
      bytes: bytes,
      inlineRawValue: _readU32(bytes, 0),
    );
  }

  _ResolvedEdit _resolveFloat(int key, double value) {
    final record = _uniqueRecord(key, 'setFloat');
    _requireType(record, SaveType.floatValue, 'setFloat');
    final bytes = _encodeF32(value, 'setFloat');
    return _ResolvedEdit(
      record: record,
      offset: record.valueOffset,
      bytes: bytes,
      inlineRawValue: _readU32(bytes, 0),
    );
  }

  _ResolvedEdit _resolveString(int key, String value) {
    final record = _uniqueRecord(key, 'setString');
    if (record.type != SaveType.string32 && record.type != SaveType.string64) {
      throw ArgumentError.value(
        record.type.label,
        'key',
        'setString needs a String32 or String64 record; '
            '${record.keyHex} is ${record.type.label}',
      );
    }
    final slot = record.dataLength;
    if (value.length > slot - 1) {
      throw ArgumentError.value(
        value,
        'value',
        'setString needs at most ${slot - 1} character(s) for a '
            '$slot-byte slot with its NUL; refusing to truncate',
      );
    }
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit < 0x20 || unit > 0x7e) {
        throw ArgumentError.value(
          value,
          'value',
          'character at index $i is outside printable ASCII (0x20..0x7e)',
        );
      }
    }
    final bytes = Uint8List(slot);
    bytes.setRange(0, value.length, value.codeUnits);
    return _ResolvedEdit(
      record: record,
      offset: _tailOffset(record, 'setString'),
      bytes: bytes,
    );
  }

  _ResolvedEdit _resolveVector3(int key, double x, double y, double z) {
    final record = _uniqueRecord(key, 'setVector3');
    _requireType(record, SaveType.vector3, 'setVector3');
    if (record.dataLength != 12) {
      throw StateError(
        'setVector3: ${record.keyHex} has a ${record.dataLength}-byte span; '
        'expected 12',
      );
    }
    final bytes = Uint8List(12);
    final data = ByteData.sublistView(bytes);
    for (final (index, value) in <(int, double)>[(0, x), (4, y), (8, z)]) {
      data.setFloat32(index, value, Endian.little);
      if (!data.getFloat32(index, Endian.little).isFinite) {
        throw ArgumentError.value(
          value,
          'value',
          'setVector3 component does not fit a finite binary32',
        );
      }
    }
    return _ResolvedEdit(
      record: record,
      offset: _tailOffset(record, 'setVector3'),
      bytes: bytes,
    );
  }

  _ResolvedEdit _resolveInt64(int key, int value) {
    final record = _uniqueRecord(key, 'setInt64');
    _requireType(record, SaveType.int64, 'setInt64');
    if (record.dataLength != 8) {
      throw StateError(
        'setInt64: ${record.keyHex} has a ${record.dataLength}-byte span; '
        'expected 8',
      );
    }
    if (value < -0x8000000000000000 || value > 0x7fffffffffffffff) {
      throw RangeError.range(
        value,
        -0x8000000000000000,
        0x7fffffffffffffff,
        'value',
        'setInt64 value does not fit a signed 64-bit integer',
      );
    }
    return _ResolvedEdit(
      record: record,
      offset: _tailOffset(record, 'setInt64'),
      bytes: _encodeU64(value),
    );
  }

  _ResolvedEdit _resolveUInt64(int key, int value) {
    final record = _uniqueRecord(key, 'setUInt64');
    _requireType(record, SaveType.uint64, 'setUInt64');
    if (record.dataLength != 8) {
      throw StateError(
        'setUInt64: ${record.keyHex} has a ${record.dataLength}-byte span; '
        'expected 8',
      );
    }
    if (value < 0) {
      throw RangeError.range(
        value,
        0,
        null,
        'value',
        'setUInt64 rejects negative values; Dart native ints cannot '
            'represent 2^63..2^64-1',
      );
    }
    return _ResolvedEdit(
      record: record,
      offset: _tailOffset(record, 'setUInt64'),
      bytes: _encodeU64(value),
    );
  }

  _ResolvedEdit _resolveRawBytes(int key, List<int> bytes) {
    final record = _uniqueRecord(key, 'setRawBytes');
    _requireType(record, SaveType.binary, 'setRawBytes');
    if (bytes.length != record.dataLength) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'setRawBytes needs exactly ${record.dataLength} byte(s) for '
            '${record.keyHex}; the file must not resize',
      );
    }
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] < 0 || bytes[i] > 0xff) {
        throw ArgumentError.value(
          bytes[i],
          'bytes',
          'byte at index $i is outside 0..255',
        );
      }
    }
    return _ResolvedEdit(
      record: record,
      offset: _tailOffset(record, 'setRawBytes'),
      bytes: Uint8List.fromList(bytes),
    );
  }

  ProgressRecord _uniqueRecord(int key, String operation) {
    final matches = _fieldsByHash[key];
    if (matches == null || matches.isEmpty) {
      throw ArgumentError.value(
        key,
        'key',
        '$operation: no field with this hash',
      );
    }
    if (matches.length != 1) {
      throw ArgumentError.value(
        key,
        'key',
        '$operation: hash occurs ${matches.length} times; refusing to guess',
      );
    }
    return matches.single;
  }

  void _requireType(
    ProgressRecord record,
    SaveType expected,
    String operation,
  ) {
    if (record.type != expected) {
      throw ArgumentError.value(
        record.type.label,
        'key',
        '$operation needs a ${expected.label} record; '
            '${record.keyHex} is ${record.type.label}',
      );
    }
  }

  int _tailOffset(ProgressRecord record, String operation) {
    final offset = record.dataOffset;
    if (offset == null) {
      throw StateError('$operation: ${record.keyHex} has no tail data');
    }
    return offset;
  }

  ProgressRecord _copyRecord(
    ProgressRecord record,
    Uint8List bytes,
    int? rawValue,
  ) => ProgressRecord(
    bytes: bytes,
    key: record.key,
    rawValue: rawValue ?? record.rawValue,
    index: record.index,
    type: record.type,
    valueOffset: record.valueOffset,
    dataOffset: record.dataOffset,
    dataLength: record.dataLength,
    isSentinel: record.isSentinel,
  );

  Map<SaveType, ProgressSection> _buildSections() {
    final recordsByType = <SaveType, List<ProgressRecord>>{};
    for (final record in _records) {
      (recordsByType[record.type] ??= <ProgressRecord>[]).add(record);
    }

    final sentinelsByType = <SaveType, ProgressRecord>{};
    for (final sentinel in _sentinels) {
      if (sentinelsByType.containsKey(sentinel.type)) {
        throw StateError('duplicate sentinel for ${sentinel.type.label}');
      }
      sentinelsByType[sentinel.type] = sentinel;
    }

    final map = <SaveType, ProgressSection>{};
    for (final type in SaveType.values) {
      final sentinel = sentinelsByType[type];
      if (sentinel == null) {
        throw StateError('missing sentinel for ${type.label}');
      }
      map[type] = ProgressSection(
        type: type,
        sentinel: sentinel,
        records: recordsByType[type] ?? const <ProgressRecord>[],
      );
    }
    return Map<SaveType, ProgressSection>.unmodifiable(map);
  }

  Map<int, List<ProgressRecord>> _buildFieldsByHash() {
    final map = <int, List<ProgressRecord>>{};
    for (final record in _records) {
      (map[record.key] ??= <ProgressRecord>[]).add(record);
    }
    return Map<int, List<ProgressRecord>>.unmodifiable(
      <int, List<ProgressRecord>>{
        for (final entry in map.entries)
          entry.key: List<ProgressRecord>.unmodifiable(entry.value),
      },
    );
  }

  static Uint8List _encodeU32(int value) {
    final bytes = Uint8List(4);
    for (var i = 0; i < 4; i++) {
      bytes[i] = (value >> (8 * i)) & 0xff;
    }
    return bytes;
  }

  static Uint8List _encodeU64(int value) {
    final bytes = Uint8List(8);
    for (var i = 0; i < 8; i++) {
      bytes[i] = (value >> (8 * i)) & 0xff;
    }
    return bytes;
  }

  static Uint8List _encodeF32(double value, String operation) {
    if (!value.isFinite) {
      throw ArgumentError.value(
        value,
        'value',
        '$operation needs a finite binary32 value',
      );
    }
    final bytes = Uint8List(4);
    final data = ByteData.sublistView(bytes);
    data.setFloat32(0, value, Endian.little);
    if (!data.getFloat32(0, Endian.little).isFinite) {
      throw ArgumentError.value(
        value,
        'value',
        '$operation value does not fit a finite binary32',
      );
    }
    return bytes;
  }

  static int _readU32(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  @override
  String toString() =>
      'ProgressSave($fieldCount fields, $recordCount records, $length bytes, '
      'dataOffset: 0x${dataOffset.toRadixString(16)}'
      '${isEdited ? ', edited' : ''})';
}

/// A fully validated edit, ready to patch.
final class _ResolvedEdit {
  const _ResolvedEdit({
    required this.record,
    required this.offset,
    required this.bytes,
    this.inlineRawValue,
  });

  final ProgressRecord record;
  final int offset;
  final Uint8List bytes;
  final int? inlineRawValue;
}
