import 'package:material_ui/material_ui.dart';

import '../../bloc/shell/tab_definition.dart';
import 'v1_gap_panel.dart';

/// Per-area completion, keys, and navigation state.
class DungeonsTab extends StatelessWidget {
  const DungeonsTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Source: assets/fields/groups.json stats.tabs.dungeons, schema revision
    // 0x2d80eb: 42 named, 0 hash-only across 7 groups.
    return const V1GapPanel(
      tab: ShellTab.dungeons,
      reason:
          'Only three dungeons have named DungeonInfo.* item flags, small keys '
          'are per-room flags, and only one heart-container flag is named.',
      namedCount: 42,
    );
  }
}
