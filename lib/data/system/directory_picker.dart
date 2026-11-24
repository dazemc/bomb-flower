/// Host filesystem seams for the save-file workflows.
///
/// `lib/presentation/**` never imports `dart:io`. The dialogs and the
/// save-session cubit talk to these narrow ports instead, and every
/// implementation here converts host failures into a value the UI can report.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;

import 'host_platform.dart';

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

/// One call to a native folder chooser.
///
/// Injected so tests can script a chooser without loading a platform plugin.
typedef DirectoryPathChooser = Future<String?> Function({
  String? initialDirectory,
  String? confirmButtonText,
});

/// A [DirectoryPicker] backed by `package:file_selector`'s folder chooser.
///
/// This is the Flutter-team picker already chosen for this app
/// (`docs/LIMITATIONS.md:182-188`: the human ruled out `file_picker` because
/// `bitsdojo_window_windows` pins `win32 ^5.1.1`, and chose `file_selector
/// ^1.1.0`), and `file_selector_windows` is already registered by the Windows
/// runner, so wiring it here closes a documented gap rather than adding a
/// dependency. The Windows COM/IFileDialog itself is UNVERIFIED on this Linux
/// host.
///
/// [chooser] is the plugin seam; when it is omitted the plugin is loaded only
/// at call time, so constructing this picker under `flutter test` is inert.
/// Never throws: a cancelled or failed dialog is `null`.
final class FileSelectorDirectoryPicker implements DirectoryPicker {
  /// Creates a picker using [chooser], or `package:file_selector` when omitted.
  const FileSelectorDirectoryPicker({this.chooser, this.confirmButtonText});

  /// Injected chooser, or `null` to call `package:file_selector` at pick time.
  ///
  /// Tests pass a scripted chooser, so the plugin is never loaded.
  final DirectoryPathChooser? chooser;

  /// Button label used when [DirectoryPicker.pickDirectory] names no title.
  final String? confirmButtonText;

  @override
  Future<String?> pickDirectory({String? title, String? initialPath}) async {
    final start = initialPath?.trim();
    final confirm = title ?? confirmButtonText;
    try {
      final chosen = await (chooser ?? _pluginChooser)(
        initialDirectory: start == null || start.isEmpty ? null : start,
        confirmButtonText: confirm,
      );
      final trimmed = chosen?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      // A missing plugin or a failing native dialog must not break the flow.
      return null;
    }
  }
}

/// The real `package:file_selector` call, reached only when one is made.
Future<String?> _pluginChooser({
  String? initialDirectory,
  String? confirmButtonText,
}) {
  return file_selector.getDirectoryPath(
    initialDirectory: initialDirectory,
    confirmButtonText: confirmButtonText,
  );
}

/// The picker this app uses by default: native per host, chosen at call time.
///
/// Windows and macOS get [FileSelectorDirectoryPicker] — the registered
/// `file_selector` implementations — because `zenity`/`kdialog`/`qarma` are
/// Linux programs. Linux and Fuchsia keep the existing
/// [SystemDirectoryPicker] chain, and an unknown host also gets the
/// `file_selector` path rather than assuming a Linux desktop.
///
/// The platform is read inside [pickDirectory], never in the constructor, so
/// `const PlatformDirectoryPicker()` is inert until a user actually asks for a
/// folder, and tests can inject the platform and both backends.
final class PlatformDirectoryPicker implements DirectoryPicker {
  /// Creates a platform-aware picker.
  const PlatformDirectoryPicker({
    this.platform,
    this.fileSelector = const FileSelectorDirectoryPicker(),
    this.system = const SystemDirectoryPicker(),
  });

  /// Host platform override; `null` means [currentHostPlatform] at call time.
  final HostPlatform? platform;

  /// Backend for Windows, macOS and unknown hosts.
  final DirectoryPicker fileSelector;

  /// Backend for Linux and Fuchsia.
  final DirectoryPicker system;

  /// The backend [platform] selects, read afresh on every call.
  DirectoryPicker get backend => switch (platform ?? currentHostPlatform()) {
    HostPlatform.linux || HostPlatform.fuchsia => system,
    HostPlatform.windows ||
    HostPlatform.macos ||
    HostPlatform.other => fileSelector,
  };

  @override
  Future<String?> pickDirectory({String? title, String? initialPath}) {
    return backend.pickDirectory(title: title, initialPath: initialPath);
  }
}

/// [environment]'s [name], trimmed, or `null` when unset or blank.
String? _environmentValue(Map<String, String> environment, String name) {
  final value = environment[name]?.trim();
  return value == null || value.isEmpty ? null : value;
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
    this.progressSavePresent = false,
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

  /// Whether `progress.sav` sits directly in [path].
  ///
  /// A save root holds `slot_NN/progress.sav`; a `slot_NN` folder holds
  /// `progress.sav` itself. This flag is what tells those two shapes apart
  /// without reading any save bytes.
  final bool progressSavePresent;

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
      final progress = await FileSystemEntity.type(
        '$path${Platform.pathSeparator}progress.sav',
      );
      return SaveFolderInfo(
        path: path,
        exists: exists,
        isDirectory: isDirectory,
        slotDirectories: List<String>.unmodifiable(slots),
        parentExists: parentExists,
        progressSavePresent: progress == FileSystemEntityType.file,
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
  /// Creates a store. [directory] defaults to [defaultDirectory].
  RecentPathsFileStore({String? directory, this.maxEntries = 10})
    : directory = directory ?? defaultDirectory();

  /// Directory holding `recent.json`.
  final String directory;

  /// Maximum number of paths retained.
  final int maxEntries;

  /// Full path of the JSON file.
  String get filePath => '$directory${Platform.pathSeparator}recent.json';

  /// Resolves the default config directory for [platform].
  ///
  /// [platform] defaults to [currentHostPlatform] and [environment] to the
  /// process environment. Paths are built with `package:path`'s Windows or
  /// POSIX context, so the rules can be exercised on any host.
  ///
  /// * Windows: `%APPDATA%\bomb-flower`.
  /// * Linux and Fuchsia: `$XDG_CONFIG_HOME/bomb-flower`, then
  ///   `$HOME/.config/bomb-flower`.
  /// * Anything else (including macOS): nothing is established, so the last
  ///   resort is `<system temp>/bomb-flower`. That is a deliberate last resort,
  ///   not a policy: recent folders are a convenience and a per-machine temp
  ///   folder is better than refusing to remember anything.
  static String defaultDirectory({
    Map<String, String>? environment,
    HostPlatform? platform,
  }) {
    final host = platform ?? currentHostPlatform();
    final env = environment ?? Platform.environment;
    final path = hostPathContext(host);
    final app = 'bomb-flower';
    final roaming = _environmentValue(env, 'APPDATA');
    final xdgConfig = _environmentValue(env, 'XDG_CONFIG_HOME');
    final home = _environmentValue(env, 'HOME');
    switch (host) {
      case HostPlatform.windows:
        if (roaming != null) {
          return path.join(roaming, app);
        }
      case HostPlatform.linux:
      case HostPlatform.fuchsia:
        if (xdgConfig != null) {
          return path.join(xdgConfig, app);
        }
        if (home != null) {
          return path.join(home, '.config', app);
        }
      case HostPlatform.macos:
      case HostPlatform.other:
        break;
    }
    return path.join(Directory.systemTemp.path, app);
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
