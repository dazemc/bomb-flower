import 'package:material_ui/material_ui.dart' hide Banner;

import '../theme/bomb_flower_colors.dart';
import '../theme/bomb_flower_spacing.dart';
import '../theme/bomb_flower_typography.dart';
import '../widgets/common/banner.dart';
import '../widgets/common/brass_button.dart';
import 'dialog_copy.dart';
import 'save_dialog_frame.dart';

/// What the user chose in [UnsavedChangesDialog].
enum UnsavedChangesChoice {
  /// Save the edits, then continue.
  save,

  /// Discard the edits.
  discard,

  /// Keep editing.
  cancel,
}

/// Save / Discard / Cancel for a dirty project.
class UnsavedChangesDialog extends StatelessWidget {
  /// Creates the dialog.
  const UnsavedChangesDialog({
    super.key,
    required this.changedFieldCount,
    this.changedByteCount = 0,
    this.path,
  });

  /// Number of fields that differ from the saved state.
  final int changedFieldCount;

  /// Number of bytes that differ from the saved state.
  final int changedByteCount;

  /// Save root, shown for context.
  final String? path;

  /// Shows the dialog. Dismissal without a choice counts as Cancel.
  static Future<UnsavedChangesChoice> show(
    BuildContext context, {
    required int changedFieldCount,
    int changedByteCount = 0,
    String? path,
  }) async {
    final choice = await showDialog<UnsavedChangesChoice>(
      context: context,
      barrierDismissible: false,
      barrierColor: BombFlowerColors.scrim,
      builder: (dialogContext) => UnsavedChangesDialog(
        changedFieldCount: changedFieldCount,
        changedByteCount: changedByteCount,
        path: path,
      ),
    );
    return choice ?? UnsavedChangesChoice.cancel;
  }

  @override
  Widget build(BuildContext context) {
    final fields = changedFieldCount == 1
        ? '1 changed field'
        : '$changedFieldCount changed fields';
    return SaveDialogFrame(
      title: 'Unsaved changes',
      subtitle: path,
      icon: Icons.warning_amber_outlined,
      destructive: true,
      maxWidth: 480,
      footer: SaveDialogActions(
        children: <Widget>[
          BrassButton(
            key: const Key('unsaved-cancel'),
            label: 'Cancel',
            variant: BrassButtonVariant.secondary,
            autofocus: true,
            onPressed: () =>
                Navigator.of(context).pop(UnsavedChangesChoice.cancel),
          ),
          BrassButton(
            key: const Key('unsaved-discard'),
            label: 'Discard',
            icon: Icons.delete_outline,
            variant: BrassButtonVariant.destructive,
            onPressed: () =>
                Navigator.of(context).pop(UnsavedChangesChoice.discard),
          ),
          BrassButton(
            key: const Key('unsaved-save'),
            label: 'Save',
            icon: Icons.save,
            onPressed: () =>
                Navigator.of(context).pop(UnsavedChangesChoice.save),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Banner(
            key: const Key('unsaved-count-banner'),
            variant: BannerVariant.warning,
            title: '$fields are not saved',
            message: changedByteCount > 0
                ? '$changedByteCount changed bytes. '
                      '${SaveWorkflowCopy.originalFilesUntouched}'
                : SaveWorkflowCopy.originalFilesUntouched,
          ),
          const SizedBox(height: BombFlowerSpacing.lg),
          Text(
            'Save keeps the edits. Discard closes this window without saving. '
            'Cancel returns to the editor.',
            style: BombFlowerTypography.body.copyWith(
              color: BombFlowerColors.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
