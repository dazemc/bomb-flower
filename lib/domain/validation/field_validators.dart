/// Pure validators for scalar Ocarina of Time save fields.
///
/// # Evidence
///
/// The rules below cite where they come from. Three evidence levels are used:
///
/// * **Byte-verified** — the field width, signedness, or encoding was checked
///   against the reverse-engineered save format. Violations are errors.
/// * **Game convention** — the value is representable in the bytes but the
///   vanilla game never produces it (heart floors, wallet capacities, rotation
///   ranges). Violations are warnings so a modded or imported save is not
///   blocked.
/// * **Inferred** — a rule derived from the brief or from related fields but
///   not directly observed. Also a warning unless it makes the value
///   unreadable.
///
/// # Format facts encoded here
///
/// * `PlayerStatus.MaxLife` is an Int32 in **quarter hearts**: a heart is four
///   units, so a vanilla 20-heart save stores `80`. The game's minimum is three
///   hearts (`12`) and its vanilla maximum is twenty (`80`).
/// * `PlayerStatus.Life` is the current health in the same quarter-heart units.
///   It may be `0` at death. A save editor still warns below one full heart
///   (`4`).
/// * `PlayerStatus.CurrentRupee` is an Int32 and cannot be negative. Wallet
///   capacity lives in a separate String64 record (`Item_Wallet_Small`,
///   `Item_Wallet_Medium`, `Item_Wallet_Large`) with capacities 99, 200 and
///   500. The capacity table is a game rule, not a byte invariant, and the
///   wallet item may be unknown or modded, so capacity violations warn.
/// * Bottles occupy five slots (A–E). The bottle value is an Enum whose member
///   is stored as the 32-bit Murmur3 hash of the member name. Unknown hashes
///   are preserved and warned about rather than rejected: a 32-bit hash is
///   always readable, and mods can add members.
/// * Equipment is stored as game actor strings in 64-byte NUL-terminated
///   slots. The string itself therefore holds at most 63 bytes. Swords are
///   `Weapon_Sword_*`, shields `Weapon_Shield_*`, tunics/armor `Armor_*`,
///   boots `Boots_*`, and ocarinas `Item_Ocarina_*`. A value with any other
///   prefix is not an equipment actor and is an error.
/// * Booleans are stored as Int32 values that must be exactly `0` or `1`.
/// * Positions and rotations are f32 values; NaN and infinity are not valid.
/// * Strings are printable ASCII (`0x20`–`0x7E`) and NUL-terminated, so their
///   content length is at most `slot size - 1`.
library;

import 'validation_result.dart';

/// Number of quarter-heart units in one full heart.
///
/// Byte-verified: health is stored in quarter hearts.
const int quarterHeartsPerHeart = 4;

/// Hearts in a vanilla maximum-health save (20).
///
/// Game convention, not a byte invariant.
const int vanillaMaximumHearts = 20;

/// Hearts in the game's minimum maximum-health value (3).
///
/// Game convention, not a byte invariant.
const int vanillaMinimumHearts = 3;

/// Quarter-heart value of [vanillaMaximumHearts]: `80`.
const int vanillaMaximumMaxLife = vanillaMaximumHearts * quarterHeartsPerHeart;

/// Quarter-heart value of [vanillaMinimumHearts]: `12`.
const int vanillaMinimumMaxLife = vanillaMinimumHearts * quarterHeartsPerHeart;

/// Largest signed 32-bit integer.
const int int32Max = 2147483647;

/// Smallest signed 32-bit integer.
const int int32Min = -2147483648;

/// Largest finite f32 value.
///
/// Byte-verified: positions and rotations are 32-bit floats. A double above
/// this magnitude rounds to infinity when written as f32.
const double float32Max = 3.4028234663852886e38;

/// Maximum bytes in an equipment actor string.
///
/// The byte-verified storage slot is 64 bytes including the NUL terminator, so
/// the decoded string has at most 63 bytes.
const int maxEquipmentActorLength = 63;

