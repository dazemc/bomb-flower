/// Export plans, backup policy, and export results.
library;

import 'identity.dart';
import 'save_project.dart';
import 'save_snapshot.dart';
import 'validation.dart';

/// How bytes leave the open project.
enum ExportMode {
  /// Replace files in the source root in place.
  saveInPlace,

  /// Write the current state to a distinct destination.
  saveAs,

  /// Copy the opened original bytes to a new location.
  duplicate,
}

/// How originals and previous versions are treated during export.
final class const BackupPolicy({
  final String sidecarSuffix = '.bombflower-original',
  final bool keepPreviousVersion = true,
  final Duration? autosaveInterval,
  final bool verifyAfterWrite = true,
}) {
  /// The default policy: sidecar original, one `.bak`, verify writes.
  static const BackupPolicy standard = BackupPolicy();
}

/// A fully validated description of what an export will write.
final class const ExportPlan(
  final SaveProject project,
  final ExportMode mode,
  final String destinationRoot,
  final Map<SaveSlotId, SaveSnapshot> writes,
  final List<ValidationIssue> blockingIssues,
  final BackupPolicy backupPolicy,
  final bool requiresIntegrityRecompute,
) {
  /// Whether no blocking issue exists.
  bool get isSafe => blockingIssues.isEmpty;

  /// Slots that will be written.
  Set<SaveSlotId> get slots => writes.keys.toSet();
}

/// The outcome of an export attempt.
final class ExportResult {
  /// Creates a result.
  const ExportResult({
    required this.succeeded,
    this.writtenPaths = const <SaveSlotId, String>{},
    this.fingerprints = const <SaveSlotId, int>{},
    this.project,
    this.issues = const <ValidationIssue>[],
    this.error,
  });

  /// A refused export with [issues] and no writes.
  factory ExportResult.blocked(List<ValidationIssue> issues) =>
      ExportResult(succeeded: false, issues: issues);

  /// Whether every write and verification succeeded.
  final bool succeeded;

  /// Absolute path written for each slot.
  final Map<SaveSlotId, String> writtenPaths;

  /// FNV-1a 32 hint of each written payload.
  final Map<SaveSlotId, int> fingerprints;

  /// The project updated with new saved fingerprints, when successful.
  final SaveProject? project;

  /// Validation or write issues encountered.
  final List<ValidationIssue> issues;

  /// A human-readable error for an unexpected failure.
  final String? error;

  /// Whether the attempt did not succeed.
  bool get failed => !succeeded;

  @override
  String toString() =>
      'ExportResult(succeeded: $succeeded, slots: '
      '${writtenPaths.map((slot, path) => MapEntry(slot.value, path))})';
}
