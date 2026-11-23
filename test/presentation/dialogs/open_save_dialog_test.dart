import 'package:bomb_flower/data/system/directory_lister.dart';
import 'package:bomb_flower/presentation/dialogs/open_save_dialog.dart';
import 'package:bomb_flower/presentation/widgets/common/brass_button.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'dialog_test_support.dart';

DirectoryEntry slot(String path) => DirectoryEntry(
  path: path,
  name: path.split('/').last,
  isDirectory: true,
  isSlotDirectory: true,
);

FakeDirectoryLister buildLister() => FakeDirectoryLister(<String, DirectoryListing>{
  '/save': DirectoryListing(
    path: '/save',
    parentPath: '/',
    entries: <DirectoryEntry>[slot('/save/slot_00'), slot('/save/slot_01')],
  ),
  '/empty': const DirectoryListing(
    path: '/empty',
    parentPath: '/',
    entries: <DirectoryEntry>[],
  ),
  '/save/progress.sav': const DirectoryListing(
    path: '/save/progress.sav',
    entries: <DirectoryEntry>[],
    error: 'Not a folder',
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

Future<void> jumpTo(WidgetTester tester, String path) async {
  await tester.enterText(find.byKey(const Key('open-save-path')), path);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a typed file path shows an inline error, not a throw', (
    tester,
  ) async {
    final launch = await launchDialog<String>(
      tester,
      (context) => OpenSaveDialog.show(
        context,
        probe: FakeSaveFolderProbe(),
        recentPaths: FakeRecentPathsStore(),
        directoryLister: buildLister(),
        initialPath: '/save',
      ),
    );
    await tester.pumpAndSettle();

    await jumpTo(tester, '/save/progress.sav');

    expect(find.byKey(const Key('open-save-listing-error')), findsOneWidget);
    expect(find.text('Not a folder'), findsOneWidget);
    expect(openEnabled(tester), isFalse);
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a folder without slot folders disables Open with a reason', (
    tester,
  ) async {
    final launch = await launchDialog<String>(
      tester,
      (context) => OpenSaveDialog.show(
        context,
        probe: FakeSaveFolderProbe(),
        recentPaths: FakeRecentPathsStore(),
        directoryLister: buildLister(),
        initialPath: '/save',
      ),
    );
    await tester.pumpAndSettle();

    await jumpTo(tester, '/empty');

    expect(find.byKey(const Key('open-save-blocked-reason')), findsOneWidget);
    expect(openEnabled(tester), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a folder with a slot_00 folder opens and records the path', (
    tester,
  ) async {
    final recents = FakeRecentPathsStore();
    final launch = await launchDialog<String>(
      tester,
      (context) => OpenSaveDialog.show(
        context,
        probe: FakeSaveFolderProbe(),
        recentPaths: recents,
        directoryLister: buildLister(),
        initialPath: '/empty',
      ),
    );
    await tester.pumpAndSettle();

    await jumpTo(tester, '/save');

    expect(fieldText(tester), '/save');
    expect(find.byKey(const Key('open-save-valid')), findsOneWidget);
    expect(find.textContaining('slot_00, slot_01'), findsOneWidget);
    expect(openEnabled(tester), isTrue);

    await tester.tap(find.byKey(const Key('open-save-submit')));
    await tester.pumpAndSettle();

    expect(await launch.future, '/save');
    expect(recents.added, <String>['/save']);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('the path field follows navigation', (tester) async {
    final launch = await launchDialog<String>(
      tester,
      (context) => OpenSaveDialog.show(
        context,
        probe: FakeSaveFolderProbe(),
        recentPaths: FakeRecentPathsStore(),
        directoryLister: buildLister(),
        initialPath: '/save',
      ),
    );
    await tester.pumpAndSettle();

    expect(fieldText(tester), '/save');

    await jumpTo(tester, '/empty');
    expect(fieldText(tester), '/empty');

    await jumpTo(tester, '/save');
    expect(fieldText(tester), '/save');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('Escape cancels without opening anything', (tester) async {
    final launch = await launchDialog<String>(
      tester,
      (context) => OpenSaveDialog.show(
        context,
        probe: FakeSaveFolderProbe(),
        recentPaths: FakeRecentPathsStore(),
        directoryLister: buildLister(),
        initialPath: '/save',
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(await launch.future, isNull);
    expect(find.text('Open save folder'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
