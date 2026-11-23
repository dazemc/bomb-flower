import 'package:bomb_flower/domain/formatting/hearts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HeartsDisplay.fromQuarterHearts', () {
    test('renders 0 quarter units as empty health', () {
      final display = HeartsDisplay.fromQuarterHearts(0);
      expect(display.quarterHearts, 0);
      expect(display.fullHearts, 0);
      expect(display.quarterRemainder, 0);
      expect(display.totalHearts, 0);
      expect(display.text, '0 hearts');
    });

    test('splits one quarter unit into a remainder', () {
      final display = HeartsDisplay.fromQuarterHearts(1);
      expect(display.fullHearts, 0);
      expect(display.quarterRemainder, 1);
      expect(display.totalHearts, 0.25);
      expect(display.text, '0.25 hearts');
    });

    test('renders half a heart', () {
      expect(HeartsDisplay.fromQuarterHearts(2).text, '0.5 hearts');
    });

    test('renders three quarters', () {
      expect(HeartsDisplay.fromQuarterHearts(3).text, '0.75 hearts');
    });

    test('uses the singular for exactly one heart', () {
      final display = HeartsDisplay.fromQuarterHearts(4);
      expect(display.fullHearts, 1);
      expect(display.quarterRemainder, 0);
      expect(display.totalHearts, 1);
      expect(display.text, '1 heart');
    });

    test('renders 1.5 hearts', () {
      final display = HeartsDisplay.fromQuarterHearts(6);
      expect(display.fullHearts, 1);
      expect(display.quarterRemainder, 2);
      expect(display.text, '1.5 hearts');
    });

    test('renders 1.75 hearts', () {
      final display = HeartsDisplay.fromQuarterHearts(7);
      expect(display.fullHearts, 1);
      expect(display.quarterRemainder, 3);
      expect(display.text, '1.75 hearts');
    });

    test('renders the three-heart minimum', () {
      final display = HeartsDisplay.fromQuarterHearts(12);
      expect(display.fullHearts, 3);
      expect(display.quarterRemainder, 0);
      expect(display.text, '3 hearts');
    });

    test('renders the twenty-heart vanilla maximum', () {
      final display = HeartsDisplay.fromQuarterHearts(80);
      expect(display.fullHearts, 20);
      expect(display.quarterRemainder, 0);
      expect(display.totalHearts, 20);
      expect(display.text, '20 hearts');
    });

    test('rejects negative quarter hearts instead of clamping', () {
      expect(() => HeartsDisplay.fromQuarterHearts(-1), throwsArgumentError);
    });
  });

  group('formatQuarterHearts', () {
    test('uses trimmed ASCII decimals', () {
      expect(formatQuarterHearts(0), '0');
      expect(formatQuarterHearts(1), '0.25');
      expect(formatQuarterHearts(3), '0.75');
      expect(formatQuarterHearts(4), '1');
      expect(formatQuarterHearts(6), '1.5');
      expect(formatQuarterHearts(7), '1.75');
      expect(formatQuarterHearts(12), '3');
      expect(formatQuarterHearts(14), '3.5');
      expect(formatQuarterHearts(80), '20');
    });

    test('rejects negative quarter hearts instead of clamping', () {
      expect(() => formatQuarterHearts(-4), throwsArgumentError);
    });
  });

  group('parseQuarterHearts', () {
    test('parses whole hearts', () {
      expect(parseQuarterHearts('3').quarterHearts, 12);
      expect(parseQuarterHearts('0').quarterHearts, 0);
      expect(parseQuarterHearts(' 2 ').quarterHearts, 8);
      expect(parseQuarterHearts('185').quarterHearts, 740);
    });

    test('parses decimal hearts exactly', () {
      expect(parseQuarterHearts('3.5').quarterHearts, 14);
      expect(parseQuarterHearts('3.50').quarterHearts, 14);
      expect(parseQuarterHearts('0.25').quarterHearts, 1);
      expect(parseQuarterHearts('0.5').quarterHearts, 2);
      expect(parseQuarterHearts('1.75').quarterHearts, 7);
    });

    test('parses quarter fractions exactly', () {
      expect(parseQuarterHearts('14/4').quarterHearts, 14);
      expect(parseQuarterHearts('3/4').quarterHearts, 3);
      expect(parseQuarterHearts('2/8').quarterHearts, 1);
      expect(parseQuarterHearts('14 / 4').quarterHearts, 14);
    });

    test('round-trips every requested quarter count', () {
      for (final quarters in <int>[0, 1, 3, 4, 6, 7, 12, 80]) {
        final text = formatQuarterHearts(quarters);
        expect(
          parseQuarterHearts(text).quarterHearts,
          quarters,
          reason: '$quarters via "$text"',
        );
      }
    });

    test('rejects values that are not whole quarter hearts', () {
      for (final input in <String>['2/7', '1/8', '1.1', '0.0001']) {
        final result = parseQuarterHearts(input);
        expect(result.isValid, isFalse, reason: input);
        expect(result.quarterHearts, isNull, reason: input);
        expect(result.error, isNotNull, reason: input);
      }
    });

    test('rejects junk and malformed fractions', () {
      for (final input in <String>[
        '',
        '   ',
        'abc',
        '3.',
        '3/4/5',
        '1/0',
        '1/-4',
        'NaN',
        'Infinity',
        '1e3',
        '+3',
      ]) {
        final result = parseQuarterHearts(input);
        expect(result.isValid, isFalse, reason: '"$input"');
        expect(result.error, isNotNull, reason: '"$input"');
      }
    });

    test('rejects negative values instead of clamping to zero', () {
      final result = parseQuarterHearts('-1');
      expect(result.isValid, isFalse);
      expect(result.error, contains('negative'));
    });

    test('rejects values that overflow the Int32 health field', () {
      final result = parseQuarterHearts('99999999999999999999');
      expect(result.isValid, isFalse);
      expect(result.error, contains('too large'));
    });
  });
}
