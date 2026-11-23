import 'package:material_ui/material_ui.dart';

import '../../bloc/shell/tab_definition.dart';
import 'placeholder_tab.dart';

/// Searchable event-flag table with safe bulk bit operations.
class FlagsTab extends StatelessWidget {
  const FlagsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderTab(tab: ShellTab.flags);
  }
}
