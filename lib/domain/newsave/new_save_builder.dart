/// Pure-Dart construction of a new Ocarina of Time save.
///
/// The builder emits the bytes only. It imports no Flutter, no `dart:io`, and
/// no codec; it never reads a sample save. The data layer's `NewSaveWriter`
/// owns the filesystem rules.
library;

import 'dart:typed_data';

import '../save/caption_layout.dart';
import '../save/progress_layout.dart' as layout;
import '../schema/gamedata_schema.dart';
import 'new_save_spec.dart';

/// The bytes and counts produced by [NewSaveBuilder.build].
final class NewSaveBuild {
  /// Creates a build.
  const NewSaveBuild({
    required this.progressBytes,
    required this.captionBytes,
    required this.dataOffset,
    required this.recordCount,
    required this.fieldCount,
    required this.sentinelCount,
    required this.sectionCounts,
  });

  /// The complete `progress.sav`.
  final Uint8List progressBytes;

  /// The complete `caption.sav`.
  final Uint8List captionBytes;

  /// The absolute start of the pointer-referenced tail in [progressBytes].
  final int dataOffset;

  /// The number of 8-byte records in [progressBytes].
  final int recordCount;

  /// The number of field records (records minus sentinels and the footer).
  final int fieldCount;

  /// The number of `{0, typeId}` sentinel records.
  final int sentinelCount;

  /// Field count by type id, 1..32. Empty sections are present with count 0.
  final Map<int, int> sectionCounts;
}

/// A new-save build failure with a stable code.
final class NewSaveBuildException implements Exception {
  /// Creates a failure.
  const NewSaveBuildException(this.message, {this.code});

  /// Human-readable explanation.
  final String message;

  /// Stable machine-readable code, or `null` when no more specific code fits.
  final String? code;

  @override
  String toString() => code == null
      ? 'NewSaveBuildException: $message'
      : 'NewSaveBuildException[$code]: $message';
}

/// Builds the verified `progress.sav` and `caption.sav` layout from a schema.
///
/// The progress file uses the schema's defaults and the verified record order.
/// It matches the shipped samples' container arithmetic:
/// `120,572 = 40 + 8 * 11,958 + 24,868`, where 24,868 is the tail including
/// the samples' 8-byte zero trailer.
///
/// The first `Binary` field (section 19, lowest record index) is emitted as a
/// `u32 400` length word plus 400 zero bytes, matching the verified 404-byte
/// sample span. The other two are the 4-byte `u32 0` empty blobs. The payload
/// lengths are the verified sample spans; the payload contents are zeros
/// because the sample bytes are unknown, so this does not claim to reproduce
/// them.
///
/// The footer value stays exactly `0x1D6F4` (`ProgressLayout.footerValue`),
/// which is `120,564 = 120,572 - 8`, the offset of the samples' zero trailer.
/// The footer is opaque on read and is never followed as a pointer. Real
/// played saves are larger and carry extra trailing bytes after the footer
/// value, so the value is not a total-length field.
///
/// The caption file is built directly from [CaptionLayout]: magic, the 1392
/// marker, the six date entries observed in all three samples, the scene and
/// map path, and a JPEG. The date is fixed at 2026-01-01 00:00:00, the date in
/// every verified sample; the wall clock is never consulted.
abstract final class NewSaveBuilder {
  /// Builds a save from [schema] and [spec].
  ///
  /// Throws [NewSaveBuildException] when a spec choice cannot be stored or
  /// when the schema's record metadata is not the verified layout.
  static NewSaveBuild build({
    required GameDataSchema schema,
    required NewSaveSpec spec,
  }) {
    _rejectProfileName(spec.profileName);
    final plan = _RecordPlan.fromSchema(schema);
    final overrides = _startPositionOverrides(schema, plan, spec.startPosition);

    final tail = _TailWriter();
    final binarySpanLengths = <int>[];
    for (final field in plan.fieldOrder) {
      if (!_tailTypes.contains(field.type)) {
        continue;
      }
      final index = field.recordIndex!;
      plan.values[index] = plan.dataOffset + tail.length;
      final binarySpanLength = field.type == SaveType.binary
          ? (binarySpanLengths.isEmpty
                ? _firstBinarySpanLength
                : _emptyBinarySpanLength)
          : null;
      if (binarySpanLength != null) {
        binarySpanLengths.add(binarySpanLength);
      }
      _emitTail(
        tail,
        field,
        startPosition: overrides[index],
        binarySpanLength: binarySpanLength,
      );
    }
    _assertBinarySpans(binarySpanLengths);
    final tailBeforeTrailer = tail.length;
    tail.zeros(_sampleTrailerLength);
    if (tail.length - tailBeforeTrailer != _sampleTrailerLength) {
      _inconsistent(
        'The sample trailer is ${tail.length - tailBeforeTrailer} bytes; the '
        'verified samples have $_sampleTrailerLength.',
      );
    }

    return NewSaveBuild(
      progressBytes: _buildProgress(plan, tail),
      captionBytes: _buildCaption(spec),
      dataOffset: plan.dataOffset,
      recordCount: plan.recordCount,
      fieldCount: plan.fieldOrder.length,
      sentinelCount: layout.ProgressLayout.sentinelCount,
      sectionCounts: Map<int, int>.unmodifiable(plan.sectionCounts),
    );
  }

  static void _rejectProfileName(String? profileName) {
    if (profileName == null) {
      return;
    }
    throw NewSaveBuildException(
      'profileName "$profileName" cannot be stored: no verified schema field '
      'carries a profile or player name. The only name-like on-disk fields are '
      'PlayerStatus.* equipment strings and WarpPoint_*.LocationName.',
      code: 'profile_name_unavailable',
    );
  }

