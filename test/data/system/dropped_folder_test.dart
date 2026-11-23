import 'dart:io';

import 'package:bomb_flower/data/system/dropped_folder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the drop resolver. Every case builds a real temporary tree,
/// because the resolver's whole job is to read the host filesystem and turn it
/// into one honest verdict.
void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bomb_flower_drop_');
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  String join(String parent, String child) =>
      '$parent${Platform.pathSeparator}$child';

  Directory folder(String name) =>
      Directory(join(temp.path, name))..createSync(recursive: true);

  void writeProgress(String directory) {
    File(join(directory, progressSaveName)).writeAsStringSync('save');
  }

  Future<DroppedFolderResult> resolve(String? path) =>
      resolveDroppedFolder(path);

  test('a profile folder holding slot_NN/progress.sav is a root', () async {
    final profile = folder('kokiri-start');
    final slot = folder('kokiri-start/slot_00');
    writeProgress(slot.path);

    final result = await resolve(profile.path);

    expect(result, isA<DroppedFolderRoot>());
    expect((result as DroppedFolderRoot).path, profile.path);
  });

  test('a folder holding progress.sav directly is a root', () async {
    final direct = folder('direct-save');
    writeProgress(direct.path);

    final result = await resolve(direct.path);

    expect(result, isA<DroppedFolderRoot>());
    expect((result as DroppedFolderRoot).path, direct.path);
  });

  test('dropping the parent of one profile folder opens that child', () async {
    final profile = folder('outer/kokiri-start');
    final slot = folder('outer/kokiri-start/slot_01');
    writeProgress(slot.path);

    final result = await resolve(join(temp.path, 'outer'));

    expect(result, isA<DroppedFolderRoot>());
    expect((result as DroppedFolderRoot).path, profile.path);
  });

  test('a dropped slot folder is refused and names its parent', () async {
    final profile = folder('profile');
    final slot = folder('profile/slot_00');
    writeProgress(slot.path);

    final result = await resolve(slot.path);

    expect(result, isA<DroppedFolderInvalid>());
    final invalid = result as DroppedFolderInvalid;
    expect(invalid.path, slot.path);
    expect(invalid.reason, contains('That is a slot folder.'));
    expect(invalid.reason, contains(profile.path));
    expect(invalid.reason, isNot(contains('damaged')));
  });

  test('a dropped file is refused and says a folder is expected', () async {
    final file = File(join(temp.path, 'notes.txt'))
      ..writeAsStringSync('not a save');

    final result = await resolve(file.path);

    expect(result, isA<DroppedFolderInvalid>());
    final invalid = result as DroppedFolderInvalid;
    expect(invalid.path, file.path);
    expect(invalid.reason, contains('slot_00'));
    expect(invalid.reason, contains('not a file'));
  });

  test('an empty folder is refused and says what to drop', () async {
    final empty = folder('empty');

    final result = await resolve(empty.path);

    expect(result, isA<DroppedFolderInvalid>());
    final invalid = result as DroppedFolderInvalid;
    expect(invalid.reason, contains('slot_00'));
    expect(invalid.reason, contains('not a save'));
  });

  test('a missing path, blank input, and non-strings never throw', () async {
    final missing = await resolve(join(temp.path, 'missing'));
    expect(missing, isA<DroppedFolderInvalid>());
    expect(
      (missing as DroppedFolderInvalid).reason,
      contains(saveRootExpectation),
    );

    final blank = await resolve('   ');
    expect(blank, isA<DroppedFolderInvalid>());
    expect((blank as DroppedFolderInvalid).path, isEmpty);

    final absent = await resolve(null);
    expect(absent, isA<DroppedFolderInvalid>());
    expect((absent as DroppedFolderInvalid).reason, saveRootExpectation);
  });

  test('two candidate saves under one dropped folder are ambiguous', () async {
    final first = folder('outer/first');
    writeProgress(folder('outer/first/slot_00').path);
    final second = folder('outer/second');
    writeProgress(folder('outer/second/slot_00').path);

    final result = await resolve(join(temp.path, 'outer'));

    expect(result, isA<DroppedFolderInvalid>());
    expect((result as DroppedFolderInvalid).path, join(temp.path, 'outer'));
    expect(result.reason, contains('slot_00'));
    expect(first.existsSync(), isTrue);
    expect(second.existsSync(), isTrue);
  });
}
