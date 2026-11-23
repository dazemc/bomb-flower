/// Read-only directory listing for the in-app save picker.
///
/// `lib/presentation/**` never imports `dart:io`; the picker dialog consumes
/// this port instead of touching the filesystem itself, so every host failure
/// arrives as a value the UI can render.
library;

import 'dart:io';

/// One child of a listed directory.
final class DirectoryEntry {
  /// Creates an entry.
  const DirectoryEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.isSlotDirectory = false,
    this.containsSlots = false,
  });

  /// Absolute path of the child.
  final String path;

  /// Basename shown in the listing.
  final String name;

  /// Whether the child is a directory.
  final bool isDirectory;

  /// Whether the basename matches `^slot_\d{2}$`.
  final bool isSlotDirectory;

  /// Whether this directory has a `slot_00`..`slot_09` child.
  final bool containsSlots;
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

  /// Names of the immediate `slot_NN` children.
  List<String> get slotNames => <String>[
    for (final entry in entries)
      if (entry.isSlotDirectory) entry.name,
  ];

  /// Whether this directory directly contains at least one save slot.
  bool get isProfile => slotNames.isNotEmpty;
}

/// Lists directories for the save picker. Never throws.
abstract interface class DirectoryLister {
  /// `$HOME`, or `null` when the environment does not name one.
  String? get homeDirectory;

  /// Lists [path], expanding `~` and resolving relative paths.
  ///
  /// Returns a [DirectoryListing] whose [DirectoryListing.error] explains any
  /// unreadable or non-directory path instead of throwing.
  Future<DirectoryListing> list(String path);
}

/// The real filesystem lister.
final class IoDirectoryLister implements DirectoryLister {
  /// Creates a lister.
  const IoDirectoryLister();

  static final RegExp _slotName = RegExp(r'^slot_\d{2}$');

  @override
  String? get homeDirectory {
    final home = Platform.environment['HOME']?.trim();
    return home == null || home.isEmpty ? null : home;
  }

  @override
  Future<DirectoryListing> list(String path) async {
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

      final children = await Directory(
        normalized,
      ).list(followLinks: false).toList();
      final entries = await Future.wait(children.map(_describe));
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
    final containsSlots = isDirectory && await _containsSlot(path);
    return DirectoryEntry(
      path: path,
      name: name,
      isDirectory: isDirectory,
      isSlotDirectory: isSlot,
      containsSlots: containsSlots,
    );
  }

  /// Probes `slot_00`..`slot_09` and stops at the first hit.
  Future<bool> _containsSlot(String directory) async {
    for (var index = 0; index < 10; index++) {
      final slot = 'slot_${index.toString().padLeft(2, '0')}';
      final candidate = '$directory${Platform.pathSeparator}$slot';
      try {
        if (await Directory(candidate).exists()) {
          return true;
        }
      } catch (_) {
        // One unreadable candidate is not evidence of a slot folder.
      }
    }
    return false;
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