/// Capacity of `Item_Wallet_Small`.
///
/// Game convention: the capacity is not stored in the wallet String64 record.
const int smallWalletCapacity = 99;

/// Capacity of `Item_Wallet_Medium`.
///
/// Game convention.
const int mediumWalletCapacity = 200;

/// Capacity of `Item_Wallet_Large`, also the largest vanilla capacity.
///
/// Game convention.
const int largeWalletCapacity = 500;

/// One known bottle enum member and its stored hash.
///
/// The enum value is the 32-bit Murmur3 hash of the member name; these thirteen
/// hashes were recovered from the save format. Bottle slots are A through E.
final class BottleOption {
  /// Creates a bottle option.
  const BottleOption({required this.name, required this.hash});

  /// Enum member name as stored by the game, for example `RedPotion`.
  final String name;

  /// Unsigned 32-bit Murmur3 hash of [name].
  final int hash;

  @override
  String toString() =>
      'BottleOption($name, 0x${hash.toRadixString(16).padLeft(8, '0')})';
}

const List<BottleOption> _bottles = <BottleOption>[
  BottleOption(name: 'Empty', hash: 0xBE69DE49),
  BottleOption(name: 'RedPotion', hash: 0xEABA6067),
  BottleOption(name: 'GreenPotion', hash: 0x049D37C1),
  BottleOption(name: 'BluePotion', hash: 0xF383D6E5),
  BottleOption(name: 'BlueFire', hash: 0x1C293517),
  BottleOption(name: 'Fish', hash: 0x1E834EF8),
  BottleOption(name: 'Letter', hash: 0x0F24E808),
  BottleOption(name: 'BigPoe', hash: 0xCDC21471),
  BottleOption(name: 'Poe', hash: 0x02084F9E),
  BottleOption(name: 'Bug', hash: 0x74D62ECB),
  BottleOption(name: 'Fairy', hash: 0x6F49E357),
  BottleOption(name: 'MaxMilk', hash: 0x73356827),
  BottleOption(name: 'HalfMilk', hash: 0xEEF6E4B0),
];

/// Every known bottle member, in the order the format lists them.
///
/// The returned list is the internal constant list and is unmodifiable.
List<BottleOption> allBottleOptions() => _bottles;

/// Stable issue codes produced by these validators.
abstract final class ValidationCode {
  /// `MaxLife` is negative.
  static const String healthMaxNegative = 'health.max_negative';

  /// `MaxLife` cannot be stored in an Int32.
  static const String healthMaxOutsideInt32 = 'health.max_outside_int32';

  /// `MaxLife` is not a whole number of hearts.
  static const String healthMaxNotMultipleOfFour =
      'health.max_not_multiple_of_four';

  /// `MaxLife` is below the three-heart vanilla floor.
  static const String healthMaxBelowVanillaMinimum =
      'health.max_below_vanilla_minimum';

  /// `MaxLife` is above the twenty-heart vanilla ceiling.
  static const String healthMaxAboveVanillaMaximum =
      'health.max_above_vanilla_maximum';

  /// `Life` is negative.
  static const String healthLifeNegative = 'health.life_negative';

  /// `Life` is greater than `MaxLife`.
  static const String healthLifeExceedsMax = 'health.life_exceeds_max';

  /// `Life` is zero, which is legal at death.
  static const String healthLifeAtDeath = 'health.life_at_death';

  /// `Life` is above zero but below one full heart.
  static const String healthLifeBelowOneHeart = 'health.life_below_one_heart';

  /// Rupees are negative.
  static const String rupeesNegative = 'rupees.negative';

  /// Rupees are outside the signed 32-bit range.
  static const String rupeesOutsideInt32 = 'rupees.outside_int32';

  /// Rupees exceed the selected wallet's capacity.
  static const String rupeesAboveWallet = 'rupees.above_wallet';

  /// Rupees exceed every vanilla wallet capacity and the wallet is unknown.
  static const String rupeesAboveVanillaMaximum =
      'rupees.above_vanilla_maximum';

  /// A boolean field is not `0` or `1`.
  static const String boolNotZeroOrOne = 'bool.not_zero_or_one';

