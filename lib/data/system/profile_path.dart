/// Resolves save-folder paths for the open-save form and picks its start folder.
///
/// This is the only place the open flow's path rules touch the filesystem, and
/// they do it through [DirectoryLister] so the same rules run against a fake in
/// tests. Nothing here throws: a bad path is [ProfilePathRejected] with a short,
/// user-facing reason, and an unreadable folder is [ProfilePathUnreadable].
library;

import 'dart:io';

import 'directory_lister.dart';

/// The folder shape the open form expects, named in every refusal.
const String profileFolderShape =
    'a profile folder containing slot_NN/progress.sav';

/// XDG variable that names the data root on Linux.
const String _xdgDataHomeVariable = 'XDG_DATA_HOME';

/// Longshot's save directory, relative to the platform data root.
const String _longshotSaveSuffix = 'longshot/save';

/// What one typed path resolved to.
sealed class ProfilePathResolution {
  /// Allows subclasses to be const.
  const ProfilePathResolution();
}

/// The typed path names an openable save root.
final class ProfilePathResolved extends ProfilePathResolution {
  /// Creates a resolved result for [path].
  const ProfilePathResolved(this.path);

  /// The folder to hand to the session, never a `slot_NN` folder itself.
  final String path;
}

/// The folder can be read but is not an openable save root.
final class ProfilePathRejected extends ProfilePathResolution {
  /// Creates a rejection with a user-facing [message].
  const ProfilePathRejected(this.message);

  /// One sentence naming what was expected.
  final String message;
}

/// The folder could not be read at all.
final class ProfilePathUnreadable extends ProfilePathResolution {
  /// Creates an unreadable result with the reader-facing [message].
  const ProfilePathUnreadable(this.message);

  /// The listing failure, for example `Not a folder`.
  final String message;
}

/// A slot directory name, for example `slot_03`.
final RegExp _slotFolderName = RegExp(r'^slot_\d{2}$');

/// Resolves [rawPath] into an openable save root through [lister].
///
/// Rules, in order: a `slot_NN` basename, or a folder holding `progress.sav`
/// directly, means the parent is the root; a folder holding any
/// `slot_NN/progress.sav` child is the root; anything else is
/// [ProfilePathRejected] naming [profileFolderShape], and an unreadable path is
/// [ProfilePathUnreadable] with the lister's own message.
Future<ProfilePathResolution> resolveProfilePath(
  String rawPath, {
  DirectoryLister lister = const IoDirectoryLister(),
}) async {
  final typed = rawPath.trim();
  if (typed.isEmpty) {
    return const ProfilePathRejected('Enter the path to $profileFolderShape.');
  }
  final listing = await lister.list(typed);
  if (listing.error != null) {
    return ProfilePathUnreadable(listing.error!);
  }
  if (listing.isProfile) {
    return ProfilePathResolved(listing.path);
  }
  final holdsProgressSave = listing.entries.any(
    (entry) => !entry.isDirectory && entry.name == progressSaveName,
  );
  final isSlotFolder = _slotFolderName.hasMatch(_baseName(listing.path));
  if (holdsProgressSave || isSlotFolder) {
    final parent = listing.parentPath;
    if (parent != null) {
      final parentListing = await lister.list(parent);
      if (parentListing.error != null) {
        return ProfilePathUnreadable(parentListing.error!);
      }
      if (parentListing.isProfile) {
        return ProfilePathResolved(parentListing.path);
      }
    }
  }
  return ProfilePathRejected(
    '${listing.path} is not $profileFolderShape.',
  );
}

/// Longshot's save base directory, resolved at runtime, or `null` when the
/// platform's location is not established.
///
/// Order: `$XDG_DATA_HOME/longshot/save` when the variable is set; then on
/// Linux `$HOME/.local/share/longshot/save`; otherwise `null`.
///
/// Windows and macOS: Longshot's save location has not been established by
/// evidence in this repository, so no path is invented there; callers degrade
/// to the OS default (or `null`) instead. UNVERIFIED.
String? longshotSaveBase({Map<String, String>? environment}) {
  // Only Linux/Fuchsia have an evidenced save location. Returning `null`
  // elsewhere keeps Windows/macOS on the OS default rather than inventing a
  // POSIX path. UNVERIFIED on Windows and macOS.
  if (!(Platform.isLinux || Platform.isFuchsia)) {
    return null;
  }
  final env = environment ?? Platform.environment;
  final xdg = env[_xdgDataHomeVariable]?.trim();
  if (xdg != null && xdg.isNotEmpty) {
    return '${_trimSeparators(xdg)}/$_longshotSaveSuffix';
  }
  final home = env['HOME']?.trim();
  if (home != null && home.isNotEmpty) {
    return '${_trimSeparators(home)}/.local/share/$_longshotSaveSuffix';
  }
  return null;
}

