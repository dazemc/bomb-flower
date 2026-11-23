import 'package:material_ui/material_ui.dart';

import '../../widgets/common/parchment_panel.dart';
import '../../widgets/common/rune_chip.dart';
import '../../widgets/common/seed_pod_mark.dart';
import '../../widgets/common/section_header.dart';
import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../../bloc/shell/tab_definition.dart';
import 'placeholder_tab.dart';

/// Overview landing tab: honest empty identity, the original seed-pod mark,
/// and three explicitly unavailable stat slots. No fake values.
class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final definition = ShellTab.overview.definition;
    final palette = context.bombFlowerTheme;

    return TabPageFrame(
      child: ParchmentPanel(
        grainSeed: 2,
        padding: const EdgeInsets.fromLTRB(
          BombFlowerSpacing.panelPadding,
          0,
          BombFlowerSpacing.panelPadding,
          BombFlowerSpacing.panelPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              eyebrow: definition.eyebrow,
              title: definition.title,
              titleStyle: BombFlowerTypography.h1,
              description: definition.purpose,
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final identity = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'No save file open',
                      style: BombFlowerTypography.h2.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: BombFlowerSpacing.sm),
                    Text(
                      'Open a save to inspect its player, inventory, world '
                      'state, and outstanding changes.',
                      style: BombFlowerTypography.body.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                );
                final mark = SeedPodMark(
                  size: 96,
                  color: BombFlowerColors.stone,
                  accentColor: BombFlowerColors.brassInk,
                  filled: true,
                );

                if (constraints.maxWidth < 620) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      mark,
                      const SizedBox(height: BombFlowerSpacing.xl),
                      identity,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    mark,
                    const SizedBox(width: BombFlowerSpacing.xxxl),
                    Expanded(child: identity),
                  ],
                );
              },
            ),
            const SizedBox(height: BombFlowerSpacing.xxxl),
            const TabIntroPanel(tab: ShellTab.overview),
            const SizedBox(height: BombFlowerSpacing.xxxl),
            Text(
              'At a glance',
              style: BombFlowerTypography.h3.copyWith(
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.md),
            const Wrap(
              spacing: BombFlowerSpacing.xl,
              runSpacing: BombFlowerSpacing.xl,
              children: <Widget>[
                _UnavailableStat(label: 'Completion', icon: Icons.route),
                _UnavailableStat(label: 'Play time', icon: Icons.schedule),
                _UnavailableStat(
                  label: 'Modified fields',
                  icon: Icons.edit_note,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UnavailableStat extends StatelessWidget {
  const _UnavailableStat({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    return Semantics(
      container: true,
      label: '$label unavailable. Save engine not connected.',
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(BombFlowerSpacing.xl),
        decoration: BoxDecoration(
          color: BombFlowerColors.parchmentSunken,
          borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
          border: Border.all(color: BombFlowerColors.stone),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 16, color: palette.textMuted),
                const SizedBox(width: BombFlowerSpacing.md),
                Text(
                  label.toUpperCase(),
                  style: BombFlowerTypography.overline.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: BombFlowerSpacing.lg),
            Text(
              '—',
              style: BombFlowerTypography.h2.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: BombFlowerSpacing.sm),
            const RuneChip(
              variant: RuneChipVariant.unknown,
              label: 'Unavailable',
              semanticLabel: 'Value unavailable until the save engine lands',
            ),
            const SizedBox(height: BombFlowerSpacing.sm),
            Text(
              'No save data loaded',
              style: BombFlowerTypography.caption.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
