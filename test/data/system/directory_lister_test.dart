import 'dart:io';

import 'package:bomb_flower/data/system/directory_lister.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const lister = IoDirectoryLister();
  late Directory temp;
  late Directory root;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bomb_flower_lister_');
    root = Directory('${temp.path}/root')..createSync();
    Directory('${root.path}/alpha').createSync();
    Directory('${root.path}/alpha/slot_00').createSync();
    File('${root.path}/alpha/slot_00/progress.sav').writeAsStringSync('x');
    Directory('${root.path}/beta').createSync();
    Directory('${root.path}/orphan/slot_00').createSync(recursive: true);
    Directory('${root.path}/slot_100').createSync();
    Directory('${root.path}/.hidden').createSync();
    File('${root.path}/zeta.txt').writeAsStringSync('text');
    File('${root.path}/Alpha.txt').writeAsStringSync('text');
    File('${root.path}/.dotfile').writeAsStringSync('secret');
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  test('lists directories first, then files, case-insensitively', () async {
    final listing = await lister.list(root.path);

    expect(listing.error, isNull);
    expect(listing.path, root.path);
    expect(listing.parentPath, temp.path);
    expect(listing.entries.map((entry) => entry.name).toList(), <String>[
      'alpha',
      'beta',
      'orphan',
      'slot_100',
      'Alpha.txt',
      'zeta.txt',
    ]);
    expect(listing.entries.take(4).every((entry) => entry.isDirectory), isTrue);
    expect(
      listing.entries.skip(4).every((entry) => !entry.isDirectory),
      isTrue,
    );
    expect(listing.isProfile, isFalse);
  });

  test('hides dot-entries by default and lists them on request', () async {
    final hiddenOff = await lister.list(root.path);
    expect(
      hiddenOff.entries.where((entry) => entry.name.startsWith('.')),
      isEmpty,
    );

    final hiddenOn = await lister.list(root.path, includeHidden: true);
    expect(
      hiddenOn.entries.map((entry) => entry.name),
      containsAll(<String>['.hidden', '.dotfile']),
    );
  });

  test('a profile needs slot_NN/progress.sav, not just slot_NN', () async {
    final alpha = await lister.list('${root.path}/alpha');
    expect(alpha.isProfile, isTrue);
    expect(alpha.slotNames, <String>['slot_00']);
    expect(alpha.entries.single.isSlotDirectory, isTrue);
    expect(alpha.entries.single.hasProgressSave, isTrue);

    final orphan = await lister.list('${root.path}/orphan');
    expect(orphan.isProfile, isFalse);
    expect(orphan.slotNames, isEmpty);
    expect(orphan.entries.single.isSlotDirectory, isTrue);
    expect(orphan.entries.single.hasProgressSave, isFalse);
  });

  test('marks the parent that contains an openable slot', () async {
    final parent = await lister.list(root.path);
    final alphaEntry = parent.entries.firstWhere((e) => e.name == 'alpha');
    final betaEntry = parent.entries.firstWhere((e) => e.name == 'beta');
    final orphanEntry = parent.entries.firstWhere((e) => e.name == 'orphan');
    expect(alphaEntry.containsSlots, isTrue);
    expect(betaEntry.containsSlots, isFalse);
    expect(orphanEntry.containsSlots, isFalse);

    // `slot_100` is not one of the ten slot names.
    final misnamed = parent.entries.firstWhere((e) => e.name == 'slot_100');
    expect(misnamed.isSlotDirectory, isFalse);
  });

  test('returns an error for a missing path instead of throwing', () async {
    final listing = await lister.list('${root.path}/missing');

    expect(listing.error, isNotNull);
    expect(listing.error, contains('Cannot read this folder'));
    expect(listing.entries, isEmpty);
  });

  test('returns Not a folder for a file', () async {
    final listing = await lister.list('${root.path}/zeta.txt');

    expect(listing.error, 'Not a folder');
    expect(listing.entries, isEmpty);
  });

  test('strips trailing separators and expands ~', () async {
    final trailing = await lister.list('${root.path}/alpha/');
    expect(trailing.error, isNull);
    expect(trailing.path, '${root.path}/alpha');

    final home = lister.homeDirectory;
    if (home != null) {
      final expanded = await lister.list('~');
      expect(expanded.error, isNull);
      expect(expanded.path, Directory(home).absolute.path);
    }
  });

  test('homeDirectory mirrors HOME', () {
    final home = Platform.environment['HOME']?.trim();
    if (home == null || home.isEmpty) {
      expect(lister.homeDirectory, isNull);
    } else {
      expect(lister.homeDirectory, home);
    }
  });

  test('homeDirectory prefers HOME and falls back to USERPROFILE', () {
    const both = IoDirectoryLister(
      environment: <String, String>{
        'HOME': '/home/d',
        'USERPROFILE': r'C:\Users\d',
      },
    );
    expect(both.homeDirectory, '/home/d');

    const windowsOnly = IoDirectoryLister(
      environment: <String, String>{'USERPROFILE': r'C:\Users\d'},
    );
    expect(windowsOnly.homeDirectory, r'C:\Users\d');

    const blank = IoDirectoryLister(
      environment: <String, String>{'HOME': '  ', 'USERPROFILE': ''},
    );
    expect(blank.homeDirectory, isNull);
  });

  test(
    'an injected home still expands ~ without touching the process environment',
    () async {
      final home = Directory.systemTemp.createTempSync('bomb_flower_home_');
      addTearDown(() {
        if (home.existsSync()) {
          home.deleteSync(recursive: true);
        }
      });
      final injected = IoDirectoryLister(
        environment: <String, String>{'HOME': home.path},
      );

      final expanded = await injected.list('~');
      expect(expanded.error, isNull);
      expect(expanded.path, home.path);
    },
  );
}
