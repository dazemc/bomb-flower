/// Human-readable quarter-heart formatting and parsing.
///
/// Health is stored in quarter hearts: one heart is four units, so `14` quarter
/// units is 3.5 hearts. This library never clamps: parsing rejects a value that
/// is not a whole number of quarter hearts, and formatting a negative value is
/// a programmer error rather than a silent 0.
library;

import 'scalars.dart';

const int _unitsPerHeart = 4;

/// Largest signed 32-bit value; the health field is stored as an Int32.
const int _int32Max = 2147483647;

/// A formatted health value derived from a quarter-heart count.
///
/// [quarterHearts] may be `0` (death) through any positive value; the save
/// field is an Int32. [text] is deliberately plain ASCII words, with no emoji
/// or heart glyph, so it renders in a terminal, a test, and a text-only export.
final class HeartsDisplay {
  const HeartsDisplay._({
    required this.quarterHearts,
    required this.fullHearts,
    required this.quarterRemainder,
    required this.totalHearts,
    required this.text,
  });

  /// Splits [quarterHearts] into whole hearts and a 0–3 quarter remainder.
  ///
  /// Throws [ArgumentError] when [quarterHearts] is negative; negative health
  /// is not a display problem to hide, it is invalid input.
  factory HeartsDisplay.fromQuarterHearts(int quarterHearts) {
    if (quarterHearts < 0) {
      throw ArgumentError.value(
        quarterHearts,
        'quarterHearts',
        'must not be negative',
      );
    }
    final fullHearts = quarterHearts ~/ _unitsPerHeart;
    final quarterRemainder = quarterHearts % _unitsPerHeart;
    final totalHearts = quarterHearts / _unitsPerHeart;
    final quantity = formatQuarterHearts(quarterHearts);
    return HeartsDisplay._(
      quarterHearts: quarterHearts,
      fullHearts: fullHearts,
      quarterRemainder: quarterRemainder,
      totalHearts: totalHearts,
      text: totalHearts == 1 ? '1 heart' : '$quantity hearts',
    );
  }

  /// The original count in quarter hearts.
  final int quarterHearts;

  /// Whole hearts, floored.
  final int fullHearts;

  /// Quarter units left after [fullHearts]; always 0, 1, 2 or 3.
  final int quarterRemainder;

  /// Exact value as hearts, for example `3.5`.
  final double totalHearts;

  /// Plain text, for example `3.5 hearts`, `1 heart` or `0 hearts`.
  final String text;

  @override
  String toString() => 'HeartsDisplay($text)';
}

/// Formats [quarterHearts] as a trimmed decimal heart count.
///
/// `0` → `"0"`, `4` → `"1"`, `6` → `"1.5"`, `7` → `"1.75"`, `14` → `"3.5"`,
/// `80` → `"20"`. Decimal notation was chosen over fraction glyphs so the
/// output is ASCII and round-trips through [parseQuarterHearts] exactly.
///
/// Throws [ArgumentError] for a negative count; this function does not clamp.
String formatQuarterHearts(int quarterHearts) {
  if (quarterHearts < 0) {
    throw ArgumentError.value(
      quarterHearts,
      'quarterHearts',
      'must not be negative',
    );
  }
  return formatFloat32(quarterHearts / _unitsPerHeart, decimals: 2);
}

