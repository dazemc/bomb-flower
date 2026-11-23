import 'package:bomb_flower/data/system/directory_picker.dart';
import 'package:bomb_flower/presentation/dialogs/open_save_dialog.dart';
import 'package:bomb_flower/presentation/widgets/common/brass_button.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dialog_test_support.dart';

SaveFolderInfo folder({
  required bool exists,
  required bool isDirectory,
  List<String> slots = const <String>[],
  bool parentExists = true,
}) => SaveFolderInfo(
  path: '',
  exists: exists,
  isDirectory: isDirectory,
  slotDirectories: slots,
  parentExists: parentExists,
);

FakeSaveFolderProbe buildProbe() =>
    FakeSaveFolderProbe(<String, SaveFolderInfo>{
      '/save': folder(
        exists: true,
        isDirectory: true,
        slots: <String>['slot_00', 'slot_01'],
      ),
      '/save/progress.sav': folder(exists: true, isDirectory: false),
      '/empty': folder(exists: true, isDirectory: true),
      '/picked': folder(
        exists: true,
        isDirectory: true,
        slots: <String>['slot_00'],
      ),
    });

bool openEnabled(WidgetTester tester) =>
    tester
        .widget<BrassButton>(find.byKey(const Key('open-save-submit')))
        .onPressed !=
    null;

String fieldText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('open-save-path')))
    .controller!
    .text;

void main() {
  testWidgets('rejects a file path and keeps Open disabled', (tester) async {
    final probe = buildProbe();
    final launch = await launchDialog<String>(
      tester,
      (context) => OpenSaveDialog.show(
        context,
        probe: probe,
        recentPaths: FakeRecentPathsStore(),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('open-save-path')),
      '/save/progress.sav',
    );
    await tester.pumpAndSettle();

    expect(
      find.text('That path is a file, not a save folder.'),
      findsOneWidget,
    );
    expect(openEnabled(tester), isFalse);
    await tester.tap(find.byKey(const Key('open-save-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Open save folder'), findsOneWidget);

    // The rejected submit keeps the dialog open, so dismiss it for real before
    // awaiting the route future; a bare `completes` would wait out the timeout.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  });

  testWidgets('rejects a directory without slot_* folders', (tester) async {
    final launch = await launchDialog<String>(
      tester,
      (context) => OpenSaveDialog.show(
        context,
        probe: buildProbe(),
        recentPaths: FakeRecentPathsStore(),
      ),
    );

    await tester.enterText(find.byKey(const Key('open-save-path')), '/empty');
    await tester.pumpAndSettle();

    expect(find.textContaining('No slot_* folders were found'), findsOneWidget);
    expect(openEnabled(tester), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  });

  testWidgets('accepts a directory with a slot_00 folder', (tester) async {
    final recents = FakeRecentPathsStore();
    final launch = await launchDialog<String>(
      tester,
      (context) => OpenSaveDialog.show(
        context,
        probe: buildProbe(),
        recentPaths: recents,
      ),
    );

    await tester.enterText(find.byKey(const Key('open-save-path')), '/save');
    await tester.pumpAndSettle();

    expect(find.textContaining('slot_00, slot_01'), findsOneWidget);
    expect(openEnabled(tester), isTrue);

    await tester.tap(find.byKey(const Key('open-save-submit')));
    await tester.pumpAndSettle();

    expect(await launch.future, '/save');
    expect(recents.added, <String>['/save']);
  });

  testWidgets('shows the picker fallback hint when no picker is wired', (
    tester,
  ) async {
    await launchDialog<String>(
      tester,
      (context) => OpenSaveDialog.show(
        context,
        probe: buildProbe(),
        recentPaths: FakeRecentPathsStore(),
      ),
    );

    await tester.tap(find.byKey(const Key('open-save-browse')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No system folder picker is wired'),
      findsOneWidget,
    );
  });

  testWidgets('Browse fills the field and validates the picked folder', (
    tester,
  ) async {
    final picker = FakeDirectoryPicker(result: '/picked');
    final launch = await launchDialog<String>(
      tester,
      (context) => OpenSaveDialog.show(
        context,
        probe: buildProbe(),
        recentPaths: FakeRecentPathsStore(),
        directoryPicker: picker,
      ),
    );

    await tester.tap(find.byKey(const Key('open-save-browse')));
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(fieldText(tester), '/picked');
    expect(openEnabled(tester), isTrue);
    await tester.tap(find.byKey(const Key('open-save-submit')));
    await tester.pumpAndSettle();
    expect(await launch.future, '/picked');
  });

  testWidgets('a cancelled picker shows a hint but keeps the typed path', (
    tester,
  ) async {
    final picker = FakeDirectoryPicker();
    await launchDialog<String>(
      tester,
      (context) => OpenSaveDialog.show(
        context,
        probe: buildProbe(),
        recentPaths: FakeRecentPathsStore(),
        directoryPicker: picker,
      ),
    );
    await tester.enterText(find.byKey(const Key('open-save-path')), '/save');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-save-browse')));
    await tester.pumpAndSettle();

    expect(fieldText(tester), '/save');
    expect(find.byKey(const Key('open-save-picker-hint')), findsOneWidget);
    expect(openEnabled(tester), isTrue);
  });

  testWidgets('a recent folder fills the field', (tester) async {
    final recents = FakeRecentPathsStore(<String>['/save']);
    final launch = await launchDialog<String>(
      tester,
      (context) => OpenSaveDialog.show(
        context,
        probe: buildProbe(),
        recentPaths: recents,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-save-recent-0')));
    await tester.pumpAndSettle();

    expect(fieldText(tester), '/save');
    expect(openEnabled(tester), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  });

  testWidgets('Escape cancels without opening anything', (tester) async {
    final launch = await launchDialog<String>(
      tester,
      (context) => OpenSaveDialog.show(
        context,
        probe: buildProbe(),
        recentPaths: FakeRecentPathsStore(),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(await launch.future, isNull);
    expect(find.text('Open save folder'), findsNothing);
  });
}
