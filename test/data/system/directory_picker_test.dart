import 'dart:io';

import 'package:bomb_flower/data/system/directory_picker.dart';
import 'package:bomb_flower/data/system/host_platform.dart';
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

/// A [DirectoryPicker] that records the calls its backend received.
final class RecordingPicker implements DirectoryPicker {
  RecordingPicker(this.label, {this.result});

  final String label;
  final String? result;
  final List<String> calls = <String>[];

  @override
  Future<String?> pickDirectory({String? title, String? initialPath}) async {
    calls.add(label);
    return result;
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

  group('PlatformDirectoryPicker', () {
    test('windows selects the file_selector picker', () async {
      final fileSelector = RecordingPicker('file_selector', result: r'C:\save');
      final system = RecordingPicker('system');
      final picker = PlatformDirectoryPicker(
        platform: HostPlatform.windows,
        fileSelector: fileSelector,
        system: system,
      );

      expect(await picker.pickDirectory(title: 'Open'), r'C:\save');
      expect(fileSelector.calls, <String>['file_selector']);
      expect(system.calls, isEmpty);
      expect(picker.backend, same(fileSelector));
    });

    test('linux keeps the zenity/kdialog chain', () async {
      final fileSelector = RecordingPicker('file_selector');
      final runner = FakeProcessRunner(<String, ProcessOutcome>{
        'zenity': const ProcessOutcome.completed(0, '/save/root\n'),
      });
      final system = SystemDirectoryPicker(runner: runner);
      final picker = PlatformDirectoryPicker(
        platform: HostPlatform.linux,
        fileSelector: fileSelector,
        system: system,
      );

      expect(await picker.pickDirectory(), '/save/root');
      expect(runner.calls.single, startsWith('zenity --file-selection'));
      expect(fileSelector.calls, isEmpty);
      expect(picker.backend, same(system));
    });

    test(
      'fuchsia follows the Linux chain and other hosts the file_selector one',
      () {
        final fileSelector = RecordingPicker('file_selector');
        final system = RecordingPicker('system');

        expect(
          PlatformDirectoryPicker(
            platform: HostPlatform.fuchsia,
            fileSelector: fileSelector,
            system: system,
          ).backend,
          same(system),
        );
        expect(
          PlatformDirectoryPicker(
            platform: HostPlatform.other,
            fileSelector: fileSelector,
            system: system,
          ).backend,
          same(fileSelector),
        );
        expect(
          PlatformDirectoryPicker(
            platform: HostPlatform.macos,
            fileSelector: fileSelector,
            system: system,
          ).backend,
          same(fileSelector),
        );
      },
    );
  });

  group('FileSelectorDirectoryPicker', () {
    test('passes the start folder and title, then trims the result', () async {
      String? start;
      String? confirm;
      final picker = FileSelectorDirectoryPicker(
        chooser: ({String? initialDirectory, String? confirmButtonText}) async {
          start = initialDirectory;
          confirm = confirmButtonText;
          return r'  C:\picked  ';
        },
      );

      expect(
        await picker.pickDirectory(
          title: 'Choose',
          initialPath: '  C:\\start  ',
        ),
        r'C:\picked',
      );
      expect(start, r'C:\start');
      expect(confirm, 'Choose');
    });

    test('a cancelled or failing dialog is null, never a throw', () async {
      final cancelled = FileSelectorDirectoryPicker(
        chooser: ({
          String? initialDirectory,
          String? confirmButtonText,
        }) async => null,
      );
      final failing = FileSelectorDirectoryPicker(
        chooser: ({
          String? initialDirectory,
          String? confirmButtonText,
        }) async => throw StateError('no plugin'),
      );

      expect(await cancelled.pickDirectory(), isNull);
      expect(await failing.pickDirectory(), isNull);
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

    test(
      'default config directory follows the platform, never the temp folder',
      () {
        final windows = RecentPathsFileStore.defaultDirectory(
          environment: const <String, String>{
            'APPDATA': r'C:\Users\d\AppData\Roaming',
            'LOCALAPPDATA': r'C:\Users\d\AppData\Local',
          },
          platform: HostPlatform.windows,
        );
        expect(windows, r'C:\Users\d\AppData\Roaming\bomb-flower');
        expect(windows, isNot(contains('/')));
        expect(windows, isNot(contains('TEMP')));

        expect(
          RecentPathsFileStore.defaultDirectory(
            environment: const <String, String>{'XDG_CONFIG_HOME': '/cfg'},
            platform: HostPlatform.linux,
          ),
          '/cfg/bomb-flower',
        );
        expect(
          RecentPathsFileStore.defaultDirectory(
            environment: const <String, String>{'HOME': '/home/d'},
            platform: HostPlatform.linux,
          ),
          '/home/d/.config/bomb-flower',
        );

        // Documented last resort only: nothing resolved for this platform.
        expect(
          RecentPathsFileStore.defaultDirectory(
            environment: const <String, String>{},
            platform: HostPlatform.other,
          ),
          '${Directory.systemTemp.path}/bomb-flower',
        );
      },
    );

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

    test('reports a slot folder holding progress.sav directly', () async {
      final slot = Directory('${temp.path}/slot_00')..createSync();
      File('${slot.path}/progress.sav').writeAsStringSync('save');

      final info = await probe.inspect(slot.path);

      expect(info.isDirectory, isTrue);
      expect(info.progressSavePresent, isTrue);
      expect(info.containsSaveSlots, isFalse);
      expect(info.isSaveRoot, isFalse);
    });

    test('a save root reports no progress.sav directly', () async {
      Directory('${temp.path}/slot_00').createSync();

      final info = await probe.inspect(temp.path);

      expect(info.progressSavePresent, isFalse);
      expect(info.isSaveRoot, isTrue);
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
