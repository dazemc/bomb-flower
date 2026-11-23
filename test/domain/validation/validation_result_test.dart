import 'package:bomb_flower/domain/validation/validation_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ValidationIssue', () {
    const issue = ValidationIssue(
      code: 'health.max_negative',
      severity: Severity.error,
      field: 'PlayerStatus.MaxLife',
      message: 'MaxLife cannot be negative.',
      actual: -4,
      expected: '0..2147483647',
    );

    test('exposes severity helpers', () {
      expect(issue.isError, isTrue);
      expect(issue.isWarning, isFalse);
      expect(issue.field, 'PlayerStatus.MaxLife');
      expect(issue.actual, -4);
      expect(issue.expected, '0..2147483647');
    });

    test('compares by value', () {
      const same = ValidationIssue(
        code: 'health.max_negative',
        severity: Severity.error,
        field: 'PlayerStatus.MaxLife',
        message: 'MaxLife cannot be negative.',
        actual: -4,
        expected: '0..2147483647',
      );
      expect(issue, equals(same));
      expect(issue.hashCode, equals(same.hashCode));
      expect(
        issue ==
            const ValidationIssue(
              code: 'health.max_negative',
              severity: Severity.warning,
              field: 'PlayerStatus.MaxLife',
              message: 'MaxLife cannot be negative.',
              actual: -4,
              expected: '0..2147483647',
            ),
        isFalse,
      );
    });

    test('formats a diagnostic string', () {
      expect(issue.toString(), contains('health.max_negative'));
      expect(issue.toString(), contains('PlayerStatus.MaxLife'));
    });
  });

  group('ValidationResult', () {
    const error = ValidationIssue(
      code: 'a.error',
      severity: Severity.error,
      field: 'a',
      message: 'bad',
    );
    const warning = ValidationIssue(
      code: 'a.warning',
      severity: Severity.warning,
      field: 'a',
      message: 'odd',
    );
    const info = ValidationIssue(
      code: 'a.info',
      severity: Severity.info,
      field: 'a',
      message: 'note',
    );

    test('separates errors, warnings and infos', () {
      final result = ValidationResult(<ValidationIssue>[error, warning, info]);
      expect(result.hasErrors, isTrue);
      expect(result.hasWarnings, isTrue);
      expect(result.isValid, isFalse);
      expect(result.isEmpty, isFalse);
      expect(result.errors, hasLength(1));
      expect(result.warnings, hasLength(1));
      expect(result.infos, hasLength(1));
      expect(result.forField('a'), hasLength(3));
      expect(result.forField('b'), isEmpty);
    });

    test('warnings alone keep the value valid', () {
      final result = ValidationResult(<ValidationIssue>[warning, info]);
      expect(result.hasErrors, isFalse);
      expect(result.hasWarnings, isTrue);
      expect(result.isValid, isTrue);
    });

    test('empty result is valid and empty', () {
      const result = ValidationResult.empty();
      expect(result.isEmpty, isTrue);
      expect(result.isValid, isTrue);
      expect(result.hasErrors, isFalse);
      expect(result.hasWarnings, isFalse);
      expect(result.issues, isEmpty);
    });

    test('merge appends issues in order', () {
      final first = ValidationResult(<ValidationIssue>[error]);
      final second = ValidationResult(<ValidationIssue>[warning, info]);
      final merged = first.merge(second);
      expect(merged.issues, <ValidationIssue>[error, warning, info]);
      expect(merged.hasErrors, isTrue);
      expect(merged.hasWarnings, isTrue);
      expect(first.issues, hasLength(1));
    });

    test('mergeAll combines every result', () {
      final merged = ValidationResult.mergeAll(<ValidationResult>[
        const ValidationResult.empty(),
        ValidationResult(<ValidationIssue>[warning]),
        ValidationResult(<ValidationIssue>[error, info]),
      ]);
      expect(merged.issues, hasLength(3));
      expect(merged.hasErrors, isTrue);
      expect(merged.hasWarnings, isTrue);
    });

    test('issues are unmodifiable and copying does not alias the source', () {
      final source = <ValidationIssue>[error];
      final result = ValidationResult(source);
      source.add(warning);
      expect(result.issues, <ValidationIssue>[error]);
      expect(() => result.issues.add(warning), throwsUnsupportedError);
    });

    test('describes its counts', () {
      final result = ValidationResult(<ValidationIssue>[error, warning]);
      expect(result.toString(), contains('2 issues'));
      expect(result.toString(), contains('errors: true'));
      expect(result.toString(), contains('warnings: true'));
    });
  });
}
