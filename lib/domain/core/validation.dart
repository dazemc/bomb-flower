/// Validation issues and aggregate result.
library;

import 'identity.dart';

/// How serious a [ValidationIssue] is.
enum Severity {
  /// Provenance or informational reminder.
  info,

  /// Worth showing; does not block export.
  warning,

  /// Blocks export.
  error,
}

/// One problem found while validating layout, bytes, or export state.
final class const ValidationIssue(
  final Severity severity,
  final String code,
  final String message,
  final SaveSlotId slot, {
  final FieldId? field,
  final String? remedy,
}) {
  /// Whether this issue blocks export.
  bool get isBlocking => severity == Severity.error;

  /// Whether this issue is a provenance notice rather than a problem.
  ///
  /// A [ValidationCodes.fieldUnverified] warning says the field's meaning is
  /// not backed by research and the field is therefore read-only. Nothing is
  /// wrong with the save, so a status line must not count it as a warning.
  /// The same code emitted at [Severity.error] (a verified field with no
  /// citation) is a real problem and is deliberately not informational.
  bool get isInformational =>
      severity == Severity.warning && code == ValidationCodes.fieldUnverified;

  /// Whether this issue asks the user to act.
  ///
  /// [Severity.error] blocking is reported through [isBlocking]; a warning is
  /// actionable unless it is a provenance notice. `field.out_of_range` stays
  /// actionable: an out-of-range value is something to look at, while "this
  /// field is not research-verified" is not.
  bool get isActionableWarning =>
      severity == Severity.warning && !isInformational;

  @override
  bool operator ==(Object other) =>
      other is ValidationIssue &&
      other.severity == severity &&
      other.code == code &&
      other.message == message &&
      other.slot == slot &&
      other.field == field &&
      other.remedy == remedy;

  @override
  int get hashCode => Object.hash(severity, code, message, slot, field, remedy);

  @override
  String toString() =>
      'ValidationIssue(${severity.name}, $code, ${slot.value}): $message';
}

/// Stable validation issue codes from the engine contract.
abstract final class ValidationCodes {
  /// The detected layout version is unknown or newer than supported.
  static const String layoutUnsupported = 'layout.unsupported';

  /// A slot is missing or its length differs from the layout.
  static const String fileSizeMismatch = 'file.size_mismatch';

  /// A field is inferred or unverified and therefore not editable.
  static const String fieldUnverified = 'field.unverified';

  /// A field's current bytes are outside its declared bounds.
  static const String fieldOutOfRange = 'field.out_of_range';

  /// A field span is empty, negative, or outside the slot.
  static const String fieldSpanInvalid = 'field.span_invalid';

  /// An integrity scheme is unconfirmed, or no recomputer can service it.
  static const String integrityUnconfirmed = 'integrity.unconfirmed';

  /// A confirmed integrity value does not match the bytes.
  static const String checksumMismatch = 'checksum.mismatch';

  /// A write did not verify after the atomic rename.
  static const String writeVerifyFailed = 'write.verify_failed';

  /// An existing sidecar cannot be reused or safely replaced.
  static const String backupConflict = 'backup.conflict';

  /// Source, sidecar, and destination paths overlap or are invalid.
  static const String pathConflict = 'path.conflict';
}

/// Immutable aggregate of [ValidationIssue]s.
final class ValidationResult {
  /// Copies [issues] into an unmodifiable list.
  ValidationResult(Iterable<ValidationIssue> issues)
    : issues = List<ValidationIssue>.unmodifiable(issues);

  /// An empty result.
  const ValidationResult.empty() : issues = const <ValidationIssue>[];

  /// The issues, in reporting order.
  final List<ValidationIssue> issues;

  /// Issues with [Severity.error].
  List<ValidationIssue> get blockingIssues =>
      issues.where((issue) => issue.isBlocking).toList(growable: false);

  /// Warnings and infos that do not block export.
  List<ValidationIssue> get nonBlockingIssues =>
      issues.where((issue) => !issue.isBlocking).toList(growable: false);

  /// Whether any issue blocks export.
  bool get hasBlockingErrors => issues.any((issue) => issue.isBlocking);

  /// Whether no issue exists.
  bool get isEmpty => issues.isEmpty;

  /// Whether export is permitted.
  bool get canExport => !hasBlockingErrors;

  /// Filters issues for [slot].
  List<ValidationIssue> forSlot(SaveSlotId slot) =>
      issues.where((issue) => issue.slot == slot).toList(growable: false);

  @override
  String toString() =>
      'ValidationResult(${issues.length} issues, '
      'blocking: $hasBlockingErrors)';
}
