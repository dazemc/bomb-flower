import 'package:material_ui/material_ui.dart';

import '../../bloc/shell/tab_definition.dart';
import 'placeholder_tab.dart';

/// Player identity, form, placement, and world-state toggles.
class PlayerWorldTab extends StatelessWidget {
  const PlayerWorldTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderTab(tab: ShellTab.playerWorld);
  }
}
