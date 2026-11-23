/// Audit done-audit-05, criterion 9: eleven reachable tabs.
///
/// Pumps the real `AppShell` (the shell widget, not a stand-in) inside the real
/// theme and a real `ShellCubit`, then taps every declared tab. It also proves
/// no tab renders the retired "Engine pending" placeholder.
library;

import 'package:bomb_flower/presentation/bloc/shell/shell_cubit.dart';
import 'package:bomb_flower/presentation/bloc/shell/tab_definition.dart';
import 'package:bomb_flower/presentation/shell/app_shell.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<ShellCubit> pumpShell(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1360, 1400);
  addTearDown(tester.view.reset);
  final cubit = ShellCubit();
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      home: BlocProvider<ShellCubit>.value(
        value: cubit,
        child: const AppShell(),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
  return cubit;
}

void main() {
  testWidgets('all eleven tabs are present, tappable, and not placeholders', (
    tester,
  ) async {
    final cubit = await pumpShell(tester);

    expect(kTabDefinitions, hasLength(11));
    expect(
      kTabDefinitions.map((definition) => definition.title).toList(),
      <String>[
        'Overview',
        'Player/World',
        'Inventory',
        'Equipment',
        'Resources',
        'Progression',
        'Dungeons',
        'Collectibles',
        'Flags',
        'Advanced Data',
        'Settings',
      ],
    );

    for (final definition in kTabDefinitions) {
      final tab = definition.tab;
      final navKey = Key('nav-tab-${tab.name}');
      expect(
        find.byKey(navKey),
        findsOneWidget,
        reason: 'nav entry for ${tab.name} is missing',
      );

      await tester.tap(find.byKey(navKey));
      await tester.pumpAndSettle();

      expect(cubit.state.activeTab, tab, reason: 'tapping ${tab.name}');
      expect(
        find.byKey(Key('tab-page-${tab.name}')),
        findsOneWidget,
        reason: '${tab.name} did not render its page widget',
      );
      // The old placeholder chip must not appear anywhere in the tree.
      expect(
        find.text('Engine pending'),
        findsNothing,
        reason: '${tab.name} still renders the engine-pending placeholder',
      );
      // The rail label is present (expanded rail at 1360 px).
      expect(
        find.text(definition.title),
        findsWidgets,
        reason: 'rail label for ${tab.name}',
      );
      debugPrint(
        '[audit] tab ${tab.name} -> ${cubit.state.activeTab.name} '
        'page=tab-page-${tab.name} placeholder=false',
      );
    }
  });

  testWidgets('tab content is honest until a save is open (empty state)', (
    tester,
  ) async {
    await pumpShell(tester);
    // Overview is the default tab; every tab renders an empty-state panel.
    expect(find.textContaining('Open a save'), findsWidgets);
    expect(find.text('Engine pending'), findsNothing);
  });
}
