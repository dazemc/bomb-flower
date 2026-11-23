import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import 'rune_chip.dart';

/// Page or panel heading with an eyebrow, title, optional description and
/// actions, and the one permitted brass double rule.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.titleStyle,
    this.description,
    this.actions = const <Widget>[],
    this.isModified = false,
    this.countLabel,
    this.padding = const EdgeInsets.only(
      top: BombFlowerSpacing.xl,
      bottom: BombFlowerSpacing.lg,
    ),
  });

  final String eyebrow;
  final String title;

  /// Defaults to the h2 style. Overview passes h1.
  final TextStyle? titleStyle;
  final String? description;
  final List<Widget> actions;
  final bool isModified;
  final String? countLabel;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final resolvedTitleStyle = (titleStyle ?? BombFlowerTypography.h2).copyWith(
      color: palette.textPrimary,
    );

    return Semantics(
      container: true,
      header: true,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              eyebrow.toUpperCase(),
              style: BombFlowerTypography.overline.copyWith(
                color: palette.accentInk,
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.xs),
            LayoutBuilder(
              builder: (context, constraints) {
                final titleRow = Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        title,
                        style: resolvedTitleStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isModified) ...<Widget>[
                      const SizedBox(width: BombFlowerSpacing.md),
                      const RuneChip(
                        variant: RuneChipVariant.modified,
                        label: 'Modified',
                      ),
                    ],
                  ],
                );

                if (actions.isEmpty) return titleRow;

                final actionRow = Wrap(
                  spacing: BombFlowerSpacing.md,
                  runSpacing: BombFlowerSpacing.md,
                  alignment: WrapAlignment.end,
                  children: actions,
                );

                if (constraints.maxWidth < 640) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      titleRow,
                      const SizedBox(height: BombFlowerSpacing.md),
                      actionRow,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: titleRow),
                    const SizedBox(width: BombFlowerSpacing.xl),
                    actionRow,
                  ],
                );
              },
            ),
            if (description != null) ...<Widget>[
              const SizedBox(height: BombFlowerSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Text(
                  description!,
                  style: BombFlowerTypography.body.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ),
            ],
            if (countLabel != null) ...<Widget>[
              const SizedBox(height: BombFlowerSpacing.xs),
              Text(
                countLabel!,
                style: BombFlowerTypography.caption.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
            const SizedBox(height: BombFlowerSpacing.lg),
            const _HeaderRules(),
          ],
        ),
      ),
    );
  }
}

class _HeaderRules extends StatelessWidget {
  const _HeaderRules();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(height: 1, color: BombFlowerColors.stone),
        const SizedBox(height: 2),
        Container(
          height: 1,
          width: 64,
          color: BombFlowerColors.brassInk.withValues(alpha: 0.6),
        ),
      ],
    );
  }
}
