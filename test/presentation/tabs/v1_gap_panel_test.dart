import 'package:bomb_flower/presentation/bloc/shell/tab_definition.dart';
import 'package:bomb_flower/presentation/shell/tabs/collectibles_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/dungeons_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/flags_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/placeholder_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/progression_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/v1_gap_panel.dart';
import 'package:bomb_flower/presentation/widgets/common/banner.dart';
import 'package:bomb_flower/presentation/widgets/common/section_header.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_toggle.dart';
import 'package:bomb_flower/presentation/widgets/controls/numeric_field.dart';
import 'package:bomb_flower/presentation/widgets/controls/rune_checkbox.dart';
import 'package:bomb_flower/presentation/widgets/selectors/searchable_select.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Banner;

import 'support/tab_test_harness.dart';

final class _GapCase {
  const _GapCase({
    required this.name,
    required this.tab,
    required this.widget,
    required this.count,
    required this.keyword,
  });

  final String name;
  final ShellTab tab;
  final Widget widget;

  /// Verified named-field count rendered from assets/fields/groups.json.
  final String count;

  /// The tab-specific limitation that must be named in the explanation.
  final String keyword;
}

const List<_GapCase> _cases = <_GapCase>[
  _GapCase(
    name: 'Progression',
    tab: ShellTab.progression,
    widget: ProgressionTab(),
    count: '297',
    keyword: 'medallion',
  ),
  _GapCase(
    name: 'Dungeons',
    tab: ShellTab.dungeons,
    widget: DungeonsTab(),
    count: '42',
    keyword: 'DungeonInfo',
  ),
  _GapCase(
    name: 'Collectibles',
    tab: ShellTab.collectibles,
    widget: CollectiblesTab(),
    count: '159',
    keyword: 'Gold Skulltula',
  ),
  _GapCase(
    name: 'Flags',
    tab: ShellTab.flags,
    widget: FlagsTab(),
    count: '3,443',
    keyword: '10,212',
  ),
];

void main() {
  for (final gap in _cases) {
    testWidgets('${gap.name} shows the v1 gap state and no editor', (
      tester,
    ) async {
      await pumpTab(tester, gap.widget, size: const Size(1100, 700));

      expect(find.byType(V1GapPanel), findsOneWidget);
      expect(find.byType(PlaceholderTab), findsNothing);

      final banner = tester.widget<Banner>(
        find.widgetWithText(Banner, 'Not available in this v1 build'),
      );
      expect(banner.variant, BannerVariant.info);
      expect(banner.action, isNull);

      expect(find.textContaining(gap.count), findsWidgets);
      expect(find.textContaining(gap.keyword), findsWidgets);
      expect(
        find.textContaining('remain inspectable in Advanced Data'),
        findsOneWidget,
      );
      expect(
        find.text('Read-only placeholder — no editing controls.'),
        findsOneWidget,
      );

      expect(
        find.descendant(
          of: find.byType(SectionHeader),
          matching: find.text(gap.tab.definition.purpose),
        ),
        findsOneWidget,
      );

      expect(find.byType(NumericField), findsNothing);
      expect(find.byType(BrassToggle), findsNothing);
      expect(find.byType(RuneCheckbox), findsNothing);
      expect(
        find.byWidgetPredicate((widget) => widget is SearchableSelect<dynamic>),
        findsNothing,
      );
      expect(find.byType(TextField), findsNothing);

      expectNoOverflow(tester);
    });
  }
}
