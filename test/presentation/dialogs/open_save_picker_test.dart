import 'dart:async';
import 'dart:io';

import 'package:bomb_flower/data/system/directory_lister.dart';
import 'package:bomb_flower/presentation/dialogs/open_save_dialog.dart';
import 'package:bomb_flower/presentation/widgets/common/brass_button.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'dialog_test_support.dart';

/// A lister over a real temp tree, read synchronously so widget tests never
/// wait on the event loop.
final class TempTreeLister implements DirectoryLister {
  TempTreeLister(this.homeDirectory);

  @override
  final String? homeDirectory;

  final List<String> calls = <String>[];

  static final RegExp _slotName = RegExp(r'^slot_\d{2}$');

  @override
  Future<DirectoryListing> list(String path) {
    calls.add(path);
    final directory = Directory(path);
    if (!directory.existsSync()) {
      return Future<DirectoryListing>.value(
        DirectoryListing(
          path: path,
          entries: const <DirectoryEntry>[],
          error: 'Cannot read this folder: it does not exist.',
        ),
      );
    }
    final entries = <DirectoryEntry>[];
    for (final entity in directory.listSync(followLinks: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      final isDirectory = entity is Directory;
      var containsSlots = false;
      if (isDirectory) {
        for (var index = 0; index < 10; index++) {
          final slot = 'slot_${index.toString().padLeft(2, '0')}';
          if (Directory(
            '${entity.path}${Platform.pathSeparator}$slot',
          ).existsSync()) {
            containsSlots = true;
            break;
          }
        }
      }
      entries.add(
        DirectoryEntry(
          path: entity.path,
          name: name,
          isDirectory: isDirectory,
          isSlotDirectory: isDirectory && _slotName.hasMatch(name),
          containsSlots: containsSlots,
        ),
      );
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    final parent = directory.parent.path;
    return Future<DirectoryListing>.value(
      DirectoryListing(
        path: directory.path,
        entries: entries,
        parentPath: parent == directory.path ? null : parent,
      ),
    );
  }
}

/// A lister whose listing never completes, for the anti-wedge regression.
final class NeverLister implements DirectoryLister {
  final Completer<DirectoryListing> completer =
      Completer<DirectoryListing>();
  final List<String> calls = <String>[];

  @override
  String? get homeDirectory => '/home/test';

  @override
  Future<DirectoryListing> list(String path) {
    calls.add(path);
    return completer.future;
  }
}

bool openEnabled(WidgetTester tester) =>
    tester
        .widget<BrassButton>(find.byKey(const Key('open-save-submit')))
        .onPressed !=
    null;

String fieldText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('open-save-path')))
    .controller!
    .text;

Future<void> doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<DialogLauncher<String>> openPicker(
  WidgetTester tester, {
  required DirectoryLister lister,
  required String initialPath,
  FakeRecentPathsStore? recents,
}) {
  return launchDialog<String>(
    tester,
    (context) => OpenSaveDialog.show(
      context,
      probe: FakeSaveFolderProbe(),
      recentPaths: recents ?? FakeRecentPathsStore(),
      directoryLister: lister,
      initialPath: initialPath,
    ),
  );
}