  /// A bottle hash is outside the 32-bit enum domain.
  static const String bottleHashOutOfRange = 'bottle.hash_out_of_range';

  /// A bottle hash is not one of the thirteen known members.
  static const String bottleUnknownHash = 'bottle.unknown_hash';

  /// The equipment kind is not recognised.
  static const String equipmentUnknownKind = 'equipment.unknown_kind';

  /// The equipment slot is empty.
  static const String equipmentEmpty = 'equipment.empty';

  /// The actor string does not have the prefix required by its kind.
  static const String equipmentUnknownActor = 'equipment.unknown_actor';

  /// The actor string has a valid prefix but is not in the verified list.
  static const String equipmentUnlistedActor = 'equipment.unlisted_actor';

  /// A string is longer than its storage slot allows.
  static const String stringTooLong = 'string.too_long';

  /// A string contains a code unit outside printable ASCII.
  static const String stringNotAscii = 'string.not_ascii';

  /// A float is NaN or infinite.
  static const String floatNotFinite = 'float.not_finite';

  /// A finite double is too large to be represented as f32.
  static const String floatOverflowsFloat32 = 'float.overflows_float32';

  /// A float is outside its caller-supplied bounds.
  static const String floatOutOfRange = 'float.out_of_range';

  /// A rotation is outside the conventional angle ranges.
  static const String rotationOutsideConventions =
      'rotation.outside_conventions';

  /// An integer is outside the signed 32-bit range.
  static const String intOutsideInt32 = 'int.outside_int32';

  /// An integer is outside a caller-supplied range.
  static const String intOutOfRange = 'int.out_of_range';

  /// An enum hash is not in the caller-supplied member set.
  static const String enumUnknownMember = 'enum.unknown_member';
}

/// Validates `PlayerStatus.MaxLife`, stored as an Int32 in quarter hearts.
///
/// Byte-verified: the field is a signed 32-bit integer and one heart is four
/// units, so a non-multiple of four cannot describe a whole heart. A negative
/// or out-of-Int32 value is an error.
///
/// Game conventions: the vanilla floor of three hearts (`12`) and ceiling of
/// twenty hearts (`80`) are warnings, because a modded save can store other
/// values without corrupting the field.
ValidationResult validateMaxLife(
  int maxLife, {
  String field = 'PlayerStatus.MaxLife',
}) {
  if (maxLife < 0) {
    return ValidationResult(<ValidationIssue>[
      ValidationIssue(
        code: ValidationCode.healthMaxNegative,
        severity: Severity.error,
        field: field,
        message:
            'MaxLife is an Int32 quarter-heart count and cannot be negative; '
            'a heart is $quarterHeartsPerHeart units.',
        actual: maxLife,
        expected: '0..$int32Max',
      ),
    ]);
  }
  if (maxLife > int32Max) {
    return ValidationResult(<ValidationIssue>[
      ValidationIssue(
        code: ValidationCode.healthMaxOutsideInt32,
        severity: Severity.error,
        field: field,
        message: 'MaxLife does not fit in the signed 32-bit field.',
        actual: maxLife,
        expected: '0..$int32Max',
      ),
    ]);
  }

  final issues = <ValidationIssue>[];
  if (maxLife % quarterHeartsPerHeart != 0) {
    issues.add(
      ValidationIssue(
        code: ValidationCode.healthMaxNotMultipleOfFour,
        severity: Severity.error,
        field: field,
        message:
            'MaxLife is stored in quarter hearts, so it must be a whole '
            'number of hearts; $maxLife is not divisible by '
            '$quarterHeartsPerHeart.',
        actual: maxLife,
        expected: 'multiple of $quarterHeartsPerHeart',
      ),
    );
  }
  if (maxLife < vanillaMinimumMaxLife) {
    issues.add(
      ValidationIssue(
        code: ValidationCode.healthMaxBelowVanillaMinimum,
        severity: Severity.warning,
        field: field,
        message:
            'MaxLife is below the vanilla three-heart minimum '
            '($vanillaMinimumMaxLife quarter units). This is a game-rule '
            'convention, not a byte invariant.',
        actual: maxLife,
        expected: '>= $vanillaMinimumMaxLife',
      ),
    );
  }
  if (maxLife > vanillaMaximumMaxLife) {
    issues.add(
      ValidationIssue(
        code: ValidationCode.healthMaxAboveVanillaMaximum,
        severity: Severity.warning,
        field: field,
        message:
            'MaxLife is above the vanilla twenty-heart maximum '
            '($vanillaMaximumMaxLife quarter units). This is a game-rule '
            'convention, not a byte invariant.',
        actual: maxLife,
        expected: '<= $vanillaMaximumMaxLife',
      ),
    );
  }
  return ValidationResult(issues);
}

