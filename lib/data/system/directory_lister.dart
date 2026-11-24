/// Read-only directory listing for the in-app save picker.
///
/// `lib/presentation/**` never imports `dart:io`; the picker dialog consumes
/// this port instead of touching the filesystem itself, so every host failure
/// arrives as a value the UI can render.
library;

import 'dart:io';

/// File name every save slot folder holds.
const String progressSaveName = 'progress.sav';

/// One child of a listed directory.
final class DirectoryEntry {
  /// Creates an entry.
  const DirectoryEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.isSlotDirectory = false,
    this.containsSlots = false,
    this.hasProgressSave = false,
  });

  /// Absolute path of the child.
  final String path;

  /// Basename shown in the listing.
  final String name;

  /// Whether the child is a directory.
  final bool isDirectory;

  /// Whether the basename matches `^slot_\d{2}$`.
  final bool isSlotDirectory;

  /// Whether a child directory directly holds `progress.sav`.
  final bool containsSlots;

  /// Whether `progress.sav` sits directly inside this directory.
  final bool hasProgressSave;
}

/// The contents of one directory, or the reason they could not be read.
final class DirectoryListing {
  /// Creates a listing.
  const DirectoryListing({
    required this.path,
    required this.entries,
    this.parentPath,
    this.error,
  });

  /// Normalised absolute path that was listed.
  final String path;

  /// Immediate children, directories first then files, case-insensitive.
  final List<DirectoryEntry> entries;

  /// Parent directory, or `null` at the filesystem root.
  final String? parentPath;

  /// Reader-facing failure, or `null` when [entries] is authoritative.
  final String? error;

  /// Names of the immediate child directories that hold `progress.sav`.
  ///
  /// Slot identity is the file, never a `slot_NN` name: a slot folder with an
  /// unrelated name still counts.
  List<String> get slotNames => <String>[
    for (final entry in entries)
      if (entry.hasProgressSave) entry.name,
  ];

  /// Whether this directory directly contains an openable save slot.
  ///
  /// A bare folder named like a slot is not enough: the app's save root check
  /// requires `<slot>/progress.sav`, so Open must not offer a folder the app
  /// will refuse.
  bool get isProfile => slotNames.isNotEmpty;
}

/// Lists directories for the save picker. Never throws.
abstract interface class DirectoryLister {
  /// `$HOME`, falling back to `$USERPROFILE`, or `null` when neither is set.
  String? get homeDirectory;

  /// Lists [path], expanding `~` and resolving relative paths.
  ///
  /// Dot-entries are omitted unless [includeHidden] is true. Returns a
  /// [DirectoryListing] whose [DirectoryListing.error] explains any unreadable
  /// or non-directory path instead of throwing.
  Future<DirectoryListing> list(String path, {bool includeHidden = false});
}

/// The real filesystem lister.
///
/// [environment] is injected only so tests can exercise the home-directory
/// rules without mutating the process environment; it defaults to
/// [Platform.environment]. Filesystem reads always use the real host, so a test
/// that injects a Windows-shaped `USERPROFILE` exercises the lookup rule, not a
/// Windows filesystem.
final class IoDirectoryLister implements DirectoryLister {
  /// Creates a lister reading HOME and USERPROFILE from [environment].
  const IoDirectoryLister({this.environment});

  /// Environment map this lister reads, or `null` for [Platform.environment].
  ///
  /// Injected by tests so the home-directory rule can be exercised without
  /// mutating the process environment.
  final Map<String, String>? environment;

  static final RegExp _slotName = RegExp(r'^slot_\d{2}$');

