import 'package:bomb_flower/domain/validation/field_validators.dart';
import 'package:bomb_flower/domain/validation/validation_result.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _codes(ValidationResult result) =>
    result.issues.map((issue) => issue.code).toList(growable: false);

String _repeat(String unit, int count) =>
    List<String>.filled(count, unit).join();

void main() {
  group('validateMaxLife', () {
    test('accepts the vanilla minimum and maximum', () {
      for (final value in <int>[12, 80]) {
        final result = validateMaxLife(value);
        expect(result.isValid, isTrue, reason: 'MaxLife $value');
        expect(result.issues, isEmpty, reason: 'MaxLife $value');
      }
    });

    test('warns below three hearts without failing', () {
      final result = validateMaxLife(4);
      expect(result.isValid, isTrue);
      expect(result.hasWarnings, isTrue);
      expect(_codes(result), <String>[
        ValidationCode.healthMaxBelowVanillaMinimum,
      ]);
      expect(validateMaxLife(0).hasWarnings, isTrue);
    });

    test('rejects a negative Int32 MaxLife', () {
      final result = validateMaxLife(-4);
      expect(result.isValid, isFalse);
      expect(result.issues, hasLength(1));
      expect(_codes(result), <String>[ValidationCode.healthMaxNegative]);
      expect(result.issues.single.actual, -4);
    });

    test('rejects a non-multiple of four', () {
      final result = validateMaxLife(13);
      expect(result.isValid, isFalse);
      expect(
        _codes(result),
        contains(ValidationCode.healthMaxNotMultipleOfFour),
      );
      expect(
        validateMaxLife(14).hasErrors,
        isTrue,
        reason: '14 quarter units is 3.5 hearts',
      );
    });

    test('boundary 11 is both misaligned and below the vanilla floor', () {
      final result = validateMaxLife(11);
      expect(result.hasErrors, isTrue);
      expect(result.hasWarnings, isTrue);
      expect(
        _codes(result),
        containsAll(<String>[
          ValidationCode.healthMaxNotMultipleOfFour,
          ValidationCode.healthMaxBelowVanillaMinimum,
        ]),
      );
    });

    test('boundary 81 is both misaligned and above the vanilla ceiling', () {
      final result = validateMaxLife(81);
      expect(result.hasErrors, isTrue);
      expect(result.hasWarnings, isTrue);
      expect(
        _codes(result),
        containsAll(<String>[
          ValidationCode.healthMaxNotMultipleOfFour,
          ValidationCode.healthMaxAboveVanillaMaximum,
        ]),
      );
    });

    test('boundary 999 is reported instead of clamped', () {
      final result = validateMaxLife(999);
      expect(result.hasErrors, isTrue);
      expect(result.hasWarnings, isTrue);
      expect(
        _codes(result),
        containsAll(<String>[
          ValidationCode.healthMaxNotMultipleOfFour,
          ValidationCode.healthMaxAboveVanillaMaximum,
        ]),
      );
      expect(
        result.issues
            .firstWhere(
              (issue) =>
                  issue.code == ValidationCode.healthMaxAboveVanillaMaximum,
            )
            .actual,
        999,
      );
    });

    test('above twenty hearts but aligned is only a warning', () {
      final result = validateMaxLife(84);
      expect(result.isValid, isTrue);
      expect(result.hasWarnings, isTrue);
      expect(_codes(result), <String>[
        ValidationCode.healthMaxAboveVanillaMaximum,
      ]);
    });

    test('rejects a value outside the Int32 field', () {
      final result = validateMaxLife(int32Max + 1);
      expect(result.isValid, isFalse);
      expect(_codes(result), <String>[ValidationCode.healthMaxOutsideInt32]);
    });
  });

  group('validateLife', () {
    test('accepts full and partial living health', () {
      for (final (life, maxLife) in <(int, int)>[
        (4, 12),
        (11, 12),
        (12, 12),
        (4, 4),
        (80, 80),
      ]) {
        final result = validateLife(life, maxLife);
        expect(result.isValid, isTrue, reason: '$life/$maxLife');
        expect(result.issues, isEmpty, reason: '$life/$maxLife');
      }
    });

    test('warns at zero because death is legal', () {
      final result = validateLife(0, 12);
      expect(result.isValid, isTrue);
      expect(_codes(result), <String>[ValidationCode.healthLifeAtDeath]);
    });

    test('warns below one full heart but above zero', () {
      for (final life in <int>[1, 2, 3]) {
        final result = validateLife(life, 12);
        expect(result.isValid, isTrue, reason: 'Life $life');
        expect(_codes(result), <String>[
          ValidationCode.healthLifeBelowOneHeart,
        ], reason: 'Life $life');
      }
    });

    test('rejects negative life', () {
      final result = validateLife(-1, 12);
      expect(result.isValid, isFalse);
      expect(_codes(result), <String>[ValidationCode.healthLifeNegative]);
    });

    test('rejects life above max life', () {
      final result = validateLife(13, 12);
      expect(result.isValid, isFalse);
      expect(_codes(result), <String>[ValidationCode.healthLifeExceedsMax]);
      expect(validateLife(81, 80).hasErrors, isTrue);
    });
  });

  group('validateRupees', () {
    test('accepts non-negative counts', () {
      expect(validateRupees(0).isValid, isTrue);
      expect(validateRupees(1).isValid, isTrue);
      expect(validateRupees(500).isValid, isTrue);
    });

    test('rejects negative and out-of-Int32 counts', () {
      expect(_codes(validateRupees(-1)), <String>[
        ValidationCode.rupeesNegative,
      ]);
      expect(_codes(validateRupees(int32Max + 1)), <String>[
        ValidationCode.rupeesOutsideInt32,
      ]);
    });

    test('enforces known wallet capacities as warnings', () {
      for (final (rupees, capacity) in <(int, int)>[
        (99, smallWalletCapacity),
        (200, mediumWalletCapacity),
        (500, largeWalletCapacity),
      ]) {
        expect(
          validateRupees(rupees, walletCapacity: capacity).issues,
          isEmpty,
          reason: '$rupees/$capacity',
        );
      }
      final aboveSmall = validateRupees(
        100,
        walletCapacity: smallWalletCapacity,
      );
      expect(aboveSmall.isValid, isTrue);
      expect(_codes(aboveSmall), <String>[ValidationCode.rupeesAboveWallet]);
      expect(validateRupees(201, walletCapacity: 200).hasWarnings, isTrue);
      expect(validateRupees(501, walletCapacity: 500).hasWarnings, isTrue);
    });

    test('warns above every vanilla wallet when the wallet is unknown', () {
      final result = validateRupees(501);
      expect(result.isValid, isTrue);
      expect(_codes(result), <String>[
        ValidationCode.rupeesAboveVanillaMaximum,
      ]);
      expect(validateRupees(999).hasWarnings, isTrue);
      expect(
        validateRupees(501, walletCapacity: 500).issues.single.code,
        ValidationCode.rupeesAboveWallet,
      );
    });

    test('rejects a negative wallet capacity as a programmer error', () {
      expect(() => validateRupees(0, walletCapacity: -1), throwsArgumentError);
    });
  });

  group('validateBool', () {
    test('accepts only zero and one', () {
      expect(validateBool(0).isValid, isTrue);
      expect(validateBool(1).isValid, isTrue);
    });

    test('rejects other integers', () {
      for (final value in <int>[2, -1, 999]) {
        final result = validateBool(value);
        expect(result.isValid, isFalse, reason: 'bool $value');
        expect(_codes(result), <String>[ValidationCode.boolNotZeroOrOne]);
      }
    });
  });

  group('bottles', () {
    test('lists thirteen unique known members', () {
      final options = allBottleOptions();
      expect(options, hasLength(13));
      expect(options.map((option) => option.name).toSet(), hasLength(13));
      expect(options.map((option) => option.hash).toSet(), hasLength(13));
    });

    test('round-trips every known hash to its name', () {
      for (final option in allBottleOptions()) {
        expect(
          bottleNameFor(option.hash),
          option.name,
          reason: option.toString(),
        );
        expect(validateBottleHash(option.hash).isValid, isTrue);
      }
    });

    test('resolves the signed two\'s-complement form', () {
      expect(bottleNameFor(0xEABA6067), 'RedPotion');
      expect(bottleNameFor(-356884377), 'RedPotion');
      expect(validateBottleHash(-356884377).issues, isEmpty);
    });

    test('returns null for unknown and out-of-range hashes', () {
      expect(bottleNameFor(0), isNull);
      expect(bottleNameFor(0xFFFFFFFF), isNull);
      expect(bottleNameFor(0x100000000), isNull);
    });

    test('warns for an unknown but storable hash', () {
      final result = validateBottleHash(0);
      expect(result.isValid, isTrue);
      expect(_codes(result), <String>[ValidationCode.bottleUnknownHash]);
      expect(validateBottleHash(-1).hasWarnings, isTrue);
    });

    test('rejects a hash outside the 32-bit domain', () {
      final result = validateBottleHash(0x100000000);
      expect(result.isValid, isFalse);
      expect(_codes(result), <String>[ValidationCode.bottleHashOutOfRange]);
    });

    test('reports the requested field', () {
      final result = validateBottleHash(0, field: 'BottleSlotA');
      expect(result.issues.single.field, 'BottleSlotA');
    });
  });

  group('validateEquipmentString', () {
    test('accepts the verified swords and shields', () {
      for (final sword in <String>[
        'Weapon_Sword_Kokiri',
        'Weapon_Sword_Master',
        'Weapon_Sword_Biggoron',
      ]) {
        expect(
          validateEquipmentString(sword, kind: 'sword').issues,
          isEmpty,
          reason: sword,
        );
      }
      for (final shield in <String>[
        'Weapon_Shield_Deku',
        'Weapon_Shield_Hylian',
        'Weapon_Shield_Mirror',
      ]) {
        expect(
          validateEquipmentString(shield, kind: 'shield').issues,
          isEmpty,
          reason: shield,
        );
      }
    });

    test('accepts the prefix-only armour, boots and ocarina kinds', () {
      expect(
        validateEquipmentString('Armor_Tunic_Kokiri', kind: 'tunic').isValid,
        isTrue,
      );
      expect(
        validateEquipmentString('Armor_Tunic_Zora', kind: 'armor').isValid,
        isTrue,
      );
      expect(
        validateEquipmentString('Boots_Basic', kind: 'boots').isValid,
        isTrue,
      );
      expect(
        validateEquipmentString('Item_Ocarina_Fairy', kind: 'ocarina').isValid,
        isTrue,
      );
    });

    test('rejects an unknown prefix', () {
      final result = validateEquipmentString('Sword_Kokiri', kind: 'sword');
      expect(result.isValid, isFalse);
      expect(_codes(result), <String>[ValidationCode.equipmentUnknownActor]);
      expect(
        validateEquipmentString('Item_Bottle', kind: 'ocarina').hasErrors,
        isTrue,
      );
    });

    test('rejects an empty slot and a bare prefix', () {
      expect(_codes(validateEquipmentString('', kind: 'sword')), <String>[
        ValidationCode.equipmentEmpty,
      ]);
      expect(
        _codes(validateEquipmentString('Weapon_Sword_', kind: 'sword')),
        <String>[ValidationCode.equipmentUnknownActor],
      );
    });

    test('warns for a correct prefix with an unverified actor', () {
      final result = validateEquipmentString('Weapon_Sword_Foo', kind: 'sword');
      expect(result.isValid, isTrue);
      expect(_codes(result), <String>[ValidationCode.equipmentUnlistedActor]);
    });

    test('rejects a value whose prefix belongs to another kind', () {
      final result = validateEquipmentString(
        'Weapon_Sword_Kokiri',
        kind: 'shield',
      );
      expect(result.isValid, isFalse);
      expect(_codes(result), <String>[ValidationCode.equipmentUnknownActor]);
    });

    test('rejects an unknown kind', () {
      final result = validateEquipmentString(
        'Armor_Tunic_Kokiri',
        kind: 'mask',
      );
      expect(result.isValid, isFalse);
      expect(_codes(result), <String>[ValidationCode.equipmentUnknownKind]);
    });

    test('rejects non-ASCII and control characters', () {
      expect(
        validateEquipmentString('Weapon_Sword_Kokirí', kind: 'sword').hasErrors,
        isTrue,
      );
      expect(
        validateEquipmentString(
          'Weapon_Sword_Ko\nkiri',
          kind: 'sword',
        ).hasErrors,
        isTrue,
      );
      expect(
        _codes(validateEquipmentString('Weapon_Sword_Kokirí', kind: 'sword')),
        contains(ValidationCode.stringNotAscii),
      );
    });

    test('accepts 63 content bytes and rejects 64', () {
      final atLimit = 'Weapon_Sword_${_repeat('A', 50)}';
      final overLimit = 'Weapon_Sword_${_repeat('A', 51)}';
      expect(atLimit.length, 63);
      expect(overLimit.length, 64);

      final accepted = validateEquipmentString(atLimit, kind: 'sword');
      expect(accepted.isValid, isTrue);
      expect(_codes(accepted), <String>[ValidationCode.equipmentUnlistedActor]);

      final rejected = validateEquipmentString(overLimit, kind: 'sword');
      expect(rejected.isValid, isFalse);
      expect(_codes(rejected), contains(ValidationCode.stringTooLong));
    });
  });

  group('validatePrintableAscii', () {
    test('accepts empty and printable content', () {
      expect(validatePrintableAscii('', maxLength: 0).isValid, isTrue);
      expect(validatePrintableAscii('Player', maxLength: 63).isValid, isTrue);
      expect(validatePrintableAscii(' ', maxLength: 1).isValid, isTrue);
      expect(validatePrintableAscii('~', maxLength: 1).isValid, isTrue);
    });

    test('accepts exactly the limit and rejects one more', () {
      expect(
        validatePrintableAscii(_repeat('A', 63), maxLength: 63).isValid,
        isTrue,
      );
      final result = validatePrintableAscii(_repeat('A', 64), maxLength: 63);
      expect(result.isValid, isFalse);
      expect(_codes(result), <String>[ValidationCode.stringTooLong]);
      expect(result.issues.single.actual, 64);
    });

    test('rejects non-ASCII and non-printable code units', () {
      for (final value in <String>['Café', 'a\nb', '\u0000', '\u007F']) {
        final result = validatePrintableAscii(value, maxLength: 63);
        expect(result.isValid, isFalse, reason: value);
        expect(_codes(result), <String>[ValidationCode.stringNotAscii]);
      }
    });

    test('rejects a negative maximum length as a programmer error', () {
      expect(
        () => validatePrintableAscii('x', maxLength: -1),
        throwsArgumentError,
      );
    });
  });

  group('validateFloat32', () {
    test('accepts finite in-range values and inclusive bounds', () {
      expect(validateFloat32(0).isValid, isTrue);
      expect(validateFloat32(-1.5).isValid, isTrue);
      expect(validateFloat32(1, min: 1, max: 2).isValid, isTrue);
      expect(validateFloat32(2, min: 1, max: 2).isValid, isTrue);
    });

    test('rejects NaN and infinities', () {
      for (final value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final result = validateFloat32(value);
        expect(result.isValid, isFalse, reason: '$value');
        expect(_codes(result), <String>[ValidationCode.floatNotFinite]);
      }
    });

    test('rejects values that overflow f32', () {
      final result = validateFloat32(1e39);
      expect(result.isValid, isFalse);
      expect(_codes(result), <String>[ValidationCode.floatOverflowsFloat32]);
    });

    test('rejects values outside supplied bounds', () {
      final low = validateFloat32(0.999, min: 1, max: 2);
      expect(low.isValid, isFalse);
      expect(_codes(low), <String>[ValidationCode.floatOutOfRange]);
      final high = validateFloat32(2.001, min: 1, max: 2);
      expect(high.isValid, isFalse);
      expect(_codes(high), <String>[ValidationCode.floatOutOfRange]);
    });

    test('rejects inverted or NaN bounds as programmer errors', () {
      expect(() => validateFloat32(0, min: 2, max: 1), throwsArgumentError);
      expect(() => validateFloat32(0, min: double.nan), throwsArgumentError);
    });
  });

  group('validateRotation', () {
    test('accepts the conventional ranges', () {
      for (final value in <double>[-180, -90, 0, 180, 359, 360]) {
        expect(
          validateRotation(value).isValid,
          isTrue,
          reason: 'rotation $value',
        );
        expect(validateRotation(value).issues, isEmpty, reason: '$value');
      }
    });

    test('warns outside the conventional ranges', () {
      for (final value in <double>[-181, 361, 720]) {
        final result = validateRotation(value);
        expect(result.isValid, isTrue, reason: 'rotation $value');
        expect(_codes(result), <String>[
          ValidationCode.rotationOutsideConventions,
        ], reason: 'rotation $value');
      }
    });

    test('NaN is an error rather than a rotation warning', () {
      final result = validateRotation(double.nan);
      expect(result.isValid, isFalse);
      expect(_codes(result), <String>[ValidationCode.floatNotFinite]);
    });
  });

  group('integer validators', () {
    test('validateInt32 accepts the Int32 boundaries', () {
      expect(validateInt32(0).isValid, isTrue);
      expect(validateInt32(int32Max).isValid, isTrue);
      expect(validateInt32(int32Min).isValid, isTrue);
      expect(_codes(validateInt32(int32Max + 1)), <String>[
        ValidationCode.intOutsideInt32,
      ]);
      expect(_codes(validateInt32(int32Min - 1)), <String>[
        ValidationCode.intOutsideInt32,
      ]);
    });

    test('validateIntBounds is inclusive', () {
      expect(validateIntBounds(1, min: 1, max: 10).isValid, isTrue);
      expect(validateIntBounds(10, min: 1, max: 10).isValid, isTrue);
      expect(validateIntBounds(5, min: 1, max: 10).isValid, isTrue);
      expect(_codes(validateIntBounds(0, min: 1, max: 10)), <String>[
        ValidationCode.intOutOfRange,
      ]);
      expect(_codes(validateIntBounds(11, min: 1, max: 10)), <String>[
        ValidationCode.intOutOfRange,
      ]);
    });

    test('validateIntBounds rejects inverted bounds', () {
      expect(() => validateIntBounds(0, min: 2, max: 1), throwsArgumentError);
    });
  });

  group('validateEnumHash', () {
    test('accepts a member and warns for an unknown member', () {
      expect(validateEnumHash(5, const <int>{1, 5}).issues, isEmpty);
      final unknown = validateEnumHash(7, const <int>{1, 5});
      expect(unknown.isValid, isTrue);
      expect(_codes(unknown), <String>[ValidationCode.enumUnknownMember]);
    });

    test('warns for an empty member set', () {
      final result = validateEnumHash(0, const <int>{});
      expect(result.hasWarnings, isTrue);
      expect(_codes(result), <String>[ValidationCode.enumUnknownMember]);
    });
  });
}
