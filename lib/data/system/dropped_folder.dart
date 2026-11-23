/// Resolves a path dropped onto the window to the save root it names.
///
/// The native runner only forwards the raw path; this file is the one place
/// that inspects it on disk, so `lib/presentation/**` stays `dart:io`-free.
/// Nothing here throws: every failure is a [DroppedFolderInvalid] carrying
/// wording the user can act on, ready for the existing open-failure panel.
library;

import 'dart:io';

/// The result of resolving one dropped path.
sealed class DroppedFolderResult {
  /// Allows subclasses to be const.
  const DroppedFolderResult();
}

/// The dropped path names a folder the save engine can open.
final class DroppedFolderRoot extends DroppedFolderResult {
  /// Creates a root result for [path].
  const DroppedFolderRoot(this.path);

  /// The save root to open, trimmed but otherwise as supplied.
  final String path;
}

/// The dropped path is not a save root, with the reason to show the user.
final class DroppedFolderInvalid extends DroppedFolderResult {
  /// Creates an invalid result for [path] with a short [reason].
  const DroppedFolderInvalid(this.path, this.reason);

  /// The trimmed path that was rejected.
  final String path;

  /// Human-readable explanation naming what was expected.
  final String reason;
}

/// File name every save slot folder holds.
const String progressSaveName = 'progress.sav';

/// What a drop should contain, stated by every refusal.
const String saveRootExpectation =
    'Drop the profile folder that contains slot_00, not a file.';

/// A slot directory name, for example `slot_03`.
final RegExp _slotDirectoryName = RegExp(r'^slot_\d+$');

/// Resolves [rawPath] to a save root. Never throws.
///
/// A save root is the profile folder: either it holds `progress.sav` directly,
/// or it holds at least one `slot_NN/progress.sav`. A dropped `slot_NN` folder
/// is a selection mistake, so it is refused with the parent named. Dropping a
/// folder that contains exactly one save root opens that child, which covers
/// "I dropped the parent". Anything else is refused with [saveRootExpectation].
Future<DroppedFolderResult> resolveDroppedFolder(String? rawPath) async {
  final path = rawPath?.trim() ?? '';
  if (path.isEmpty) {
    return const DroppedFolderInvalid('', saveRootExpectation);
  }

  try {
    final type = await FileSystemEntity.type(path);
    if (type != FileSystemEntityType.directory) {
      return DroppedFolderInvalid(path, saveRootExpectation);
    }

    // A dropped slot folder is refused before the direct-progress check: the
    // engine can never open it, and the honest answer names its parent.
    if (_isSlotDirectory(path) && await _holdsProgressSave(path)) {
      final parent = _parentOf(path);
      final reason = parent == null || parent.isEmpty
          ? 'That is a slot folder. Drop the folder that contains it.'
          : 'That is a slot folder. Drop the folder that contains it '
                '($parent).';
      return DroppedFolderInvalid(path, reason);
    }

    if (await _isSaveRoot(path)) {
      return DroppedFolderRoot(path);
    }

    final child = await _singleSaveRootChild(path);
    if (child != null) {
      return DroppedFolderRoot(child);
    }

    return DroppedFolderInvalid(
      path,
      'That folder is not a save. $saveRootExpectation',
    );
  } on FileSystemException {
    return DroppedFolderInvalid(
      path,
      'That folder could not be read. $saveRootExpectation',
    );
  } catch (_) {
    return DroppedFolderInvalid(
      path,
      'That folder could not be inspected. $saveRootExpectation',
    );
  }
}

/// Whether [path] is a folder the engine can open.
Future<bool> _isSaveRoot(String path) async {
  if (await _holdsProgressSave(path)) {
    return true;
  }
  await for (final entity in Directory(path).list(followLinks: false)) {
    if (entity is! Directory) {
      continue;
    }
    if (!_slotDirectoryName.hasMatch(_baseName(entity.path))) {
      continue;
    }
    if (await _holdsProgressSave(entity.path)) {
      return true;
    }
  }
  return false;
}

/// The only save root directly inside [path], or `null` when none or several.
Future<String?> _singleSaveRootChild(String path) async {
  String? found;
  await for (final entity in Directory(path).list(followLinks: false)) {
    if (entity is! Directory) {
      continue;
    }
    // A nested slot folder is not a root; refusing it elsewhere names the
    // parent, so it is skipped rather than returned as a "save root".
    if (_isSlotDirectory(entity.path)) {
      continue;
    }
    if (!await _isSaveRoot(entity.path)) {
      continue;
    }
    if (found != null) {
      return null;
    }
    found = entity.path;
  }
  return found;
}

Future<bool> _holdsProgressSave(String directory) async {
  final type = await FileSystemEntity.type(_join(directory, progressSaveName));
  return type == FileSystemEntityType.file;
}

bool _isSlotDirectory(String path) =>
    _slotDirectoryName.hasMatch(_baseName(path));

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

String? _parentOf(String path) {
  var normalized = path.replaceAll('\\', '/');
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  final separator = normalized.lastIndexOf('/');
  if (separator <= 0) {
    return null;
  }
  return normalized.substring(0, separator);
}
