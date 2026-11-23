import 'package:bomb_flower/domain/formatting/scalars.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatRupees', () {
    test('groups thousands with commas', () {
      expect(formatRupees(0), '0');
      expect(formatRupees(1), '1');
      expect(formatRupees(999), '999');
      expect(formatRupees(1000), '1,000');
      expect(formatRupees(120572), '120,572');
      expect(formatRupees(1234567890), '1,234,567,890');
    });

    test('keeps a negative sign outside the grouped digits', () {
      expect(formatRupees(-1), '-1');
      expect(formatRupees(-1234), '-1,234');
    });
  });

  group('formatFloat32', () {
    test('trims trailing zeros', () {
      expect(formatFloat32(1), '1');
      expect(formatFloat32(1.5), '1.5');
      expect(formatFloat32(0.25), '0.25');
      expect(formatFloat32(1.23456, decimals: 2), '1.23');
      expect(formatFloat32(2, decimals: 0), '2');
      expect(formatFloat32(-1.5), '-1.5');
    });

    test('normalises negative zero', () {
      expect(formatFloat32(-0.0), '0');
    });

    test('renders non-finite values without throwing', () {
      expect(formatFloat32(double.nan), 'NaN');
      expect(formatFloat32(double.infinity), 'Infinity');
      expect(formatFloat32(double.negativeInfinity), '-Infinity');
    });

    test('rejects an out-of-range decimal count', () {
      expect(() => formatFloat32(1, decimals: -1), throwsRangeError);
      expect(() => formatFloat32(1, decimals: 21), throwsRangeError);
    });
  });

  group('formatVector3', () {
    test('uses fixed decimals and parentheses', () {
      expect(formatVector3(1, 2.5, -3.2), '(1.00, 2.50, -3.20)');
      expect(formatVector3(1, 2.5, -3.2, 1), '(1.0, 2.5, -3.2)');
      expect(formatVector3(1, 2, -3, 0), '(1, 2, -3)');
    });

    test('rejects an out-of-range decimal count', () {
      expect(() => formatVector3(1, 2, 3, 21), throwsRangeError);
    });
  });

  group('formatHex32', () {
    test('pads to eight lower-case digits', () {
      expect(formatHex32(0), '0x00000000');
      expect(formatHex32(1), '0x00000001');
      expect(formatHex32(0xBE69DE49), '0xbe69de49');
      expect(formatHex32(-1), '0xffffffff');
    });

    test('masks values wider than 32 bits', () {
      expect(formatHex32(0x100000001), '0x00000001');
    });
  });

  group('formatBytes', () {
    test('keeps exact bytes below one MiB', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1,023 B');
      expect(formatBytes(120572), '120,572 B');
      expect(formatBytes(1048575), '1,048,575 B');
    });

    test('uses binary units from one MiB upward', () {
      expect(formatBytes(1048576), '1 MiB');
      expect(formatBytes(1258291), '1.2 MiB');
      expect(formatBytes(1572864), '1.5 MiB');
      expect(formatBytes(1073741824), '1 GiB');
      expect(formatBytes(1099511627776), '1 TiB');
    });

    test('rejects a negative byte count', () {
      expect(() => formatBytes(-1), throwsArgumentError);
    });
  });

  group('formatPercent', () {
    test('formats fractions as percentages', () {
      expect(formatPercent(0), '0%');
      expect(formatPercent(0.42), '42%');
      expect(formatPercent(0.5), '50%');
      expect(formatPercent(1), '100%');
      expect(formatPercent(0.125, decimals: 1), '12.5%');
      expect(formatPercent(0.999, decimals: 1), '99.9%');
    });

    test('renders non-finite input without throwing', () {
      expect(formatPercent(double.nan), 'NaN%');
      expect(formatPercent(double.infinity), 'Infinity%');
    });

    test('rejects an out-of-range decimal count', () {
      expect(() => formatPercent(0.5, decimals: 21), throwsRangeError);
    });
  });
}
