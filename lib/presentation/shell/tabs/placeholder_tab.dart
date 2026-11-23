import 'package:material_ui/material_ui.dart';

import '../../bloc/shell/tab_definition.dart';
import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../../widgets/common/parchment_panel.dart';
import '../../widgets/common/rune_chip.dart';
import '../../widgets/common/section_header.dart';

/// Shared scroll frame for every tab: 24 px gutter (32 at wide sizes), content
/// capped at 1680 px and centered in the canopy gutter.
class TabPageFrame extends StatelessWidget {
  const TabPageFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = constraints.maxWidth >= BombFlowerSpacing.wideBreakpoint
            ? BombFlowerSpacing.contentGutterWide
            : BombFlowerSpacing.contentGutter;
        return SingleChildScrollView(
          padding: EdgeInsets.all(gutter),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: BombFlowerSpacing.contentMaxWidth,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// The explicit "engine pending" explainer shown by all eleven tabs.
class TabIntroPanel extends StatelessWidget {
  const TabIntroPanel({super.key, required this.tab});

  final ShellTab tab;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final definition = tab.definition;

    return ParchmentPanel(
      backgroundColor: BombFlowerColors.parchmentSunken,
      grainSeed: tab.index + 40,
      padding: const EdgeInsets.all(BombFlowerSpacing.panelPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: BombFlowerSpacing.lg,
            runSpacing: BombFlowerSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                'What this tab will show',
                style: BombFlowerTypography.h3.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              const RuneChip(
                variant: RuneChipVariant.unknown,
                label: 'Engine pending',
                semanticLabel: 'Engine pending: this section is not connected to save data',
              ),
            ],
          ),
          const SizedBox(height: BombFlowerSpacing.md),
          Text(
            definition.purpose,
            style: BombFlowerTypography.body.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: BombFlowerSpacing.sm),
          Text(
            'This is application chrome only. Controls, validation, and save '
            'fields arrive with the save engine; no save data is loaded yet.',
            style: BombFlowerTypography.caption.copyWith(
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// One placeholder tab: section header, explainer panel with the design line,
/// and an explicit engine-pending chip.
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({super.key, required this.tab});

  final ShellTab tab;

  @override
  Widget build(BuildContext context) {
    final definition = tab.definition;
    return TabPageFrame(
      child: ParchmentPanel(
        grainSeed: tab.index + 2,
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
              description: definition.purpose,
            ),
            const SizedBox(height: BombFlowerSpacing.sm),
            TabIntroPanel(tab: tab),
          ],
        ),
      ),
    );
  }
}