  static Map<int, SavePosition> _startPositionOverrides(
    GameDataSchema schema,
    _RecordPlan plan,
    SavePosition? startPosition,
  ) {
    if (startPosition == null) {
      return const <int, SavePosition>{};
    }

    final field = schema.byNameOnDisk('Player_Pos_For_Map');
    if (field == null) {
      throw const NewSaveBuildException(
        'startPosition was set, but no on-disk field is named '
        'Player_Pos_For_Map; the verified field hash is 0x960AD56A.',
        code: 'start_position_unavailable',
      );
    }
    if (field.hash != 0x960AD56A || field.type != SaveType.vector3) {
      throw NewSaveBuildException(
        'startPosition was set, but Player_Pos_For_Map resolved to '
        '${_describe(field)} with type ${field.type.wireName}; the verified '
        'field is Vector3 with hash 0x960AD56A.',
        code: 'start_position_unavailable',
      );
    }
    final index = field.recordIndex;
    if (index == null || !plan.fieldOrder.contains(field)) {
      throw NewSaveBuildException(
        'startPosition was set, but ${_describe(field)} is not part of the '
        'built record table.',
        code: 'start_position_unavailable',
      );
    }
    return <int, SavePosition>{index: startPosition};
  }

  static Uint8List _buildProgress(_RecordPlan plan, _TailWriter tail) {
    final tailBytes = tail.takeBytes();
    final expectedTailLength =
        layout.ProgressLayout.sampleFileLength - plan.dataOffset;
    if (tailBytes.length != expectedTailLength) {
      _inconsistent(
        'The emitted tail is ${tailBytes.length} bytes; the verified samples '
        'have $expectedTailLength.',
      );
    }
    if (!_hasZeroTrailer(tailBytes, _sampleTrailerLength)) {
      _inconsistent(
        'The last $_sampleTrailerLength tail bytes are not the verified zero '
        'trailer.',
      );
    }

    final progress = Uint8List(plan.dataOffset + tailBytes.length);
    final data = ByteData.sublistView(progress);

    data.setUint32(
      layout.ProgressLayout.magicOffset,
      layout.ProgressLayout.magicValue,
      Endian.little,
    );
    data.setUint32(
      layout.ProgressLayout.revisionOffset,
      layout.ProgressLayout.revision,
      Endian.little,
    );
    data.setUint32(
      layout.ProgressLayout.dataOffsetFieldOffset,
      plan.dataOffset,
      Endian.little,
    );
    // 0x0C..0x27 stays zero from Uint8List's initialization.

    for (var i = 0; i < plan.recordCount; i++) {
      final offset =
          layout.ProgressLayout.recordStart +
          i * layout.ProgressLayout.recordSize;
      data.setUint32(offset, plan.keys[i], Endian.little);
      data.setUint32(offset + 4, plan.values[i], Endian.little);
    }

    progress.setRange(plan.dataOffset, progress.length, tailBytes);
    if (progress.length != layout.ProgressLayout.sampleFileLength) {
      _inconsistent(
        'The built progress.sav is ${progress.length} bytes; the verified '
        'samples are ${layout.ProgressLayout.sampleFileLength}.',
      );
    }
    if (layout.ProgressLayout.footerValue !=
        progress.length - _sampleTrailerLength) {
      _inconsistent(
        'The footer value 0x'
        '${layout.ProgressLayout.footerValue.toRadixString(16)} is not the '
        "samples' trailer offset 0x"
        '${(progress.length - _sampleTrailerLength).toRadixString(16)}.',
      );
    }
    return progress;
  }

  static bool _hasZeroTrailer(Uint8List bytes, int length) {
    if (bytes.length < length) {
      return false;
    }
    for (var i = bytes.length - length; i < bytes.length; i++) {
      if (bytes[i] != 0) {
        return false;
      }
    }
    return true;
  }

  static Uint8List _buildCaption(NewSaveSpec spec) {
    _checkCaptionName(spec.scene, 'scene');
    _checkCaptionName(spec.mapPath, 'mapPath');

    final jpeg = spec.createCaptionScreenshot
        ? _defaultCaptionJpeg
        : _markerOnlyJpeg;
    final caption = Uint8List(CaptionLayout.jpegOffset + jpeg.length);
    final data = ByteData.sublistView(caption);

    data.setUint32(
      CaptionLayout.magicOffset,
      CaptionLayout.magicValue,
      Endian.little,
    );
    data.setUint32(
      CaptionLayout.layoutCheckOffset,
      CaptionLayout.layoutCheckValue,
      Endian.little,
    );

    for (final descriptor in CaptionLayout.dateFields) {
      data.setUint32(descriptor.sampleOffset, descriptor.key, Endian.little);
      data.setUint32(
        descriptor.sampleOffset + 4,
        _sampleCaptionDate[descriptor.field]!,
        Endian.little,
      );
    }

    _writeCaptionName(caption, CaptionLayout.sceneNameOffset, spec.scene);
    _writeCaptionName(caption, CaptionLayout.mapPathOffset, spec.mapPath);

    data.setUint32(CaptionLayout.jpegLengthOffset, jpeg.length, Endian.little);
    caption.setRange(CaptionLayout.jpegOffset, caption.length, jpeg);
    return caption;
  }

