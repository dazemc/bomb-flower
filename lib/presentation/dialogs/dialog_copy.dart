/// User-facing copy shared by the save-file dialogs.
///
/// The wording is part of the contract: the game clamps instead of rejecting,
/// the format has no checksum, and Longshot loads the newest progress.sav.
library;

import '../../../domain/core/core.dart';

/// Stable strings for the save workflows.
abstract final class SaveWorkflowCopy {
  /// Longshot's load order depends on the newest mtime, not on the slot id.
  static String notNewestSlot(SaveSlotId newest) =>
      'This is not the newest slot; Longshot will load ${newest.value}. '
      'Save to the newest slot or update its timestamp.';

  /// The game is more permissive than this editor.
  static const String gameClampsInvalidValues =
      'The game silently clamps invalid values when it loads a save. '
      "This editor's validation is the only safeguard.";

  /// There is no checksum in this format.
  static const String noChecksum =
      'This save format has no checksum. This editor cannot detect '
      'pre-existing tampering.';

  /// Closing or browsing does not touch the files on disk.
  static const String originalFilesUntouched =
      'The save files on disk are not modified until you save. '
      'Closing now only discards the edits in this window.';

  /// The sidecar keeps the open-time bytes for a reset.
  static String originalBackupRetained(String backupPath) =>
      'The retained original backup stays at $backupPath.';

  /// The mtime checkbox label required by the autosave-slot workflow.
  static const String makeNewestLabel =
      'Make this slot the newest so Longshot loads it';

  /// Why the mtime checkbox exists.
  static const String newestSlotExplanation =
      "Longshot's Continue uses the newest progress.sav by modification time, "
      'not the lowest slot number.';

  /// A warning shown when a restore may change the load order.
  static const String resetMayChangeLoadOrder =
      'Restoring writes this slot file, which may change which progress.sav is '
      'newest. Longshot will then load that newest file.';
}
