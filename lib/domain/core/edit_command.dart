/// Validated, atomic edit commands.
library;

import 'dart:typed_data';

import 'byte_region.dart';
import 'field_metadata.dart';
import 'identity.dart';

/// A refused field write.
///
/// The engine throws this before creating a patch, bumping a revision, or
/// touching history. There is intentionally no clamping or truncation path.
final class FieldWriteException implements Exception {
  /// Creates a refusal with a stable [code] and human-readable [message].
  const FieldWriteException(this.code, this.message, {this.field, this.value});

  /// Stable machine-readable code, also reported by validation where relevant.
  final String code;

  /// Human-readable explanation.
  final String message;

  /// The field being written, when known.
  final FieldId? field;

  /// The rejected value, when useful for diagnostics.
  final Object? value;

  @override
  String toString() {
    final where = field == null ? '' : ' (${field!.value})';
    return 'FieldWriteException[$code]$where: $message';
  }
}

/// Stable [FieldWriteException.code] values.
abstract final class FieldWriteCodes {
  /// The field id is not present in the layout.
  static const String unknown = 'field.unknown';

  /// The descriptor and command disagree, or the slot document is absent.
  static const String mismatch = 'field.mismatch';

  /// The field is inferred, unverified, or read-only.
  static const String notEditable = 'field.not_editable';

  /// The declared span is empty, negative, or outside the slot.
  static const String spanInvalid = 'field.span_invalid';

  /// The value is negative, outside `[min, max]`, or wider than the span.
  static const String outOfRange = 'field.out_of_range';

  /// The enumeration key is not in the descriptor's choices.
  static const String unknownEnum = 'field.unknown_enum';

  /// The bit index is outside `span.length * 8`.
  static const String bitOutOfRange = 'field.bit_out_of_range';

  /// A `SetBytes` target is not fully inside the declared field span.
  static const String targetOutsideSpan = 'field.target_outside_span';

  /// A byte payload length does not match its target span.
  static const String lengthMismatch = 'field.length_mismatch';

  /// The command does not apply to the descriptor's field kind.
  static const String kindMismatch = 'field.kind_mismatch';
}

/// A semantic edit to one field.
///
/// Commands are values. [validate] checks everything a write needs against the
/// descriptor and current bytes; [encodePatch] validates first, then returns
/// the exact patch. Neither method mutates the region.
sealed class EditCommand {
  /// Creates a command targeting [field].
  const EditCommand(this.field);

  /// The field this command edits.
  final FieldId field;

  /// A short human-readable description for the audit log.
  String get description;

  /// Throws [FieldWriteException] if the command cannot be applied.
  void validate(FieldDescriptor descriptor, ByteRegion content);

  /// Validates, then encodes exactly the bytes this command changes.
  BytePatch encodePatch(FieldDescriptor descriptor, ByteRegion content);

  void _checkCommon(FieldDescriptor descriptor, ByteRegion content) {
    if (descriptor.id != field) {
      throw FieldWriteException(
        FieldWriteCodes.mismatch,
        'Descriptor ${descriptor.id.value} does not match command $field',
        field: field,
      );
    }
    if (!descriptor.isEditable) {
      throw FieldWriteException(
        FieldWriteCodes.notEditable,
        'Field ${field.value} is ${descriptor.confidence.name}'
        '${descriptor.readOnly ? ' or read-only' : ''}',
        field: field,
      );
    }
    if (!descriptor.span.isValid ||
        descriptor.span.length == 0 ||
        descriptor.span.end > content.length) {
      throw FieldWriteException(
        FieldWriteCodes.spanInvalid,
        'Field span ${descriptor.span} is outside ${content.length} bytes',
        field: field,
      );
    }
  }

  void _checkNumericKind(FieldDescriptor descriptor) {
    const numeric = <FieldKind>{
      FieldKind.integer,
      FieldKind.enumeration,
      FieldKind.boolean,
      FieldKind.bitfield,
    };
    if (!numeric.contains(descriptor.kind)) {
      throw FieldWriteException(
        FieldWriteCodes.kindMismatch,
        'Field ${field.value} is ${descriptor.kind.name}, not numeric',
        field: field,
      );
    }
  }

  void _checkValue(FieldDescriptor descriptor, int value) {
    if (value < 0) {
      throw FieldWriteException(
        FieldWriteCodes.outOfRange,
        'Value $value is negative; layouts declare unsigned bounds only',
        field: field,
        value: value,
      );
    }
    final min = descriptor.min;
    if (min != null && value < min) {
      throw FieldWriteException(
        FieldWriteCodes.outOfRange,
        'Value $value is below the declared minimum $min',
        field: field,
        value: value,
      );
    }
    final max = descriptor.max;
    if (max != null && value > max) {
      throw FieldWriteException(
        FieldWriteCodes.outOfRange,
        'Value $value is above the declared maximum $max',
        field: field,
        value: value,
      );
    }
    final width = descriptor.span.length;
    if (width > 8) {
      throw FieldWriteException(
        FieldWriteCodes.spanInvalid,
        'A scalar needs at most 8 bytes; span is $width',
        field: field,
        value: value,
      );
    }
    if (width < 8) {
      final limit = 1 << (width * 8);
      if (value >= limit) {
        throw FieldWriteException(
          FieldWriteCodes.outOfRange,
          'Value $value does not fit in $width byte(s)',
          field: field,
          value: value,
        );
      }
    }
  }

  Uint8List _encodeUnsigned(
    FieldDescriptor descriptor,
    ByteSpan span,
    int value,
  ) {
    final out = Uint8List(span.length);
    for (var i = 0; i < span.length; i++) {
      final shift = i * 8;
      final byte = (value >> shift) & 0xff;
      final target = descriptor.endianness == Endian.big
          ? span.length - 1 - i
          : i;
      out[target] = byte;
    }
    return out;
  }
}

