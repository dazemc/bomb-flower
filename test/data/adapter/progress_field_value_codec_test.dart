import 'dart:typed_data';

import 'package:bomb_flower/data/adapter/progress_field_value_codec.dart';
import 'package:bomb_flower/domain/core/byte_region.dart';
import 'package:bomb_flower/domain/core/field_metadata.dart';
import 'package:bomb_flower/domain/core/field_value.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:flutter_test/flutter_test.dart';

const _codec = ProgressFieldValueCodec();

FieldDescriptor _descriptor(
  FieldKind kind, {
  int offset = 0,
  required int length,
  num? min,
  Map<String, int> choices = const <String, int>{},
}) {
  return FieldDescriptor(
    const FieldId('test.field'),
    const SaveSlotId('slot1'),
    'Test field',
    kind,
    ByteSpan(offset, length),
    FieldConfidence.verified,
    'test',
    min: min,
    choices: choices,
  );
}

ByteRegion _content(List<int> bytes) => ByteRegion.fromBytes(bytes);

Uint8List _le32(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _le64(int value) {
  final data = ByteData(8)..setInt64(0, value, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _float32(double value) {
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _padded(Uint8List bytes, int length) {
  final out = Uint8List(length)..setRange(0, bytes.length, bytes);
  return out;
}

void main() {
  group('boolean', () {
    test('1 is true', () {
      final content = _content(_le32(1));
      expect(
        _codec.decode(_descriptor(FieldKind.boolean, length: 4), content),
        const BoolValue(true),
      );
    });

    test('0 is false', () {
      final content = _content(_le32(0));
      expect(
        _codec.decode(_descriptor(FieldKind.boolean, length: 4), content),
        const BoolValue(false),
      );
    });

    test('2 is not a boolean', () {
      final content = _content(_le32(2));
      expect(
        _codec.decode(_descriptor(FieldKind.boolean, length: 4), content),
        isNull,
      );
    });
  });

  group('integer', () {
    test('signed when min is negative', () {
      final content = _content(_le32(0xFFFFFFF6));
      expect(
        _codec.decode(
          _descriptor(FieldKind.integer, length: 4, min: -2147483648),
          content,
        ),
        const IntValue(-10),
      );
    });

    test('unsigned when min is not negative', () {
      final content = _content(_le32(0xFFFFFFF6));
      expect(
        _codec.decode(
          _descriptor(FieldKind.integer, length: 4, min: 0),
          content,
        ),
        const IntValue(4294967286),
      );
    });

    test('8-byte integer keeps the 64-bit bit pattern', () {
      final negative = _content(_le64(-10));
      expect(
        _codec.decode(
          _descriptor(FieldKind.integer, length: 8, min: -9223372036854775808),
          negative,
        ),
        const IntValue(-10),
      );

      final positive = _content(_le64(1234567890123));
      expect(
        _codec.decode(
          _descriptor(FieldKind.integer, length: 8, min: 0),
          positive,
        ),
        const IntValue(1234567890123),
      );
    });

    test('float-shaped integer decodes to its raw bits', () {
      final content = _content(_float32(1.5));
      expect(
        _codec.decode(
          _descriptor(FieldKind.integer, length: 4, min: 0),
          content,
        ),
        const IntValue(0x3FC00000),
      );
    });

    test('unsupported width is refused', () {
      final content = _content(<int>[0x01, 0x00]);
      expect(
        _codec.decode(_descriptor(FieldKind.integer, length: 2), content),
        isNull,
      );
    });
  });

  group('enumeration', () {
    test('known hash maps to its name', () {
      final content = _content(_le32(0x11223344));
      expect(
        _codec.decode(
          _descriptor(
            FieldKind.enumeration,
            length: 4,
            choices: const <String, int>{'gold': 0x11223344},
          ),
          content,
        ),
        const EnumValue(key: 'gold', rawValue: 0x11223344),
      );
    });

    test('unknown hash keeps the raw value with an empty key', () {
      final content = _content(_le32(0xDEADBEEF));
      expect(
        _codec.decode(
          _descriptor(
            FieldKind.enumeration,
            length: 4,
            choices: const <String, int>{'gold': 0x11223344},
          ),
          content,
        ),
        const EnumValue(key: '', rawValue: 0xDEADBEEF),
      );
    });
  });

  group('string', () {
    test('32-byte span decodes up to the first NUL', () {
      final content = _content(
        _padded(Uint8List.fromList(<int>[...'Iron Sword'.codeUnits, 0]), 32),
      );
      expect(
        _codec.decode(_descriptor(FieldKind.string, length: 32), content),
        const StringValue('Iron Sword'),
      );
    });

    test('no NUL in the span is refused', () {
      final content = _content(
        _padded(Uint8List(32)..fillRange(0, 32, 0x41), 32),
      );
      expect(
        _codec.decode(_descriptor(FieldKind.string, length: 32), content),
        isNull,
      );
    });

    test('non-printable byte before the NUL is refused', () {
      final content = _content(
        _padded(Uint8List.fromList(<int>[0x41, 0x42, 0x01, 0x00]), 32),
      );
      expect(
        _codec.decode(_descriptor(FieldKind.string, length: 32), content),
        isNull,
      );
    });
  });

  group('vector', () {
    test('12-byte span decodes three little-endian float32 values', () {
      final content = _content(
        Uint8List.fromList(<int>[
          ..._float32(1.5),
          ..._float32(-2.25),
          ..._float32(3),
        ]),
      );
      expect(
        _codec.decode(_descriptor(FieldKind.vector, length: 12), content),
        VectorValue(<double>[1.5, -2.25, 3]),
      );
    });
  });

  group('refusals', () {
    test('span past the end of the content is null', () {
      final content = _content(_le32(1));
      expect(
        _codec.decode(
          _descriptor(FieldKind.integer, offset: 2, length: 4),
          content,
        ),
        isNull,
      );
    });

    test('list kind is null', () {
      final content = _content(_le32(1));
      expect(
        _codec.decode(_descriptor(FieldKind.list, length: 4), content),
        isNull,
      );
    });
  });
}