/// Validates `PlayerStatus.Life`, the current health in quarter hearts.
///
/// Byte-verified: the field is an Int32 in the same quarter-heart units as
/// `MaxLife`, so it cannot be negative and cannot exceed `MaxLife`. Zero is a
/// valid death state.
///
/// Editor convention: the brief asks a save editor to warn below one full
/// heart (`4` quarter units). That warning is advisory only. This function does
/// not repeat [validateMaxLife]'s own multiplicity check; callers validating a
/// whole status record should merge both results.
ValidationResult validateLife(
  int life,
  int maxLife, {
  String field = 'PlayerStatus.Life',
}) {
  final issues = <ValidationIssue>[];
  if (life < 0) {
    issues.add(
      ValidationIssue(
        code: ValidationCode.healthLifeNegative,
        severity: Severity.error,
        field: field,
        message: 'Life is an Int32 quarter-heart count and cannot be negative.',
        actual: life,
        expected: '0..$maxLife',
      ),
    );
  } else if (life > maxLife) {
    issues.add(
      ValidationIssue(
        code: ValidationCode.healthLifeExceedsMax,
        severity: Severity.error,
        field: field,
        message: 'Life ($life) exceeds MaxLife ($maxLife).',
        actual: life,
        expected: '0..$maxLife',
      ),
    );
  } else if (life == 0) {
    issues.add(
      ValidationIssue(
        code: ValidationCode.healthLifeAtDeath,
        severity: Severity.warning,
        field: field,
        message:
            'Life is zero. That is legal at death, but a save editor should '
            'show it explicitly rather than silently treating it as a full '
            'refill.',
        actual: life,
        expected: '4..$maxLife for a living save',
      ),
    );
  } else if (life < quarterHeartsPerHeart) {
    issues.add(
      ValidationIssue(
        code: ValidationCode.healthLifeBelowOneHeart,
        severity: Severity.warning,
        field: field,
        message:
            'Life is below one full heart ($quarterHeartsPerHeart quarter '
            'units); the player will be in critical health or dead on load.',
        actual: life,
        expected: '>= $quarterHeartsPerHeart',
      ),
    );
  }
  return ValidationResult(issues);
}

