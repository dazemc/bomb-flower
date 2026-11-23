import 'dart:async';
import 'dart:io';

import 'package:bomb_flower/data/system/directory_lister.dart';
import 'package:bomb_flower/presentation/dialogs/open_save_dialog.dart';
import 'package:bomb_flower/presentation/shell/tabs/settings_tab.dart';
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
  Future<DirectoryListing> list(
    String path, {
    bool includeHidden = false,
  }) {
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
      if (!includeHidden && name.startsWith('.')) {
        continue;
      }
      final isDirectory = entity is Directory;
      final hasProgressSave =
          isDirectory &&
          File(
            '${entity.path}${Platform.pathSeparator}$progressSaveName',
          ).existsSync();
      var containsSlots = false;
      if (isDirectory) {
        for (var index = 0; index < 10; index++) {
          final slot = 'slot_${index.toString().padLeft(2, '0')}';
          if (File(
            '${entity.path}${Platform.pathSeparator}$slot'
            '${Platform.pathSeparator}$progressSaveName',
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
          hasProgressSave: hasProgressSave,
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
  Future<DirectoryListing> list(
    String path, {
    bool includeHidden = false,
  }) {
    calls.add(path);
    return completer.future;
  }
}

bool openEnabled(WidgetTester tester) =>
    tester
        .widget<BrassButton>(find.byKey(const Key('open-save-submit')))
        .onPressed !=
    null;

bool hiddenSwitchValue(WidgetTester tester) =>
    tester.widget<Switch>(find.byKey(const Key('open-save-show-hidden'))).value;

String fieldText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('open-save-path')))
    .controller!
    .text;

Future<DialogLauncher<String>> openPicker(
  WidgetTester tester, {
  required DirectoryLister lister,
  required String initialPath,
  FakeRecentPathsStore? recents,
  SettingsStore? settingsStore,
}) {
  return launchDialog<String>(
    tester,
    (context) => OpenSaveDialog.show(
      context,
      probe: FakeSaveFolderProbe(),
      recentPaths: recents ?? FakeRecentPathsStore(),
      directoryLister: lister,
      settingsStore: settingsStore ?? InMemorySettingsStore(),
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
    File('${root.path}/profile/slot_00/progress.sav').writeAsStringSync('x');
    Directory('${root.path}/fakeProfile/slot_00').createSync(recursive: true);
    Directory('${root.path}/.hidden').createSync();
    File('${root.path}/alpha/notes.txt').writeAsStringSync('note');
    File('${root.path}/.dotfile').writeAsStringSync('secret');
    File('${root.path}/zeta.txt').writeAsStringSync('text');
    lister = TempTreeLister(root.path);
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  testWidgets('lists dirs-first, single tap descends, .. returns, dots hidden', (
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
    expect(find.byKey(const Key('open-save-entry-.hidden')), findsNothing);
    expect(find.byKey(const Key('open-save-entry-.dotfile')), findsNothing);

    final firstDirectory = tester
        .getTopLeft(find.byKey(const Key('open-save-entry-alpha')))
        .dy;
    final file = tester
        .getTopLeft(find.byKey(const Key('open-save-entry-zeta.txt')))
        .dy;
    expect(firstDirectory, lessThan(file));

    // One tap on a plain folder descends; no double click required.
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('open-save-entry-alpha'))),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(fieldText(tester), '${root.path}/alpha');
    expect(find.byKey(const Key('open-save-entry-notes.txt')), findsOneWidget);

    // One tap on `..` returns to the parent.
    await tester.tap(find.byKey(const Key('open-save-parent')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(fieldText(tester), root.path);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a selected profile can be entered with Enter', (tester) async {
    final launch = await openPicker(
      tester,
      lister: lister,
      initialPath: root.path,
    );
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('open-save-entry-profile'))),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-save-selected')), findsOneWidget);
    expect(fieldText(tester), root.path);
    expect(openEnabled(tester), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fieldText(tester), '${root.path}/profile');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('Open is disabled for a folder without an openable slot', (
    tester,
  ) async {
    final launch = await openPicker(
      tester,
      lister: lister,
      initialPath: root.path,
    );
    await tester.pumpAndSettle();

    // fakeProfile has slot_00 but no slot_00/progress.sav.
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('open-save-entry-fakeProfile'))),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(fieldText(tester), '${root.path}/fakeProfile');
    expect(find.byKey(const Key('open-save-blocked-reason')), findsOneWidget);
    expect(openEnabled(tester), isFalse);

    // Selecting the bare slot does not turn an unopenable folder into a root.
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('open-save-entry-slot_00'))),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(openEnabled(tester), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a single tap on a profile enables Open and opens it once', (
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
          settingsStore: InMemorySettingsStore(),
          initialPath: root.path,
        );
      },
    );
    await tester.pumpAndSettle();

    final profile = '${root.path}/profile';
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('open-save-entry-profile'))),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-save-selected')), findsOneWidget);
    expect(openEnabled(tester), isTrue);

    await tester.tap(find.byKey(const Key('open-save-submit')));
    await tester.pumpAndSettle();

    expect(await launch.future, profile);
    expect(shows, 1);
    expect(recents.added, <String>[profile]);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('hidden folders are off by default and toggled on and kept', (
    tester,
  ) async {
    final settings = InMemorySettingsStore();
    await openPicker(
      tester,
      lister: lister,
      initialPath: root.path,
      settingsStore: settings,
    );
    await tester.pumpAndSettle();

    expect(hiddenSwitchValue(tester), isFalse);
    expect(find.byKey(const Key('open-save-entry-.hidden')), findsNothing);
    expect(settings.lastValue.showHiddenEntries, isFalse);

    await tester.tap(find.byKey(const Key('open-save-show-hidden')));
    await tester.pumpAndSettle();

    expect(hiddenSwitchValue(tester), isTrue);
    expect(find.byKey(const Key('open-save-entry-.hidden')), findsOneWidget);
    expect(settings.lastValue.showHiddenEntries, isTrue);

    // Persisted across a close and reopen with the same store.
    await tester.tap(find.byKey(const Key('open-save-cancel')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dialog-launch')));
    await tester.pumpAndSettle();

    expect(hiddenSwitchValue(tester), isTrue);
    expect(find.byKey(const Key('open-save-entry-.hidden')), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-save-cancel')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('it never closes itself while idle', (tester) async {
    final launch = await openPicker(
      tester,
      lister: lister,
      initialPath: root.path,
    );
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(OpenSaveDialog), findsOneWidget);
    expect(launch.isCompleted, isFalse);

    await tester.tap(find.byKey(const Key('open-save-cancel')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('the up control keeps the dialog open and lists the parent', (
    tester,
  ) async {
    final launch = await openPicker(
      tester,
      lister: lister,
      initialPath: '${root.path}/alpha',
    );
    await tester.pumpAndSettle();
    expect(fieldText(tester), '${root.path}/alpha');

    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('open-save-parent'))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OpenSaveDialog), findsOneWidget);
    expect(fieldText(tester), root.path);
    expect(launch.isCompleted, isFalse);

    await tester.tap(find.byKey(const Key('open-save-cancel')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a disabled up control at the filesystem root is inert', (
    tester,
  ) async {
    final scripted = FakeDirectoryLister(<String, DirectoryListing>{
      '/root': const DirectoryListing(
        path: '/root',
        entries: <DirectoryEntry>[],
        parentPath: null,
      ),
    });
    final launch = await openPicker(
      tester,
      lister: scripted,
      initialPath: '/root',
    );
    await tester.pumpAndSettle();
    expect(fieldText(tester), '/root');

    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('open-save-parent'))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OpenSaveDialog), findsOneWidget);
    expect(fieldText(tester), '/root');
    expect(launch.isCompleted, isFalse);

    await tester.tap(find.byKey(const Key('open-save-cancel')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('up and Cancel are different controls', (tester) async {
    final launch = await openPicker(
      tester,
      lister: lister,
      initialPath: '${root.path}/alpha',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-save-parent')), findsOneWidget);
    expect(find.byKey(const Key('open-save-cancel')), findsOneWidget);

    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('open-save-parent'))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OpenSaveDialog), findsOneWidget);
    expect(launch.isCompleted, isFalse);

    await tester.tap(find.byKey(const Key('open-save-cancel')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(await launch.future, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('footer buttons are hittable across their full width', (
    tester,
  ) async {
    final launch = await openPicker(
      tester,
      lister: lister,
      initialPath: '${root.path}/profile',
    );
    await tester.pumpAndSettle();

    final submit = find.byKey(const Key('open-save-submit'));
    final cancel = find.byKey(const Key('open-save-cancel'));
    final submitRect = tester.getRect(submit);
    final cancelRect = tester.getRect(cancel);
    debugPrint('MEASURE open=$submitRect cancel=$cancelRect');

    for (final fractionY in <double>[0.2, 0.8]) {
      for (final fractionX in <double>[0.1, 0.9]) {
        if (find.byType(OpenSaveDialog).evaluate().isEmpty) {
          await tester.tap(find.byKey(const Key('dialog-launch')));
          await tester.pumpAndSettle();
        }
        final point = Offset(
          submitRect.left + submitRect.width * fractionX,
          submitRect.top + submitRect.height * fractionY,
        );
        final hit = tester.hitTestOnBinding(point);
        debugPrint(
          'MEASURE open@$fractionX/$fractionY point=$point hits='
          '${hit.path.take(5).map((entry) => entry.target.runtimeType).toList()}',
        );
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        debugPrint(
          'MEASURE open@$fractionX/$fractionY closed='
          '${find.byType(OpenSaveDialog).evaluate().isEmpty}',
        );
        expect(find.byType(OpenSaveDialog), findsNothing);
      }
    }
    expect(await launch.future, '${root.path}/profile');

    for (final fractionY in <double>[0.2, 0.8]) {
      for (final fractionX in <double>[0.1, 0.9]) {
        if (find.byType(OpenSaveDialog).evaluate().isEmpty) {
          await tester.tap(find.byKey(const Key('dialog-launch')));
          await tester.pumpAndSettle();
        }
        final point = Offset(
          cancelRect.left + cancelRect.width * fractionX,
          cancelRect.top + cancelRect.height * fractionY,
        );
        final hit = tester.hitTestOnBinding(point);
        debugPrint(
          'MEASURE cancel@$fractionX/$fractionY point=$point hits='
          '${hit.path.take(5).map((entry) => entry.target.runtimeType).toList()}',
        );
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        debugPrint(
          'MEASURE cancel@$fractionX/$fractionY closed='
          '${find.byType(OpenSaveDialog).evaluate().isEmpty}',
        );
        expect(find.byType(OpenSaveDialog), findsNothing);
      }
    }
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

    expect(await launch.future.timeout(const Duration(seconds: 5)), isNull);
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

    expect(await launch.future.timeout(const Duration(seconds: 5)), isNull);
    expect(find.byType(OpenSaveDialog), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
