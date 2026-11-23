import 'dart:io';

import 'package:bomb_flower/data/system/directory_picker.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeProcessRunner implements ProcessRunner {
  FakeProcessRunner(this.outcomes);

  final Map<String, ProcessOutcome> outcomes;
  final List<String> calls = <String>[];
  final List<Duration> timeouts = <Duration>[];

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    calls.add(<String>[executable, ...arguments].join(' '));
    timeouts.add(timeout);
    return outcomes[executable] ?? const ProcessOutcome.unavailable();
  }
}

void main() {
  group('SystemDirectoryPicker', () {
    test('uses zenity first and trims its output', () async {
      final runner = FakeProcessRunner(<String, ProcessOutcome>{
        'zenity': const ProcessOutcome.completed(0, '/save/root\n'),
      });
      final picker = SystemDirectoryPicker(runner: runner);

      final path = await picker.pickDirectory(title: 'Open save');

      expect(path, '/save/root');
      expect(runner.calls, hasLength(1));
      expect(runner.calls.single, startsWith('zenity --file-selection'));
      expect(runner.calls.single, contains('--directory'));
      expect(runner.calls.single, contains('--title=Open save'));
      expect(runner.timeouts.single, const Duration(seconds: 3));
    });

    test('falls through to kdialog when zenity is unavailable', () async {
      final runner = FakeProcessRunner(<String, ProcessOutcome>{
        'kdialog': const ProcessOutcome.completed(0, '/kdialog/root\n'),
      });
      final picker = SystemDirectoryPicker(runner: runner);

      final path = await picker.pickDirectory(initialPath: '/save');

      expect(path, '/kdialog/root');
      expect(runner.calls.first, startsWith('zenity'));
      expect(runner.calls.last, startsWith('kdialog --getexistingdirectory'));
    });

    test('falls through to qarma when the first two are unavailable', () async {
      final runner = FakeProcessRunner(<String, ProcessOutcome>{
        'qarma': const ProcessOutcome.completed(0, '/qarma/root\n'),
      });
      final picker = SystemDirectoryPicker(runner: runner);

      expect(await picker.pickDirectory(), '/qarma/root');
      expect(runner.calls.last, startsWith('qarma --file-selection'));
    });

    test('returns null when no backend is installed', () async {
      final picker = SystemDirectoryPicker(
        runner: FakeProcessRunner(<String, ProcessOutcome>{}),
      );

      expect(await picker.pickDirectory(), isNull);
    });

    test(
      'a non-zero exit means the user cancelled, not another dialog',
      () async {
        final runner = FakeProcessRunner(<String, ProcessOutcome>{
          'zenity': const ProcessOutcome.completed(1, ''),
          'kdialog': const ProcessOutcome.completed(0, '/should/not/be/used\n'),
        });
        final picker = SystemDirectoryPicker(runner: runner);

        expect(await picker.pickDirectory(), isNull);
        expect(runner.calls, hasLength(1));
      },
    );

    test('a timeout returns null and does not stack another dialog', () async {
      final runner = FakeProcessRunner(<String, ProcessOutcome>{
        'zenity': const ProcessOutcome.timedOut(),
        'kdialog': const ProcessOutcome.completed(0, '/should/not/be/used\n'),
      });
      final picker = SystemDirectoryPicker(runner: runner);

      expect(await picker.pickDirectory(), isNull);
      expect(runner.calls, hasLength(1));
    });

    test('blank output returns null', () async {
      final picker = SystemDirectoryPicker(
        runner: FakeProcessRunner(<String, ProcessOutcome>{
          'zenity': const ProcessOutcome.completed(0, '  \n\n'),
        }),
      );

      expect(await picker.pickDirectory(), isNull);
    });

    test('the first non-empty line wins', () async {
      final picker = SystemDirectoryPicker(
        runner: FakeProcessRunner(<String, ProcessOutcome>{
          'zenity': const ProcessOutcome.completed(
            0,
            '\n/save/root\n/save/other\n',
          ),
        }),
      );

      expect(await picker.pickDirectory(), '/save/root');
    });
  });

  group('RecentPathsFileStore', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('bomb-flower-recent-');
    });

    tearDown(() {
      if (temp.existsSync()) {
        temp.deleteSync(recursive: true);
      }
    });

    test('round-trips with the newest path first', () async {
      final store = RecentPathsFileStore(directory: temp.path);

      await store.add('/save/a');
      await store.add('/save/b');
      await store.add('/save/a');

      expect(await store.read(), <String>['/save/a', '/save/b']);
      expect(store.filePath, endsWith('recent.json'));
    });

    test('caps at ten entries and drops the oldest', () async {
      final store = RecentPathsFileStore(directory: temp.path);

      for (var index = 0; index < 12; index++) {
        await store.add('/save/$index');
      }

      final paths = await store.read();
      expect(paths, hasLength(10));
      expect(paths.first, '/save/11');
      expect(paths.last, '/save/2');
      expect(paths, isNot(contains('/save/0')));
      expect(paths, isNot(contains('/save/1')));
    });

    test('survives corrupt JSON and can be written again', () async {
      final store = RecentPathsFileStore(directory: temp.path);
      await File(store.filePath).writeAsString('{not json');

      expect(await store.read(), isEmpty);

      await store.add('/save/recovered');
      expect(await store.read(), <String>['/save/recovered']);
    });

    test('survives a JSON object instead of a list', () async {
      final store = RecentPathsFileStore(directory: temp.path);
      await File(store.filePath).writeAsString('{"paths":["/save/a"]}');

      expect(await store.read(), isEmpty);
    });

    test('ignores non-string and duplicate entries', () async {
      final store = RecentPathsFileStore(directory: temp.path);
      await File(store.filePath)
          .writeAsString('["/save/a", 4, null, " /save/a ", "/save/b"]');

      expect(await store.read(), <String>['/save/a', '/save/b']);
    });

    test('clear removes the file', () async {
      final store = RecentPathsFileStore(directory: temp.path);
      await store.add('/save/a');

      await store.clear();

      expect(await store.read(), isEmpty);
      expect(File(store.filePath).existsSync(), isFalse);
    });
  });

  group('IoSaveFolderProbe', () {
    late Directory temp;
    const probe = IoSaveFolderProbe();

    setUp(() {
      temp = Directory.systemTemp.createTempSync('bomb-flower-probe-');
    });

    tearDown(() {
      if (temp.existsSync()) {
        temp.deleteSync(recursive: true);
      }
    });

    test('accepts a directory with sorted slot_* folders', () async {
      Directory('${temp.path}/slot_01').createSync();
      Directory('${temp.path}/slot_00').createSync();
      Directory('${temp.path}/other').createSync();

      final info = await probe.inspect(temp.path);

      expect(info.exists, isTrue);
      expect(info.isDirectory, isTrue);
      expect(info.isSaveRoot, isTrue);
      expect(info.slotDirectories, <String>['slot_00', 'slot_01']);
      expect(info.parentExists, isTrue);
    });

    test('rejects a directory without slot folders', () async {
      final info = await probe.inspect(temp.path);

      expect(info.isDirectory, isTrue);
      expect(info.containsSaveSlots, isFalse);
      expect(info.isSaveRoot, isFalse);
    });

    test('reports a file path as non-creatable', () async {
      final file = File('${temp.path}/progress.sav')
        ..writeAsStringSync('not a folder');

      final info = await probe.inspect(file.path);

      expect(info.exists, isTrue);
      expect(info.isDirectory, isFalse);
      expect(info.isCreatable, isFalse);
      expect(info.isSaveRoot, isFalse);
    });

    test('a missing path is creatable when its parent exists', () async {
      final info = await probe.inspect('${temp.path}/new-root');

      expect(info.exists, isFalse);
      expect(info.isCreatable, isTrue);
      expect(info.parentExists, isTrue);
    });

    test('a missing path reports a missing parent', () async {
      final info = await probe.inspect('${temp.path}/missing/new-root');

      expect(info.exists, isFalse);
      expect(info.parentExists, isFalse);
    });

    test('an empty path is reported without throwing', () async {
      final info = await probe.inspect('   ');

      expect(info.exists, isFalse);
      expect(info.isSaveRoot, isFalse);
    });
  });
}