void main() {
  late Directory temp;
  late Directory root;
  late TempTreeLister lister;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bomb_flower_picker_');
    root = Directory('${temp.path}/tree')..createSync();
    Directory('${root.path}/alpha').createSync();
    Directory('${root.path}/beta').createSync();
    Directory('${root.path}/profile').createSync();
    Directory('${root.path}/profile/slot_00').createSync();
    File('${root.path}/alpha/notes.txt').writeAsStringSync('note');
    File('${root.path}/zeta.txt').writeAsStringSync('text');
    lister = TempTreeLister(root.path);
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  testWidgets('lists a temp tree dirs-first, descends, and .. returns', (
    tester,
  ) async {
    final launch = await openPicker(
      tester,
      lister: lister,
      initialPath: root.path,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-save-entry-alpha')), findsOneWidget);
    expect(find.byKey(const Key('open-save-entry-beta')), findsOneWidget);
    expect(find.byKey(const Key('open-save-entry-profile')), findsOneWidget);
    expect(find.byKey(const Key('open-save-entry-zeta.txt')), findsOneWidget);

    final firstDirectory = tester
        .getTopLeft(find.byKey(const Key('open-save-entry-alpha')))
        .dy;
    final file = tester
        .getTopLeft(find.byKey(const Key('open-save-entry-zeta.txt')))
        .dy;
    expect(firstDirectory, lessThan(file));

    // A single click selects but never navigates. Pump past the double-tap
    // timeout so the next tap starts a fresh gesture.
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('open-save-entry-alpha'))),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(fieldText(tester), root.path);
    expect(find.byKey(const Key('open-save-selected')), findsOneWidget);

    // Enter on the selected row descends.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fieldText(tester), '${root.path}/alpha');
    expect(find.byKey(const Key('open-save-entry-notes.txt')), findsOneWidget);

    // A single tap on `..` returns to the parent.
    await tester.tap(find.byKey(const Key('open-save-parent')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(fieldText(tester), root.path);
    expect(find.byKey(const Key('open-save-entry-alpha')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('Open is disabled with a visible reason without a slot folder', (
    tester,
  ) async {
    final launch = await openPicker(
      tester,
      lister: lister,
      initialPath: root.path,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-save-blocked-reason')), findsOneWidget);
    expect(openEnabled(tester), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('Open on a slot-bearing folder runs the handler exactly once', (
    tester,
  ) async {
    final recents = FakeRecentPathsStore();
    var shows = 0;
    final launch = await launchDialog<String>(
      tester,
      (context) {
        shows++;
        return OpenSaveDialog.show(
          context,
          probe: FakeSaveFolderProbe(),
          recentPaths: recents,
          directoryLister: lister,
          initialPath: root.path,
        );
      },
    );
    await tester.pumpAndSettle();

    await doubleTap(tester, find.byKey(const Key('open-save-entry-profile')));

    final profile = '${root.path}/profile';
    expect(fieldText(tester), profile);
    expect(find.byKey(const Key('open-save-valid')), findsOneWidget);
    expect(openEnabled(tester), isTrue);

    await tester.tap(find.byKey(const Key('open-save-submit')));
    await tester.pumpAndSettle();

    expect(await launch.future, profile);
    expect(shows, 1);
    expect(recents.added, <String>[profile]);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a single tap selects a slot-bearing folder and enables Open', (
    tester,
  ) async {
    final launch = await openPicker(
      tester,
      lister: lister,
      initialPath: root.path,
    );
    await tester.pumpAndSettle();

    final profile = '${root.path}/profile';
    final row = find.byKey(const Key('open-save-entry-profile'));
    await tester.tapAt(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-save-selected')), findsOneWidget);
    expect(find.textContaining(profile), findsOneWidget);
    expect(openEnabled(tester), isTrue);

    await tester.tap(find.byKey(const Key('open-save-submit')));
    await tester.pumpAndSettle();

    expect(await launch.future, profile);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('open, Cancel, then open again succeeds', (tester) async {
    final launch = await openPicker(
      tester,
      lister: lister,
      initialPath: root.path,
    );
    await tester.pumpAndSettle();
    expect(find.byType(OpenSaveDialog), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-save-cancel')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(OpenSaveDialog), findsNothing);

    await tester.tap(find.byKey(const Key('dialog-launch')));
    await tester.pumpAndSettle();
    expect(find.byType(OpenSaveDialog), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-save-cancel')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(OpenSaveDialog), findsNothing);
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a scrim dismissal still allows reopening', (tester) async {
    await openPicker(tester, lister: lister, initialPath: root.path);
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(OpenSaveDialog), findsNothing);

    await tester.tap(find.byKey(const Key('dialog-launch')));
    await tester.pumpAndSettle();
    expect(find.byType(OpenSaveDialog), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-save-cancel')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(OpenSaveDialog), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('Cancel button is the pointer target on its own rect', (
    tester,
  ) async {
    final launch = await openPicker(
      tester,
      lister: lister,
      initialPath: root.path,
    );
    await tester.pumpAndSettle();

    final cancel = find.byKey(const Key('open-save-cancel'));
    final center = tester.getCenter(cancel);
    final hit = tester.hitTestOnBinding(center);
    final gesture = tester.renderObject(
      find.descendant(of: cancel, matching: find.byType(GestureDetector)).first,
    );

    // The pointer test must reach the button's own listener, not a barrier.
    expect(
      hit.path.any((entry) => identical(entry.target, gesture)),
      isTrue,
      reason: 'Cancel must be on the hit path at its own centre',
    );

    await tester.tapAt(center);
    await tester.pumpAndSettle();

    expect(find.byType(OpenSaveDialog), findsNothing);
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('Escape closes with null', (tester) async {
    final launch = await openPicker(
      tester,
      lister: lister,
      initialPath: root.path,
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(OpenSaveDialog), findsNothing);
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a scrim tap outside the panel closes with null', (tester) async {
    final launch = await openPicker(
      tester,
      lister: lister,
      initialPath: root.path,
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.byType(OpenSaveDialog), findsNothing);
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a tap inside the panel does not close it', (tester) async {
    final launch = await openPicker(
      tester,
      lister: lister,
      initialPath: root.path,
    );
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(find.text('Open save folder')));
    await tester.pumpAndSettle();

    expect(find.byType(OpenSaveDialog), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-save-cancel')));
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('Cancel closes while the listing never completes', (
    tester,
  ) async {
    final never = NeverLister();
    final launch = await openPicker(
      tester,
      lister: never,
      initialPath: '/somewhere/deep',
    );
    await tester.pump();

    expect(find.byType(OpenSaveDialog), findsOneWidget);
    expect(never.completer.isCompleted, isFalse);

    await tester.tap(find.byKey(const Key('open-save-cancel')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(
      await launch.future.timeout(const Duration(seconds: 5)),
      isNull,
    );
    expect(find.byType(OpenSaveDialog), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('Escape closes while the listing never completes', (
    tester,
  ) async {
    final never = NeverLister();
    final launch = await openPicker(
      tester,
      lister: never,
      initialPath: '/somewhere/deep',
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(
      await launch.future.timeout(const Duration(seconds: 5)),
      isNull,
    );
    expect(find.byType(OpenSaveDialog), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
