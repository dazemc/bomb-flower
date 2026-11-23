/// Ports the pure domain uses to reach bytes and backup storage.
///
/// Implementations live in `lib/data/io`. The domain never imports `dart:io`.
library;

import 'dart:typed_data';

import '../core/byte_region.dart';
import '../core/export_plan.dart';
import '../core/field_metadata.dart';
import '../core/field_value.dart';
import '../core/identity.dart';
import '../core/layout.dart';
import '../core/parse_result.dart';
import '../core/save_project.dart';

/// Reads and writes slot bytes in one save root.
abstract interface class SlotSource {
  /// Reads [slot], or returns `null` when the file is absent.
  Future<Uint8List?> read(SaveSlotId slot);

  /// Atomically writes [slot].
  Future<void> write(
    SaveSlotId slot,
    Uint8List bytes, {
    bool keepPreviousVersion = true,
  });

  /// Absolute path for [slot], for reporting and path-conflict checks.
  String pathFor(SaveSlotId slot);

  /// Writes several slots, staging them before renaming when supported.
  ///
  /// The default implementation writes sequentially; file-backed sources
  /// override it with a batch protocol.
  Future<void> writeAll(
    Map<SaveSlotId, Uint8List> writes, {
    bool keepPreviousVersion = true,
  }) async {
    for (final entry in writes.entries) {
      await write(
        entry.key,
        entry.value,
        keepPreviousVersion: keepPreviousVersion,
      );
    }
  }
}

/// Stores the immutable sidecar originals for one save root.
abstract interface class OriginalStore {
  /// Absolute sidecar directory.
  String get rootPath;

  /// Creates the sidecar if absent; never silently replaces an existing one.
  ///
  /// Throws [OriginalBackupException] with `backup.conflict` when an existing
  /// sidecar is incomplete or does not match [originals].
  Future<void> ensure(
    Map<SaveSlotId, ByteRegion> originals,
    BackupPolicy policy,
  );

  /// Reads the sidecar original for [slot], or `null` when absent.
  Future<Uint8List?> read(SaveSlotId slot);

  /// Whether the sidecar is ready and byte-identical to [originals].
  Future<bool> verify(Map<SaveSlotId, ByteRegion> originals);
}

/// A refused or conflicting sidecar operation.
final class OriginalBackupException implements Exception {
  /// Creates an exception with a stable [code].
  const OriginalBackupException(this.code, this.message);

  /// Stable code, normally the `backup.conflict` validation code.
  final String code;

  /// Human-readable explanation.
  final String message;

  @override
  String toString() => 'OriginalBackupException[$code]: $message';
}

/// Recomputes an opaque integrity value.
///
/// The engine never knows a checksum algorithm. A codec supplied by the layout
/// layer implements this port, and only [IntegritySpec.isConfirmed] specs are
/// handed to it.
abstract interface class IntegrityRecomputer {
  /// Returns exactly `spec.region.length` replacement bytes, or `null` when
  /// this scheme cannot be recomputed.
  Uint8List? recompute(IntegritySpec spec, ByteRegion content);

  /// Returns `true`/`false` when verification is possible, or `null` when not.
  bool? verify(IntegritySpec spec, ByteRegion content);
}

/// Decodes one field into a display value.
///
/// Returning `null` means this codec does not understand the descriptor; the
/// field stays editable by bytes but gets no decoded view.
abstract interface class FieldValueCodec {
  /// Decodes [descriptor] from [content], or returns `null`.
  ///
  /// Implementations live in the codec layer; the default numeric codec is
  /// format-agnostic.
  FieldValue? decode(FieldDescriptor descriptor, ByteRegion content);
}

/// The layout chosen for a root by the data-layer detector.
final class const LayoutSelection(
  final LayoutDescriptor layout,
  final int detectedVersion,
);

/// Why a root did not resolve to a layout.
///
/// The data layer detects the cause; the domain owns the vocabulary so a
/// resolver can report it without importing file or codec code.
enum LayoutRejectionKind {
  /// No `slot_NN/progress.sav` was found, or its magic is another format's.
  notASave,

  /// The file carries a layout revision this build does not read.
  unsupportedRevision,

  /// The file is save-shaped but its container could not be decoded.
  corrupt,
}

/// The outcome of resolving a save root to a layout.
sealed class LayoutResolution {
  /// Allows subclasses to be const.
  const LayoutResolution();
}

/// Detection found a layout this build can open.
final class LayoutResolved extends LayoutResolution {
  /// Records the detected [selection].
  const LayoutResolved(this.selection);

  /// The layout and revision the save folder holds.
  final LayoutSelection selection;
}

/// Detection refused the root, with a typed [kind] and a specific [reason].
final class LayoutRejected extends LayoutResolution {
  /// Records [kind], [reason] and, when known, the offending file [path].
  const LayoutRejected(
    this.kind,
    this.reason, {
    this.detectedVersion,
    this.path,
  });

  /// Which rejection this is.
  final LayoutRejectionKind kind;

  /// What is wrong, in the detector's or codec's own words.
  final String reason;

  /// The revision read from the file, when [kind] is a revision mismatch.
  final int? detectedVersion;

  /// The file or folder that failed, when known.
  final String? path;
}

/// Resolves a save root to a layout without writing anything.
typedef LayoutResolver = Future<LayoutResolution> Function(String rootPath);

/// Data-layer repository facade used by the presentation layer.
abstract interface class SaveRepository {
  /// Opens [rootPath] read-only.
  Future<ParseResult> open(
    String rootPath, {
    bool preserveUnknown = true,
    bool verifyIntegrity = true,
  });

  /// Creates the sidecar original if absent, never replacing an existing one.
  Future<void> ensureOriginalBackup(SaveProject project, BackupPolicy policy);

  /// Writes [plan] atomically and verifies the result.
  Future<ExportResult> writeExport(
    ExportPlan plan, {
    bool allowOverwrite = false,
  });

  /// Restores one slot from its sidecar original.
  Future<SaveProject> reset(
    SaveProject project,
    SaveSlotId slot, {
    bool clearHistory = false,
  });

  /// Copies one slot's original bytes to [destinationRoot].
  Future<ExportResult> duplicate(
    SaveProject project,
    SaveSlotId slot, {
    required String destinationRoot,
    BackupPolicy policy = BackupPolicy.standard,
    bool allowOverwrite = false,
  });
}
