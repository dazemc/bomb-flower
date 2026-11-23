import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
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
/// a large centred "Open save…" button plus the Ctrl+O / `slot_00` hint, wired
/// through [OpenSaveScope]. No scope means no invitation, so standalone uses
/// are unchanged.
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

  /// Whether an action-less state may render the open-save invitation.
  ///
  /// It only appears when an [OpenSaveScope] is an ancestor, so a state that
  /// has its own actions, or no app around it, is untouched.
  final bool offerOpenSave;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final open =
        offerOpenSave && primaryAction == null && secondaryAction == null
        ? OpenSaveScope.maybeOf(context)
        : null;

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
                ] else if (open != null) ...[
                  const SizedBox(height: BombFlowerSpacing.xxl),
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
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
