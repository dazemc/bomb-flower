import 'package:material_ui/material_ui.dart';

import '../bloc/shell/shell_state.dart';
import '../theme/bomb_flower_colors.dart';
import '../theme/bomb_flower_spacing.dart';
import '../theme/bomb_flower_typography.dart';

/// 28 px global status strip: validation summary, save path, revision.
class ShellStatusFooter extends StatelessWidget {
  const ShellStatusFooter({super.key, required this.state});

  final ShellState state;

  @override
  Widget build(BuildContext context) {
    final path = state.filePath ?? 'No save file open';
    final semantics =
        '${state.validationSummary}. ${state.statusMessage}. '
        'File: $path. Revision ${state.revision}.';
    // Never paint a healthy dot while the session reports issues.
    final dotColor = switch (state.validationHealth) {
      ShellValidationHealth.unknown => BombFlowerColors.warningLight,
      ShellValidationHealth.ok => BombFlowerColors.successLight,
      ShellValidationHealth.warnings => BombFlowerColors.warningLight,
      ShellValidationHealth.errors => BombFlowerColors.dangerLight,
    };

    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: Container(
        height: BombFlowerSpacing.footerHeight,
        decoration: const BoxDecoration(
          color: BombFlowerColors.canopy1,
          border: Border(top: BorderSide(color: BombFlowerColors.dividerDark)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: BombFlowerSpacing.lg),
        child: Row(
          children: <Widget>[
            Tooltip(
              message: state.statusMessage,
              child: Container(
                width: BombFlowerSpacing.sm,
                height: BombFlowerSpacing.sm,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: BombFlowerSpacing.md),
            Expanded(
              flex: 4,
              child: Text(
                state.validationSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BombFlowerTypography.caption.copyWith(
                  color: BombFlowerColors.boneMuted,
                ),
              ),
            ),
            const _FooterDivider(),
            Expanded(
              flex: 5,
              child: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BombFlowerTypography.caption.copyWith(
                  color: BombFlowerColors.boneMuted,
                ),
              ),
            ),
            const _FooterDivider(),
            Text(
              'rev ${state.revision}',
              maxLines: 1,
              style: BombFlowerTypography.mono.copyWith(
                fontSize: BombFlowerTypography.captionSize,
                height: 16 / 11,
                color: BombFlowerColors.boneMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterDivider extends StatelessWidget {
  const _FooterDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: BombFlowerSpacing.lg),
      color: BombFlowerColors.dividerDark,
    );
  }
}
