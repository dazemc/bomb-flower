/// Host filesystem seams for the save-file workflows.
///
/// `lib/presentation/**` never imports `dart:io`. The dialogs and the
/// save-session cubit talk to these narrow ports instead, and every
/// implementation here converts host failures into a value the UI can report.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// How a [ProcessRunner] call ended.
enum ProcessOutcomeStatus {
  /// The program started and exited (possibly with a non-zero code).
  completed,

  /// The program is not installed, or could not be started at all.
  unavailable,

  /// The program did not exit before the timeout and was killed.
  timedOut,
}

/// The result of one host-process attempt.
final class ProcessOutcome {
  /// A program that ran to completion.
  const ProcessOutcome.completed(this.exitCode, this.stdout, {this.stderr = ''})
    : status = ProcessOutcomeStatus.completed;

  /// A program that is not installed or could not be started.
  const ProcessOutcome.unavailable()
    : status = ProcessOutcomeStatus.unavailable,
      exitCode = -1,
      stdout = '',
      stderr = '';

  /// A program that was killed after the timeout.
  const ProcessOutcome.timedOut()
    : status = ProcessOutcomeStatus.timedOut,
      exitCode = -1,
      stdout = '',
      stderr = '';

  /// How the attempt ended.
  final ProcessOutcomeStatus status;

  /// Exit code; `-1` unless [status] is [ProcessOutcomeStatus.completed].
  final int exitCode;

  /// Captured standard output.
  final String stdout;

  /// Captured standard error.
  final String stderr;

  /// Whether the program ran and exited successfully.
  bool get succeeded =>
      status == ProcessOutcomeStatus.completed && exitCode == 0;
}

/// Runs one host process. Tests inject a scripted implementation.
abstract interface class ProcessRunner {
  /// Runs [executable] with [arguments] for at most [timeout].
  ///
  /// Must never throw for a missing executable or a timeout; those cases are
  /// reported as [ProcessOutcome.unavailable] and [ProcessOutcome.timedOut].
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  });
}

/// The real host process runner.
final class IoProcessRunner implements ProcessRunner {
  /// Creates a runner.
  const IoProcessRunner();

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    final Process process;
    try {
      process = await Process.start(executable, arguments);
    } catch (_) {
      return const ProcessOutcome.unavailable();
    }

    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      // A dialog is probably open. Kill it and let the caller stop rather than
      // stacking a second picker window on top.
      process.kill();
      return const ProcessOutcome.timedOut();
    } catch (_) {
      process.kill();
      return const ProcessOutcome.unavailable();
    }

    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    return ProcessOutcome.completed(exitCode, stdout, stderr: stderr);
  }
}

/// Opens the host's native folder chooser.
abstract interface class DirectoryPicker {
  /// Returns the chosen absolute path, or `null` when nothing was chosen or no
  /// native picker is installed. Never throws.
  Future<String?> pickDirectory({String? title, String? initialPath});
}

/// A [DirectoryPicker] backed by zenity, kdialog, then qarma.
///
/// The first *installed* backend is used. A completed non-zero exit means the
/// user cancelled, so no further backend is tried. A timeout also stops the
/// chain because another dialog may already be on screen.
final class SystemDirectoryPicker implements DirectoryPicker {
  /// Creates a picker.
  const SystemDirectoryPicker({
    this.runner = const IoProcessRunner(),
    this.timeout = const Duration(seconds: 3),
  });

  /// Host process seam.
  final ProcessRunner runner;

  /// Maximum time one backend may run.
  final Duration timeout;

  @override
  Future<String?> pickDirectory({String? title, String? initialPath}) async {
    final start = initialPath?.trim();
    final attempts = <(String, List<String>)>[
      (
        'zenity',
        <String>[
          '--file-selection',
          '--directory',
          if (title != null) '--title=$title',
          if (start != null && start.isNotEmpty) '--filename=$start/',
        ],
      ),
      (
        'kdialog',
        <String>[
          '--getexistingdirectory',
          if (start != null && start.isNotEmpty) start,
          if (title != null) '--title',
          ?title,
        ],
      ),
      (
        'qarma',
        <String>[
          '--file-selection',
          '--directory',
          if (title != null) '--title=$title',
          if (start != null && start.isNotEmpty) '--filename=$start/',
        ],
      ),
    ];

    try {
      for (final (executable, arguments) in attempts) {
        final outcome = await runner.run(
          executable,
          arguments,
          timeout: timeout,
        );
        switch (outcome.status) {
          case ProcessOutcomeStatus.unavailable:
            continue;
          case ProcessOutcomeStatus.timedOut:
            return null;
          case ProcessOutcomeStatus.completed:
            if (!outcome.succeeded) {
              return null;
            }
            return _firstLine(outcome.stdout);
        }
      }
    } catch (_) {
      // The port contract is that the UI never sees a process exception.
    }
    return null;
  }

  static String? _firstLine(String value) {
    for (final line in const LineSplitter().convert(value)) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }
}

/// What a candidate save folder looks like, without reading slot bytes.
final class SaveFolderInfo {
  /// Creates a folder description.
  const SaveFolderInfo({
    required this.path,
    required this.exists,
    required this.isDirectory,
    this.slotDirectories = const <String>[],
    this.parentExists = false,
  });

