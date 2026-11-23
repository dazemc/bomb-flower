/// Layout-specific field decoding for progress save data.
library;

import 'dart:typed_data';

import '../../domain/core/byte_region.dart';
import '../../domain/core/field_metadata.dart';
import '../../domain/core/field_value.dart';
import '../../domain/engine/ports.dart';

/// Decodes the progress layout's field kinds from raw save bytes.
///
/// Every width is fixed by the layout: booleans and enumerations are four
/// bytes, integers are four or eight, strings are 16/32/64 ASCII bytes, and
/// vectors and positions are three little-endian float32 values. Anything
/// outside those shapes returns `null` so the field keeps no decoded view
/// rather than a guessed one. Byte order is little-endian regardless of
/// [FieldDescriptor.endianness], which describes edit encoding, not this
/// layout's wire format.
final class ProgressFieldValueCodec implements FieldValueCodec {
  /// Creates a progress codec.
  const ProgressFieldValueCodec();

  @override
  FieldValue? decode(FieldDescriptor descriptor, ByteRegion content) {
    final span = descriptor.span;
    if (!span.isValid || span.length <= 0 || span.end > content.length) {
      return null;
    }
    return switch (descriptor.kind) {
      FieldKind.boolean => _decodeBoolean(span, content),
      FieldKind.integer => _decodeInteger(descriptor, content),
      FieldKind.enumeration => _decodeEnumeration(descriptor, content),
      FieldKind.string => _decodeString(span, content),
      FieldKind.vector || FieldKind.position => _decodeVector(span, content),
      FieldKind.bitfield || FieldKind.list => null,
    };
  }

  FieldValue? _decodeBoolean(ByteSpan span, ByteRegion content) {
    if (span.length != 4) {
      return null;
    }
    return switch (content.readU32LE(span.offset)) {
      0 => const BoolValue(false),
      1 => const BoolValue(true),
      _ => null,
    };
  }

  FieldValue? _decodeInteger(FieldDescriptor descriptor, ByteRegion content) {
    final span = descriptor.span;
    final signed = descriptor.min != null && descriptor.min! < 0;
    switch (span.length) {
      case 4:
        final raw = content.readU32LE(span.offset);
        return IntValue(signed ? raw.toSigned(32) : raw);
      case 8:
        // Dart's `int` is 64-bit two's complement, so the signed and unsigned
        // 64-bit interpretations share one bit pattern; no branch is needed.
        final bits = ByteData.sublistView(content.slice(span))
            .getInt64(0, Endian.little);
        return IntValue(bits);
      default:
        return null;
    }
  }

  FieldValue? _decodeEnumeration(
    FieldDescriptor descriptor,
    ByteRegion content,
  ) {
    final span = descriptor.span;
    if (span.length != 4) {
      return null;
    }
    final raw = content.readU32LE(span.offset);
    for (final choice in descriptor.choices.entries) {
      if (choice.value == raw) {
        return EnumValue(key: choice.key, rawValue: raw);
      }
    }
    return EnumValue(key: '', rawValue: raw);
  }

  FieldValue? _decodeString(ByteSpan span, ByteRegion content) {
    if (span.length != 16 && span.length != 32 && span.length != 64) {
      return null;
    }
    final bytes = content.slice(span);
    final terminator = bytes.indexOf(0);
    if (terminator < 0) {
      return null;
    }
    for (var i = 0; i < terminator; i++) {
      final byte = bytes[i];
      if (byte < 0x20 || byte > 0x7E) {
        return null;
      }
    }
    return StringValue(String.fromCharCodes(bytes, 0, terminator));
  }

  FieldValue? _decodeVector(ByteSpan span, ByteRegion content) {
    if (span.length != 12) {
      return null;
    }
    final data = ByteData.sublistView(content.slice(span));
    return VectorValue(<double>[
      data.getFloat32(0, Endian.little),
      data.getFloat32(4, Endian.little),
      data.getFloat32(8, Endian.little),
    ]);
  }
}
