import 'package:material_ui/material_ui.dart';

import '../../bloc/shell/tab_definition.dart';
import 'placeholder_tab.dart';

/// Equipped gear, tiers, and condition across body slots.
class EquipmentTab extends StatelessWidget {
  const EquipmentTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderTab(tab: ShellTab.equipment);
  }
}
