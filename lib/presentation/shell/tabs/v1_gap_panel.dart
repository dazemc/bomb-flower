import 'package:material_ui/material_ui.dart' hide Banner;

import '../../bloc/shell/tab_definition.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../../widgets/common/banner.dart';
import '../../widgets/common/parchment_panel.dart';
import '../../widgets/common/rune_chip.dart';
import '../../widgets/common/section_header.dart';
import 'placeholder_tab.dart';

/// Honest "not in this v1 build" state shared by the unfinished tabs.
///
/// The panel reports the verified field counts that already exist for the tab
/// and explains why no safe editor can be offered yet. It renders no editable
/// control, no disabled control that implies future work, and no invented
/// value: the only affordance is the pointer to Advanced Data, where the same
/// fields are already inspectable as raw bytes.
class V1GapPanel extends StatelessWidget {
  /// Creates the gap panel for [tab].
  const V1GapPanel({
    super.key,
    required this.tab,
    required this.reason,
    required this.namedCount,
    this.unnamedCount = 0,
  });

  /// Tab whose definition supplies the header copy.
  final ShellTab tab;

  /// Why this tab cannot be edited safely in v1. Rendered verbatim.
  final String reason;

  /// Named fields already verified for this tab.
  final int namedCount;

  /// Hash-only fields with no verified name; omitted from the message at zero.
  final int unnamedCount;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final definition = tab.definition;
    final named = _formatCount(namedCount);
    final verifiedNoun = namedCount == 1 ? 'field is' : 'fields are';
    final hashOnly = unnamedCount > 0
        ? ' ${_formatCount(unnamedCount)} more are hash-only and have no '
              'verified name.'
        : '';
    final message =
        '${definition.title} is not editable in this v1 build. $reason '
        '$named verified $verifiedNoun named in assets/fields/groups.json '
        '(revision 0x2d80eb).$hashOnly Those fields remain inspectable in '
        'Advanced Data.';

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
              countLabel: unnamedCount > 0
                  ? '$named named fields · '
                        '${_formatCount(unnamedCount)} hash-only'
                  : '$named named fields · no hash-only fields',
            ),
            const RuneChip(
              variant: RuneChipVariant.unknown,
              label: 'Not in v1',
              semanticLabel: 'Not in v1: this tab has no editor in this build',
            ),
            const SizedBox(height: BombFlowerSpacing.md),
            Banner(
              variant: BannerVariant.info,
              title: 'Not available in this v1 build',
              message: message,
            ),
            const SizedBox(height: BombFlowerSpacing.md),
            Text(
              'Read-only placeholder — no editing controls.',
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

/// Groups thousands with commas without pulling in an intl dependency.
String _formatCount(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[index]);
  }
  return buffer.toString();
}
