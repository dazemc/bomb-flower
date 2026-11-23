import 'dart:typed_data';

import 'package:bomb_flower/domain/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Matcher throwsFieldWrite(String code) => throwsA(
  isA<FieldWriteException>().having((error) => error.code, 'code', code),
);

void main() {
  late ByteRegion content;

  setUp(() {
    content = ByteRegion.fromBytes(Uint8List(256));
  });

  group('SetScalar', () {
    test('encodes big-endian into exactly the declared span', () {
      final command = const SetScalar(healthId, 42);
      final patch = command.encodePatch(healthField(), content);

      expect(patch.span, const ByteSpan(10, 2));
      expect(patch.bytes, <int>[0x00, 0x2a]);
    });

    test('honours little-endian descriptors', () {
      final patch = const SetScalar(
        healthId,
        100,
      ).encodePatch(healthField(endianness: Endian.little), content);

      expect(patch.bytes, <int>[0x64, 0x00]);
    });

    test('rejects values outside min and max', () {
      expect(
        () => const SetScalar(healthId, 101).validate(healthField(), content),
        throwsFieldWrite(FieldWriteCodes.outOfRange),
      );
      expect(
        () => const SetScalar(healthId, -1).validate(healthField(), content),
        throwsFieldWrite(FieldWriteCodes.outOfRange),
      );
    });

    test('rejects values that do not fit the span width', () {
      const narrow = FieldDescriptor(
        healthId,
        progressSlot,
        'Narrow',
        FieldKind.integer,
        ByteSpan(10, 1),
        FieldConfidence.verified,
        'test',
      );
      expect(
        () => const SetScalar(healthId, 256).validate(narrow, content),
        throwsFieldWrite(FieldWriteCodes.outOfRange),
      );
      const wide = FieldDescriptor(
        healthId,
        progressSlot,
        'Wide',
        FieldKind.integer,
        ByteSpan(10, 9),
        FieldConfidence.verified,
        'test',
      );
      expect(
        () => const SetScalar(healthId, 1).validate(wide, content),
        throwsFieldWrite(FieldWriteCodes.spanInvalid),
      );
    });

    test('rejects non-editable fields', () {
      expect(
        () => const SetScalar(
          healthId,
          1,
        ).validate(healthField(confidence: FieldConfidence.inferred), content),
        throwsFieldWrite(FieldWriteCodes.notEditable),
      );
      expect(
        () => const SetScalar(
          healthId,
          1,
        ).validate(healthField(readOnly: true), content),
        throwsFieldWrite(FieldWriteCodes.notEditable),
      );
    });

    test('rejects non-numeric kinds and invalid spans', () {
      expect(
        () => const SetScalar(nameId, 1).validate(nameField, content),
        throwsFieldWrite(FieldWriteCodes.kindMismatch),
      );
      expect(
        () => const SetScalar(healthId, 1).validate(healthField(), content),
        returnsNormally,
      );
      final short = ByteRegion.fromBytes(<int>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      expect(
        () => const SetScalar(healthId, 1).validate(healthField(), short),
        throwsFieldWrite(FieldWriteCodes.spanInvalid),
      );
    });

    test('boolean values are exactly 0 or 1', () {
      const booleanField = FieldDescriptor(
        FieldId('flag'),
        progressSlot,
        'Flag',
        FieldKind.boolean,
        ByteSpan(20, 1),
        FieldConfidence.verified,
        'test',
      );
      expect(
        () =>
            const SetScalar(FieldId('flag'), 2).validate(booleanField, content),
        throwsFieldWrite(FieldWriteCodes.outOfRange),
      );
      expect(
        const SetScalar(
          FieldId('flag'),
          1,
        ).encodePatch(booleanField, content).bytes,
        <int>[1],
      );
    });

    test('no-op encoding still returns a valid patch', () {
      final patch = const SetScalar(
        healthId,
        0,
      ).encodePatch(healthField(), content);
      expect(patch.bytes, <int>[0, 0]);
    });
  });

  group('SetBit', () {
    test('sets bit 0 as the least significant bit of the first byte', () {
      final patch = const SetBit(
        flagsId,
        0,
        true,
      ).encodePatch(flagsField, content);

      expect(patch.span, const ByteSpan(20, 1));
      expect(patch.bytes, <int>[0x01]);
    });

    test('sets bit 7 as 0x80 and clears by mask', () {
      expect(
        const SetBit(flagsId, 7, true).encodePatch(flagsField, content).bytes,
        <int>[0x80],
      );
      final full = ByteRegion.fromBytes(Uint8List(256)..[20] = 0xff);
      expect(
        const SetBit(flagsId, 0, false).encodePatch(flagsField, full).bytes,
        <int>[0xfe],
      );
    });

    test('addresses bits across multiple bytes', () {
      const wide = FieldDescriptor(
        flagsId,
        progressSlot,
        'Wide flags',
        FieldKind.bitfield,
        ByteSpan(20, 2),
        FieldConfidence.verified,
        'test',
      );
      final patch = const SetBit(flagsId, 9, true).encodePatch(wide, content);

      expect(patch.span, const ByteSpan(21, 1));
      expect(patch.bytes, <int>[0x02]);
    });

    test('rejects out-of-range and negative bit indices', () {
      expect(
        () => const SetBit(flagsId, 8, true).validate(flagsField, content),
        throwsFieldWrite(FieldWriteCodes.bitOutOfRange),
      );
      expect(
        () => const SetBit(flagsId, -1, true).validate(flagsField, content),
        throwsFieldWrite(FieldWriteCodes.bitOutOfRange),
      );
    });
  });

  group('SetEnum', () {
    test('resolves a choice to its raw wire value', () {
      final patch = const SetEnum(
        modeId,
        'adult',
      ).encodePatch(modeField, content);

      expect(patch.span, const ByteSpan(30, 1));
      expect(patch.bytes, <int>[2]);
    });

    test('rejects unknown keys and out-of-range raw values', () {
      expect(
        () => const SetEnum(modeId, 'missing').validate(modeField, content),
        throwsFieldWrite(FieldWriteCodes.unknownEnum),
      );
      const outOfRange = FieldDescriptor(
        modeId,
        progressSlot,
        'Mode',
        FieldKind.enumeration,
        ByteSpan(30, 1),
        FieldConfidence.verified,
        'test',
        choices: <String, int>{'big': 300},
      );
      expect(
        () => const SetEnum(modeId, 'big').validate(outOfRange, content),
        throwsFieldWrite(FieldWriteCodes.outOfRange),
      );
    });
  });

  group('SetBytes', () {
    test('writes inside the declared field span', () {
      final patch = SetBytes(
        nameId,
        target: ByteSpan(40, 4),
        bytes: <int>[0x41, 0x42, 0x43, 0x00],
      ).encodePatch(nameField, content);

      expect(patch.span, const ByteSpan(40, 4));
      expect(patch.bytes, <int>[0x41, 0x42, 0x43, 0x00]);
    });

    test('rejects targets outside the field span', () {
      final command = SetBytes(
        nameId,
        target: const ByteSpan(48, 1),
        bytes: <int>[0],
      );
      expect(
        () => command.validate(nameField, content),
        throwsFieldWrite(FieldWriteCodes.targetOutsideSpan),
      );
    });

    test('rejects mismatched target and byte counts', () {
      final command = SetBytes(
        nameId,
        target: const ByteSpan(40, 2),
        bytes: <int>[1],
      );
      expect(
        () => command.validate(nameField, content),
        throwsFieldWrite(FieldWriteCodes.lengthMismatch),
      );
    });

    test('copies bytes defensively', () {
      final source = <int>[1, 2, 3, 4];
      final command = SetBytes(
        nameId,
        target: const ByteSpan(40, 4),
        bytes: source,
      );
      source[0] = 99;

      expect(command.bytes, <int>[1, 2, 3, 4]);
      command.bytes[0] = 0;
      expect(command.encodePatch(nameField, content).bytes, <int>[0, 2, 3, 4]);
    });
  });

  group('validation is side-effect free', () {
    test('failed commands leave the region untouched', () {
      final before = content.materialize();
      expect(
        () => const SetScalar(healthId, 999).validate(healthField(), content),
        throwsFieldWrite(FieldWriteCodes.outOfRange),
      );
      expect(
        () => const SetBit(flagsId, 99, true).validate(flagsField, content),
        throwsFieldWrite(FieldWriteCodes.bitOutOfRange),
      );
      expect(content.materialize(), before);
      expect(content.patchCount, 0);
    });
  });

  group('command identity', () {
    test('compares by field and payload', () {
      expect(const SetScalar(healthId, 1), const SetScalar(healthId, 1));
      expect(
        const SetScalar(healthId, 1) == const SetScalar(healthId, 2),
        isFalse,
      );
      expect(const SetBit(flagsId, 1, true), const SetBit(flagsId, 1, true));
      expect(
        const SetBit(flagsId, 1, true) == const SetBit(flagsId, 2, true),
        isFalse,
      );
      expect(const SetEnum(modeId, 'a'), const SetEnum(modeId, 'a'));
      expect(
        SetBytes(nameId, target: const ByteSpan(40, 2), bytes: <int>[1, 2]),
        SetBytes(nameId, target: const ByteSpan(40, 2), bytes: <int>[1, 2]),
      );
      expect(
        SetBytes(nameId, target: const ByteSpan(40, 2), bytes: <int>[1, 2]) ==
            SetBytes(nameId, target: const ByteSpan(40, 2), bytes: <int>[1, 3]),
        isFalse,
      );
    });

    test('descriptions identify the field and payload', () {
      expect(
        const SetScalar(healthId, 7).description,
        contains('player.health'),
      );
      expect(const SetBit(flagsId, 2, true).description, contains('[2]'));
      expect(const SetEnum(modeId, 'child').description, contains('child'));
      expect(
        SetBytes(
          nameId,
          target: const ByteSpan(40, 2),
          bytes: <int>[1, 2],
        ).description,
        contains('2 bytes'),
      );
    });
  });
}
