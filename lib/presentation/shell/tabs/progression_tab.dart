import 'package:material_ui/material_ui.dart';

import '../../bloc/shell/tab_definition.dart';
import 'placeholder_tab.dart';

/// Quest-stage timeline and completion state.
class ProgressionTab extends StatelessWidget {
  const ProgressionTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderTab(tab: ShellTab.progression);
  }
}
