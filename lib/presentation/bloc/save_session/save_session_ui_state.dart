/// Presentation states for one open save session.
///
/// These types contain no Flutter widgets, no `dart:io`, and no save offsets.
/// The cubit maps the pure domain controller onto them.
library;

import 'package:equatable/equatable.dart';

import '../../../domain/core/core.dart';

/// One `slot_*` folder ordered by the mtime of its `progress.sav`.
///
/// Longshot's Continue loads the newest `progress.sav` by modification time,
/// so this is a real load-order input, not decoration.
final class SlotAgeUi extends Equatable {
  /// Creates one slot age.
  const SlotAgeUi({
    required this.slot,
    required this.progressPath,
    this.modifiedAt,
  });

  /// Logical slot id, for example `slot_01`.
  final SaveSlotId slot;

  /// Absolute path of this slot's `progress.sav`.
  final String progressPath;

  /// Last modification time, or `null` when the file is missing.
  final DateTime? modifiedAt;

  /// Whether the slot has a readable timestamp.
  bool get hasTimestamp => modifiedAt != null;

  @override
  List<Object?> get props => <Object?>[slot, progressPath, modifiedAt];
}

/// One slot as the save-session UI sees it.
final class SaveSlotUi extends Equatable {
  /// Creates a slot summary.
  const SaveSlotUi({
    required this.id,
    required this.relativePath,
    required this.isOpen,
    required this.fieldCount,
    required this.changedFieldCount,
    required this.changedByteCount,
    required this.isDirty,
    this.expectedLength,
  });

  /// Logical slot id.
  final SaveSlotId id;

  /// Path relative to the save root, owned by the layout.
  final String relativePath;

  /// Whether the layout opened this slot.
  final bool isOpen;

  /// Number of fields the codec exposed for this slot.
  final int fieldCount;

  /// Fields whose bytes differ from the open-time original.
  final int changedFieldCount;

  /// Bytes that differ from the open-time original.
  final int changedByteCount;

  /// Whether this slot is listed in the unsaved-change set.
  final bool isDirty;

  /// Expected file length from the layout, when declared.
  final int? expectedLength;

  /// Whether this is an autoload `slot_NN` progress slot.
  bool get isProgressSlot => isProgressSlotId(id);

  @override
  List<Object?> get props => <Object?>[
    id,
    relativePath,
    isOpen,
    fieldCount,
    changedFieldCount,
    changedByteCount,
    isDirty,
    expectedLength,
  ];
}

/// One written file and its post-write fingerprint.
final class SlotWriteUi extends Equatable {
  /// Creates a write report row.
  const SlotWriteUi({required this.slot, required this.path, this.fingerprint});

  /// Logical slot id.
  final SaveSlotId slot;

  /// Absolute path the export wrote and re-read.
  final String path;

  /// FNV-1a 32 hint of the written bytes, when the repository reported one.
  final int? fingerprint;

  @override
  List<Object?> get props => <Object?>[slot, path, fingerprint];
}

/// The open project, flattened for display.
final class SaveProjectUi extends Equatable {
  /// Creates a project summary.
  const SaveProjectUi({
    required this.projectId,
    required this.path,
    required this.backupPath,
    required this.layoutId,
    required this.detectedVersion,
    required this.slots,
    required this.activeSlot,
    required this.newestSlot,
    required this.slotAges,
    required this.hasUnsavedChanges,
    required this.differsFromOriginal,
    required this.changedFieldCount,
    required this.changedByteCount,
    required this.canUndo,
    required this.canRedo,
    required this.canSave,
    required this.issues,
    required this.validationSummary,
    required this.statusMessage,
    required this.preserveUnknown,
  });

  /// Stable project id from the domain.
  final String projectId;

  /// Save root.
  final String path;

  /// Retained original sidecar path.
  final String backupPath;

  /// Layout identity.
  final String layoutId;

  /// Detected layout version.
  final int detectedVersion;