  static void _checkCaptionName(String value, String field) {
    if (value.length > CaptionLayout.nameLength - 1) {
      throw NewSaveBuildException(
        'caption $field is ${value.length} code units; a '
        '${CaptionLayout.nameLength}-byte span holds at most '
        '${CaptionLayout.nameLength - 1} plus a NUL terminator.',
        code: 'caption_name_invalid',
      );
    }
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit < 0x20 || unit > 0x7e) {
        throw NewSaveBuildException(
          'caption $field has non-printable code unit '
          '0x${unit.toRadixString(16).padLeft(2, '0')} at index $i; only '
          'printable ASCII 0x20..0x7e is verified.',
          code: 'caption_name_invalid',
        );
      }
    }
  }

  static void _writeCaptionName(Uint8List out, int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      out[offset + i] = value.codeUnitAt(i);
    }
    out[offset + value.length] = 0;
  }

  static void _emitTail(
    _TailWriter tail,
    SaveFieldDef field, {
    SavePosition? startPosition,
    int? binarySpanLength,
  }) {
    switch (field.type) {
      case SaveType.booleanArray:
        final arrayLen = _arrayLen(field);
        if (arrayLen > 32) {
          _inconsistent(
            'Field ${_describe(field)} BoolArray has arrayLen $arrayLen; a '
            'single 32-bit bits word holds at most 32.',
          );
        }
        final value = _boolDefault(field);
        tail.u32(arrayLen);
        tail.u32(value ? (1 << arrayLen) - 1 : 0);
        break;

      case SaveType.integerArray:
        final arrayLen = _arrayLen(field);
        final value = _intDefault(field);
        _checkInt32(value, field);
        tail.u32(arrayLen);
        for (var i = 0; i < arrayLen; i++) {
          tail.u32(value & 0xFFFFFFFF);
        }
        break;

      case SaveType.float32Array:
        final arrayLen = _arrayLen(field);
        final bits = _float32Bits(
          _doubleDefault(field),
          code: 'schema_inconsistent',
          what: 'Field ${_describe(field)} default',
        );
        tail.u32(arrayLen);
        for (var i = 0; i < arrayLen; i++) {
          tail.u32(bits);
        }
        break;

      case SaveType.enumerationArray:
        final arrayLen = _arrayLen(field);
        final value = _enumDefault(field);
        tail.u32(arrayLen);
        for (var i = 0; i < arrayLen; i++) {
          tail.u32(value);
        }
        break;

      case SaveType.vector3:
        final position = startPosition ?? _vector3Default(field);
        final code = startPosition == null
            ? 'schema_inconsistent'
            : 'start_position_unavailable';
        final what = startPosition == null
            ? 'Field ${_describe(field)} default'
            : 'startPosition';
        tail.u32(_float32Bits(position.x, code: code, what: '$what.x'));
        tail.u32(_float32Bits(position.y, code: code, what: '$what.y'));
        tail.u32(_float32Bits(position.z, code: code, what: '$what.z'));
        break;

      case SaveType.string32:
        _writeAsciiSlot(
          tail,
          _stringDefault(field),
          layout.SaveType.string32.fixedLength!,
          field,
        );
        break;

      case SaveType.string64:
        _writeAsciiSlot(
          tail,
          _stringDefault(field),
          layout.SaveType.string64.fixedLength!,
          field,
        );
        break;

      case SaveType.string64Array:
        final arrayLen = _arrayLen(field);
        final value = _stringDefault(field);
        final slot = layout.SaveType.string64Array.elementSize!;
        tail.u32(arrayLen);
        for (var i = 0; i < arrayLen; i++) {
          _writeAsciiSlot(tail, value, slot, field);
        }
        break;

      case SaveType.binary:
        final spanLength = binarySpanLength;
        if (spanLength == null) {
          _inconsistent(
            'Field ${_describe(field)} is Binary but no verified span length '
            'was supplied.',
          );
        }
        _emitBinary(tail, spanLength);
        break;

      case SaveType.binaryArray:
        final arrayLen = _arrayLen(field);
        final value = _intDefault(field);
        _checkUint32(value, field);
        tail.u32(arrayLen);
        for (var i = 0; i < arrayLen; i++) {
          tail.u32(value);
        }
        break;

      case SaveType.unsignedIntegerArray:
        final arrayLen = _arrayLen(field);
        final value = _intDefault(field);
        _checkUint32(value, field);
        tail.u32(arrayLen);
        for (var i = 0; i < arrayLen; i++) {
          tail.u32(value);
        }
        break;

      case SaveType.int64:
        tail.i64(_intDefault(field));
        break;

      case SaveType.uint64:
        final value = _intDefault(field);
        _checkUint64(value, field);
        tail.u64(value);
        break;

      case SaveType.uint64Array:
        final arrayLen = _arrayLen(field);
        final value = _intDefault(field);
        _checkUint64(value, field);
        tail.u32(arrayLen);
        for (var i = 0; i < arrayLen; i++) {
          tail.u64(value);
        }
        break;

      case SaveType.wstring16Array:
        final arrayLen = _arrayLen(field);
        final units = _stringDefault(field).codeUnits;
        if (units.length > _wstring16CodeUnitsPerSlot) {
          throw NewSaveBuildException(
            'Field ${_describe(field)} WString16Array default is '
            '${units.length} code units; a $_wstring16SlotBytes-byte slot '
            'holds at most $_wstring16CodeUnitsPerSlot.',
            code: 'string_too_long',
          );
        }
        tail.u32(arrayLen);
        for (var i = 0; i < arrayLen; i++) {
          _writeWString16Slot(tail, units);
        }
        break;

      default:
        _inconsistent(
          'Field ${_describe(field)} has unsupported tail type '
          '${field.type.wireName}.',
        );
    }
  }

  /// Emits a `Binary` span: a `u32` payload length followed by zero bytes.
  ///
  /// [spanLength] is the verified sample span (404 for the first Binary, 4 for
  /// the other two). The payload length word is `spanLength - 4`; the payload
  /// contents are zeros because the sample bytes are unknown. This does not
  /// claim to reproduce the sample payload.
  static void _emitBinary(_TailWriter tail, int spanLength) {
    final payloadLength = spanLength - layout.ProgressLayout.valueWordSize;
    tail.u32(payloadLength);
    tail.zeros(payloadLength);
  }

  static void _assertBinarySpans(List<int> spans) {
    if (spans.length != _binaryFieldCount) {
      _inconsistent(
        'The schema has ${spans.length} Binary fields; the verified layout '
        'has $_binaryFieldCount.',
      );
    }
    if (spans[0] != _firstBinarySpanLength ||
        spans[1] != _emptyBinarySpanLength ||
        spans[2] != _emptyBinarySpanLength) {
      _inconsistent(
        'The emitted Binary spans are ${spans.join('/')}; the verified samples '
        'are $_firstBinarySpanLength/$_emptyBinarySpanLength/'
        '$_emptyBinarySpanLength in record order.',
      );
    }
  }
}