/// Validates `PlayerStatus.CurrentRupee`, a signed Int32 count.
///
/// Byte-verified: negative rupees cannot be represented as a meaningful count
/// and are an error. Values outside Int32 cannot be stored and are an error.
///
/// [walletCapacity] is the capacity of the selected wallet item (99, 200 or
/// 500 vanilla). The capacity is not stored in `CurrentRupee`, so exceeding it
/// is a warning: the wallet item is a separate String64 record and may be
/// unknown or modded. When [walletCapacity] is omitted, the vanilla maximum of
/// [largeWalletCapacity] is used as a warning threshold.
ValidationResult validateRupees(
  int rupees, {
  int? walletCapacity,
  String field = 'PlayerStatus.CurrentRupee',
}) {
  if (walletCapacity != null && walletCapacity < 0) {
    throw ArgumentError.value(
      walletCapacity,
      'walletCapacity',
      'must not be negative',
    );
  }
  if (rupees < 0) {
    return ValidationResult(<ValidationIssue>[
      ValidationIssue(
        code: ValidationCode.rupeesNegative,
        severity: Severity.error,
        field: field,
        message: 'Rupees cannot be negative.',
        actual: rupees,
        expected: '>= 0',
      ),
    ]);
  }
  if (rupees > int32Max) {
    return ValidationResult(<ValidationIssue>[
      ValidationIssue(
        code: ValidationCode.rupeesOutsideInt32,
        severity: Severity.error,
        field: field,
        message: 'The rupee count does not fit in the signed 32-bit field.',
        actual: rupees,
        expected: '0..$int32Max',
      ),
    ]);
  }

  final limit = walletCapacity ?? largeWalletCapacity;
  if (rupees > limit) {
    final walletKnown = walletCapacity != null;
    return ValidationResult(<ValidationIssue>[
      ValidationIssue(
        code: walletKnown
            ? ValidationCode.rupeesAboveWallet
            : ValidationCode.rupeesAboveVanillaMaximum,
        severity: Severity.warning,
        field: field,
        message: walletKnown
            ? 'Rupees exceed the selected wallet capacity ($limit). Wallet '
                  'capacities are a game rule, not a byte invariant.'
            : 'Rupees exceed every vanilla wallet capacity '
                  '($largeWalletCapacity) and the wallet item was not '
                  'supplied, so only this convention check applies.',
        actual: rupees,
        expected: '<= $limit',
      ),
    ]);
  }
  return const ValidationResult.empty();
}

/// Validates a stored boolean.
///
/// Byte-verified: booleans occupy an Int32 and the game writes only `0` or
/// `1`; any other value is an error.
ValidationResult validateBool(int value, {String field = 'bool'}) {
  if (value == 0 || value == 1) {
    return const ValidationResult.empty();
  }
  return ValidationResult(<ValidationIssue>[
    ValidationIssue(
      code: ValidationCode.boolNotZeroOrOne,
      severity: Severity.error,
      field: field,
      message: 'A stored boolean must be exactly 0 or 1; found $value.',
      actual: value,
      expected: '0 or 1',
    ),
  ]);
}

/// Resolves a bottle enum hash to its member name, or `null` if unknown.
///
/// The hash is the 32-bit Murmur3 hash of the member name. Both the unsigned
/// representation (`0..0xFFFFFFFF`) and the signed two's-complement value a
/// `ByteData.getInt32` read produces are accepted, so `-356884377` resolves the
/// same member as `0xEABA6067`.
String? bottleNameFor(int hash) {
  final normalized = _asUint32(hash);
  if (normalized == null) {
    return null;
  }
  for (final bottle in _bottles) {
    if (bottle.hash == normalized) {
      return bottle.name;
    }
  }
  return null;
}

/// Validates a bottle enum hash stored in one of the five bottle slots (A–E).
///
/// Byte-verified: the value is a 32-bit hash, so a value outside the 32-bit
/// domain is an error. Membership in the thirteen known members is a game
/// fact; an unknown but 32-bit hash is preserved and warned about, because a
/// mod or a newer member may legitimately use it.
ValidationResult validateBottleHash(int hash, {String field = 'bottle'}) {
  if (_asUint32(hash) == null) {
    return ValidationResult(<ValidationIssue>[
      ValidationIssue(
        code: ValidationCode.bottleHashOutOfRange,
        severity: Severity.error,
        field: field,
        message:
            'A bottle value is a 32-bit enum hash; $hash is outside the '
            'unsigned 32-bit and signed 32-bit domains.',
        actual: hash,
        expected: '0..0xFFFFFFFF or $int32Min..$int32Max',
      ),
    ]);
  }
  if (bottleNameFor(hash) == null) {
    return ValidationResult(<ValidationIssue>[
      ValidationIssue(
        code: ValidationCode.bottleUnknownHash,
        severity: Severity.warning,
        field: field,
        message:
            'Unknown bottle hash '
            '0x${_asUint32(hash)!.toRadixString(16).padLeft(8, '0')}; the '
            'bytes remain readable and are preserved as an opaque enum value.',
        actual: hash,
        expected: 'one of the 13 known bottle hashes',
      ),
    ]);
  }
  return const ValidationResult.empty();
}

