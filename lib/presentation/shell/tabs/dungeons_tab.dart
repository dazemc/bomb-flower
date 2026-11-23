import 'package:material_ui/material_ui.dart';

import '../../bloc/shell/tab_definition.dart';
import 'placeholder_tab.dart';

/// Per-area completion, keys, and navigation state.
class DungeonsTab extends StatelessWidget {
  const DungeonsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderTab(tab: ShellTab.dungeons);
  }
}
