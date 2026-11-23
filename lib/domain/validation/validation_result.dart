/// Field-level validation findings for the save editor.
///
/// This library is deliberately independent of `lib/domain/core`: the core
/// validation model is format-agnostic and still in flux, while these findings
/// describe concrete Ocarina of Time scalar fields. Both can be merged by a
/// later presentation-layer adapter without either importing the other.
library;

/// How serious a [ValidationIssue] is.
enum Severity {
  /// Provenance or reference information; nothing is wrong with the value.
  info,

  /// The value is representable but unusual, or relies on a game convention
  /// that is not byte-verified. Warnings never block an export.
  warning,

  /// The value cannot be a valid field value under the format's own rules, or
  /// it contradicts a verified structural invariant. Errors block an export.
  error,
}

/// One problem found while validating a field.
///
/// [code] is stable and machine-readable (for example
/// `health.max_not_multiple_of_four`); [message] is a human sentence that names
/// the value. [actual] and [expected] carry the raw offending value and the
/// expected value or range so a UI can render its own phrasing.
final class ValidationIssue {
  /// Creates an issue.
  const ValidationIssue({
    required this.code,
    required this.severity,
    required this.field,
    required this.message,
    this.actual,
    this.expected,
  });

  /// Stable code, lower-case with dot-separated groups.
  final String code;

  /// How serious the finding is.
  final Severity severity;

  /// Field this finding belongs to, for example `PlayerStatus.MaxLife`.
  final String field;

  /// Human-readable explanation.
  final String message;

  /// The value that was rejected, when it is meaningful to show it.
  final Object? actual;

  /// The accepted value, range, or shape, when it is meaningful to show it.
  final Object? expected;

  /// Whether this finding is [Severity.error].
  bool get isError => severity == Severity.error;

  /// Whether this finding is [Severity.warning].
  bool get isWarning => severity == Severity.warning;

  @override
  bool operator ==(Object other) =>
      other is ValidationIssue &&
      other.code == code &&
      other.severity == severity &&
      other.field == field &&
      other.message == message &&
      other.actual == actual &&
      other.expected == expected;

  @override
  int get hashCode =>
      Object.hash(code, severity, field, message, actual, expected);

  @override
  String toString() =>
      'ValidationIssue(${severity.name}, $code, $field): $message';
}

/// Immutable aggregate of [ValidationIssue]s.
///
/// [isValid] is true when no [Severity.error] is present; warnings and infos do
/// not invalidate a value. A result is empty when no issue was found.
final class ValidationResult {
  /// Copies [issues] into an unmodifiable list, preserving their order.
  ValidationResult([
    Iterable<ValidationIssue> issues = const <ValidationIssue>[],
  ]) : issues = List<ValidationIssue>.unmodifiable(issues);

  /// A result with no issues.
  const ValidationResult.empty() : issues = const <ValidationIssue>[];

  /// The issues, in reporting order.
  final List<ValidationIssue> issues;

  /// Whether at least one [Severity.error] is present.
  bool get hasErrors => issues.any((issue) => issue.isError);

  /// Whether at least one [Severity.warning] is present.
  bool get hasWarnings => issues.any((issue) => issue.isWarning);

  /// Whether the value passes every hard rule.
  bool get isValid => !hasErrors;

  /// Whether no issue at all was reported.
  bool get isEmpty => issues.isEmpty;

  /// Only the [Severity.error] issues.
  List<ValidationIssue> get errors =>
      issues.where((issue) => issue.isError).toList(growable: false);

  /// Only the [Severity.warning] issues.
  List<ValidationIssue> get warnings =>
      issues.where((issue) => issue.isWarning).toList(growable: false);

  /// Only the [Severity.info] issues.
  List<ValidationIssue> get infos => issues
      .where((issue) => issue.severity == Severity.info)
      .toList(growable: false);

  /// Combines this result with [other], preserving both issue orders.
  ValidationResult merge(ValidationResult other) =>
      ValidationResult(<ValidationIssue>[...issues, ...other.issues]);

  /// Combines every result in [results].
  static ValidationResult mergeAll(Iterable<ValidationResult> results) {
    final merged = <ValidationIssue>[];
    for (final result in results) {
      merged.addAll(result.issues);
    }
    return ValidationResult(merged);
  }

  /// Only the issues for [field].
  List<ValidationIssue> forField(String field) =>
      issues.where((issue) => issue.field == field).toList(growable: false);

  @override
  String toString() =>
      'ValidationResult(${issues.length} issues, errors: $hasErrors, '
      'warnings: $hasWarnings)';
}