  /// The inspected path as supplied.
  final String path;

  /// Whether anything exists at [path].
  final bool exists;

  /// Whether [path] exists and is a directory.
  final bool isDirectory;

  /// Immediate child directory names that start with `slot_`, sorted.
  final List<String> slotDirectories;

  /// Whether the parent directory currently exists.
  final bool parentExists;

  /// Whether at least one `slot_*` directory is present.
  bool get containsSaveSlots => slotDirectories.isNotEmpty;

  /// Whether this looks like a folder the save engine can open.
  bool get isSaveRoot => exists && isDirectory && containsSaveSlots;

  /// Whether a new save root could be created here.
  ///
  /// The atomic writer creates missing parents recursively, so the only
  /// immediate blocker is an existing non-directory. Permissions are enforced
  /// by the export itself and surfaced as a typed failure there.
  bool get isCreatable => !exists || isDirectory;
}

/// Inspects a candidate save folder.
abstract interface class SaveFolderProbe {
  /// Returns a description of [path]; never throws.
  Future<SaveFolderInfo> inspect(String path);
}

/// Real filesystem implementation of [SaveFolderProbe].
final class IoSaveFolderProbe implements SaveFolderProbe {
  /// Creates a probe.
  const IoSaveFolderProbe();

  @override
  Future<SaveFolderInfo> inspect(String rawPath) async {
    final path = rawPath.trim();
    if (path.isEmpty) {
      return const SaveFolderInfo(path: '', exists: false, isDirectory: false);
    }
    try {
      final type = await FileSystemEntity.type(path);
      final exists = type != FileSystemEntityType.notFound;
      final isDirectory = type == FileSystemEntityType.directory;
      final slots = <String>[];
      if (isDirectory) {
        await for (final entity in Directory(path).list(followLinks: false)) {
          final name = _basename(entity.path);
          if (entity is Directory && name.startsWith('slot_')) {
            slots.add(name);
          }
        }
        slots.sort();
      }
      final parent = Directory(path).parent.path;
      final parentExists = await Directory(parent).exists();
      return SaveFolderInfo(
        path: path,
        exists: exists,
        isDirectory: isDirectory,
        slotDirectories: List<String>.unmodifiable(slots),
        parentExists: parentExists,
      );
    } catch (_) {
      return SaveFolderInfo(path: path, exists: false, isDirectory: false);
    }
  }

  static String _basename(String path) {
    final separator = Platform.pathSeparator;
    final index = path.lastIndexOf(separator);
    return index < 0 ? path : path.substring(index + separator.length);
  }
}

/// Persists the recently opened save folders.
abstract interface class RecentPathsStore {
  /// Most recent first, de-duplicated, at most the store's limit.
  Future<List<String>> read();

  /// Records [path] as most recent.
  Future<void> add(String path);

  /// Removes every recorded path.
  Future<void> clear();
}

/// A JSON file of recent folders under the user's config directory.
final class RecentPathsFileStore implements RecentPathsStore {
  /// Creates a store. [directory] defaults to
  /// `$XDG_CONFIG_HOME/bomb-flower` (falling back to `$HOME/.config`).
  RecentPathsFileStore({String? directory, this.maxEntries = 10})
    : directory = directory ?? defaultDirectory();

  /// Directory holding `recent.json`.
  final String directory;

  /// Maximum number of paths retained.
  final int maxEntries;

  /// Full path of the JSON file.
  String get filePath => '$directory${Platform.pathSeparator}recent.json';

  /// Resolves the default config directory.
  static String defaultDirectory() {
    final environment = Platform.environment;
    final xdg = environment['XDG_CONFIG_HOME']?.trim();
    final base = xdg != null && xdg.isNotEmpty
        ? xdg
        : '${environment['HOME'] ?? Directory.systemTemp.path}'
              '${Platform.pathSeparator}.config';
    return '$base${Platform.pathSeparator}bomb-flower';
  }

  @override
  Future<List<String>> read() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return const <String>[];
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List<Object?>) {
        return const <String>[];
      }
      final seen = <String>{};
      final paths = <String>[];
      for (final entry in decoded) {
        if (entry is! String) {
          continue;
        }
        final trimmed = entry.trim();
        if (trimmed.isEmpty || !seen.add(trimmed)) {
          continue;
        }
        paths.add(trimmed);
        if (paths.length >= maxEntries) {
          break;
        }
      }
      return List<String>.unmodifiable(paths);
    } catch (_) {
      // A corrupt or unreadable convenience file must never block opening a
      // save; an empty list is the honest fallback.
      return const <String>[];
    }
  }

  @override
  Future<void> add(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return;
    }
    try {
      final existing = await read();
      final next = <String>[
        trimmed,
        for (final entry in existing)
          if (entry != trimmed) entry,
      ].take(maxEntries).toList(growable: false);
      await _write(next);
    } catch (_) {
      // Recent folders are a convenience; a failed write is not worth an error
      // state over the folder the user is opening.
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Clearing is best effort.
    }
  }

  Future<void> _write(List<String> paths) async {
    final folder = Directory(directory);
    await folder.create(recursive: true);
    final target = File(filePath);
    final temp = File('$filePath.tmp');
    await temp.writeAsString(jsonEncode(paths), flush: true);
    await temp.rename(target.path);
  }
}
