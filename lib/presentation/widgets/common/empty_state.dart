import 'package:material_ui/material_ui.dart';

import '../../dialogs/new_save_dialog.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../help/help_scope.dart';
import 'brass_button.dart';
import 'open_save_scope.dart';
import 'bomb_flower_mark.dart';

/// Specific, quiet empty state with the project's bomb-flower mark.
///
/// Copy should say what is empty and what the user can do next. The mark is
/// decorative and excluded from semantics by [BombFlowerMark].
///
/// The state usually sits directly on the dark canopy, so [onDark] defaults to
/// true and the copy uses the on-dark ink pair. A state inside a parchment
/// panel must pass `onDark: false`, or ink is printed dark on a dark ground.
///
/// With no caller-supplied actions, [offerOpenSave] adds the app's own way in:
/// a large centred "Open save…" button plus the Ctrl+O / `slot_00` hint when an
/// [OpenSaveScope] is present, and quiet text links to create a save or open
/// help when [NewSaveScope] / [HelpScope] are present. No scope means no
/// invitation, so standalone uses are unchanged.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.primaryAction,
    this.secondaryAction,
    this.motifSize = 48,
    this.onDark = true,
    this.offerOpenSave = true,
  });

  final String title;
  final String message;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final double motifSize;

  /// Whether the copy is painted on the dark canopy rather than on parchment.
  final bool onDark;

  /// Whether an action-less state may render the app's own invitations.
  ///
  /// The invitation appears when any of [OpenSaveScope], [NewSaveScope], or
  /// [HelpScope] is an ancestor. The large "Open save…" button and its
  /// Ctrl+O / `slot_00` hint render only when [OpenSaveScope] is present; the
  /// create and help links render whenever their scope exists. A state with
  /// its own actions, or no app around it, is untouched.
  final bool offerOpenSave;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final invitation =
        offerOpenSave && primaryAction == null && secondaryAction == null;
    final open = invitation ? OpenSaveScope.maybeOf(context) : null;
    final create = invitation ? NewSaveScope.maybeOf(context) : null;
    final help = invitation ? HelpScope.maybeOf(context) : null;
    final hasInvitation = open != null || create != null || help != null;

    return Semantics(
      container: true,
      label: '$title. $message',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(BombFlowerSpacing.huge),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                BombFlowerMark(size: motifSize, onDark: onDark),
                const SizedBox(height: BombFlowerSpacing.xl),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: BombFlowerTypography.h3.copyWith(
                    color: onDark ? palette.textOnDark : palette.textPrimary,
                  ),
                ),
                const SizedBox(height: BombFlowerSpacing.md),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: BombFlowerTypography.body.copyWith(
                    color: onDark ? palette.textMutedOnDark : palette.textMuted,
                  ),
                ),
                if (primaryAction != null || secondaryAction != null) ...[
                  const SizedBox(height: BombFlowerSpacing.xl),
                  Wrap(
                    spacing: BombFlowerSpacing.md,
                    runSpacing: BombFlowerSpacing.md,
                    alignment: WrapAlignment.center,
                    children: <Widget>[?primaryAction, ?secondaryAction],
                  ),
                ] else if (hasInvitation) ...[
                  const SizedBox(height: BombFlowerSpacing.xxl),
                  if (open != null) ...[
                    BrassButton(
                      key: const Key('empty-state-open-save'),
                      label: 'Open save…',
                      icon: Icons.folder_open,
                      iconSize: 20,
                      height: BombFlowerSpacing.colossal,
                      minWidth: 240,
                      autofocus: true,
                      onPressed: () => open(context),
                    ),
                    const SizedBox(height: BombFlowerSpacing.md),
                    Text(
                      'Ctrl+O · choose the profile folder that contains slot_00…',
                      textAlign: TextAlign.center,
                      style: BombFlowerTypography.caption.copyWith(
                        color: palette.textMutedOnDark,
                      ),
                    ),
                    if (create != null || help != null)
                      const SizedBox(height: BombFlowerSpacing.md),
                  ],
                  if (create != null || help != null)
                    Wrap(
                      spacing: BombFlowerSpacing.md,
                      runSpacing: BombFlowerSpacing.sm,
                      alignment: WrapAlignment.center,
                      children: <Widget>[
                        if (create != null)
                          BrassButton(
                            key: const Key('empty-state-new-save'),
                            label: 'Create new save',
                            variant: BrassButtonVariant.text,
                            onDark: true,
                            onPressed: () => create(context),
                          ),
                        if (help != null)
                          BrassButton(
                            key: const Key('empty-state-help'),
                            label: 'How to use Bomb Flower',
                            variant: BrassButtonVariant.text,
                            onDark: true,
                            onPressed: () => help(context),
                          ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
