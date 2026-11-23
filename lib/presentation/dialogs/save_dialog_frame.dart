import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../theme/bomb_flower_colors.dart';
import '../theme/bomb_flower_spacing.dart';
import '../theme/bomb_flower_typography.dart';
import '../widgets/common/brass_button.dart';

/// Shared parchment frame for the save-file dialogs.
///
/// It mirrors [ConfirmDialog]'s carved top rule and footer rhythm while making
/// room for a form. Escape always cancels (returns `null`), and the content
/// scrolls instead of clipping when the recent-folder list is long.
class SaveDialogFrame extends StatelessWidget {
  /// Creates a dialog frame.
  const SaveDialogFrame({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.icon = Icons.folder_open_outlined,
    this.maxWidth = 560,
    this.destructive = false,
  });

  /// Dialog title.
  final String title;

  /// Scrollable body.
  final Widget child;

  /// One-line explanation under the title.
  final String? subtitle;

  /// Footer actions.
  final Widget? footer;

  /// Header glyph.
  final IconData icon;

  /// Maximum content width.
  final double maxWidth;

  /// Whether the header uses the danger accent.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final accent = destructive
        ? BombFlowerColors.danger
        : BombFlowerColors.brassInk;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).maybePop();
        },
      },
      child: FocusTraversalGroup(
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: title,
          child: Dialog(
            insetPadding: const EdgeInsets.all(BombFlowerSpacing.xxxl),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(BombFlowerRadii.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Container(height: 3, color: accent),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        BombFlowerSpacing.xxxl,
                        BombFlowerSpacing.xxl,
                        BombFlowerSpacing.xxxl,
                        BombFlowerSpacing.lg,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(
                              top: BombFlowerSpacing.xxs,
                            ),
                            child: Icon(icon, size: 20, color: accent),
                          ),
                          const SizedBox(width: BombFlowerSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  title,
                                  style: BombFlowerTypography.h2.copyWith(
                                    color: BombFlowerColors.ink,
                                  ),
                                ),
                                if (subtitle != null) ...<Widget>[
                                  const SizedBox(height: BombFlowerSpacing.xs),
                                  Text(
                                    subtitle!,
                                    style: BombFlowerTypography.caption
                                        .copyWith(
                                          color: BombFlowerColors.inkMuted,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: BombFlowerColors.divider),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(BombFlowerSpacing.xxxl),
                        child: child,
                      ),
                    ),
                    if (footer != null) ...<Widget>[
                      const Divider(height: 1, color: BombFlowerColors.divider),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: BombFlowerSpacing.xxxl,
                          vertical: BombFlowerSpacing.xl,
                        ),
                        child: footer,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Right-aligned footer button row used by every save dialog.
class SaveDialogActions extends StatelessWidget {
  /// Creates a footer row.
  const SaveDialogActions({super.key, required this.children});

  /// Buttons in reading order.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: BombFlowerSpacing.md,
      runSpacing: BombFlowerSpacing.md,
      children: children,
    );
  }
}

/// A labelled brass secondary action used for the Cancel/Back slot.
class SaveDialogCancelButton extends StatelessWidget {
  /// Creates a cancel button.
  const SaveDialogCancelButton({
    super.key,
    this.label = 'Cancel',
    this.onPressed,
  });

  /// Button text.
  final String label;

  /// Overrides the default pop-with-null behaviour.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return BrassButton(
      label: label,
      variant: BrassButtonVariant.secondary,
      onPressed: onPressed ?? () => Navigator.of(context).pop<Object?>(null),
    );
  }
}
