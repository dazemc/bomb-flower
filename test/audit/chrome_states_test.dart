/// Audit done-audit-05, criterion 10: chrome, states, search, help, indicators.
///
/// Each case names the production widget it drives. Absent features are not
/// simulated: a test only asserts what the real widget tree renders.
library;

import 'package:bomb_flower/presentation/bloc/shell/shell_cubit.dart';
import 'package:bomb_flower/presentation/shell/app_shell.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_spacing.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/common/confirm_dialog.dart';
import 'package:bomb_flower/presentation/widgets/common/error_state.dart';
import 'package:bomb_flower/presentation/widgets/common/loading_state.dart';
import 'package:bomb_flower/presentation/widgets/controls/labelled_field.dart';
import 'package:bomb_flower/presentation/widgets/selectors/searchable_select.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> pumpShellAt(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
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
}

Future<void> pumpHost(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}

void main() {
  group('title bar (bitsdojo-backed AppTitleBar)', () {
    testWidgets('minimise, maximise and close controls are present',
        (tester) async {
      await pumpShellAt(tester, const Size(1360, 880));
      expect(find.byTooltip('Minimize'), findsOneWidget);
      expect(find.byTooltip('Maximize'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      debugPrint('[audit] title bar controls: Minimize/Maximize/Close present');
    });

    testWidgets('drag and double-click-to-maximise are wired', (tester) async {
      await pumpShellAt(tester, const Size(1360, 880));
      final draggable = find.byWidgetPredicate(
        (widget) =>
            widget is GestureDetector &&
            widget.onPanStart != null &&
            widget.onDoubleTap != null,
      );
      expect(draggable, findsWidgets);
      debugPrint('[audit] drag region GestureDetector(onPanStart+onDoubleTap) found');
    });

    testWidgets('clean shell shows no unsaved-changes semantics', (tester) async {
      await pumpShellAt(tester, const Size(1360, 880));
      expect(find.byKey(const Key('title-bar-dirty-indicator')), findsOneWidget);
      expect(find.bySemanticsLabel('Unsaved changes'), findsNothing);
      debugPrint('[audit] dirty indicator present but unlit on a clean shell');
    });
  });

  group('responsive behaviour', () {
    testWidgets('rail collapses below 1280 and the action bar overflows',
        (tester) async {
      await pumpShellAt(tester, const Size(1360, 880));
      expect(
        tester.getSize(find.byKey(const Key('shell-nav-rail'))).width,
        BombFlowerSpacing.navRailWidth,
      );
      expect(find.byKey(const Key('shell-action-overflow')), findsNothing);

      tester.view.physicalSize = const Size(1100, 880);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('shell-nav-rail'))).width,
        BombFlowerSpacing.navRailIconOnlyWidth,
      );
      expect(find.byKey(const Key('shell-action-overflow')), findsOneWidget);
      debugPrint(
        '[audit] rail 232->64 px at 1100; file actions collapse to overflow',
      );
    });
  });

  group('states', () {
    testWidgets('empty state is rendered with no save open', (tester) async {
      await pumpShellAt(tester, const Size(1360, 880));
      expect(find.textContaining('Open a save'), findsWidgets);
    });

    testWidgets('loading state renders its label', (tester) async {
      await pumpHost(
        tester,
        const LoadingState(label: 'Reading preferences…'),
      );
      expect(find.text('Reading preferences…'), findsOneWidget);
    });

    testWidgets('error state renders message, retry and details', (tester) async {
      await pumpHost(
        tester,
        ErrorState(
          title: 'Could not open save',
          message: 'The folder is not a Longshot save.',
          details: 'ParseCorrupt: magic 0x00000000',
          onRetry: () {},
        ),
      );
      expect(find.text('Could not open save'), findsOneWidget);
      expect(find.text('The folder is not a Longshot save.'), findsOneWidget);
      expect(find.text('Retry'), findsWidgets);
      expect(find.textContaining('details'), findsWidgets);
    });

    testWidgets('confirmation dialog returns false/true from Cancel/Confirm',
        (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: BombFlowerThemeData.build(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await ConfirmDialog.show(
                      context,
                      title: 'Discard changes?',
                      message: 'Unsaved edits will be lost.',
                      cancelLabel: 'Keep editing',
                      confirmLabel: 'Discard',
                      destructive: true,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('Unsaved edits will be lost.'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });

  group('search, help, indicators', () {
    testWidgets('searchable select filters its options', (tester) async {
      await pumpHost(
        tester,
        SearchableSelect<String>(
          items: const <String>['Kokiri Sword', 'Deku Nut', 'Master Sword'],
          itemLabel: (item) => item,
          label: 'Inventory item',
          onChanged: (_) {},
        ),
      );
      await tester.tap(find.byKey(SearchableSelect.fieldKey));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(SearchableSelect.panelKey), findsOneWidget);
      expect(find.byKey(SearchableSelect.searchFieldKey), findsOneWidget);

      await tester.enterText(
        find.byKey(SearchableSelect.searchFieldKey),
        'kok',
      );
      await tester.pump();
      expect(find.text('Kokiri Sword'), findsWidgets);
      expect(find.text('Deku Nut'), findsNothing);
      debugPrint('[audit] search filtered 3 options to 1 with query "kok"');
    });

    testWidgets('help glyph and Modified/Invalid stamps render', (tester) async {
      await pumpHost(
        tester,
        LabelledField(
          label: 'Life',
          help: 'Current hearts, in quarter-hearts',
          modified: true,
          invalid: true,
          child: const Text('20'),
        ),
      );
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
      expect(find.byTooltip('Current hearts, in quarter-hearts'), findsOneWidget);
      expect(find.text('MODIFIED'), findsOneWidget);
      expect(find.text('INVALID'), findsOneWidget);
    });
  });
}
