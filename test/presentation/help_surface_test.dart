import 'package:bomb_flower/presentation/bloc/shell/shell_cubit.dart';
import 'package:bomb_flower/presentation/shell/app_shell.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_colors.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/common/empty_state.dart';
import 'package:bomb_flower/presentation/widgets/common/parchment_panel.dart';
import 'package:bomb_flower/presentation/widgets/help/help_scope.dart';
import 'package:bomb_flower/presentation/widgets/help/help_surface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _openHelp(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('help-launch'),
              onPressed: () => HelpSurface.show(context),
              child: const Text('Open help'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('help-launch')));
  await tester.pumpAndSettle();
}

/// Mounts the real shell with no save session, so the overview tab renders its
/// no-save empty state and the title bar degrades to disabled session actions.
Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1360, 880);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      home: BlocProvider<ShellCubit>(
        create: (_) => ShellCubit(windowChromeEnabled: false),
        child: const AppShell(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows every section in a parchment sheet', (tester) async {
    await _openHelp(tester);

    expect(find.byKey(const Key('help-surface')), findsOneWidget);
    for (final key in const <String>[
      'help-section-shortcuts',
      'help-section-saving',
      'help-section-unknown-bytes',
      'help-section-fields',
      'help-section-badges',
      'help-section-picker',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }

    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.textContaining('Ctrl+O'), findsOneWidget);
    expect(find.textContaining('Alt+1'), findsOneWidget);
    expect(find.textContaining('Alt+Shift+0'), findsOneWidget);
    expect(find.textContaining('Ctrl+Tab'), findsOneWidget);
    expect(find.text('F1'), findsOneWidget);
    expect(find.text('Help: this surface'), findsOneWidget);
    expect(find.textContaining('later phase'), findsNothing);
    expect(find.textContaining('TODO'), findsNothing);
    expect(find.textContaining('will be'), findsNothing);
    expect(find.textContaining('phase'), findsNothing);
    expect(find.textContaining('Esc'), findsOneWidget);

    expect(find.textContaining('.bak'), findsOneWidget);
    expect(find.textContaining('.bombflower-original'), findsOneWidget);
    expect(find.textContaining('Work on copies'), findsOneWidget);

    expect(find.text('Unknown bytes are preserved'), findsOneWidget);
    expect(find.textContaining('unknown bytes'), findsOneWidget);
    expect(find.textContaining('no checksum'), findsOneWidget);

    expect(find.text('Verified fields and hash-only fields'), findsOneWidget);
    expect(find.textContaining('hash-only'), findsWidgets);
    expect(find.textContaining('read-only'), findsOneWidget);
    expect(find.textContaining('BinaryArray'), findsOneWidget);

    expect(find.text('Modified and Invalid badges'), findsOneWidget);
    expect(find.textContaining('Modified'), findsWidgets);
    expect(find.textContaining('Invalid'), findsWidgets);

    expect(find.text('Choosing a folder on Linux'), findsOneWidget);
    expect(find.textContaining('#273'), findsOneWidget);
    expect(find.textContaining('Type the path into the field'), findsOneWidget);
    expect(find.textContaining('in-app save browser'), findsOneWidget);

    expect(
      find.ancestor(
        of: find.byKey(const Key('help-section-saving')),
        matching: find.byType(ParchmentPanel),
      ),
      findsOneWidget,
    );

    final heading = tester.widget<Text>(find.text('Keyboard shortcuts'));
    expect(heading.style?.color, BombFlowerColors.successInk);

    final rule = tester.widget<Container>(
      find.byKey(const Key('help-surface-rule')),
    );
    expect(rule.color, BombFlowerColors.brassInk);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes the surface', (tester) async {
    await _openHelp(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('help-surface')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Close button closes the surface', (tester) async {
    await _openHelp(tester);

    await tester.tap(find.byKey(const Key('help-surface-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('help-surface')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HelpScope exposes its opener to a descendant', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: BombFlowerThemeData.build(),
        home: HelpScope(
          open: (context) {
            opened++;
            return HelpSurface.show(context);
          },
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('help-scope-launch'),
                  onPressed: () {
                    final open = HelpScope.maybeOf(context);
                    expect(open, isNotNull);
                    open!(context);
                  },
                  child: const Text('Help'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('help-scope-launch')));
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(find.byKey(const Key('help-surface')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HelpScope.maybeOf is null without a scope', (tester) async {
    Future<void> Function(BuildContext)? opener;
    await tester.pumpWidget(
      MaterialApp(
        theme: BombFlowerThemeData.build(),
        home: Builder(
          builder: (context) {
            opener = HelpScope.maybeOf(context);
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );

    expect(opener, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the title-bar Help action opens the surface and Esc closes it', (
    tester,
  ) async {
    await _pumpShell(tester);
    expect(find.byKey(const Key('help-surface')), findsNothing);

    await tester.tap(find.byKey(const Key('shell-action-help')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('help-surface')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('help-surface')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('F1 opens the surface from the shell and Esc closes it', (
    tester,
  ) async {
    await _pumpShell(tester);
    expect(find.byKey(const Key('help-surface')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('help-surface')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('help-surface')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the empty-state help link opens the surface', (tester) async {
    await _pumpShell(tester);

    expect(find.byKey(const Key('empty-state-help')), findsOneWidget);
    await tester.tap(find.byKey(const Key('empty-state-help')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('help-surface')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a standalone empty state offers no help or new-save links', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BombFlowerThemeData.build(),
        home: const Scaffold(
          body: EmptyState(title: 'Nothing here', message: 'Nothing yet.'),
        ),
      ),
    );

    expect(find.byKey(const Key('empty-state-open-save')), findsNothing);
    expect(find.byKey(const Key('empty-state-new-save')), findsNothing);
    expect(find.byKey(const Key('empty-state-help')), findsNothing);
    expect(find.text('Create new save'), findsNothing);
    expect(find.text('How to use Bomb Flower'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
