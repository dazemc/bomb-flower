import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../common/rune_chip.dart';

/// The shared form-row shell used by the editing tabs.
///
/// A label, optional help glyph, and Modified/Invalid stamps sit in a [Wrap]
/// above the control, so a long label moves the stamps to the next line instead
/// of squeezing or clipping them. [help] is exposed as the row's semantic hint
/// and as a pointer tooltip.
class LabelledField extends StatelessWidget {
  const LabelledField({
    super.key,
    required this.label,
    required this.child,
    this.help,
    this.modified = false,
    this.invalid = false,
  });

  final String label;
  final Widget child;
  final String? help;
  final bool modified;
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: label,
      hint: help,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: BombFlowerSpacing.sm,
            runSpacing: BombFlowerSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              ExcludeSemantics(
                child: Text(
                  label,
                  style: BombFlowerTypography.label.copyWith(
                    color: invalid ? palette.danger : palette.textPrimary,
                  ),
                ),
              ),
              if (help != null)
                ExcludeSemantics(
                  child: Tooltip(
                    message: help!,
                    child: Icon(
                      Icons.help_outline,
                      size: 14,
                      color: palette.textMuted,
                    ),
                  ),
                ),
              if (modified)
                const RuneChip(
                  variant: RuneChipVariant.modified,
                  label: 'Modified',
                  compact: true,
                ),
              if (invalid)
                const RuneChip(
                  variant: RuneChipVariant.invalid,
                  label: 'Invalid',
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: BombFlowerSpacing.sm),
          child,
        ],
      ),
    );
  }
}
