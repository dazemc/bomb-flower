import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';

/// How strongly a displayed value is supported by evidence.
enum ProvenanceLevel { verified, observed, inferred, unknown }

extension ProvenanceLevelPresentation on ProvenanceLevel {
  String get label {
    return switch (this) {
      ProvenanceLevel.verified => 'Verified',
      ProvenanceLevel.observed => 'Observed',
      ProvenanceLevel.inferred => 'Inferred',
      ProvenanceLevel.unknown => 'Unknown',
    };
  }

  IconData get icon {
    return switch (this) {
      ProvenanceLevel.verified => Icons.verified_outlined,
      ProvenanceLevel.observed => Icons.visibility_outlined,
      ProvenanceLevel.inferred => Icons.trending_up,
      ProvenanceLevel.unknown => Icons.question_mark,
    };
  }
}

/// A small provenance stamp that keeps the UI honest about evidence.
///
/// The [source] citation is never hidden behind colour: it is the tooltip
/// message, and it is also the semantic tooltip so a screen-reader user hears
/// exactly where the value came from. The visible level word and distinct glyph
/// mean the four levels remain distinguishable in grayscale.
class ProvenanceBadge extends StatelessWidget {
  const ProvenanceBadge({super.key, required this.level, required this.source});

  final ProvenanceLevel level;

  /// Citation string, for example 'progress.sav offset 0x1C (verified by …)'.
  final String source;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final style = _BadgeStyle.forLevel(level, palette);

    return Tooltip(
      message: source,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        label: 'Provenance: ${level.label}',
        tooltip: source,
        excludeSemantics: true,
        child: Container(
          constraints: const BoxConstraints(minHeight: 22),
          padding: const EdgeInsets.symmetric(
            horizontal: BombFlowerSpacing.md,
            vertical: BombFlowerSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: style.fill,
            borderRadius: BorderRadius.circular(BombFlowerRadii.xs),
            border: Border.all(color: style.border, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(level.icon, size: 13, color: style.ink),
              const SizedBox(width: BombFlowerSpacing.xs),
              Text(
                level.label.toUpperCase(),
                style: BombFlowerTypography.caption.copyWith(
                  fontSize: 10,
                  height: 14 / 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: style.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeStyle {
  const _BadgeStyle({
    required this.fill,
    required this.border,
    required this.ink,
  });

  final Color fill;
  final Color border;
  final Color ink;

  static _BadgeStyle forLevel(ProvenanceLevel level, BombFlowerTheme palette) {
    return switch (level) {
      ProvenanceLevel.verified => _BadgeStyle(
        fill: Colors.transparent,
        border: palette.accentInk,
        ink: palette.accentInk,
      ),
      ProvenanceLevel.observed => _BadgeStyle(
        fill: palette.accent,
        border: palette.accentInk,
        ink: BombFlowerColors.ink,
      ),
      ProvenanceLevel.inferred => _BadgeStyle(
        fill: palette.surfaceSunken,
        border: palette.border,
        ink: palette.textSecondary,
      ),
      ProvenanceLevel.unknown => _BadgeStyle(
        fill: BombFlowerColors.dangerSurface,
        border: palette.danger,
        ink: BombFlowerColors.dangerInk,
      ),
    };
  }
}
