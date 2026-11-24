import 'package:bomb_flower/data/system/host_platform.dart';
import 'package:bomb_flower/data/system/longshot_launcher_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// The resolution order, exercised without a real filesystem: every branch
/// supplies its own probe, platform, environment and application path.
void main() {
  const linux = HostPlatform.linux;
  const windows = HostPlatform.windows;

  IoLongshotLauncherResolver resolver({
    required Map<String, String> environment,
    required bool Function(String path) exists,
    String executablePath = '/opt/bomb-flower/bomb_flower',
    HostPlatform platform = linux,
  }) {
    return IoLongshotLauncherResolver(
      environment: environment,
      platform: platform,
      executablePath: executablePath,
      fileProbe: exists,
    );
  }

  test('an explicit environment override wins, even over discovery', () {
    const override = '/srv/longshot/LongshotLauncher.AppImage';
    final seen = <String>[];
    final resolved = resolver(
      environment: const {longshotLauncherEnvVar: override, 'PATH': '/usr/bin'},
      exists: (path) {
        seen.add(path);
        return true;
      },
    ).resolve();

    expect(resolved, override);
    // Discovery is never consulted once the override is non-blank.
    expect(seen, isEmpty);
  });

  test('a blank override counts as unset', () {
    final resolved = resolver(
      environment: const {longshotLauncherEnvVar: '   '},
      exists: (path) => path == '/opt/bomb-flower/LongshotLauncher.AppImage',
    ).resolve();

    expect(resolved, '/opt/bomb-flower/LongshotLauncher.AppImage');
  });

  test('a launcher next to the running app is found', () {
    final resolved = resolver(
      environment: const <String, String>{},
      exists: (path) => path == '/opt/bomb-flower/longshot',
    ).resolve();

    expect(resolved, '/opt/bomb-flower/longshot');
  });

  test('next-to-app candidates are probed in preference order', () {
    final probed = <String>[];
    final resolved = resolver(
      environment: const <String, String>{},
      exists: (path) {
        probed.add(path);
        // Both the AppImage and the bare name exist; the AppImage is first.
        return path == '/opt/bomb-flower/LongshotLauncher-x86_64.AppImage' ||
            path == '/opt/bomb-flower/Longshot';
      },
    ).resolve();

    expect(resolved, '/opt/bomb-flower/LongshotLauncher-x86_64.AppImage');
    expect(probed, <String>[
      '/opt/bomb-flower/LongshotLauncher-x86_64.AppImage',
    ]);
  });

  test('a PATH entry is searched when nothing sits next to the app', () {
    final resolved = resolver(
      environment: const {'PATH': '/usr/local/bin:/usr/bin'},
      exists: (path) => path == '/usr/bin/longshot',
    ).resolve();

    expect(resolved, '/usr/bin/longshot');
  });

  test('blank PATH entries are skipped', () {
    final resolved = resolver(
      environment: const {'PATH': '::/opt/bin:'},
      exists: (path) => path == '/opt/bin/Longshot',
    ).resolve();

    expect(resolved, '/opt/bin/Longshot');
  });

  test('the next-to-app hit beats a PATH hit', () {
    final resolved = resolver(
      environment: const {'PATH': '/usr/bin'},
      exists: (path) =>
          path == '/opt/bomb-flower/longshot' || path == '/usr/bin/Longshot',
    ).resolve();

    expect(resolved, '/opt/bomb-flower/longshot');
  });

  test('windows splits PATH on ; and probes .exe candidates', () {
    final probed = <String>[];
    final resolved = resolver(
      platform: windows,
      environment: const {'PATH': r'C:\Tools;C:\Windows\System32'},
      executablePath: r'C:\Apps\bomb_flower.exe',
      exists: (path) {
        probed.add(path);
        return path == r'C:\Tools\Longshot.exe';
      },
    ).resolve();

    expect(resolved, r'C:\Tools\Longshot.exe');
    // The Windows path context is used even though this host is Linux, and the
    // first entry is joined and probed before the second is considered.
    expect(probed.first, r'C:\Apps\LongshotLauncher-x86_64.AppImage');
    expect(probed, contains(r'C:\Tools\Longshot.exe'));
  });

  test('windows finds a .exe launcher next to the app', () {
    final resolved = resolver(
      platform: windows,
      environment: const <String, String>{},
      executablePath: r'C:\Apps\bomb_flower.exe',
      exists: (path) => path == r'C:\Apps\Longshot.exe',
    ).resolve();

    expect(resolved, r'C:\Apps\Longshot.exe');
  });

  test('nothing configured and nothing found stays the empty string', () {
    final resolved = resolver(
      environment: const <String, String>{},
      exists: (path) => false,
    ).resolve();

    expect(resolved, '');
  });
}