/// The record table, validated against the verified layout and filled in order.
final class _RecordPlan {
  _RecordPlan._({
    required this.fieldOrder,
    required this.keys,
    required this.values,
    required this.recordCount,
    required this.dataOffset,
    required this.sectionCounts,
  });

  final List<SaveFieldDef> fieldOrder;
  final List<int> keys;
  final List<int> values;
  final int recordCount;
  final int dataOffset;
  final Map<int, int> sectionCounts;

  factory _RecordPlan.fromSchema(GameDataSchema schema) {
    if (schema.schemaRevision != layout.ProgressLayout.revision) {
      _inconsistent(
        'The schema revision ${schema.schemaRevision} is not the progress '
        'layout revision ${layout.ProgressLayout.revision}.',
      );
    }

    final fieldsByRecord = <int, SaveFieldDef>{};
    for (final field in schema.fields) {
      final index = field.recordIndex;
      if (index == null) {
        _inconsistent('Field ${_describe(field)} has no recordIndex.');
      }
      if (index < 0) {
        _inconsistent(
          'Field ${_describe(field)} has negative recordIndex $index.',
        );
      }
      if (field.section == null) {
        _inconsistent('Field ${_describe(field)} has no section.');
      }
      if (field.hash <= 0 || field.hash > 0xFFFFFFFF) {
        _inconsistent(
          'Field ${_describe(field)} has key ${field.hash}, which is not a '
          'usable 32-bit record key.',
        );
      }
      final previous = fieldsByRecord[index];
      if (previous != null) {
        _inconsistent(
          'Fields ${_describe(previous)} and ${_describe(field)} both claim '
          'recordIndex $index.',
        );
      }
      fieldsByRecord[index] = field;
    }

    final sections = <int, SectionDef>{};
    for (final section in schema.sections) {
      final typeId = section.typeId;
      if (typeId < 1 || typeId > layout.ProgressLayout.sentinelCount) {
        _inconsistent('Section type id $typeId is outside 1..32.');
      }
      if (sections.containsKey(typeId)) {
        _inconsistent('Section type id $typeId appears more than once.');
      }
      if (section.count <= 0) {
        _inconsistent(
          'Section $typeId is in schema.sections but has count '
          '${section.count}.',
        );
      }
      if (section.sentinelValue != typeId) {
        _inconsistent(
          'Section $typeId sentinel value is ${section.sentinelValue}, not '
          '$typeId.',
        );
      }
      final layoutType = layout.SaveType.forTypeId(typeId);
      if (layoutType == null || !layoutType.isKnown) {
        _inconsistent('Section $typeId has no known progress.sav layout.');
      }
      sections[typeId] = section;
    }

    final emptyIds = schema.emptySectionIds.toSet();
    if (emptyIds.length != schema.emptySectionIds.length) {
      _inconsistent('schema.emptySectionIds contains a duplicate.');
    }
    for (final typeId in emptyIds) {
      if (typeId < 1 || typeId > layout.ProgressLayout.sentinelCount) {
        _inconsistent('Empty section type id $typeId is outside 1..32.');
      }
      if (sections.containsKey(typeId)) {
        _inconsistent('Section $typeId is both populated and empty.');
      }
    }
    if (sections.length + emptyIds.length !=
        layout.ProgressLayout.sentinelCount) {
      _inconsistent(
        'The schema describes ${sections.length} populated and '
        '${emptyIds.length} empty sections; 32 are required.',
      );
    }
    for (
      var typeId = 1;
      typeId <= layout.ProgressLayout.sentinelCount;
      typeId++
    ) {
      if (!sections.containsKey(typeId) && !emptyIds.contains(typeId)) {
        _inconsistent('Section $typeId is neither populated nor empty.');
      }
    }

    final fieldOrder = <SaveFieldDef>[];
    final keys = <int>[];
    final values = <int>[];
    final sectionCounts = <int, int>{};
    final filled = <bool>[];
    var cursor = 0;

    void markFilled(int index) {
      if (index != filled.length) {
        _inconsistent(
          'Record slot $index is out of order; expected ${filled.length}.',
        );
      }
      filled.add(true);
    }

    for (
      var typeId = 1;
      typeId <= layout.ProgressLayout.sentinelCount;
      typeId++
    ) {
      final section = sections[typeId];
      if (section == null) {
        markFilled(cursor);
        keys.add(0);
        values.add(typeId);
        cursor++;
        sectionCounts[typeId] = 0;
        continue;
      }

      if (section.recordStart != cursor) {
        _inconsistent(
          'Section $typeId starts at record ${section.recordStart}, but the '
          'previous section ended at $cursor.',
        );
      }
      if (section.recordEnd != cursor + section.count - 1) {
        _inconsistent(
          'Section $typeId claims records ${section.recordStart}..'
          '${section.recordEnd}, which does not match count '
          '${section.count}.',
        );
      }
      if (section.sentinelRecordIndex != cursor + section.count) {
        _inconsistent(
          'Section $typeId sentinel is at record '
          '${section.sentinelRecordIndex}; the ${section.count} fields need '
          'it at ${cursor + section.count}.',
        );
      }

      final layoutType = layout.SaveType.forTypeId(typeId)!;
      for (var i = 0; i < section.count; i++) {
        final index = cursor + i;
        final field = fieldsByRecord[index];
        if (field == null) {
          _inconsistent(
            'Section $typeId expects a field at record $index, but the schema '
            'has none.',
          );
        }
        if (field.section != typeId) {
          _inconsistent(
            'Field ${_describe(field)} is in section ${field.section}, but '
            'record $index belongs to section $typeId.',
          );
        }
        if (field.type != section.type) {
          _inconsistent(
            'Field ${_describe(field)} is ${field.type.wireName}, but section '
            '$typeId is ${section.type.wireName}.',
          );
        }
        final expectedTypeId = _sectionByType[field.type];
        if (expectedTypeId == null) {
          _inconsistent(
            'Field ${_describe(field)} has no verified progress.sav section '
            'for type ${field.type.wireName}.',
          );
        }
        if (expectedTypeId != typeId) {
          _inconsistent(
            'Field ${_describe(field)} is ${field.type.wireName}, which implies '
            'section $expectedTypeId, not $typeId.',
          );
        }
        final isInline = layoutType.isInline;
        if (isInline != _inlineTypes.contains(field.type)) {
          _inconsistent(
            'Field ${_describe(field)} has type ${field.type.wireName}, which '
            'does not match the ${layoutType.label} record kind.',
          );
        }
        markFilled(index);
        keys.add(field.hash);
        values.add(isInline ? _inlineValue(field) : 0);
        fieldOrder.add(field);
      }
      cursor += section.count;
      markFilled(cursor);
      keys.add(0);
      values.add(typeId);
      cursor++;
      sectionCounts[typeId] = section.count;
    }

    final footerIndex = cursor;
    markFilled(footerIndex);
    keys.add(layout.ProgressLayout.footerKey);
    values.add(layout.ProgressLayout.footerValue);
    cursor++;
    final recordCount = cursor;

    if (fieldOrder.length != schema.fields.length) {
      _inconsistent(
        'The record table used ${fieldOrder.length} of '
        '${schema.fields.length} fields.',
      );
    }
    if (filled.length != recordCount || filled.any((value) => !value)) {
      _inconsistent('The record table has an unfilled slot.');
    }
    for (final entry in fieldsByRecord.entries) {
      if (entry.key >= footerIndex) {
        _inconsistent(
          'Field ${_describe(entry.value)} has recordIndex ${entry.key}, '
          'outside the $footerIndex field slots.',
        );
      }
    }

    if (recordCount != layout.ProgressLayout.sampleRecordCount) {
      _inconsistent(
        'The schema describes $recordCount records; the verified layout has '
        '${layout.ProgressLayout.sampleRecordCount}.',
      );
    }
    if (schema.fields.length != layout.ProgressLayout.sampleFieldCount) {
      _inconsistent(
        'The schema describes ${schema.fields.length} fields; the verified '
        'layout has ${layout.ProgressLayout.sampleFieldCount}.',
      );
    }
    final dataOffset =
        layout.ProgressLayout.recordStart +
        layout.ProgressLayout.recordSize * recordCount;
    if (dataOffset != layout.ProgressLayout.sampleDataOffset) {
      _inconsistent(
        'The computed data offset 0x${dataOffset.toRadixString(16)} is not the '
        'verified 0x'
        '${layout.ProgressLayout.sampleDataOffset.toRadixString(16)}.',
      );
    }
    if (sectionCounts.length != layout.ProgressLayout.sentinelCount) {
      _inconsistent(
        'The schema describes ${sectionCounts.length} sections; 32 are '
        'required.',
      );
    }

    return _RecordPlan._(
      fieldOrder: List<SaveFieldDef>.unmodifiable(fieldOrder),
      keys: List<int>.unmodifiable(keys),
      values: values,
      recordCount: recordCount,
      dataOffset: dataOffset,
      sectionCounts: sectionCounts,
    );
  }
}

