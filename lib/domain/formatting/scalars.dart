/// Display formatting for scalar save values.
///
/// These functions are presentation helpers, not validators: they never reject
/// a value and never clamp one. Callers validate first (see
/// `lib/domain/validation/field_validators.dart`) and format afterwards.
library;

/// Formats [value] with comma thousands separators.
///
/// `0` → `"0"`, `120572` → `"120,572"`, `-1234` → `"-1,234"`. The minus sign
/// stays outside the grouped digits.
String formatRupees(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[index]);
  }
  return '${negative ? '-' : ''}$buffer';
}

/// Formats a double with at most [decimals] fractional digits, trimming
/// trailing zeros.
///
/// `1.0` → `"1"`, `1.5` → `"1.5"`, `0.25` → `"0.25"`, `-0.0` → `"0"`. NaN and
/// infinities render as `"NaN"`, `"Infinity"` and `"-Infinity"` so a display
/// never throws; validation is responsible for rejecting them. [decimals] must
/// be between 0 and 20.
String formatFloat32(double value, {int decimals = 3}) {
  _checkDecimals(decimals);
  if (value.isNaN) {
    return 'NaN';
  }
  if (value.isInfinite) {
    return value.isNegative ? '-Infinity' : 'Infinity';
  }
  if (value == 0) {
    return '0';
  }
  final fixed = value.toStringAsFixed(decimals);
  if (!fixed.contains('.')) {
    return fixed;
  }
  var trimmed = fixed.replaceFirst(RegExp(r'0+$'), '');
  if (trimmed.endsWith('.')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

/// Formats a position as `(x, y, z)` with [decimals] fixed fractional digits.
///
/// Fixed digits keep coordinates aligned in a table: `formatVector3(1, 2.5,
/// -3.2, 1)` → `"(1.0, 2.5, -3.2)"`. [decimals] must be between 0 and 20.
String formatVector3(double x, double y, double z, [int decimals = 2]) {
  _checkDecimals(decimals);
  return '(${x.toStringAsFixed(decimals)}, '
      '${y.toStringAsFixed(decimals)}, '
      '${z.toStringAsFixed(decimals)})';
}

/// Formats [value] as a `0x`-prefixed, eight-digit lower-case 32-bit integer.
///
/// `0` → `"0x00000000"`, `0xBE69DE49` → `"0xbe69de49"`, `-1` →
/// `"0xffffffff"`. Values wider than 32 bits are masked, because every caller
/// of this helper is rendering a 32-bit field.
String formatHex32(int value) {
  final masked = value & 0xFFFFFFFF;
  return '0x${masked.toRadixString(16).padLeft(8, '0')}';
}

/// Formats a byte count for a file-size label.
///
/// Below one mebibyte the exact byte count is kept so a save's size is never
/// rounded: `0` → `"0 B"`, `120572` → `"120,572 B"`. From one MiB upward the
/// binary unit is used with at most one decimal, trimming `.0`: `1048576` →
/// `"1 MiB"`, `1258291` → `"1.2 MiB"`, `1073741824` → `"1 GiB"`.
///
/// Throws [ArgumentError] for a negative count.
String formatBytes(int bytes) {
  if (bytes < 0) {
    throw ArgumentError.value(bytes, 'bytes', 'must not be negative');
  }
  const mebibyte = 1024 * 1024;
  if (bytes < mebibyte) {
    return '${formatRupees(bytes)} B';
  }
  const units = <String>['MiB', 'GiB', 'TiB', 'PiB', 'EiB'];
  var value = bytes / mebibyte;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final fixed = value.toStringAsFixed(1);
  final trimmed = fixed.endsWith('.0')
      ? fixed.substring(0, fixed.length - 2)
      : fixed;
  return '$trimmed ${units[unit]}';
}

/// Formats a fraction (`1.0` = 100%) as a percentage.
///
/// `0` → `"0%"`, `0.42` → `"42%"`, `0.125` with `decimals: 1` → `"12.5%"`,
/// `1` → `"100%"`. Trailing zeros are trimmed, and a non-finite input renders
/// as `"NaN%"` or `"Infinity%"` instead of throwing. [decimals] must be
/// between 0 and 20.
String formatPercent(double fraction, {int decimals = 0}) {
  _checkDecimals(decimals);
  return '${formatFloat32(fraction * 100, decimals: decimals)}%';
}

void _checkDecimals(int decimals) {
  if (decimals < 0 || decimals > 20) {
    throw RangeError.range(decimals, 0, 20, 'decimals');
  }
}
