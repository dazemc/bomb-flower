import 'package:material_ui/material_ui.dart';

import '../../bloc/shell/tab_definition.dart';
import 'v1_gap_panel.dart';

/// Quest-stage timeline and completion state.
class ProgressionTab extends StatelessWidget {
  const ProgressionTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Source: assets/fields/groups.json stats.tabs.progression, schema
    // revision 0x2d80eb: 297 named, 0 hash-only across 8 groups.
    return const V1GapPanel(
      tab: ShellTab.progression,
      reason:
          'There is no medallion bitmask and no single song mask; the 164 '
          'HavePlayedEvent flags mix cutscene/room state with quest progress, '
          'so a safe editor needs the catalogue browser.',
      namedCount: 297,
    );
  }
}
