/// Format-agnostic numeric field decoding.
library;

import 'dart:typed_data';

import '../core/byte_region.dart';
import '../core/field_metadata.dart';
import '../core/field_value.dart';
import 'ports.dart';

/// Decodes integer, enumeration, boolean, and bitfield descriptors.
///
/// Strings, vectors, positions, and lists need layout-specific semantics and
/// are left to a codec supplied by the layout layer. Widths above eight bytes,
/// and full 64-bit unsigned values with the top bit set, are also left to a
/// dedicated codec rather than guessing signedness.
final class NumericFieldValueCodec implements FieldValueCodec {
  /// Creates a numeric codec.
  const NumericFieldValueCodec();

  @override
  FieldValue? decode(FieldDescriptor descriptor, ByteRegion content) {
    final span = descriptor.span;
    if (!span.isValid || span.length <= 0 || span.end > content.length) {
      return null;
    }
    final raw = readUnsigned(content, span, descriptor.endianness);
    if (raw == null) {
      return null;
    }
    return switch (descriptor.kind) {
      FieldKind.integer => IntValue(raw),
      FieldKind.enumeration => EnumValue(
        key: _keyFor(descriptor.choices, raw),
        rawValue: raw,
      ),
      FieldKind.boolean => BoolValue(raw != 0),
      FieldKind.bitfield => BitfieldValue(raw),
      FieldKind.string ||
      FieldKind.vector ||
      FieldKind.position ||
      FieldKind.list => null,
    };
  }
}

/// Reads an unsigned integer from [span] in [endianness] order.
///
/// Returns `null` for spans wider than eight bytes or when the top bit of a
/// 64-bit value is set, because Dart's `int` is signed and the engine refuses
/// to invent signedness.
int? readUnsigned(ByteRegion content, ByteSpan span, Endian endianness) {
  final width = span.length;
  if (width <= 0 || width > 8) {
    return null;
  }
  if (endianness == Endian.big) {
    if (width == 8 && content.readByte(span.offset) >= 0x80) {
      return null;
    }
    var value = 0;
    for (var i = 0; i < width; i++) {
      value = (value << 8) | content.readByte(span.offset + i);
    }
    return value;
  }
  if (width == 8 && content.readByte(span.end - 1) >= 0x80) {
    return null;
  }
  var value = 0;
  for (var i = width - 1; i >= 0; i--) {
    value = (value << 8) | content.readByte(span.offset + i);
  }
  return value;
}

String _keyFor(Map<String, int> choices, int raw) {
  for (final entry in choices.entries) {
    if (entry.value == raw) {
      return entry.key;
    }
  }
  return '';
}
