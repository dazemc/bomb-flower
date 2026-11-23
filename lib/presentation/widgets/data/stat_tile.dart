import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';

/// Tone for a [StatTile]. Tone is supplementary: the tile also prints a
/// severity word and glyph, so colour is never the only signal.
enum StatSeverity { neutral, success, info, warning, danger }

extension StatSeverityPresentation on StatSeverity {
  String get label {
    return switch (this) {
      StatSeverity.neutral => 'Value',
      StatSeverity.success => 'Healthy',
      StatSeverity.info => 'Information',
      StatSeverity.warning => 'Warning',
      StatSeverity.danger => 'Danger',
    };
  }

  IconData get icon {
    return switch (this) {
      StatSeverity.neutral => Icons.circle_outlined,
      StatSeverity.success => Icons.check_circle_outline,
      StatSeverity.info => Icons.info_outline,
      StatSeverity.warning => Icons.warning_amber_outlined,
      StatSeverity.danger => Icons.error_outline,
    };
  }
}

/// A compact parchment stat for Overview and Resources.
///
/// [value] is a pre-formatted String by design: this widget never computes or
/// invents a domain value. Long labels, values, and units wrap through a [Wrap]
/// instead of being truncated. The whole tile is one read-only semantic node.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.severity = StatSeverity.neutral,
    this.help,
    this.width,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final StatSeverity severity;
  final String? help;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final severityColor = _severityColor(palette);
    final valueText = unit == null ? value : '$value $unit';
    final semanticLabel =
        '$label: $valueText'
        '${severity == StatSeverity.neutral ? '' : ', ${severity.label}'}';

    final tile = Semantics(
      container: true,
      readOnly: true,
      label: semanticLabel,
      hint: help,
      excludeSemantics: true,
      child: Container(
        width: width,
        constraints: const BoxConstraints(minWidth: 160),
        padding: const EdgeInsets.all(BombFlowerSpacing.xl),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 17, color: palette.accentInk),
                  const SizedBox(width: BombFlowerSpacing.md),
                ],
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: BombFlowerTypography.overline.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
                if (help != null) ...<Widget>[
                  const SizedBox(width: BombFlowerSpacing.xs),
                  Tooltip(
                    message: help!,
                    excludeFromSemantics: true,
                    child: Icon(
                      Icons.help_outline,
                      size: 14,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: BombFlowerSpacing.lg),
            Wrap(
              spacing: BombFlowerSpacing.xs,
              runSpacing: BombFlowerSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: <Widget>[
                Text(
                  value,
                  style: BombFlowerTypography.h2.copyWith(
                    color: palette.textPrimary,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                if (unit != null)
                  Text(
                    unit!,
                    style: BombFlowerTypography.body.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
              ],
            ),
            if (severity != StatSeverity.neutral) ...<Widget>[
              const SizedBox(height: BombFlowerSpacing.sm),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(severity.icon, size: 13, color: severityColor),
                  const SizedBox(width: BombFlowerSpacing.xs),
                  Flexible(
                    child: Text(
                      severity.label.toUpperCase(),
                      style: BombFlowerTypography.caption.copyWith(
                        color: severityColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    return tile;
  }

  Color _severityColor(BombFlowerTheme palette) {
    return switch (severity) {
      StatSeverity.neutral => palette.textMuted,
      StatSeverity.success => palette.success,
      StatSeverity.info => palette.info,
      StatSeverity.warning => palette.warning,
      StatSeverity.danger => palette.danger,
    };
  }
}

/// A neutral fallback tile used when a panel needs to reserve a stat position
/// without inventing a value.
class UnavailableStatTile extends StatelessWidget {
  const UnavailableStatTile({
    super.key,
    required this.label,
    this.icon,
    this.help,
    this.width,
  });

  final String label;
  final IconData? icon;
  final String? help;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return StatTile(
      label: label,
      value: '—',
      unit: 'Unavailable',
      icon: icon,
      severity: StatSeverity.warning,
      help: help,
      width: width,
    );
  }
}