  /// Layout slots in declaration order.
  final List<SaveSlotUi> slots;

  /// The progress slot currently being edited or selected.
  final SaveSlotId? activeSlot;

  /// The `slot_*` folder whose `progress.sav` has the newest mtime.
  final SaveSlotId? newestSlot;

  /// Every detected `slot_*` folder, sorted by slot name.
  final List<SlotAgeUi> slotAges;

  /// Whether changed bytes have not been exported.
  final bool hasUnsavedChanges;

  /// Whether current bytes differ from the open-time original.
  final bool differsFromOriginal;

  /// Changed fields across the whole project.
  final int changedFieldCount;

  /// Changed bytes across the whole project.
  final int changedByteCount;

  /// Whether undo is available.
  final bool canUndo;

  /// Whether redo is available.
  final bool canRedo;

  /// Whether an export would write something.
  final bool canSave;

  /// Engine validation issues.
  final List<ValidationIssue> issues;

  /// Human-readable issue counts.
  final String validationSummary;

  /// Last action summary for the status line.
  final String statusMessage;

  /// Whether untouched bytes are preserved on export.
  final bool preserveUnknown;

  /// Whether any issue blocks export.
  bool get hasBlockingErrors => issues.any((issue) => issue.isBlocking);

  /// Number of blocking issues.
  int get blockingIssueCount =>
      issues.where((issue) => issue.isBlocking).length;

  /// Number of warning issues.
  int get warningCount =>
      issues.where((issue) => issue.severity == Severity.warning).length;

  /// Slots that are open.
  List<SaveSlotUi> get openSlots =>
      slots.where((slot) => slot.isOpen).toList(growable: false);

  /// The age row for [slot], if the host reported one.
  SlotAgeUi? ageFor(SaveSlotId? slot) {
    if (slot == null) {
      return null;
    }
    for (final age in slotAges) {
      if (age.slot == slot) {
        return age;
      }
    }
    return null;
  }

  /// Whether the active progress slot is the one Longshot will load.
  ///
  /// No known newest slot means there is nothing to warn about.
  bool get isActiveSlotNewest {
    final newest = newestSlot;
    final active = activeSlot;
    if (newest == null || active == null) {
      return true;
    }
    return newest == active;
  }

  /// Whether the action "Use newest slot" can switch to an open slot.
  bool get canUseNewestSlot {
    final newest = newestSlot;
    if (newest == null) {
      return false;
    }
    return slots.any((slot) => slot.id == newest && slot.isOpen);
  }

  /// The active slot's age row.
  SlotAgeUi? get activeAge => ageFor(activeSlot);

  @override
  List<Object?> get props => <Object?>[
    projectId,
    path,
    backupPath,
    layoutId,
    detectedVersion,
    slots,
    activeSlot,
    newestSlot,
    slotAges,
    hasUnsavedChanges,
    differsFromOriginal,
    changedFieldCount,
    changedByteCount,
    canUndo,
    canRedo,
    canSave,
    issues,
    validationSummary,
    statusMessage,
    preserveUnknown,
  ];
}

/// Whether a slot id is an autoload progress slot (`slot_00`, `slot_01`, ...).
bool isProgressSlotId(SaveSlotId slot) =>
    RegExp(r'^slot_\d+$').hasMatch(slot.value);

/// Why a save-session action failed.
enum SaveSessionErrorKind {
  /// The layout resolver has no layout for the folder.
  unsupportedLayout,

  /// The slot files exist but do not form a valid project.
  corruptSave,

  /// An export or reset was refused.
  refused,

  /// A change was refused by the field rules.
  editRefused,

  /// The filesystem or a host process failed.
  ioFailure,

  /// A save was written but the newest-slot timestamp was not.
  timestampFailed,

  /// No project is open for the requested action.
  notOpen,

  /// The save engine is not wired in this build.
  disabled,
}

/// Session presentation states.
sealed class SaveSessionUiState extends Equatable {
  /// Allows subclasses to be const.
  const SaveSessionUiState();

