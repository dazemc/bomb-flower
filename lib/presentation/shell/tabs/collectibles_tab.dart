import 'package:material_ui/material_ui.dart';

import '../../bloc/shell/tab_definition.dart';
import 'v1_gap_panel.dart';

/// Grouped collectible totals and per-entry found state.
class CollectiblesTab extends StatelessWidget {
  const CollectiblesTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Source: assets/fields/groups.json stats.tabs.collectibles, schema
    // revision 0x2d80eb: 159 named, 0 hash-only across 6 groups.
    return const V1GapPanel(
      tab: ShellTab.collectibles,
      reason:
          'No Gold Skulltula total and no Big Poe total exist; only per-event '
          'flags and the named token stock count are verified.',
      namedCount: 159,
    );
  }
}