/// Parses a human heart count into quarter hearts.
///
/// Accepted forms, after trimming surrounding whitespace:
///
/// * a whole number of hearts: `"3"` → `12`
/// * a decimal number of hearts: `"3.5"` → `14`, `"0.25"` → `1`
/// * a heart fraction: `"14/4"` → `14`, `"3/4"` → `3`
///
/// The input must resolve to an exact whole number of quarter hearts. `"1/8"`
/// (0.125 hearts, half a quarter unit), `"1.1"` (4.4 quarter units), negatives,
/// `NaN`, empty strings, and arbitrary junk are rejected rather than rounded or
/// clamped.
/// There is no upper bound check here: `"185"` parses to `740` quarter units,
/// and callers apply [HeartsDisplay] or the health validators separately.
QuarterHeartsParseResult parseQuarterHearts(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return const QuarterHeartsParseResult.invalid('Enter a heart value.');
  }
  if (text.startsWith('-')) {
    return const QuarterHeartsParseResult.invalid('Health cannot be negative.');
  }
  if (text.contains('/')) {
    final parts = text.split('/');
    if (parts case [final numeratorText, final denominatorText]) {
      final numerator = BigInt.tryParse(numeratorText.trim());
      final denominator = BigInt.tryParse(denominatorText.trim());
      if (numerator == null || denominator == null) {
        return const QuarterHeartsParseResult.invalid(
          'A fraction must contain two whole numbers, like 14/4.',
        );
      }
      if (denominator == BigInt.zero) {
        return const QuarterHeartsParseResult.invalid(
          'The fraction denominator cannot be zero.',
        );
      }
      if (denominator < BigInt.zero) {
        return const QuarterHeartsParseResult.invalid(
          'The fraction denominator must be positive.',
        );
      }
      if (numerator < BigInt.zero) {
        return const QuarterHeartsParseResult.invalid(
          'Health cannot be negative.',
        );
      }
      return _fromFraction(numerator, denominator);
    }
    return const QuarterHeartsParseResult.invalid(
      'A fraction must have exactly one slash, like 14/4.',
    );
  }

  final match = _decimalPattern.firstMatch(text);
  if (match == null) {
    return const QuarterHeartsParseResult.invalid(
      'Use a whole number (3), a decimal (3.5), or a fraction (14/4).',
    );
  }
  final wholeText = match.group(1)!;
  final fractionText = match.group(2) ?? '';
  final scale = _pow10(fractionText.length);
  final whole = BigInt.tryParse(wholeText);
  if (whole == null) {
    return const QuarterHeartsParseResult.invalid('Heart value is too large.');
  }
  final fraction = fractionText.isEmpty
      ? BigInt.zero
      : BigInt.tryParse(fractionText);
  if (fraction == null) {
    return const QuarterHeartsParseResult.invalid('Heart value is too large.');
  }
  return _fromFraction(whole * scale + fraction, scale);
}

/// Result of [parseQuarterHearts].
///
/// Exactly one of [quarterHearts] and [error] is non-null.
final class QuarterHeartsParseResult {
  const QuarterHeartsParseResult._(this.quarterHearts, this.error);

  /// A successful parse, in quarter hearts.
  const QuarterHeartsParseResult.valid(int quarterHearts)
    : this._(quarterHearts, null);

  /// A failed parse with a human-readable reason.
  const QuarterHeartsParseResult.invalid(String error) : this._(null, error);

  /// The parsed quarter-heart count, or `null` on failure.
  final int? quarterHearts;

  /// The failure reason, or `null` on success.
  final String? error;

  /// Whether a value was parsed.
  bool get isValid => quarterHearts != null;

  @override
  String toString() => isValid
      ? 'QuarterHeartsParseResult($quarterHearts)'
      : 'QuarterHeartsParseResult.invalid($error)';
}

final RegExp _decimalPattern = RegExp(r'^(\d+)(?:\.(\d+))?$');

BigInt _pow10(int exponent) {
  var value = BigInt.one;
  for (var index = 0; index < exponent; index++) {
    value *= BigInt.from(10);
  }
  return value;
}

QuarterHeartsParseResult _fromFraction(BigInt numerator, BigInt denominator) {
  final scaled = numerator * BigInt.from(_unitsPerHeart);
  if (scaled % denominator != BigInt.zero) {
    return QuarterHeartsParseResult.invalid(
      'That is ${scaled / denominator} quarter hearts; only whole quarter '
      'hearts are stored (for example 14/4).',
    );
  }
  final quarters = scaled ~/ denominator;
  if (quarters > BigInt.from(_int32Max)) {
    return const QuarterHeartsParseResult.invalid(
      'Heart value is too large for a 32-bit health field.',
    );
  }
  return QuarterHeartsParseResult.valid(quarters.toInt());
}
