import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

/// The eleven primary sections of the editor.
///
/// Declaration order is the navigation order. Keep [kTabDefinitions] in the
/// same order; [ShellTab.definition] indexes into it and tests enforce the
/// mapping.
enum ShellTab {
  overview,
  playerWorld,
  inventory,
  equipment,
  resources,
  progression,
  dungeons,
  collectibles,
  flags,
  advancedData,
  settings,
}

enum TabGroup { character, worldAndData }

extension ShellTabDefinition on ShellTab {
  TabDefinition get definition => kTabDefinitions[index];
}

/// Static presentation metadata for one tab. No save data lives here.
class TabDefinition {
  const TabDefinition({
    required this.tab,
    required this.title,
    required this.eyebrow,
    required this.purpose,
    required this.shortcutLabel,
    required this.icon,
    required this.group,
  });

  final ShellTab tab;
  final String title;
  final String eyebrow;

  /// One line from the design contract; also used by placeholder copy.
  final String purpose;
  final String shortcutLabel;
  final IconData icon;
  final TabGroup group;
}

/// Group overlines appear in the nav rail at full width.
const List<TabDefinition> kTabDefinitions = <TabDefinition>[
  TabDefinition(
    tab: ShellTab.overview,
    title: 'Overview',
    eyebrow: 'Overview',
    purpose: 'At-a-glance save identity, health, and outstanding changes.',
    shortcutLabel: 'Alt 1',
    icon: Icons.space_dashboard_outlined,
    group: TabGroup.character,
  ),
  TabDefinition(
    tab: ShellTab.playerWorld,
    title: 'Player/World',
    eyebrow: 'Player & World',
    purpose: 'Identity, form, placement, and world-state toggles.',
    shortcutLabel: 'Alt 2',
    icon: Icons.person_outline,
    group: TabGroup.character,
  ),
  TabDefinition(
    tab: ShellTab.inventory,
    title: 'Inventory',
    eyebrow: 'Inventory',
    purpose: 'Six-by-four inventory grid and per-slot properties.',
    shortcutLabel: 'Alt 3',
    icon: Icons.inventory_2_outlined,
    group: TabGroup.character,
  ),
  TabDefinition(
    tab: ShellTab.equipment,
    title: 'Equipment',
    eyebrow: 'Equipment',
    purpose: 'Equipped gear, tiers, and condition across body slots.',
    shortcutLabel: 'Alt 4',
    icon: Icons.shield_outlined,
    group: TabGroup.character,
  ),
  TabDefinition(
    tab: ShellTab.resources,
    title: 'Resources',
    eyebrow: 'Resources',
    purpose: 'Vitals, currency, and consumable counts.',
    shortcutLabel: 'Alt 5',
    icon: Icons.favorite_border,
    group: TabGroup.character,
  ),
  TabDefinition(
    tab: ShellTab.progression,
    title: 'Progression',
    eyebrow: 'Progression',
    purpose: 'Quest-stage timeline and completion state.',
    shortcutLabel: 'Alt 6',
    icon: Icons.route_outlined,
    group: TabGroup.character,
  ),
  TabDefinition(
    tab: ShellTab.dungeons,
    title: 'Dungeons',
    eyebrow: 'Dungeons',
    purpose: 'Per-area completion, keys, and navigation state.',
    shortcutLabel: 'Alt 7',
    icon: Icons.map_outlined,
    group: TabGroup.worldAndData,
  ),
  TabDefinition(
    tab: ShellTab.collectibles,
    title: 'Collectibles',
    eyebrow: 'Collectibles',
    purpose: 'Grouped collectible totals and per-entry found state.',
    shortcutLabel: 'Alt 8',
    icon: Icons.auto_awesome_outlined,
    group: TabGroup.worldAndData,
  ),
  TabDefinition(
    tab: ShellTab.flags,
    title: 'Flags',
    eyebrow: 'Event Flags',
    purpose: 'Searchable event-flag table with safe bulk bit operations.',
    shortcutLabel: 'Alt 0',
    icon: Icons.flag_outlined,
    group: TabGroup.worldAndData,
  ),
  TabDefinition(
    tab: ShellTab.advancedData,
    title: 'Advanced Data',
    eyebrow: 'Advanced Data',
    purpose: 'Raw byte inspection, checksums, and import/export.',
    shortcutLabel: 'Alt+Shift+0',
    icon: Icons.data_object,
    group: TabGroup.worldAndData,
  ),
  TabDefinition(
    tab: ShellTab.settings,
    title: 'Settings',
    eyebrow: 'Settings',
    purpose: 'File safety, editor behavior, accessibility, diagnostics.',
    shortcutLabel: 'Ctrl+,',
    icon: Icons.settings_outlined,
    group: TabGroup.worldAndData,
  ),
];

/// Direct tab-jump shortcut, or null when the chord is not a mapped jump.
///
/// Flags is Alt+0, Advanced Data is Alt+Shift+0, and Settings is Ctrl+,.
/// Alt+1..Alt+8 cover the first eight tabs. Meta chords are ignored.
ShellTab? shellTabForShortcut({
  required LogicalKeyboardKey key,
  bool alt = false,
  bool ctrl = false,
  bool shift = false,
  bool meta = false,
}) {
  if (meta) return null;

  if (alt && !ctrl) {
    if (shift) {
      return key == LogicalKeyboardKey.digit0 ? ShellTab.advancedData : null;
    }
    if (key == LogicalKeyboardKey.digit0) return ShellTab.flags;
    const digitKeys = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
    ];
    final index = digitKeys.indexOf(key);
    if (index >= 0) return ShellTab.values[index];
    return null;
  }

  if (ctrl && !alt && !shift && key == LogicalKeyboardKey.comma) {
    return ShellTab.settings;
  }

  return null;
}

/// Ctrl+Tab / Ctrl+Shift+Tab produce +1 / -1, or null for other chords.
int? shellCycleDeltaForShortcut({
  required LogicalKeyboardKey key,
  bool alt = false,
  bool ctrl = false,
  bool shift = false,
  bool meta = false,
}) {
  if (!ctrl || alt || meta || key != LogicalKeyboardKey.tab) return null;
  return shift ? -1 : 1;
}