  /// `HOME`, falling back to `USERPROFILE` when `HOME` is unset.
  ///
  /// The same two variables the path rules use, so a Windows host (no `HOME`)
  /// and a POSIX host (`HOME`) both name a home folder.
  @override
  String? get homeDirectory {
    final env = environment ?? Platform.environment;
    for (final name in const <String>['HOME', 'USERPROFILE']) {
      final value = env[name]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  @override
  Future<DirectoryListing> list(
    String path, {
    bool includeHidden = false,
  }) async {
    final normalized = _normalize(path);
    try {
      final type = await FileSystemEntity.type(normalized);
      if (type == FileSystemEntityType.notFound) {
        return DirectoryListing(
          path: normalized,
          entries: const <DirectoryEntry>[],
          error: 'Cannot read this folder: it does not exist.',
        );
      }
      if (type != FileSystemEntityType.directory) {
        return DirectoryListing(
          path: normalized,
          entries: const <DirectoryEntry>[],
          error: 'Not a folder',
        );
      }

      final children = await Directory(normalized)
          .list(followLinks: false)
          .toList();
      final visible = includeHidden
          ? children
          : children
                .where((entity) => !_basename(entity.path).startsWith('.'))
                .toList(growable: false);
      final entries = await Future.wait(visible.map(_describe));
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.name.compareTo(b.name);
      });
      return DirectoryListing(
        path: normalized,
        entries: List<DirectoryEntry>.unmodifiable(entries),
        parentPath: _parentOf(normalized),
      );
    } on FileSystemException catch (error) {
      return DirectoryListing(
        path: normalized,
        entries: const <DirectoryEntry>[],
        error: 'Cannot read this folder: ${error.message}',
      );
    } catch (error) {
      return DirectoryListing(
        path: normalized,
        entries: const <DirectoryEntry>[],
        error: 'Cannot read this folder: $error',
      );
    }
  }

  Future<DirectoryEntry> _describe(FileSystemEntity entity) async {
    final path = _stripTrailing(entity.path);
    final name = _basename(path);
    var isDirectory = false;
    try {
      isDirectory =
          await FileSystemEntity.type(path) == FileSystemEntityType.directory;
    } catch (_) {
      // An unreadable child is still shown, as a plain file row.
    }
    final isSlot = isDirectory && _slotName.hasMatch(name);
    final hasProgressSave = isDirectory && await _hasProgressSave(path);
    final containsSlots = isDirectory && await _containsSlot(path);
    return DirectoryEntry(
      path: path,
      name: name,
      isDirectory: isDirectory,
      isSlotDirectory: isSlot,
      containsSlots: containsSlots,
      hasProgressSave: hasProgressSave,
    );
  }

  /// Whether any immediate child directory holds `progress.sav`.
  ///
  /// One pass over the directory: slots are identified by the file, never by a
  /// `slot_NN` name. An unreadable child is not evidence either way.
  Future<bool> _containsSlot(String directory) async {
    try {
      await for (final entity in Directory(
        directory,
      ).list(followLinks: false)) {
        final type = await FileSystemEntity.type(entity.path);
        if (type != FileSystemEntityType.directory) {
          continue;
        }
        if (await _hasProgressSave(entity.path)) {
          return true;
        }
      }
    } on FileSystemException {
      // An unreadable directory is not evidence of an openable slot.
    }
    return false;
  }

  Future<bool> _hasProgressSave(String directory) async {
    try {
      return await File('$directory${Platform.pathSeparator}$progressSaveName')
          .exists();
    } catch (_) {
      return false;
    }
  }

  String _normalize(String raw) {
    var path = raw.trim();
    final home = homeDirectory;
    if (path.isEmpty) {
      path = home ?? Directory.current.path;
    }
    if (path == '~' || path.startsWith('~/') || path.startsWith('~\\')) {
      if (home != null) {
        final rest = path.length <= 2 ? '' : path.substring(2);
        path = rest.isEmpty ? home : '$home${Platform.pathSeparator}$rest';
      }
    }
    var absolute = Directory(path).absolute.path;
    while (absolute.length > 1 &&
        (absolute.endsWith('/') || absolute.endsWith('\\'))) {
      absolute = absolute.substring(0, absolute.length - 1);
    }
    return absolute;
  }

  static String? _parentOf(String path) {
    final parent = Directory(path).parent.path;
    return parent == path ? null : parent;
  }

  static String _stripTrailing(String path) {
    var trimmed = path;
    while (trimmed.length > 1 &&
        (trimmed.endsWith('/') || trimmed.endsWith('\\'))) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static String _basename(String path) {
    final index = path.lastIndexOf(RegExp(r'[/\\]'));
    return index < 0 ? path : path.substring(index + 1);
  }
}