/// Validates a decoded equipment actor string for [kind].
///
/// [slot] is the decoded string held in the 64-byte NUL-terminated storage
/// slot, not the slot's field name. The byte-verified slot size means at most
/// [maxEquipmentActorLength] (63) content bytes, and the content must be
/// printable ASCII.
///
/// [kind] is one of `sword`, `shield`, `tunic`/`armor`, `boots` or `ocarina`.
/// An unknown kind is an error. A known prefix but an unverified member (for
/// example a modded `Weapon_Sword_Foo`) is a warning; an unknown prefix (for
/// example `Sword_Kokiri`) is an error because the value cannot be an
/// equipment actor of that kind.
ValidationResult validateEquipmentString(
  String slot, {
  required String kind,
  String? field,
}) {
  final normalizedKind = kind.trim().toLowerCase();
  final issueField = field ?? 'equipment.$normalizedKind';
  final issues = <ValidationIssue>[
    ...validatePrintableAscii(
      slot,
      maxLength: maxEquipmentActorLength,
      field: issueField,
    ).issues,
  ];

  final spec = _equipmentKinds[normalizedKind];
  if (spec == null) {
    issues.add(
      ValidationIssue(
        code: ValidationCode.equipmentUnknownKind,
        severity: Severity.error,
        field: issueField,
        message:
            'Unknown equipment kind "$kind"; expected sword, shield, tunic, '
            'armor, boots or ocarina.',
        actual: kind,
        expected: _equipmentKinds.keys.join(', '),
      ),
    );
    return ValidationResult(issues);
  }
  if (slot.isEmpty) {
    issues.add(
      ValidationIssue(
        code: ValidationCode.equipmentEmpty,
        severity: Severity.error,
        field: issueField,
        message: 'The equipment slot is empty.',
        actual: slot,
        expected: '${spec.prefix}...',
      ),
    );
    return ValidationResult(issues);
  }
  if (!slot.startsWith(spec.prefix) || slot.length == spec.prefix.length) {
    issues.add(
      ValidationIssue(
        code: ValidationCode.equipmentUnknownActor,
        severity: Severity.error,
        field: issueField,
        message:
            'An equipment actor for $normalizedKind must start with '
            '"${spec.prefix}" and name an actor after it.',
        actual: slot,
        expected:
            '${spec.prefix}<Actor>'
            '${spec.verified.isEmpty ? '' : ' (verified: ${spec.verified.join(', ')})'}',
      ),
    );
    return ValidationResult(issues);
  }
  if (spec.verified.isNotEmpty && !spec.verified.contains(slot)) {
    issues.add(
      ValidationIssue(
        code: ValidationCode.equipmentUnlistedActor,
        severity: Severity.warning,
        field: issueField,
        message:
            '"$slot" has the right prefix but is not one of the verified '
            'vanilla actors. It may be modded; the bytes are preserved.',
        actual: slot,
        expected: spec.verified.join(', '),
      ),
    );
  }
  return ValidationResult(issues);
}

/// Validates printable ASCII of at most [maxLength] bytes.
///
/// Byte-verified: strings are printable ASCII (`0x20`–`0x7E`) and
/// NUL-terminated inside a fixed slot, so the decoded content is at most the
/// slot size minus one. [value] is measured in UTF-16 code units, which equals
/// bytes for the only accepted alphabet. The first offending code unit is
/// reported; control characters, `0x7F`, and every non-ASCII code unit are
/// rejected.
ValidationResult validatePrintableAscii(
  String value, {
  required int maxLength,
  String field = 'string',
}) {
  if (maxLength < 0) {
    throw ArgumentError.value(maxLength, 'maxLength', 'must not be negative');
  }
  final issues = <ValidationIssue>[];
  if (value.length > maxLength) {
    issues.add(
      ValidationIssue(
        code: ValidationCode.stringTooLong,
        severity: Severity.error,
        field: field,
        message:
            'String is ${value.length} code units; the slot allows at '
            'most $maxLength.',
        actual: value.length,
        expected: '<= $maxLength',
      ),
    );
  }
  for (var index = 0; index < value.length; index++) {
    final unit = value.codeUnitAt(index);
    if (unit < 0x20 || unit > 0x7E) {
      final hex = unit.toRadixString(16).toUpperCase().padLeft(4, '0');
      issues.add(
        ValidationIssue(
          code: ValidationCode.stringNotAscii,
          severity: Severity.error,
          field: field,
          message:
              'String must be printable ASCII (0x20..0x7E); found U+$hex at '
              'index $index.',
          actual: 'U+$hex',
          expected: 'printable ASCII',
        ),
      );
      break;
    }
  }
  return ValidationResult(issues);
}

