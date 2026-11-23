import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import 'seed_pod_mark.dart';

/// Specific, quiet empty state with an original seed-pod line motif.
///
/// Copy should say what is empty and what the user can do next. The motif is
/// decorative and excluded from semantics by [SeedPodMark].
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.primaryAction,
    this.secondaryAction,
    this.motifSize = 48,
  });

  final String title;
  final String message;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final double motifSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;

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
                SeedPodMark(
                  size: motifSize,
                  color: BombFlowerColors.stone.withValues(alpha: 0.7),
                  accentColor: BombFlowerColors.stone.withValues(alpha: 0.7),
                ),
                const SizedBox(height: BombFlowerSpacing.xl),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: BombFlowerTypography.h3.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: BombFlowerSpacing.md),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: BombFlowerTypography.body.copyWith(
                    color: palette.textMuted,
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
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
