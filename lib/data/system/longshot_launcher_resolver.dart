/// Resolves the Longshot launcher executable at use time.
///
/// No machine-specific absolute path is shipped as a default: the editor's
/// preference starts empty, and the title-bar Launch action asks this port
/// where a launcher actually is. `lib/presentation/**` never imports `dart:io`,
/// so every filesystem and environment read happens here.
library;

import 'dart:io';

import 'host_platform.dart';

/// Environment variable naming an explicit launcher executable.
///
/// This follows the repository's `BOMB_FLOWER_*` convention (compare
/// `BOMB_FLOWER_OPEN`, `BOMB_FLOWER_LONGSHOT_SAVES`). A value here wins over
/// discovery, even when the named file does not exist: the launcher port then
/// reports the missing path instead of silently starting something else.
const String longshotLauncherEnvVar = 'BOMB_FLOWER_LONGSHOT_LAUNCHER';

/// Whether [path] names an existing file.
///
/// Injected so every resolution branch is testable without a real filesystem.
typedef LauncherFileProbe = bool Function(String path);

/// Resolves the launcher executable to start, or the empty string.
///
/// The empty string means "nothing is configured and nothing was found"; it is
/// never a fabricated path.
abstract interface class LongshotLauncherResolver {
  /// Returns the launcher path to start, or `''` when there is none.
  String resolve();
}

/// Real resolver: environment override, next-to-app discovery, then `PATH`.
///
/// [environment] defaults to the process environment and [platform] to
/// [currentHostPlatform] **at call time**, so a const instance is inert until
/// the Launch action asks it a question. [executablePath] defaults to
/// `Platform.resolvedExecutable`, and [fileProbe] to a real file check.
///
/// Candidates, in order:
///
/// 1. `BOMB_FLOWER_LONGSHOT_LAUNCHER`, returned verbatim (trimmed).
/// 2. Next to the running app: `LongshotLauncher-x86_64.AppImage`,
///    `LongshotLauncher.AppImage`, `Longshot`, `longshot`, plus `.exe`
///    variants of the extensionless names on Windows.
/// 3. A `PATH` lookup for `Longshot`, `longshot`, `LongshotLauncher`, plus
///    `.exe` variants on Windows. `PATH` is split on `;` for Windows and `:`
///    otherwise, never on `Platform.pathSeparator`.
///
/// Paths are joined with `package:path`'s Windows or POSIX context chosen from
/// [platform], so the Windows rules run on a Linux test host.
final class IoLongshotLauncherResolver implements LongshotLauncherResolver {
  /// Creates a resolver.
  const IoLongshotLauncherResolver({
    this.environment,
    this.platform,
    this.executablePath,
    this.fileProbe,
  });

  /// Environment map; `null` reads [Platform.environment] in [resolve].
  final Map<String, String>? environment;

  /// Host platform; `null` reads [currentHostPlatform] in [resolve].
  final HostPlatform? platform;

  /// Running app path; `null` reads [Platform.resolvedExecutable].
  final String? executablePath;

  /// File-existence probe; `null` stats the real filesystem.
  final LauncherFileProbe? fileProbe;

  @override
  String resolve() {
    final env = environment ?? Platform.environment;
    final host = platform ?? currentHostPlatform();
    final path = hostPathContext(host);
    final exists = fileProbe ?? _isFile;

    final override = env[longshotLauncherEnvVar]?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }

    final executable = executablePath ?? Platform.resolvedExecutable;
    final applicationDirectory = path.dirname(executable);
    for (final name in _nextToAppCandidateNames(host)) {
      final candidate = path.join(applicationDirectory, name);
      if (exists(candidate)) {
        return candidate;
      }
    }

    final pathValue = _pathValue(env, host);
    if (pathValue != null) {
      final separator = host == HostPlatform.windows ? ';' : ':';
      for (final entry in pathValue.split(separator)) {
        final directory = entry.trim().replaceAll('"', '');
        if (directory.isEmpty) {
          continue;
        }
        for (final name in _pathCandidateNames(host)) {
          final candidate = path.join(directory, name);
          if (exists(candidate)) {
            return candidate;
          }
        }
      }
    }

    return '';
  }

  static bool _isFile(String path) => FileSystemEntity.isFileSync(path);

  /// `PATH`'s value, accepting Windows' usual `Path` spelling too.
  static String? _pathValue(
    Map<String, String> environment,
    HostPlatform host,
  ) {
    final primary = environment['PATH'];
    if (primary != null && primary.trim().isNotEmpty) {
      return primary;
    }
    if (host == HostPlatform.windows) {
      final alternate = environment['Path'];
      if (alternate != null && alternate.trim().isNotEmpty) {
        return alternate;
      }
    }
    return null;
  }
}

/// Executables probed beside the running application, in preference order.
List<String> _nextToAppCandidateNames(HostPlatform host) {
  const posix = <String>[
    'LongshotLauncher-x86_64.AppImage',
    'LongshotLauncher.AppImage',
    'Longshot',
    'longshot',
  ];
  if (host != HostPlatform.windows) {
    return posix;
  }
  // Native Windows builds carry `.exe`; the AppImage names stay untouched.
  return <String>[...posix, 'Longshot.exe', 'longshot.exe'];
}

/// Executables probed in each `PATH` entry, in preference order.
List<String> _pathCandidateNames(HostPlatform host) {
  const posix = <String>['Longshot', 'longshot', 'LongshotLauncher'];
  if (host != HostPlatform.windows) {
    return posix;
  }
  return <String>[
    ...posix,
    'Longshot.exe',
    'longshot.exe',
    'LongshotLauncher.exe',
  ];
}
