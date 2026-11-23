import 'package:material_ui/material_ui.dart';

import '../../bloc/shell/tab_definition.dart';
import 'v1_gap_panel.dart';

/// Searchable event-flag table with safe bulk bit operations.
class FlagsTab extends StatelessWidget {
  const FlagsTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Source: assets/fields/groups.json stats.tabs.flags, schema revision
    // 0x2d80eb: 3,443 named, 6,769 hash-only, 10,212 Bool fields in 1 group.
    return const V1GapPanel(
      tab: ShellTab.flags,
      reason:
          '10,212 Bool fields need a dedicated paginated browser; raw bytes '
          'are available in Advanced Data.',
      namedCount: 3443,
      unnamedCount: 6769,
    );
  }
}