/// Validates an f32 field value.
///
/// Byte-verified: positions and rotations are f32, so NaN and infinity are not
/// legal values, and a finite double whose magnitude exceeds [float32Max] would
/// become infinity when stored. [min] and [max] are inclusive optional bounds
/// supplied by the field's descriptor. Passing NaN as a bound, or a [min]
/// greater than [max], is a programmer error and throws [ArgumentError].
ValidationResult validateFloat32(
  double value, {
  double? min,
  double? max,
  String field = 'float',
}) {
  if (min != null && min.isNaN) {
    throw ArgumentError.value(min, 'min', 'must not be NaN');
  }
  if (max != null && max.isNaN) {
    throw ArgumentError.value(max, 'max', 'must not be NaN');
  }
  if (min != null && max != null && min > max) {
    throw ArgumentError('min ($min) must not exceed max ($max)');
  }
  if (value.isNaN) {
    return ValidationResult(<ValidationIssue>[
      ValidationIssue(
        code: ValidationCode.floatNotFinite,
        severity: Severity.error,
        field: field,
        message: 'NaN is not a valid f32 field value.',
        actual: 'NaN',
        expected: 'a finite number',
      ),
    ]);
  }
  if (value.isInfinite) {
    return ValidationResult(<ValidationIssue>[
      ValidationIssue(
        code: ValidationCode.floatNotFinite,
        severity: Severity.error,
        field: field,
        message: 'Infinity is not a valid f32 field value.',
        actual: value > 0 ? 'Infinity' : '-Infinity',
        expected: 'a finite number',
      ),
    ]);
  }
  if (value.abs() > float32Max) {
    return ValidationResult(<ValidationIssue>[
      ValidationIssue(
        code: ValidationCode.floatOverflowsFloat32,
        severity: Severity.error,
        field: field,
        message: 'The value rounds to infinity when stored as f32.',
        actual: value,
        expected: '|value| <= $float32Max',
      ),
    ]);
  }
  final issues = <ValidationIssue>[];
  if (min != null && value < min) {
    issues.add(
      ValidationIssue(
        code: ValidationCode.floatOutOfRange,
        severity: Severity.error,
        field: field,
        message: 'Value $value is below the minimum $min.',
        actual: value,
        expected: '>= $min',
      ),
    );
  }
  if (max != null && value > max) {
    issues.add(
      ValidationIssue(
        code: ValidationCode.floatOutOfRange,
        severity: Severity.error,
        field: field,
        message: 'Value $value is above the maximum $max.',
        actual: value,
        expected: '<= $max',
      ),
    );
  }
  return ValidationResult(issues);
}

/// Validates a rotation f32 against the game's conventional angle ranges.
///
/// Byte-verified: rotations are f32. Game convention: the game writes angles
/// either as −180..180 or as 0..360, so the accepted union is −180..360
/// inclusive. A finite value outside that union is a warning, not an error:
/// the angle is representable and can be normalised, but it is not a form the
/// vanilla game writes.
ValidationResult validateRotation(double value, {String field = 'rotation'}) {
  final issues = validateFloat32(value, field: field).issues.toList();
  if (!value.isFinite || value.abs() > float32Max) {
    return ValidationResult(issues);
  }
  if (value < -180 || value > 360) {
    issues.add(
      ValidationIssue(
        code: ValidationCode.rotationOutsideConventions,
        severity: Severity.warning,
        field: field,
        message:
            'Rotation $value is outside the conventional −180..180 and '
            '0..360 ranges. It is representable, but the game may normalise '
            'it on load.',
        actual: value,
        expected: '−180..360',
      ),
    );
  }
  return ValidationResult(issues);
}

