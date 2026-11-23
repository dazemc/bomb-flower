/// Startup open-folder selection from the host environment.
///
/// This is the only place the app reads `dart:io` for startup: presentation
/// receives a [StartupOpen] classification and never inspects the filesystem.
/// Nothing here throws; every failure is [StartupOpenInvalid] with a short
/// reason, so a bad environment variable cannot block startup.
library;

import 'dart:io';

/// Environment variable naming a save folder to open at startup.
const String startupOpenEnvVar = 'BOMB_FLOWER_OPEN';

/// What the host environment asked the app to open at startup.
sealed class StartupOpen {
  /// Allows subclasses to be const.
  const StartupOpen();
}

/// The environment named an existing save folder.
final class StartupOpenRequested extends StartupOpen {
  /// Creates a requested result for [path].
  const StartupOpenRequested(this.path);

  /// The folder to open, exactly as the environment supplied it after trimming.
  final String path;
}

/// The environment named no folder, or only whitespace.
final class StartupOpenAbsent extends StartupOpen {
  /// Creates an absent result.
  const StartupOpenAbsent();
}

/// The environment named a path that is not an existing save folder.
final class StartupOpenInvalid extends StartupOpen {
  /// Creates an invalid result for [path] with a short [reason].
  const StartupOpenInvalid(this.path, this.reason);

  /// The trimmed path that was rejected.
  final String path;

  /// Human-readable explanation, safe for a status line.
  final String reason;
}

/// A slot directory name, for example `slot_03`.
final RegExp _slotDirectoryName = RegExp(r'^slot_\d+$');

/// Reads [startupOpenEnvVar] and classifies it.
///
/// [environment] defaults to [Platform.environment]; tests pass a map so they
/// never mutate the real process environment.
StartupOpen resolveStartupOpen({Map<String, String>? environment}) {
  final resolved = environment ?? Platform.environment;
  return resolveStartupOpenFor(resolved[startupOpenEnvVar]);
}

/// Classifies [rawPath] without reading the environment.
///
/// A blank value is [StartupOpenAbsent]. An existing folder is
/// [StartupOpenRequested] when it holds a `progress.sav` directly or at least
/// one `slot_NN` child holding a `progress.sav`; anything else is
/// [StartupOpenInvalid]. Never throws.
StartupOpen resolveStartupOpenFor(String? rawPath) {
  final path = rawPath?.trim() ?? '';
  if (path.isEmpty) {
    return const StartupOpenAbsent();
  }
  try {
    final directory = Directory(path);
    if (!directory.existsSync()) {
      return StartupOpenInvalid(path, 'The folder does not exist.');
    }
    if (_hasProgressSave(path)) {
      return StartupOpenRequested(path);
    }
    final entries = directory.listSync(followLinks: false);
    for (final entry in entries) {
      if (entry is! Directory) {
        continue;
      }
      if (!_slotDirectoryName.hasMatch(_baseName(entry.path))) {
        continue;
      }
      if (_hasProgressSave(entry.path)) {
        return StartupOpenRequested(path);
      }
    }
    return StartupOpenInvalid(
      path,
      'No progress.sav or slot_NN/progress.sav was found in this folder.',
    );
  } on FileSystemException catch (error) {
    return StartupOpenInvalid(
      path,
      'The folder could not be read: ${error.message}',
    );
  } catch (error) {
    return StartupOpenInvalid(
      path,
      'The folder could not be inspected: $error',
    );
  }
}

bool _hasProgressSave(String root) =>
    File(_join(root, 'progress.sav')).existsSync();

String _join(String parent, String child) {
  if (parent.endsWith('/') || parent.endsWith('\\')) {
    return '$parent$child';
  }
  return '$parent${Platform.pathSeparator}$child';
}

String _baseName(String path) {
  var normalized = path.replaceAll('\\', '/');
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  final separator = normalized.lastIndexOf('/');
  return separator < 0 ? normalized : normalized.substring(separator + 1);
}
