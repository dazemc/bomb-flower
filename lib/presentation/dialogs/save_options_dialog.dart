import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart' hide Banner;

import '../bloc/save_session/save_session_ui_state.dart';
import '../theme/bomb_flower_colors.dart';
import '../theme/bomb_flower_spacing.dart';
import '../theme/bomb_flower_typography.dart';
import '../widgets/common/banner.dart';
import '../widgets/common/brass_button.dart';
import '../widgets/controls/rune_checkbox.dart';
import 'dialog_copy.dart';
import 'save_dialog_frame.dart';
import 'slot_rotation_warning.dart';

/// The confirmed options for an in-place save.
final class SaveOptionsRequest extends Equatable {
  /// Creates a request.
  const SaveOptionsRequest({required this.markNewest});

  /// Whether to stamp the edited progress.sav after the write succeeds.
  final bool markNewest;

  @override
  List<Object?> get props => <Object?>[markNewest];
}

/// Confirms an in-place save, including the mtime choice.
///
/// The checkbox starts on because Longshot loads the newest progress.sav; the
/// checkbox, not the save itself, is the explicit permission to change mtimes.
class SaveOptionsDialog extends StatefulWidget {
  /// Creates the dialog.
  const SaveOptionsDialog({super.key, required this.project});

  /// Project that will be written.
  final SaveProjectUi project;

  /// Shows the dialog and returns the confirmed options, or `null`.
  static Future<SaveOptionsRequest?> show(
    BuildContext context, {
    required SaveProjectUi project,
  }) {
    return showDialog<SaveOptionsRequest>(
      context: context,
      barrierColor: BombFlowerColors.scrim,
      builder: (dialogContext) => SaveOptionsDialog(project: project),
    );
  }

  @override
  State<SaveOptionsDialog> createState() => _SaveOptionsDialogState();
}

class _SaveOptionsDialogState extends State<SaveOptionsDialog> {
  bool _markNewest = true;

  bool get _showNewestOption {
    final active = widget.project.activeSlot;
    return active != null && isProgressSlotId(active);
  }

  void _submit() {
    Navigator.of(context)
        .pop(SaveOptionsRequest(markNewest: _showNewestOption && _markNewest));
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final active = project.activeSlot;
    return SaveDialogFrame(
      title: 'Save changes',
      subtitle: project.path,
      icon: Icons.save_outlined,
      maxWidth: 520,
      footer: SaveDialogActions(
        children: <Widget>[
          const SaveDialogCancelButton(key: Key('save-options-cancel')),
          BrassButton(
            key: const Key('save-options-submit'),
            label: 'Save',
            icon: Icons.save,
            onPressed: _submit,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!project.isActiveSlotNewest && project.newestSlot != null) ...[
            SlotRotationWarning(project: project),
            const SizedBox(height: BombFlowerSpacing.lg),
          ],
          Banner(
            variant: project.hasBlockingErrors
                ? BannerVariant.danger
                : BannerVariant.info,
            title: project.hasBlockingErrors
                ? '${project.blockingIssueCount} blocking issue(s)'
                : 'Ready to write ${project.openSlots.length} slot(s)',
            message: project.hasBlockingErrors
                ? 'A blocking validation issue prevents the export. Nothing '
                      'will be written.'
                : 'Files are written atomically and verified after the rename.',
          ),
          const SizedBox(height: BombFlowerSpacing.lg),
          for (final slot in project.openSlots)
            Padding(
              padding: const EdgeInsets.only(bottom: BombFlowerSpacing.xxs),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      slot.relativePath,
                      style: BombFlowerTypography.mono.copyWith(
                        fontSize: 11,
                        height: 16 / 11,
                        color: BombFlowerColors.inkSecondary,
                      ),
                    ),
                  ),
                  Text(
                    slot.isDirty
                        ? '${slot.changedFieldCount} changed'
                        : 'unchanged',
                    style: BombFlowerTypography.caption.copyWith(
                      color: slot.isDirty
                          ? BombFlowerColors.brassInk
                          : BombFlowerColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          if (_showNewestOption) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.xl),
            RuneCheckbox(
              key: const Key('save-options-mark-newest'),
              value: _markNewest,
              label: SaveWorkflowCopy.makeNewestLabel,
              onChanged: (value) {
                setState(() => _markNewest = value ?? false);
              },
            ),
            const SizedBox(height: BombFlowerSpacing.xs),
            Text(
              '${SaveWorkflowCopy.newestSlotExplanation} '
              'Active slot: ${active?.value}.',
              style: BombFlowerTypography.caption.copyWith(
                color: BombFlowerColors.inkMuted,
              ),
            ),
          ],
          const SizedBox(height: BombFlowerSpacing.lg),
          Text(
            SaveWorkflowCopy.gameClampsInvalidValues,
            key: const Key('save-options-clamp-copy'),
            style: BombFlowerTypography.caption.copyWith(
              color: BombFlowerColors.inkSecondary,
            ),
          ),
          const SizedBox(height: BombFlowerSpacing.sm),
          Text(
            SaveWorkflowCopy.noChecksum,
            key: const Key('save-options-no-checksum-copy'),
            style: BombFlowerTypography.caption.copyWith(
              color: BombFlowerColors.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
