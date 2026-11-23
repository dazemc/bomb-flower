import 'package:material_ui/material_ui.dart';

import '../theme/bomb_flower_colors.dart';
import '../widgets/common/confirm_dialog.dart';
import 'dialog_copy.dart';

/// Confirms restoring one slot from the retained open-time original.
class ResetSlotDialog extends StatelessWidget {
  /// Creates the dialog.
  const ResetSlotDialog({
    super.key,
    required this.slotLabel,
    required this.backupPath,
    this.backupSlotPath,
  });

  /// Human label for the slot, for example `slot_00`.
  final String slotLabel;

  /// Sidecar root that retains the original bytes.
  final String backupPath;

  /// Optional exact file retained for this slot.
  final String? backupSlotPath;

  /// Shows the dialog and returns true only after an explicit confirmation.
  static Future<bool> show(
    BuildContext context, {
    required String slotLabel,
    required String backupPath,
    String? backupSlotPath,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: BombFlowerColors.scrim,
      builder: (dialogContext) => ResetSlotDialog(
        slotLabel: slotLabel,
        backupPath: backupPath,
        backupSlotPath: backupSlotPath,
      ),
    ).then((value) => value ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final file = backupSlotPath;
    return ConfirmDialog(
      title: 'Restore $slotLabel from the original backup?',
      message:
          'This writes the open-time bytes for $slotLabel back to disk and '
          'replaces the current bytes in that slot. Other slots are not '
          'touched. ${SaveWorkflowCopy.resetMayChangeLoadOrder}',
      detail: file == null ? 'Backup: $backupPath' : 'Backup: $file',
      cancelLabel: 'Cancel',
      confirmLabel: 'Restore slot',
      destructive: true,
    );
  }
}
