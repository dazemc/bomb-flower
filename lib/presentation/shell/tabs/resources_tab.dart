import 'package:material_ui/material_ui.dart';

import '../../bloc/shell/tab_definition.dart';
import 'placeholder_tab.dart';

/// Vitals, currency, and consumable counts.
class ResourcesTab extends StatelessWidget {
  const ResourcesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderTab(tab: ShellTab.resources);
  }
}
