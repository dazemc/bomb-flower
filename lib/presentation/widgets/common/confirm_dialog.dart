import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_typography.dart';
import 'brass_button.dart';

/// Modal confirmation with explicit target words and a safe initial focus.
///
/// Destructive dialogs are not dismissible by clicking the scrim and focus
/// Cancel first. The primary destructive action is never brass.
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.detail,
    this.cancelLabel = 'Cancel',
    this.confirmLabel = 'Confirm',
    this.destructive = false,
  });

  final String title;
  final String message;
  final String? detail;
  final String cancelLabel;
  final String confirmLabel;
  final bool destructive;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String? detail,
    String cancelLabel = 'Cancel',
    String confirmLabel = 'Confirm',
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !destructive,
      barrierColor: BombFlowerColors.scrim,
      builder: (dialogContext) {
        return ConfirmDialog(
          title: title,
          message: message,
          detail: detail,
          cancelLabel: cancelLabel,
          confirmLabel: confirmLabel,
          destructive: destructive,
        );
      },
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: Dialog(
        insetPadding: const EdgeInsets.all(BombFlowerSpacing.xxxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(BombFlowerRadii.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(height: 3, color: BombFlowerColors.brassInk),
                Padding(
                  padding: const EdgeInsets.all(BombFlowerSpacing.xxxl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(
                              top: BombFlowerSpacing.xs,
                            ),
                            child: Icon(
                              destructive
                                  ? Icons.warning_amber_outlined
                                  : Icons.help_outline,
                              size: 20,
                              color: destructive
                                  ? BombFlowerColors.danger
                                  : BombFlowerColors.brassInk,
                            ),
                          ),
                          const SizedBox(width: BombFlowerSpacing.lg),
                          Expanded(
                            child: Text(
                              title,
                              style: BombFlowerTypography.h2.copyWith(
                                color: BombFlowerColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: BombFlowerSpacing.lg),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text(
                          message,
                          style: BombFlowerTypography.body.copyWith(
                            color: BombFlowerColors.inkSecondary,
                          ),
                        ),
                      ),
                      if (detail != null) ...<Widget>[
                        const SizedBox(height: BombFlowerSpacing.md),
                        Text(
                          detail!,
                          style: BombFlowerTypography.label.copyWith(
                            fontSize: 12,
                            height: 18 / 12,
                            color: BombFlowerColors.danger,
                          ),
                        ),
                      ],
                      const SizedBox(height: BombFlowerSpacing.xxl),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: BombFlowerSpacing.md,
                        runSpacing: BombFlowerSpacing.md,
                        children: <Widget>[
                          BrassButton(
                            label: cancelLabel,
                            variant: BrassButtonVariant.secondary,
                            autofocus: destructive,
                            onPressed: () => Navigator.of(context).pop(false),
                          ),
                          BrassButton(
                            label: confirmLabel,
                            variant: destructive
                                ? BrassButtonVariant.destructive
                                : BrassButtonVariant.primary,
                            autofocus: !destructive,
                            onPressed: () => Navigator.of(context).pop(true),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
