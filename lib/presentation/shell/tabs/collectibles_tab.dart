import 'package:material_ui/material_ui.dart';

import '../../bloc/shell/tab_definition.dart';
import 'placeholder_tab.dart';

/// Grouped collectible totals and per-entry found state.
class CollectiblesTab extends StatelessWidget {
  const CollectiblesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderTab(tab: ShellTab.collectibles);
  }
}
