/// Starts the shipped Longshot launcher as a detached host process.
///
/// `lib/presentation/**` never imports `dart:io`. The title-bar Launch action
/// talks to this narrow port instead, and every host failure comes back as a
/// [LaunchResult] the UI can show rather than an exception.
library;

import 'dart:io';

/// How a launch attempt ended.
enum LaunchStatus {
  /// The launcher process was started and detached.
  started,

  /// Nothing exists at the configured path.
  missing,

  /// Something exists at the path but has no execute bit.
  notExecutable,

  /// The process could not be started even though the path was executable.
  failed,
}

/// The outcome of one launch attempt.
final class LaunchResult {
  /// Creates a result. [detail] carries the host's message for [failed].
  const LaunchResult({
    required this.status,
    required this.path,
    this.detail,
  });

  /// How the attempt ended.
  final LaunchStatus status;

  /// The path the attempt targeted, trimmed.
  final String path;

  /// The host's explanation, when [status] is [LaunchStatus.failed].
  final String? detail;

  /// Whether the launcher process is now running detached.
  bool get started => status == LaunchStatus.started;

  /// The user-facing line for this outcome; it always names [path].
  String get message {
    return switch (status) {
      LaunchStatus.started => 'Longshot launcher started',
      LaunchStatus.missing => 'Longshot launcher not found: $path',
      LaunchStatus.notExecutable =>
        'Longshot launcher is not executable: $path',
      LaunchStatus.failed =>
        'Could not start the Longshot launcher: $path (${detail ?? 'unknown error'})',
    };
  }
}

/// Starts the launcher at a caller-supplied path. Never throws.
abstract interface class LongshotLauncher {
  /// Starts [path] detached and reports what happened.
  Future<LaunchResult> launch(String path);
}

/// Real filesystem implementation of [LongshotLauncher].
///
/// The launcher is detached with no stdin, stdout or stderr wiring: the editor
/// must not own its lifetime, and it must not block on an exit code.
final class IoLongshotLauncher implements LongshotLauncher {
  /// Creates a launcher.
  const IoLongshotLauncher();

  @override
  Future<LaunchResult> launch(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return const LaunchResult(status: LaunchStatus.missing, path: '');
    }

    final FileStat stat;
    try {
      stat = await File(trimmed).stat();
    } on FileSystemException catch (error) {
      // A path the host refuses to stat is indistinguishable from a missing
      // file for the user, so report the friendlier of the two states.
      return LaunchResult(
        status: LaunchStatus.missing,
        path: trimmed,
        detail: error.message,
      );
    }
    if (stat.type == FileSystemEntityType.notFound) {
      return LaunchResult(status: LaunchStatus.missing, path: trimmed);
    }

    // Any of the user, group or other execute bits is enough to try.
    if (stat.mode & 0x49 == 0) {
      return LaunchResult(status: LaunchStatus.notExecutable, path: trimmed);
    }

    try {
      await Process.start(
        trimmed,
        const <String>[],
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (error) {
      return LaunchResult(
        status: LaunchStatus.failed,
        path: trimmed,
        detail: error.message,
      );
    } on FileSystemException catch (error) {
      return LaunchResult(
        status: LaunchStatus.failed,
        path: trimmed,
        detail: error.message,
      );
    }
    return LaunchResult(status: LaunchStatus.started, path: trimmed);
  }
}
