import 'dart:io';

import 'package:bomb_flower/data/system/directory_lister.dart';
import 'package:bomb_flower/data/system/host_platform.dart';
import 'package:bomb_flower/data/system/profile_path.dart';
import 'package:flutter_test/flutter_test.dart';

/// The per-platform save/backup rules, exercised on Linux through the injected
/// platform and environment seams. Nothing here reads `Platform.isWindows` or
/// needs a Windows machine.
void main() {
  const windows = HostPlatform.windows;
  const linux = HostPlatform.linux;
  const roaming = r'C:\Users\d\AppData\Roaming';
  const local = r'C:\Users\d\AppData\Local';
  const profile = r'C:\Users\d';

  group('resolveLongshotSaveLocations', () {
    test('windows: %APPDATA% names the launcher save folder', () {
      final locations = resolveLongshotSaveLocations(
        environment: const {'APPDATA': roaming},
        platform: windows,
      );

      expect(locations.saveBase, r'C:\Users\d\AppData\Roaming\Longshot\save');
      expect(locations.backupBase, isNull);
    });

    test('windows: with %APPDATA% unset the documented game folder under '
        '%USERPROFILE% is the fallback', () {
      final locations = resolveLongshotSaveLocations(
        environment: const {'USERPROFILE': profile},
        platform: windows,
      );

      expect(locations.saveBase, r'C:\Users\d\Games\Longshot\user\save');
      expect(locations.backupBase, isNull);
    });

    test('windows: %LOCALAPPDATA% names the backup folder', () {
      final locations = resolveLongshotSaveLocations(
        environment: const {
          'APPDATA': roaming,
          'LOCALAPPDATA': local,
          'USERPROFILE': profile,
        },
        platform: windows,
      );

      expect(
        locations.backupBase,
        r'C:\Users\d\AppData\Local\Longshot\oot-save-backups',
      );
      expect(locations.saveBase, r'C:\Users\d\AppData\Roaming\Longshot\save');
    });

    test('windows: with no variables set nothing is invented', () {
      final locations = resolveLongshotSaveLocations(
        environment: const <String, String>{},
        platform: windows,
      );

      expect(locations.saveBase, isNull);
      expect(locations.backupBase, isNull);
    });

    test('windows: blank variables count as unset', () {
      final locations = resolveLongshotSaveLocations(
        environment: const {
          'APPDATA': '   ',
          'USERPROFILE': '',
          'LOCALAPPDATA': ' ',
        },
        platform: windows,
      );

      expect(locations.saveBase, isNull);
      expect(locations.backupBase, isNull);
    });

    test('linux: XDG_DATA_HOME then HOME are unchanged', () {
      final xdg = resolveLongshotSaveLocations(
        environment: const {'XDG_DATA_HOME': '/data', 'HOME': '/home/d'},
        platform: linux,
      );
      expect(xdg.saveBase, '/data/longshot/save');
      expect(xdg.backupBase, '/data/longshot/save-backup');

      final home = resolveLongshotSaveLocations(
        environment: const {'HOME': '/home/d'},
        platform: linux,
      );
      expect(home.saveBase, '/home/d/.local/share/longshot/save');
      expect(home.backupBase, '/home/d/.local/share/longshot/save-backup');

      final none = resolveLongshotSaveLocations(
        environment: const <String, String>{},
        platform: linux,
      );
      expect(none.saveBase, isNull);
      expect(none.backupBase, isNull);
    });

    test('linux: XDG_DATA_HOME wins over HOME and keeps POSIX separators', () {
      final locations = resolveLongshotSaveLocations(
        environment: const {'XDG_DATA_HOME': '/data/', 'HOME': '/home/d'},
        platform: linux,
      );

      expect(locations.saveBase, '/data/longshot/save');
      expect(locations.saveBase, isNot(contains(r'\')));
    });

    test('macos: no save location is invented', () {
      final locations = resolveLongshotSaveLocations(
        environment: const {
          'HOME': '/Users/d',
          'APPDATA': roaming,
          'LOCALAPPDATA': local,
        },
        platform: HostPlatform.macos,
      );

      expect(locations.saveBase, isNull);
      expect(locations.backupBase, isNull);
    });

    test('an unknown host invents nothing', () {
      final locations = resolveLongshotSaveLocations(
        environment: const {'HOME': '/anything'},
        platform: HostPlatform.other,
      );

      expect(locations.saveBase, isNull);
      expect(locations.backupBase, isNull);
    });

    test(
      'windows: the result uses backslashes and never a hardcoded C: drive',
      () {
        final locations = resolveLongshotSaveLocations(
          environment: const {'APPDATA': r'D:\Profiles\d\AppData\Roaming'},
          platform: windows,
        );

        expect(
          locations.saveBase,
          r'D:\Profiles\d\AppData\Roaming\Longshot\save',
        );
        expect(locations.saveBase, isNot(contains('/')));
        expect(locations.saveBase, isNot(contains('C:')));
      },
    );

    test('longshotSaveBase stays a source-compatible delegate', () {
      expect(
        longshotSaveBase(
          environment: const {'XDG_DATA_HOME': '/data'},
          platform: linux,
        ),
        '/data/longshot/save',
      );
      expect(
        longshotSaveBase(
          environment: const {'APPDATA': roaming},
          platform: windows,
        ),
        r'C:\Users\d\AppData\Roaming\Longshot\save',
      );
    });
  });

  group('resolveOpenSaveStartFolder', () {
    test(
      'windows: the home fallback reads USERPROFILE when HOME is absent',
      () async {
        final home = Directory.systemTemp.createTempSync('bomb_flower_user_');
        addTearDown(() {
          if (home.existsSync()) {
            home.deleteSync(recursive: true);
          }
        });

        final start = await resolveOpenSaveStartFolder(
          environment: {'USERPROFILE': home.path},
          // No HOME: the injected lister reports none, so the environment path
          // rule is what is under test.
          lister: const IoDirectoryLister(environment: <String, String>{}),
          platform: windows,
        );

        expect(start, home.path);
      },
    );

    test(
      'linux: HOME still resolves the start folder when no save exists',
      () async {
        final home = Directory.systemTemp.createTempSync('bomb_flower_home_');
        addTearDown(() {
          if (home.existsSync()) {
            home.deleteSync(recursive: true);
          }
        });

        final start = await resolveOpenSaveStartFolder(
          environment: {'HOME': home.path},
          lister: const IoDirectoryLister(environment: <String, String>{}),
          platform: linux,
        );

        expect(start, home.path);
      },
    );
  });
}