/// Validates that [value] fits in a signed 32-bit integer.
ValidationResult validateInt32(int value, {String field = 'int32'}) {
  if (value < int32Min || value > int32Max) {
    return ValidationResult(<ValidationIssue>[
      ValidationIssue(
        code: ValidationCode.intOutsideInt32,
        severity: Severity.error,
        field: field,
        message: 'Value does not fit in a signed 32-bit integer.',
        actual: value,
        expected: '$int32Min..$int32Max',
      ),
    ]);
  }
  return const ValidationResult.empty();
}

/// Validates that [value] is inside the inclusive range [min]..[max].
///
/// This is the generic bound check used by field descriptors. Passing a [min]
/// greater than [max] is a programmer error and throws [ArgumentError].
ValidationResult validateIntBounds(
  int value, {
  required int min,
  required int max,
  String field = 'int',
}) {
  if (min > max) {
    throw ArgumentError('min ($min) must not exceed max ($max)');
  }
  if (value < min || value > max) {
    return ValidationResult(<ValidationIssue>[
      ValidationIssue(
        code: ValidationCode.intOutOfRange,
        severity: Severity.error,
        field: field,
        message: 'Value $value is outside the allowed range $min..$max.',
        actual: value,
        expected: '$min..$max',
      ),
    ]);
  }
  return const ValidationResult.empty();
}

/// Validates that an enum hash is one of [allowed].
///
/// Byte-verified: enum members are 32-bit hashes, so any 32-bit value is
/// storable. Membership is a game fact; an unknown member is a warning so a
/// modded or forward-version enum value is preserved instead of rejected.
/// Supplying an empty [allowed] set therefore warns for every value.
ValidationResult validateEnumHash(
  int hash,
  Set<int> allowed, {
  String field = 'enum',
}) {
  if (allowed.contains(hash)) {
    return const ValidationResult.empty();
  }
  return ValidationResult(<ValidationIssue>[
    ValidationIssue(
      code: ValidationCode.enumUnknownMember,
      severity: Severity.warning,
      field: field,
      message:
          'Enum hash $hash is not a known member; the 32-bit value is '
          'preserved as opaque data.',
      actual: hash,
      expected: allowed.isEmpty ? 'a non-empty member set' : allowed.join(', '),
    ),
  ]);
}

final class _EquipmentKind {
  const _EquipmentKind({
    required this.prefix,
    this.verified = const <String>{},
  });

  final String prefix;
  final Set<String> verified;
}

const Map<String, _EquipmentKind> _equipmentKinds = <String, _EquipmentKind>{
  'sword': _EquipmentKind(
    prefix: 'Weapon_Sword_',
    verified: <String>{
      'Weapon_Sword_Kokiri',
      'Weapon_Sword_Master',
      'Weapon_Sword_Biggoron',
    },
  ),
  'shield': _EquipmentKind(
    prefix: 'Weapon_Shield_',
    verified: <String>{
      'Weapon_Shield_Deku',
      'Weapon_Shield_Hylian',
      'Weapon_Shield_Mirror',
    },
  ),
  'tunic': _EquipmentKind(prefix: 'Armor_'),
  'armor': _EquipmentKind(prefix: 'Armor_'),
  'boots': _EquipmentKind(prefix: 'Boots_'),
  'ocarina': _EquipmentKind(prefix: 'Item_Ocarina_'),
};

/// Returns [value] as an unsigned 32-bit hash, or `null` outside the signed and
/// unsigned 32-bit domains.
int? _asUint32(int value) {
  if (value >= 0 && value <= 0xFFFFFFFF) {
    return value;
  }
  if (value >= int32Min && value < 0) {
    return value & 0xFFFFFFFF;
  }
  return null;
}
