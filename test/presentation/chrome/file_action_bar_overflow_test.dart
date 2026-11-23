import 'dart:ui' show PointerDeviceKind;

import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/presentation/dialogs/open_save_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/core/fixtures.dart';
import '../dialogs/dialog_test_support.dart';
import 'app_title_bar_actions_test.dart'
    show buildCubit, disposeCubit, pumpTitleBar;

/// The labels the collapsed popup must list, in display order.
const List<String> menuLabels = <String>[
  'Open save…',
  'Save',
  'Save As…',
  'Duplicate',
  'Reset slot…',
  'Undo',
  'Redo',
  'Compare',
  'Launch Longshot',
];

const Key overflowKey = Key('shell-action-overflow');

/// Finds the popup entry for [key].
Finder menuEntry(String key) => find.byKey(Key(key));

/// A real desktop click: mouse down, a few pixels of movement (well past the
/// 2 px precise-pointer pan slop), then mouse up.
///
/// This is the gesture that used to lose the arena to the title bar's window
/// drag recognizer, so the trigger never saw a tap.
Future<void> clickWithSlightMovement(
  WidgetTester tester,
  Finder target, {
  Offset by = const Offset(3, 0),
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveBy(by);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Opens the collapsed popup with a plain tap.
Future<void> openOverflow(WidgetTester tester) async {
  await tester.tap(find.byKey(overflowKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a slight mouse movement still opens the collapsed popup', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');

    await pumpTitleBar(
      tester,
      cubit: harness.cubit,
      size: const Size(1100, 700),
    );

    await clickWithSlightMovement(tester, find.byKey(overflowKey));

    expect(find.byKey(const Key('shell-action-open')), findsOneWidget);
    expect(find.byKey(const Key('shell-action-launch')), findsOneWidget);
  });

  testWidgets('the collapsed popup lists every action with icons and labels', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');

    await pumpTitleBar(
      tester,
      cubit: harness.cubit,
      size: const Size(1100, 700),
    );

    await openOverflow(tester);

    for (final label in menuLabels) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Every entry carries its leading icon.
    expect(find.byIcon(Icons.folder_open_outlined), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_outlined), findsOneWidget);

    // Only the genuinely bound Ctrl+O is hinted; no invented accelerators.
    expect(find.text('Ctrl+O'), findsOneWidget);
    expect(find.textContaining('Ctrl+S'), findsNothing);
  });

  testWidgets('Open save… in the popup runs the wide-layout handler once', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');
    final recentPaths = FakeRecentPathsStore();
    final lister = FakeDirectoryLister();

    await pumpTitleBar(
      tester,
      cubit: harness.cubit,
      size: const Size(1100, 700),
      recentPaths: recentPaths,
      directoryLister: lister,
    );

    await openOverflow(tester);
    expect(lister.calls, isEmpty);

    await tester.tap(find.text('Open save…'));
    await tester.pumpAndSettle();

    expect(find.byType(OpenSaveDialog), findsOneWidget);
    expect(lister.calls, hasLength(1));
  });

  testWidgets('Undo is listed but not selectable while the save is clean', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');

    await pumpTitleBar(
      tester,
      cubit: harness.cubit,
      size: const Size(1100, 700),
    );

    await openOverflow(tester);

    final undo = tester.widget<MenuItemButton>(menuEntry('shell-action-undo'));
    expect(undo.onPressed, isNull);
    expect(find.text('Undo'), findsOneWidget);

    harness.cubit.edit(const SetScalar(healthId, 42));
    await tester.pumpAndSettle();

    final enabledUndo = tester.widget<MenuItemButton>(
      menuEntry('shell-action-undo'),
    );
    expect(enabledUndo.onPressed, isNotNull);
  });

  testWidgets('Compare in the popup follows the dirty project', (tester) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');

    await pumpTitleBar(
      tester,
      cubit: harness.cubit,
      size: const Size(1100, 700),
    );

    await openOverflow(tester);
    expect(
      tester
          .widget<MenuItemButton>(menuEntry('shell-action-compare'))
          .onPressed,
      isNull,
    );

    harness.cubit.edit(const SetScalar(healthId, 42));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<MenuItemButton>(menuEntry('shell-action-compare'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('Escape closes the popup without invoking an action', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');
    final recentPaths = FakeRecentPathsStore();

    await pumpTitleBar(
      tester,
      cubit: harness.cubit,
      size: const Size(1100, 700),
      recentPaths: recentPaths,
    );

    await openOverflow(tester);
    expect(find.text('Open save…'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Open save…'), findsNothing);
    expect(find.byType(OpenSaveDialog), findsNothing);
    expect(recentPaths.reads, 0);
  });

  testWidgets('arrows move the popup focus and Enter activates', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');
    final recentPaths = FakeRecentPathsStore();

    await pumpTitleBar(
      tester,
      cubit: harness.cubit,
      size: const Size(1100, 700),
      recentPaths: recentPaths,
    );

    await openOverflow(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(OpenSaveDialog), findsOneWidget);
  });

  testWidgets('1360 px keeps the inline row and drops the overflow trigger', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');

    await pumpTitleBar(
      tester,
      cubit: harness.cubit,
      size: const Size(1360, 880),
    );

    expect(find.byKey(const Key('shell-action-open')), findsOneWidget);
    expect(find.byKey(const Key('shell-action-compare')), findsOneWidget);
    expect(find.byKey(overflowKey), findsNothing);

    // The window-drag recognizer still covers the brand and the empty space,
    // but no longer sits above the inline action cluster.
    final dragRegion = find.byWidgetPredicate(
      (widget) => widget is GestureDetector && widget.onPanStart != null,
    );
    expect(
      find.ancestor(of: find.text('BOMB FLOWER'), matching: dragRegion),
      findsOneWidget,
    );
    for (final key in <String>['shell-action-open', 'shell-action-compare']) {
      expect(
        find.ancestor(of: find.byKey(Key(key)), matching: dragRegion),
        findsNothing,
        reason: key,
      );
    }
  });

  testWidgets('an inline action survives the same slight mouse movement', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');
    final recentPaths = FakeRecentPathsStore();
    final lister = FakeDirectoryLister();

    await pumpTitleBar(
      tester,
      cubit: harness.cubit,
      size: const Size(1360, 880),
      recentPaths: recentPaths,
      directoryLister: lister,
    );

    await clickWithSlightMovement(
      tester,
      find.byKey(const Key('shell-action-open')),
    );

    expect(find.byType(OpenSaveDialog), findsOneWidget);
    expect(lister.calls, hasLength(1));
  });

  testWidgets('clicking outside closes the popup without invoking', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');
    final recentPaths = FakeRecentPathsStore();

    await pumpTitleBar(
      tester,
      cubit: harness.cubit,
      size: const Size(1100, 700),
      recentPaths: recentPaths,
    );

    await openOverflow(tester);
    expect(find.text('Open save…'), findsOneWidget);

    await tester.tapAt(const Offset(600, 500));
    await tester.pumpAndSettle();

    expect(find.text('Open save…'), findsNothing);
    expect(find.byType(OpenSaveDialog), findsNothing);
    expect(recentPaths.reads, 0);
  });

  testWidgets('the overflow trigger is announced as More actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');

    await pumpTitleBar(
      tester,
      cubit: harness.cubit,
      size: const Size(1100, 700),
    );

    try {
      expect(
        tester
            .widget<Tooltip>(
              find.descendant(
                of: find.byKey(overflowKey),
                matching: find.byType(Tooltip),
              ),
            )
            .message,
        'More actions',
      );
      expect(find.bySemanticsLabel('More actions'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