/// Signature for the modification-time probe used to pick the newest profile.
///
/// Injected so resolver tests never need a real `longshot/save` tree.
typedef ModifiedAt = DateTime Function(String path);

/// Stamp used when a path's modification time cannot be read.
final DateTime _unknownModified = DateTime.fromMillisecondsSinceEpoch(
  0,
  isUtc: true,
);

/// The newest profile folder under [saveBase] that holds `slot_NN/progress.sav`.
///
/// The profile directory names are discovered through [lister] (the existing
/// profile rule), never synthesised. Several profiles have no established
/// "current" one, so the one whose slots were written most recently wins; ties
/// and the no-profile case return `null`.
Future<String?> newestOpenableProfile(
  String saveBase, {
  DirectoryLister lister = const IoDirectoryLister(),
  ModifiedAt modifiedAt = _ioModifiedAt,
}) async {
  final listing = await lister.list(saveBase);
  if (listing.error != null) {
    return null;
  }
  String? newest;
  DateTime? newestStamp;
  for (final entry in listing.entries) {
    if (!entry.isDirectory || !entry.containsSlots) {
      continue;
    }
    final stamp = await _lastWrite(entry.path, lister, modifiedAt);
    if (newest == null || stamp.isAfter(newestStamp!)) {
      newest = entry.path;
      newestStamp = stamp;
    }
  }
  return newest;
}

/// Ordered start folder for the open-save dialog, or `null` when none exists.
///
/// In order: `$XDG_DATA_HOME` (or `~/.local/share`) + `longshot/save` + a
/// profile discovered under it (the existing profile rule, never a guessed
/// user id); then [lastUsedPath] when it is readable; then the lister's
/// [DirectoryLister.homeDirectory] when non-empty, falling back to the process
/// `HOME`; then `null`, which leaves the field empty for the OS folder picker
/// rather than inventing a path that does not exist.
///
/// Windows and macOS degrade through [longshotSaveBase] returning `null`;
/// those platforms are UNVERIFIED.
Future<String?> resolveOpenSaveStartFolder({
  Map<String, String>? environment,
  String? lastUsedPath,
  DirectoryLister lister = const IoDirectoryLister(),
  ModifiedAt modifiedAt = _ioModifiedAt,
}) async {
  final env = environment ?? Platform.environment;
  final base = longshotSaveBase(environment: env);
  if (base != null) {
    final profile = await newestOpenableProfile(
      base,
      lister: lister,
      modifiedAt: modifiedAt,
    );
    if (profile != null) {
      return profile;
    }
  }
  final lastUsed = lastUsedPath?.trim();
  if (lastUsed != null &&
      lastUsed.isNotEmpty &&
      await _readable(lastUsed, lister)) {
    return lastUsed;
  }
  final listerHome = lister.homeDirectory?.trim();
  final envHome = env['HOME']?.trim();
  final home = listerHome == null || listerHome.isEmpty ? envHome : listerHome;
  if (home != null && home.isNotEmpty && await _readable(home, lister)) {
    return home;
  }
  return null;
}

/// Whether [path] lists without an error, through the injected port.
Future<bool> _readable(String path, DirectoryLister lister) async {
  return (await lister.list(path)).error == null;
}

/// Latest modification time among the profile's slot saves, or the profile
/// folder's own mtime when no slot save is readable.
Future<DateTime> _lastWrite(
  String profile,
  DirectoryLister lister,
  ModifiedAt modifiedAt,
) async {
  var stamp = modifiedAt(profile);
  final listing = await lister.list(profile);
  if (listing.error != null) {
    return stamp;
  }
  for (final entry in listing.entries) {
    if (!entry.isDirectory ||
        !entry.isSlotDirectory ||
        !entry.hasProgressSave) {
      continue;
    }
    final modified = modifiedAt(_join(entry.path, progressSaveName));
    if (modified.isAfter(stamp)) {
      stamp = modified;
    }
  }
  return stamp;
}

/// Real modification time, or an epoch stamp when the path cannot be read.
DateTime _ioModifiedAt(String path) {
  try {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      return Directory(path).statSync().modified;
    }
    if (type == FileSystemEntityType.file) {
      return File(path).statSync().modified;
    }
  } on FileSystemException {
    // Unreadable is not evidence of recency.
  }
  return _unknownModified;
}

String _trimSeparators(String path) {
  var trimmed = path;
  while (trimmed.length > 1 &&
      (trimmed.endsWith('/') || trimmed.endsWith('\\'))) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

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