/// A growable little-endian tail writer.
final class _TailWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  int get length => _builder.length;

  void u8(int value) {
    _builder.addByte(value);
  }

  void u16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void i64(int value) {
    final data = ByteData(8)..setInt64(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void u64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void zeros(int count) {
    if (count <= 0) {
      return;
    }
    _builder.add(Uint8List(count));
  }

  Uint8List takeBytes() => _builder.takeBytes();
}

const Map<SaveType, int> _sectionByType = <SaveType, int>{
  SaveType.boolean: 1,
  SaveType.booleanArray: 2,
  SaveType.integer: 3,
  SaveType.integerArray: 4,
  SaveType.float32: 5,
  SaveType.float32Array: 6,
  SaveType.enumeration: 7,
  SaveType.enumerationArray: 8,
  SaveType.vector3: 11,
  SaveType.string32: 15,
  SaveType.string64: 17,
  SaveType.string64Array: 18,
  SaveType.binary: 19,
  SaveType.binaryArray: 20,
  SaveType.unsignedInteger: 21,
  SaveType.unsignedIntegerArray: 22,
  SaveType.int64: 23,
  SaveType.uint64: 25,
  SaveType.uint64Array: 26,
  SaveType.wstring16Array: 28,
};

const Set<SaveType> _inlineTypes = <SaveType>{
  SaveType.boolean,
  SaveType.integer,
  SaveType.float32,
  SaveType.enumeration,
  SaveType.unsignedInteger,
};

const Set<SaveType> _tailTypes = <SaveType>{
  SaveType.booleanArray,
  SaveType.integerArray,
  SaveType.float32Array,
  SaveType.enumerationArray,
  SaveType.vector3,
  SaveType.string32,
  SaveType.string64,
  SaveType.string64Array,
  SaveType.binary,
  SaveType.binaryArray,
  SaveType.unsignedIntegerArray,
  SaveType.int64,
  SaveType.uint64,
  SaveType.uint64Array,
  SaveType.wstring16Array,
};

/// The first `Binary` field's verified sample span: 404 bytes.
///
/// The 404 bytes are the verified sample span, but the payload contents are
/// zeros because the sample bytes are unknown. This is not a claim to
/// reproduce the sample payload.
const int _firstBinarySpanLength = 404;

/// The other two `Binary` fields' verified sample span: an empty 4-byte blob.
const int _emptyBinarySpanLength = 4;

/// The number of `Binary` fields in the verified schema.
const int _binaryFieldCount = 3;

/// The samples' zero trailer after the last tail span (0x1D6F4..0x1D6FC).
const int _sampleTrailerLength = 8;

const int _wstring16SlotBytes = 32;
const int _wstring16CodeUnitsPerSlot = _wstring16SlotBytes ~/ 2;

const Map<CaptionDateField, int> _sampleCaptionDate = <CaptionDateField, int>{
  CaptionDateField.year: 2026,
  CaptionDateField.month: 1,
  CaptionDateField.day: 1,
  CaptionDateField.hour: 0,
  CaptionDateField.minute: 0,
  CaptionDateField.second: 0,
};

const List<int> _markerOnlyJpeg = <int>[0xFF, 0xD8, 0xFF, 0xD9];

/// An original 1x1 JPEG generated for Bomb Flower with Pillow (quality 90).
///
/// It is a single dark-green pixel encoded by a standard JPEG encoder, not
/// game data or game artwork. `CaptionCodec` only requires the SOI/EOI
/// markers and a length that reaches EOF.
const List<int> _defaultCaptionJpeg = <int>[
  0xff,
  0xd8,
  0xff,
  0xe0,
  0x00,
  0x10,
  0x4a,
  0x46,
  0x49,
  0x46,
  0x00,
  0x01,
  0x01,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0xff,
  0xdb,
  0x00,
  0x43,
  0x00,
  0x03,
  0x02,
  0x02,
  0x03,
  0x02,
  0x02,
  0x03,
  0x03,
  0x03,
  0x03,
  0x04,
  0x03,
  0x03,
  0x04,
  0x05,
  0x08,
  0x05,
  0x05,
  0x04,
  0x04,
  0x05,
  0x0a,
  0x07,
  0x07,
  0x06,
  0x08,
  0x0c,
  0x0a,
  0x0c,
  0x0c,
  0x0b,
  0x0a,
  0x0b,
  0x0b,
  0x0d,
  0x0e,
  0x12,
  0x10,
  0x0d,
  0x0e,
  0x11,
  0x0e,
  0x0b,
  0x0b,
  0x10,
  0x16,
  0x10,
  0x11,
  0x13,
  0x14,
  0x15,
  0x15,
  0x15,
  0x0c,
  0x0f,
  0x17,
  0x18,
  0x16,
  0x14,
  0x18,
  0x12,
  0x14,
  0x15,
  0x14,
  0xff,
  0xdb,
  0x00,
  0x43,
  0x01,
  0x03,
  0x04,
  0x04,
  0x05,
  0x04,
  0x05,
  0x09,
  0x05,
  0x05,
  0x09,
  0x14,
  0x0d,
  0x0b,
  0x0d,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0x14,
  0xff,
  0xc0,
  0x00,
  0x11,
  0x08,
  0x00,
  0x01,
  0x00,
  0x01,
  0x03,
  0x01,
  0x22,
  0x00,
  0x02,
  0x11,
  0x01,
  0x03,
  0x11,
  0x01,
  0xff,
  0xc4,
  0x00,
  0x1f,
  0x00,
  0x00,
  0x01,
  0x05,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x01,
  0x02,
  0x03,
  0x04,
  0x05,
  0x06,
  0x07,
  0x08,
  0x09,
  0x0a,
  0x0b,
  0xff,
  0xc4,
  0x00,
  0xb5,
  0x10,
  0x00,
  0x02,
  0x01,
  0x03,
  0x03,
  0x02,
  0x04,
  0x03,
  0x05,
  0x05,
  0x04,
  0x04,
  0x00,
  0x00,
  0x01,
  0x7d,
  0x01,
  0x02,
  0x03,
  0x00,
  0x04,
  0x11,
  0x05,
  0x12,
  0x21,
  0x31,
  0x41,
  0x06,
  0x13,
  0x51,
  0x61,
  0x07,
  0x22,
  0x71,
  0x14,
  0x32,
  0x81,
  0x91,
  0xa1,
  0x08,
  0x23,
  0x42,
  0xb1,
  0xc1,
  0x15,
  0x52,
  0xd1,
  0xf0,
  0x24,
  0x33,
  0x62,
  0x72,
  0x82,
  0x09,
  0x0a,
  0x16,
  0x17,
  0x18,
  0x19,
  0x1a,
  0x25,
  0x26,
  0x27,
  0x28,
  0x29,
  0x2a,
  0x34,
  0x35,
  0x36,
  0x37,
  0x38,
  0x39,
  0x3a,
  0x43,
  0x44,
  0x45,
  0x46,
  0x47,
  0x48,
  0x49,
  0x4a,
  0x53,
  0x54,
  0x55,
  0x56,
  0x57,
  0x58,
  0x59,
  0x5a,
  0x63,
  0x64,
  0x65,
  0x66,
  0x67,
  0x68,
  0x69,
  0x6a,
  0x73,
  0x74,
  0x75,
  0x76,
  0x77,
  0x78,
  0x79,
  0x7a,
  0x83,
  0x84,
  0x85,
  0x86,
  0x87,
  0x88,
  0x89,
  0x8a,
  0x92,
  0x93,
  0x94,
  0x95,
  0x96,
  0x97,
  0x98,
  0x99,
  0x9a,
  0xa2,
  0xa3,
  0xa4,
  0xa5,
  0xa6,
  0xa7,
  0xa8,
  0xa9,
  0xaa,
  0xb2,
  0xb3,
  0xb4,
  0xb5,
  0xb6,
  0xb7,
  0xb8,
  0xb9,
  0xba,
  0xc2,
  0xc3,
  0xc4,
  0xc5,
  0xc6,
  0xc7,
  0xc8,
  0xc9,
  0xca,
  0xd2,
  0xd3,
  0xd4,
  0xd5,
  0xd6,
  0xd7,
  0xd8,
  0xd9,
  0xda,
  0xe1,
  0xe2,
  0xe3,
  0xe4,
  0xe5,
  0xe6,
  0xe7,
  0xe8,
  0xe9,
  0xea,
  0xf1,
  0xf2,
  0xf3,
  0xf4,
  0xf5,
  0xf6,
  0xf7,
  0xf8,
  0xf9,
  0xfa,
  0xff,
  0xc4,
  0x00,
  0x1f,
  0x01,
  0x00,
  0x03,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x01,
  0x02,
  0x03,
  0x04,
  0x05,
  0x06,
  0x07,
  0x08,
  0x09,
  0x0a,
  0x0b,
  0xff,
  0xc4,
  0x00,
  0xb5,
  0x11,
  0x00,
  0x02,
  0x01,
  0x02,
  0x04,
  0x04,
  0x03,
  0x04,
  0x07,
  0x05,
  0x04,
  0x04,
  0x00,
  0x01,
  0x02,
  0x77,
  0x00,
  0x01,
  0x02,
  0x03,
  0x11,
  0x04,
  0x05,
  0x21,
  0x31,
  0x06,
  0x12,
  0x41,
  0x51,
  0x07,
  0x61,
  0x71,
  0x13,
  0x22,
  0x32,
  0x81,
  0x08,
  0x14,
  0x42,
  0x91,
  0xa1,
  0xb1,
  0xc1,
  0x09,
  0x23,
  0x33,
  0x52,
  0xf0,
  0x15,
  0x62,
  0x72,
  0xd1,
  0x0a,
  0x16,
  0x24,
  0x34,
  0xe1,
  0x25,
  0xf1,
  0x17,
  0x18,
  0x19,
  0x1a,
  0x26,
  0x27,
  0x28,
  0x29,
  0x2a,
  0x35,
  0x36,
  0x37,
  0x38,
  0x39,
  0x3a,
  0x43,
  0x44,
  0x45,
  0x46,
  0x47,
  0x48,
  0x49,
  0x4a,
  0x53,
  0x54,
  0x55,
  0x56,
  0x57,
  0x58,
  0x59,
  0x5a,
  0x63,
  0x64,
  0x65,
  0x66,
  0x67,
  0x68,
  0x69,
  0x6a,
  0x73,
  0x74,
  0x75,
  0x76,
  0x77,
  0x78,
  0x79,
  0x7a,
  0x82,
  0x83,
  0x84,
  0x85,
  0x86,
  0x87,
  0x88,
  0x89,
  0x8a,
  0x92,
  0x93,
  0x94,
  0x95,
  0x96,
  0x97,
  0x98,
  0x99,
  0x9a,
  0xa2,
  0xa3,
  0xa4,
  0xa5,
  0xa6,
  0xa7,
  0xa8,
  0xa9,
  0xaa,
  0xb2,
  0xb3,
  0xb4,
  0xb5,
  0xb6,
  0xb7,
  0xb8,
  0xb9,
  0xba,
  0xc2,
  0xc3,
  0xc4,
  0xc5,
  0xc6,
  0xc7,
  0xc8,
  0xc9,
  0xca,
  0xd2,
  0xd3,
  0xd4,
  0xd5,
  0xd6,
  0xd7,
  0xd8,
  0xd9,
  0xda,
  0xe2,
  0xe3,
  0xe4,
  0xe5,
  0xe6,
  0xe7,
  0xe8,
  0xe9,
  0xea,
  0xf2,
  0xf3,
  0xf4,
  0xf5,
  0xf6,
  0xf7,
  0xf8,
  0xf9,
  0xfa,
  0xff,
  0xda,
  0x00,
  0x0c,
  0x03,
  0x01,
  0x00,
  0x02,
  0x11,
  0x03,
  0x11,
  0x00,
  0x3f,
  0x00,
  0xf8,
  0xca,
  0x8a,
  0x28,
  0xaf,
  0x08,
  0xf9,
  0xc3,
  0xff,
  0xd9,
];

String _describe(SaveFieldDef field) {
  final hash = field.hash;
  final hashText = hash < 0
      ? '-0x${(-hash).toRadixString(16)}'
      : layout.ProgressLayout.keyHex(hash);
  final name = field.name;
  return name == null ? 'hash $hashText' : '$name ($hashText)';
}

Never _inconsistent(String message) {
  throw NewSaveBuildException(message, code: 'schema_inconsistent');
}

bool _boolDefault(SaveFieldDef field) {
  final value = field.defaultValue;
  if (value is! bool) {
    _inconsistent('Field ${_describe(field)} default is not a bool: $value.');
  }
  return value;
}

int _intDefault(SaveFieldDef field) {
  final value = field.defaultValue;
  if (value is! int) {
    _inconsistent(
      'Field ${_describe(field)} default is not an integer: $value.',
    );
  }
  return value;
}

double _doubleDefault(SaveFieldDef field) {
  final value = field.defaultValue;
  if (value is! num) {
    _inconsistent('Field ${_describe(field)} default is not a number: $value.');
  }
  return value.toDouble();
}

String _stringDefault(SaveFieldDef field) {
  final value = field.defaultValue;
  if (value is! String) {
    _inconsistent('Field ${_describe(field)} default is not a string: $value.');
  }
  return value;
}

int _arrayLen(SaveFieldDef field) {
  final value = field.arrayLen;
  if (value == null) {
    _inconsistent(
      'Field ${_describe(field)} is ${field.type.wireName} but has no '
      'arrayLen.',
    );
  }
  if (value < 0) {
    _inconsistent('Field ${_describe(field)} has negative arrayLen $value.');
  }
  return value;
}

int _inlineValue(SaveFieldDef field) {
  switch (field.type) {
    case SaveType.boolean:
      return _boolDefault(field) ? 1 : 0;
    case SaveType.integer:
      final value = _intDefault(field);
      _checkInt32(value, field);
      return value & 0xFFFFFFFF;
    case SaveType.float32:
      return _float32Bits(
        _doubleDefault(field),
        code: 'schema_inconsistent',
        what: 'Field ${_describe(field)} default',
      );
    case SaveType.enumeration:
      return _enumDefault(field);
    case SaveType.unsignedInteger:
      final value = _intDefault(field);
      _checkUint32(value, field);
      return value;
    default:
      _inconsistent(
        'Field ${_describe(field)} is ${field.type.wireName}, which is not an '
        'inline scalar.',
      );
  }
}

int _enumDefault(SaveFieldDef field) {
  final value = _intDefault(field);
  _checkUint32(value, field);
  final table = field.enumTable;
  if (table == null) {
    _inconsistent(
      'Field ${_describe(field)} is ${field.type.wireName} but has no enum '
      'table.',
    );
  }
  if (table.member(value) == null) {
    _inconsistent(
      'Field ${_describe(field)} default '
      '${layout.ProgressLayout.keyHex(value)} is not a member of enum table '
      '${table.key}.',
    );
  }
  return value;
}

SavePosition _vector3Default(SaveFieldDef field) {
  final value = field.defaultValue;
  if (value is! Map<Object?, Object?>) {
    _inconsistent(
      'Field ${_describe(field)} Vector3 default is not a map: $value.',
    );
  }
  final x = value['x'];
  final y = value['y'];
  final z = value['z'];
  if (x is! num || y is! num || z is! num) {
    _inconsistent(
      'Field ${_describe(field)} Vector3 default must have numeric x, y and '
      'z: $value.',
    );
  }
  return SavePosition(x: x.toDouble(), y: y.toDouble(), z: z.toDouble());
}

void _checkInt32(int value, SaveFieldDef field) {
  if (value < -0x80000000 || value > 0x7FFFFFFF) {
    _inconsistent(
      'Field ${_describe(field)} default $value does not fit a signed 32-bit '
      'integer.',
    );
  }
}

void _checkUint32(int value, SaveFieldDef field) {
  if (value < 0 || value > 0xFFFFFFFF) {
    _inconsistent(
      'Field ${_describe(field)} default $value does not fit an unsigned '
      '32-bit integer.',
    );
  }
}

void _checkUint64(int value, SaveFieldDef field) {
  if (value < 0) {
    _inconsistent(
      'Field ${_describe(field)} default $value does not fit an unsigned '
      '64-bit integer.',
    );
  }
}

int _float32Bits(double value, {required String code, required String what}) {
  if (!value.isFinite) {
    throw NewSaveBuildException('$what is not finite: $value.', code: code);
  }
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  if (!data.getFloat32(0, Endian.little).isFinite) {
    throw NewSaveBuildException(
      '$what is outside the finite binary32 range: $value.',
      code: code,
    );
  }
  return data.getUint32(0, Endian.little);
}

void _writeAsciiSlot(
  _TailWriter tail,
  String value,
  int slot,
  SaveFieldDef field,
) {
  final units = value.codeUnits;
  if (units.length > slot - 1) {
    throw NewSaveBuildException(
      'Field ${_describe(field)} default string is ${units.length} code '
      'units; a $slot-byte slot holds at most ${slot - 1} plus a NUL.',
      code: 'string_too_long',
    );
  }
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit == 0 || unit > 0x7e) {
      throw NewSaveBuildException(
        'Field ${_describe(field)} default string has code unit '
        '0x${unit.toRadixString(16).padLeft(2, '0')} at index $i; only '
        '0x01..0x7e are storable.',
        code: 'string_not_encodable',
      );
    }
  }
  for (final unit in units) {
    tail.u8(unit);
  }
  tail.zeros(slot - units.length);
}

void _writeWString16Slot(_TailWriter tail, List<int> units) {
  for (final unit in units) {
    tail.u16(unit);
  }
  tail.zeros((_wstring16CodeUnitsPerSlot - units.length) * 2);
}
