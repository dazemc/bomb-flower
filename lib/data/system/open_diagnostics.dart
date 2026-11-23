/// Pure diagnostics for one save-root open attempt.
///
/// Nothing here reads the filesystem or writes to stdout: the folder shape
/// arrives as a [SaveFolderInfo] from [SaveFolderProbe], and the caller decides
/// where the returned log line goes. That keeps both the slot-folder
/// misdiagnosis and the one-line open log testable without a host.
library;

import '../../domain/core/parse_result.dart';
import 'directory_picker.dart';

/// Outcome labels of one open attempt, matching the engine's parse result names.
enum OpenOutcome {
  /// Every slot opened and every declared field is verified.
  ok('ParseOk'),

  /// The project opened with unverified, read-only fields.
  unverified('ParseUnverified'),

  /// The layout is unknown, newer than supported, or gapped.
  unsupported('ParseUnsupported'),

  /// The bytes do not form a complete, well-formed project.
  corrupt('ParseCorrupt');

  const OpenOutcome(this.label);

  /// Engine-facing label used in the open log.
  final String label;

  /// Whether this outcome carries a reason.
  bool get hasReason => this == OpenOutcome.unsupported || this == corrupt;
}

/// Whether [info] describes a `slot_NN` folder holding a `progress.sav`.
///
/// A save root is the profile folder that contains `slot_NN`; a slot folder is
/// never a root. Detecting that shape here lets the open path explain the user's
/// mistake instead of blaming the data for a missing nested slot.
bool isSlotFolderRoot(SaveFolderInfo info) {
  if (!info.exists || !info.isDirectory) {
    return false;
  }
  if (!_slotDirectoryName.hasMatch(_baseName(info.path))) {
    return false;
  }
  return info.progressSavePresent;
}

/// The message to show when the chosen root is a slot folder, or `null`.
///
/// The message names the parent folder the user should pick instead, because
/// "damaged or incomplete" would blame the data for a selection mistake.
String? slotFolderMisselection(SaveFolderInfo info) {
  if (!isSlotFolderRoot(info)) {
    return null;
  }
  final parent = _parentOf(info.path);
  if (parent == null || parent.isEmpty) {
    return null;
  }
  return 'That is a slot folder. Choose the folder that contains it ($parent).';
}

/// Maps a parse result onto its log outcome and optional reason.
({OpenOutcome outcome, String? reason}) openOutcomeOf(ParseResult result) {
  return switch (result) {
    ParseOk() => (outcome: OpenOutcome.ok, reason: null),
    ParseUnverified() => (outcome: OpenOutcome.unverified, reason: null),
    ParseUnsupported(:final reason) => (
      outcome: OpenOutcome.unsupported,
      reason: reason,
    ),
    ParseCorrupt(:final reason) => (
      outcome: OpenOutcome.corrupt,
      reason: reason,
    ),
  };
}

/// One stdout line for one open attempt: `open <path> -> <outcome>[: reason]`.
///
/// Only the path and the engine's own reason text are included. Save bytes and
/// field values never reach this function, so they can never reach the log.
String formatOpenLogLine({
  required String path,
  required OpenOutcome outcome,
  String? reason,
  int? unverifiedFieldCount,
}) {
  final trimmed = reason?.trim() ?? '';
  final suffix = outcome.hasReason && trimmed.isNotEmpty ? ': $trimmed' : '';
  final count = outcome == OpenOutcome.unverified ? unverifiedFieldCount : null;
  final counter = count == null
      ? ''
      : ' ($count unverified field${count == 1 ? '' : 's'})';
  return 'open $path -> ${outcome.label}$counter$suffix';
}

final RegExp _slotDirectoryName = RegExp(r'^slot_\d+$');

String _baseName(String path) {
  final normalized = path.trim();
  if (normalized.isEmpty) {
    return '';
  }
  var end = normalized.length;
  while (end > 1 && _isSeparator(normalized[end - 1])) {
    end--;
  }
  final trimmed = normalized.substring(0, end);
  final index = trimmed.lastIndexOf(RegExp(r'[/\\]'));
  return index < 0 ? trimmed : trimmed.substring(index + 1);
}

String? _parentOf(String path) {
  final normalized = path.trim();
  if (normalized.isEmpty) {
    return null;
  }
  var end = normalized.length;
  while (end > 1 && _isSeparator(normalized[end - 1])) {
    end--;
  }
  final trimmed = normalized.substring(0, end);
  final index = trimmed.lastIndexOf(RegExp(r'[/\\]'));
  if (index <= 0) {
    return null;
  }
  return trimmed.substring(0, index);
}

bool _isSeparator(String char) => char == '/' || char == '\\';
