import 'package:material_ui/material_ui.dart';

import '../../bloc/shell/tab_definition.dart';
import 'placeholder_tab.dart';

/// Raw byte inspection, checksums, and import/export.
class AdvancedDataTab extends StatelessWidget {
  const AdvancedDataTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderTab(tab: ShellTab.advancedData);
  }
}
