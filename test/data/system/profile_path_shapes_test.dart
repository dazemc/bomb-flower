import 'dart:io';

import 'package:bomb_flower/data/system/directory_lister.dart';
import 'package:bomb_flower/data/system/profile_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const lister = IoDirectoryLister();
  late Directory temp;
  late Directory save;
  late Directory profile;
  late Directory slot;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bomb_flower_shape_');
    save = Directory('${temp.path}/save')..createSync();
    profile = Directory('${save.path}/5a3c9e1f0b7d24680000000000000001')
      ..createSync();
    slot = Directory('${profile.path}/slot_02')..createSync();
    File('${slot.path}/progress.sav').writeAsStringSync('x');
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  Future<ProfilePathResolution> resolve(String path) =>
      resolveProfilePath(path, lister: lister);

  test('a save/<user id> profile folder resolves to itself', () async {
    final result = await resolve(profile.path);

    expect(result, isA<ProfilePathResolved>());
    expect((result as ProfilePathResolved).path, profile.path);
  });

  test('a slot folder resolves to its profile', () async {
    final result = await resolve(slot.path);

    expect(result, isA<ProfilePathResolved>());
    expect((result as ProfilePathResolved).path, profile.path);
  });

  test('a progress.sav file path resolves to its profile', () async {
    final result = await resolve('${slot.path}/$progressSaveName');

    expect(result, isA<ProfilePathResolved>());
    expect((result as ProfilePathResolved).path, profile.path);
  });

  test('a bare save root with one profile resolves to that profile', () async {
    final result = await resolve(save.path);

    expect(result, isA<ProfilePathResolved>());
    expect((result as ProfilePathResolved).path, profile.path);
  });

  test(
    'a bare save root with two profiles is ambiguous and lists both candidates',
    () async {
      final second = Directory('${save.path}/ffffffffffffffffffffffffffffffff')
        ..createSync();
      Directory('${second.path}/slot_07').createSync();
      File('${second.path}/slot_07/progress.sav').writeAsStringSync('x');

      final result = await resolve(save.path);

      expect(result, isA<ProfilePathAmbiguous>());
      final candidates = (result as ProfilePathAmbiguous).candidates;
      expect(candidates, <String>[second.path, profile.path]..sort());
      expect(() => candidates.add('/elsewhere'), throwsUnsupportedError);
    },
  );

  test('a nonexistent path is unreadable', () async {
    final result = await resolve('${temp.path}/missing');

    expect(result, isA<ProfilePathUnreadable>());
    expect(
      (result as ProfilePathUnreadable).message,
      contains('does not exist'),
    );
  });

  test('a folder with no progress.sav anywhere beneath is rejected, naming progress.sav', () async {
    final empty = Directory('${temp.path}/empty/deeper/deepest')
      ..createSync(recursive: true);
    Directory('${empty.path}/also-empty').createSync();

    final result = await resolve('${temp.path}/empty');

    expect(result, isA<ProfilePathRejected>());
    final message = (result as ProfilePathRejected).message;
    expect(message, contains(progressSaveName));
    expect(
      message,
      isNot(
        contains('is not a profile folder containing slot_NN/progress.sav'),
      ),
    );
  });

  test('a slot whose folder name is not slot_NN still resolves by its progress.sav', () async {
    final root = Directory('${temp.path}/named')..createSync();
    final namedProfile = Directory(
      '${root.path}/ffffffffffffffffffffffffffffffff',
    )..createSync();
    final namedSlot = Directory('${namedProfile.path}/savegame_alpha')
      ..createSync();
    File('${namedSlot.path}/progress.sav').writeAsStringSync('x');

    final fromRoot = await resolve(root.path);
    expect(fromRoot, isA<ProfilePathResolved>());
    expect((fromRoot as ProfilePathResolved).path, namedProfile.path);

    final fromSlot = await resolve(namedSlot.path);
    expect(fromSlot, isA<ProfilePathResolved>());
    expect((fromSlot as ProfilePathResolved).path, namedProfile.path);
  });
}
