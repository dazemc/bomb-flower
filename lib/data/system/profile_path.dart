/// Resolves save-folder paths for the open-save form and picks its start folder.
///
/// This is the only place the open flow's path rules touch the filesystem, and
/// they do it through [DirectoryLister] so the same rules run against a fake in
/// tests. Nothing here throws: a bad path is [ProfilePathRejected] with a short,
/// user-facing reason, an unreadable folder is [ProfilePathUnreadable], and
/// several candidate roots are [ProfilePathAmbiguous], never a guess.
library;

import 'dart:io';

import 'directory_lister.dart';

/// The save-root shapes the open form accepts, named in its refusals.
const String profileFolderShape =
    'a progress.sav file path, a slot folder, a profile folder, or a save '
    'root holding profiles';

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

/// More than one profile folder sits directly under the typed save root.
final class ProfilePathAmbiguous extends ProfilePathResolution {
  /// Creates an ambiguous result with the [candidates] to choose from.
  const ProfilePathAmbiguous(this.candidates);

  /// Openable profile folders, sorted by path and unmodifiable.
  ///
  /// Never a slot folder: each candidate is a root whose child holds
  /// `progress.sav`.
  final List<String> candidates;
}

/// Deepest directory level below the typed path the scouting scan opens.
const int _scanDepth = 3;

/// Most directories the scouting scan opens before giving up.
const int _scanDirectoryBudget = 64;

/// Resolves [rawPath] into an openable save root through [lister].
///
/// The result is always the *profile folder* — the save root whose immediate
/// child holds `progress.sav` — never a slot folder, because that is what the
/// session opens.
///
/// Four typed shapes are accepted: a `progress.sav` file path, a slot folder
/// that directly holds `progress.sav`, a profile folder, or a bare save root
/// whose child profiles are discovered. A slot is identified by holding
/// `progress.sav`, never by a `slot_NN`-shaped name.
///
/// Discovery beneath a save root is bounded: three directory levels below the
/// typed folder and 64 listed directories, directories only and without
/// following links, so a mistaken `~` cannot walk a home directory. Rules, in
/// order: an empty path is [ProfilePathRejected]; a file path lists its slot
/// folder; a slot folder lists its profile; a profile is itself; a bare root
/// with one profile is that profile, with several is
/// [ProfilePathAmbiguous] (sorted candidates), and with none is rejected by
/// name. An unreadable folder is [ProfilePathUnreadable] with the lister's own
/// message.
Future<ProfilePathResolution> resolveProfilePath(
  String rawPath, {
  DirectoryLister lister = const IoDirectoryLister(),
}) async {
  final typed = rawPath.trim();
  if (typed.isEmpty) {
    return const ProfilePathRejected('Enter the path to $profileFolderShape.');
  }
  if (_baseName(typed) == progressSaveName) {
    final slotListing = await lister.list(Directory(typed).parent.path);
    if (slotListing.error != null) {
      return ProfilePathUnreadable(slotListing.error!);
    }
    if (!_holdsSaveFile(slotListing)) {
      return ProfilePathRejected(
        '${slotListing.path} contains no $progressSaveName.',
      );
    }
    return _resolveSlotParent(slotListing, lister);
  }
  final listing = await lister.list(typed);
  if (listing.error != null) {
    return ProfilePathUnreadable(listing.error!);
  }
  if (_holdsSaveFile(listing)) {
    return _resolveSlotParent(listing, lister);
  }
  if (listing.isProfile) {
    return ProfilePathResolved(listing.path);
  }
  final candidates = await _childProfiles(listing, lister);
  if (candidates.length == 1) {
    return ProfilePathResolved(candidates.single);
  }
  if (candidates.length > 1) {
    candidates.sort();
    return ProfilePathAmbiguous(List<String>.unmodifiable(candidates));
  }
  if (await _holdsSaveBeneath(listing, lister)) {
    return ProfilePathRejected(
      '${listing.path} has no slot folder directly beneath it, but '
      '$progressSaveName exists deeper; open the folder that contains the '
      'slot folder.',
    );
  }
  return ProfilePathRejected(
    '${listing.path} contains no $progressSaveName anywhere beneath it, so '
    'it is not a save folder; expected $profileFolderShape.',
  );
}

/// Whether [listing] directly holds a non-directory `progress.sav`.
bool _holdsSaveFile(DirectoryListing listing) => listing.entries.any(
  (entry) => !entry.isDirectory && entry.name == progressSaveName,
);

/// Resolves the slot folder [slot] to the profile folder that contains it.
Future<ProfilePathResolution> _resolveSlotParent(
  DirectoryListing slot,
  DirectoryLister lister,
) async {
  final parent = slot.parentPath;
  if (parent == null) {
    return ProfilePathRejected(
      '${slot.path} holds $progressSaveName but has no containing folder to '
      'open; expected $profileFolderShape.',
    );
  }
  final parentListing = await lister.list(parent);
  if (parentListing.error != null) {
    return ProfilePathUnreadable(parentListing.error!);
  }
  if (parentListing.isProfile) {
    return ProfilePathResolved(parentListing.path);
  }
  return ProfilePathRejected(
    '${slot.path} holds $progressSaveName, but ${parentListing.path} is not '
    '$profileFolderShape.',
  );
}

/// Profile folders that are immediate child directories of [listing].
Future<List<String>> _childProfiles(
  DirectoryListing listing,
  DirectoryLister lister,
) async {
  final profiles = <String>[];
  for (final entry in listing.entries) {
    if (!entry.isDirectory) {
      continue;
    }
    final child = await lister.list(entry.path);
    if (child.error != null) {
      continue;
    }
    if (child.isProfile) {
      profiles.add(child.path);
    }
  }
  return profiles;
}

/// Whether a directory at most [_scanDepth] levels below [listing] holds a
/// `progress.sav` file, opening at most [_scanDirectoryBudget] directories.
///
/// The typed folder's own children are the first level, so the scan never
/// re-opens a folder [resolveProfilePath] already read, and it stops as soon as
/// the budget is spent rather than walking an arbitrary tree.
Future<bool> _holdsSaveBeneath(
  DirectoryListing listing,
  DirectoryLister lister,
) async {
  var level = <String>[
    for (final entry in listing.entries)
      if (entry.isDirectory) entry.path,
  ];
  var visited = 1;
  for (var depth = 1; depth <= _scanDepth; depth++) {
    final next = <String>[];
    for (final directory in level) {
      if (visited >= _scanDirectoryBudget) {
        return false;
      }
      visited++;
      final child = await lister.list(directory);
      if (child.error != null) {
        continue;
      }
      for (final entry in child.entries) {
        if (entry.isDirectory) {
          next.add(entry.path);
        } else if (entry.name == progressSaveName) {
          return true;
        }
      }
    }
    if (next.isEmpty) {
      return false;
    }
    level = next;
  }
  return false;
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

/// The newest profile folder under [saveBase] that holds a child directory
/// with `progress.sav`.
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
    if (!entry.isDirectory || !entry.hasProgressSave) {
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