  @override
  List<Object?> get props => const <Object?>[];
}

/// No project is open.
final class SaveSessionClosed extends SaveSessionUiState {
  /// Creates the closed state.
  const SaveSessionClosed();

  @override
  String toString() => 'SaveSessionClosed()';
}

/// A folder is being parsed.
final class SaveSessionOpening extends SaveSessionUiState {
  /// Creates the opening state.
  const SaveSessionOpening(this.path);

  /// Folder being opened.
  final String path;

  @override
  List<Object?> get props => <Object?>[path];

  @override
  String toString() => 'SaveSessionOpening($path)';
}

/// The project is editable.
final class SaveSessionReady extends SaveSessionUiState {
  /// Creates the ready state.
  const SaveSessionReady(this.project);

  /// Flattened project.
  final SaveProjectUi project;

  @override
  List<Object?> get props => <Object?>[project];

  @override
  String toString() => 'SaveSessionReady(${project.path})';
}

/// An export is in flight.
final class SaveSessionSaving extends SaveSessionUiState {
  /// Creates the saving state.
  const SaveSessionSaving({
    required this.project,
    required this.destinationPath,
    required this.mode,
  });

  /// Project being written.
  final SaveProjectUi project;

  /// Root being written to.
  final String destinationPath;

  /// Export mode.
  final ExportMode mode;

  @override
  List<Object?> get props => <Object?>[project, destinationPath, mode];

  @override
  String toString() => 'SaveSessionSaving($destinationPath)';
}

/// An export succeeded.
final class SaveSessionSaved extends SaveSessionUiState {
  /// Creates the saved state.
  const SaveSessionSaved({
    required this.path,
    required this.mode,
    this.project,
    this.written = const <SlotWriteUi>[],
    this.warnings = const <String>[],
    this.statusMessage = 'Save complete',
  });

  /// Root that was written.
  final String path;

  /// Export mode.
  final ExportMode mode;

  /// The project after the export, when available.
  final SaveProjectUi? project;

  /// Files written and verified.
  final List<SlotWriteUi> written;

  /// Non-fatal problems, such as a failed mtime update.
  final List<String> warnings;

  /// Summary for the status line.
  final String statusMessage;

  /// Whether anything was written.
  int get writtenCount => written.length;

  @override
  List<Object?> get props => <Object?>[
    path,
    mode,
    project,
    written,
    warnings,
    statusMessage,
  ];

  @override
  String toString() => 'SaveSessionSaved($path, ${written.length} file(s))';
}

/// Closing was requested while unsaved changes exist.
///
/// The project is still open and untouched. The UI must ask the user, then call
/// `confirmDiscard()` (discard) or `cancelDiscard()` (keep editing).
final class SaveSessionPendingDiscard extends SaveSessionUiState {
  /// Creates the guard state.
  const SaveSessionPendingDiscard(this.project);

  /// The dirty project that would be lost.
  final SaveProjectUi project;

  @override
  List<Object?> get props => <Object?>[project];

  @override
  String toString() =>
      'SaveSessionPendingDiscard(${project.changedFieldCount} changed field(s))';
}

/// A failed action.
final class SaveSessionError extends SaveSessionUiState {
  /// Creates an error state.
  const SaveSessionError({
    required this.message,
    this.details,
    this.recoverable = false,
    this.kind = SaveSessionErrorKind.ioFailure,
    this.project,
  });

  /// Friendly, primary explanation.
  final String message;

  /// Technical context, safe to show under an expander or copy button.
  final String? details;

  /// Whether the same session can continue after fixing the cause.
  final bool recoverable;

  /// Failure category.
  final SaveSessionErrorKind kind;

  /// The project that remains open, if any.
  final SaveProjectUi? project;

  @override
  List<Object?> get props => <Object?>[
    message,
    details,
    recoverable,
    kind,
    project,
  ];

  @override
  String toString() => 'SaveSessionError(${kind.name}: $message)';
}