/// Sets the whole numeric value of a field.
final class const SetScalar(super.field, final int value) extends EditCommand {
  @override
  String get description => 'SetScalar(${field.value}) = $value';

  @override
  void validate(FieldDescriptor descriptor, ByteRegion content) {
    _checkCommon(descriptor, content);
    _checkNumericKind(descriptor);
    _checkValue(descriptor, value);
    if (descriptor.kind == FieldKind.boolean && value != 0 && value != 1) {
      throw FieldWriteException(
        FieldWriteCodes.outOfRange,
        'A boolean field accepts 0 or 1, not $value',
        field: field,
        value: value,
      );
    }
  }

  @override
  BytePatch encodePatch(FieldDescriptor descriptor, ByteRegion content) {
    validate(descriptor, content);
    return BytePatch(
      descriptor.span,
      _encodeUnsigned(descriptor, descriptor.span, value),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SetScalar && other.field == field && other.value == value;

  @override
  int get hashCode => Object.hash(field, value);
}

/// Sets one bit inside a field span.
///
/// Bit 0 is the least significant bit of the first byte of the span; bit 7 is
/// the most significant bit of that byte. This is a generic byte convention,
/// not a game-specific meaning.
final class const SetBit(super.field, final int bit, final bool value)
    extends EditCommand {
  @override
  String get description => 'SetBit(${field.value})[$bit] = $value';

  @override
  void validate(FieldDescriptor descriptor, ByteRegion content) {
    _checkCommon(descriptor, content);
    _checkNumericKind(descriptor);
    final bitCount = descriptor.span.length * 8;
    if (bit < 0 || bit >= bitCount) {
      throw FieldWriteException(
        FieldWriteCodes.bitOutOfRange,
        'Bit $bit is outside 0..${bitCount - 1}',
        field: field,
        value: bit,
      );
    }
  }

  @override
  BytePatch encodePatch(FieldDescriptor descriptor, ByteRegion content) {
    validate(descriptor, content);
    final byteIndex = bit ~/ 8;
    final mask = 1 << (bit % 8);
    final absolute = descriptor.span.offset + byteIndex;
    final current = content.readByte(absolute);
    final next = value ? (current | mask) : (current & ~mask);
    return BytePatch(ByteSpan(absolute, 1), <int>[next & 0xff]);
  }

  @override
  bool operator ==(Object other) =>
      other is SetBit &&
      other.field == field &&
      other.bit == bit &&
      other.value == value;

  @override
  int get hashCode => Object.hash(field, bit, value);
}

/// Selects an enumeration key and writes its raw wire value.
final class const SetEnum(super.field, final String key) extends EditCommand {
  @override
  String get description => 'SetEnum(${field.value}) = $key';

  @override
  void validate(FieldDescriptor descriptor, ByteRegion content) {
    _checkCommon(descriptor, content);
    _checkNumericKind(descriptor);
    final raw = descriptor.choices[key];
    if (raw == null) {
      throw FieldWriteException(
        FieldWriteCodes.unknownEnum,
        'Key "$key" is not one of ${descriptor.choices.keys.join(', ')}',
        field: field,
        value: key,
      );
    }
    _checkValue(descriptor, raw);
  }

  @override
  BytePatch encodePatch(FieldDescriptor descriptor, ByteRegion content) {
    validate(descriptor, content);
    final raw = descriptor.choices[key]!;
    return BytePatch(
      descriptor.span,
      _encodeUnsigned(descriptor, descriptor.span, raw),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SetEnum && other.field == field && other.key == key;

  @override
  int get hashCode => Object.hash(field, key);
}

/// Writes raw bytes into a subrange fully contained by the field span.
///
/// This is the escape hatch for strings, vectors, positions, lists, and
/// research tools. The layout still owns the outer span and length.
final class SetBytes extends EditCommand {
  /// Creates a byte write; [bytes] is defensively copied.
  SetBytes(super.field, {required this.target, required List<int> bytes})
    : bytes = Uint8List.fromList(bytes);

  /// Absolute target inside the slot; must be contained by the field span.
  final ByteSpan target;

  /// Replacement bytes; length must equal [target]'s length.
  final Uint8List bytes;

  @override
  String get description =>
      'SetBytes(${field.value}) at 0x${target.offset.toRadixString(16)} '
      '(${bytes.length} bytes)';

  @override
  void validate(FieldDescriptor descriptor, ByteRegion content) {
    _checkCommon(descriptor, content);
    if (!target.isValid) {
      throw FieldWriteException(
        FieldWriteCodes.targetOutsideSpan,
        'Target span $target is invalid',
        field: field,
      );
    }
    if (!descriptor.span.contains(target)) {
      throw FieldWriteException(
        FieldWriteCodes.targetOutsideSpan,
        'Target $target is not inside field span ${descriptor.span}',
        field: field,
      );
    }
    if (bytes.length != target.length) {
      throw FieldWriteException(
        FieldWriteCodes.lengthMismatch,
        '${bytes.length} byte(s) do not fit target length ${target.length}',
        field: field,
        value: bytes.length,
      );
    }
  }

  @override
  BytePatch encodePatch(FieldDescriptor descriptor, ByteRegion content) {
    validate(descriptor, content);
    return BytePatch(target, bytes);
  }

  @override
  bool operator ==(Object other) =>
      other is SetBytes &&
      other.field == field &&
      other.target == target &&
      _bytesEqual(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(field, target, Object.hashAll(bytes));
}

bool _bytesEqual(Uint8List a, Uint8List b) {
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
