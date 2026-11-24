/// Resolves save-folder paths for the open-save form and picks its start folder.
///
/// This is the only place the open flow's path rules touch the filesystem, and
/// they do it through [DirectoryLister] so the same rules run against a fake in
/// tests. Nothing here throws: a bad path is [ProfilePathRejected] with a short,
/// user-facing reason, an unreadable folder is [ProfilePathUnreadable], and
/// several candidate roots are [ProfilePathAmbiguous], never a guess.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'directory_lister.dart';
import 'host_platform.dart';

/// The save-root shapes the open form accepts, named in its refusals.
const String profileFolderShape =
    'a progress.sav file path, a slot folder, a profile folder, or a save '
    'root holding profiles';

/// XDG variable that names the data root on Linux.
const String _xdgDataHomeVariable = 'XDG_DATA_HOME';

/// Home-directory variable on Linux and other POSIX hosts.
const String _homeVariable = 'HOME';

/// Windows roaming application-data variable (`%APPDATA%`).
const String _windowsRoamingVariable = 'APPDATA';

/// Windows local application-data variable (`%LOCALAPPDATA%`).
const String _windowsLocalVariable = 'LOCALAPPDATA';

/// Windows user-profile variable (`%USERPROFILE%`).
const String _windowsProfileVariable = 'USERPROFILE';

/// Longshot's folder name on Linux/Fuchsia, below the XDG data root.
const String _longshotFolderName = 'longshot';

/// Longshot's folder name on Windows, below `%APPDATA%`/`%LOCALAPPDATA%`.
const String _windowsLongshotFolderName = 'Longshot';

/// Slot save root folder name, below the Longshot folder.
const String _saveFolderName = 'save';

/// Longshot's backup folder name under the Linux data root.
const String _backupFolderName = 'save-backup';

/// Longshot's backup folder name under `%LOCALAPPDATA%` on Windows.
const String _windowsBackupFolderName = 'oot-save-backups';

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

/// Longshot's save location and its own backup location on one host.
///
/// The two are not interchangeable: Longshot's docs (`Longshot`'s
/// `docs/user/saves.md`, "Where Longshot keeps them") put the backup folder
/// beside — not inside — the save folder, and its contents are its own
/// `<import|export>-<name>-<timestamp>/` folders, not a save root a game can
/// open. [backupBase] must therefore never be offered as an openable root.
final class LongshotSaveLocations {
  /// Creates a pair of locations; either may be unknown (`null`).
  const LongshotSaveLocations({this.saveBase, this.backupBase});

  /// The folder whose child profiles hold `slot_NN/progress.sav`.
  ///
  /// `null` when this platform's location is not established; callers then
  /// degrade to the OS default rather than inventing a path.
  final String? saveBase;

  /// Longshot's own backup folder, or `null` when it is not established.
  ///
  /// Never an openable save root.
  final String? backupBase;
}

/// Resolves Longshot's save and backup folders for [platform].
///
/// [platform] defaults to [currentHostPlatform]; [environment] defaults to the
/// process environment. Paths are built with `package:path`'s Windows or POSIX
/// context chosen from [platform], never `Platform.pathSeparator`, so the rules
/// are testable on a Linux host.
///
/// Rules, in order, from Longshot's own documentation
/// (`~/GitHub/Longshot/docs/user/saves.md` lines 101-110,
/// `docs/user/updates-and-saves.md` lines 56-64 and
/// `docs/dev/reference/saves.md` lines 29-34, 61):
///
/// * Windows save root: `%APPDATA%\Longshot\save` when the installed launcher
///   starts the game (the launcher passes `--user`); otherwise the documented
///   default game folder's `user\save`, i.e. `%USERPROFILE%\Games\Longshot\
///   user\save`. A player who chose another game folder, or who launches with
///   `--user <folder>`, must open that folder explicitly — nothing here can
///   discover it.
/// * Windows backup root: `%LOCALAPPDATA%\Longshot\oot-save-backups`.
/// * Linux and Fuchsia save root: `$XDG_DATA_HOME/longshot/save`, then
///   `$HOME/.local/share/longshot/save`.
/// * Linux and Fuchsia backup root: `$XDG_DATA_HOME/longshot/save-backup`,
///   then `$HOME/.local/share/longshot/save-backup`.
/// * macOS and any other host: nothing is established or invented, so both are
///   `null`.
///
/// A variable that is set to whitespace counts as unset.
LongshotSaveLocations resolveLongshotSaveLocations({
  Map<String, String>? environment,
  HostPlatform? platform,
}) {
  final host = platform ?? currentHostPlatform();
  final env = environment ?? Platform.environment;
  final path = hostPathContext(host);
  final roaming = _environmentValue(env, _windowsRoamingVariable);
  final local = _environmentValue(env, _windowsLocalVariable);
  final profile = _environmentValue(env, _windowsProfileVariable);
  final xdgData = _environmentValue(env, _xdgDataHomeVariable);
  final home = _environmentValue(env, _homeVariable);

  switch (host) {
    case HostPlatform.windows:
      final saveBase = roaming != null
          ? path.join(roaming, _windowsLongshotFolderName, _saveFolderName)
          : profile != null
          ? path.join(profile, 'Games', 'Longshot', 'user', _saveFolderName)
          : null;
      final backupBase = local == null
          ? null
          : path.join(
              local,
              _windowsLongshotFolderName,
              _windowsBackupFolderName,
            );
      return LongshotSaveLocations(saveBase: saveBase, backupBase: backupBase);
    case HostPlatform.linux:
    case HostPlatform.fuchsia:
      final dataRoot =
          xdgData ?? (home == null ? null : path.join(home, '.local', 'share'));
      if (dataRoot == null) {
        return const LongshotSaveLocations();
      }
      return LongshotSaveLocations(
        saveBase: path.join(dataRoot, _longshotFolderName, _saveFolderName),
        backupBase: path.join(dataRoot, _longshotFolderName, _backupFolderName),
      );
    case HostPlatform.macos:
    case HostPlatform.other:
      // No established location; not invented. UNVERIFIED.
      return const LongshotSaveLocations();
  }
}

/// Longshot's save base directory for [platform], or `null` when unknown.
///
/// A thin delegate over [resolveLongshotSaveLocations] kept for callers that
/// only need the openable save root. Per-platform rules are documented there.
String? longshotSaveBase({
  Map<String, String>? environment,
  HostPlatform? platform,
}) {
  return resolveLongshotSaveLocations(
    environment: environment,
    platform: platform,
  ).saveBase;
}

/// [environment]'s [name], trimmed, or `null` when unset or blank.
String? _environmentValue(Map<String, String> environment, String name) {
  final value = environment[name]?.trim();
  return value == null || value.isEmpty ? null : value;
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
  HostPlatform? platform,
}) async {
  final path = hostPathContext(platform ?? currentHostPlatform());
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
    final stamp = await _lastWrite(entry.path, lister, modifiedAt, path);
    if (newest == null || stamp.isAfter(newestStamp!)) {
      newest = entry.path;
      newestStamp = stamp;
    }
  }
  return newest;
}

/// Ordered start folder for the open-save dialog, or `null` when none exists.
///
/// In order: Longshot's save root for [platform] (see
/// [resolveLongshotSaveLocations]) plus a profile discovered under it (the
/// existing profile rule, never a guessed user id); then [lastUsedPath] when
/// it is readable; then the lister's [DirectoryLister.homeDirectory] when
/// non-empty, falling back to `HOME` and then `USERPROFILE` from [environment];
/// then `null`, which leaves the field empty for the OS folder picker rather
/// than inventing a path that does not exist.
///
/// [platform] defaults to [currentHostPlatform]. On macOS and unknown hosts the
/// save root is `null`, so resolution falls through to the home folder; no
/// location is invented there. UNVERIFIED on Windows and macOS.
Future<String?> resolveOpenSaveStartFolder({
  Map<String, String>? environment,
  String? lastUsedPath,
  DirectoryLister lister = const IoDirectoryLister(),
  ModifiedAt modifiedAt = _ioModifiedAt,
  HostPlatform? platform,
}) async {
  final env = environment ?? Platform.environment;
  final host = platform ?? currentHostPlatform();
  final base = longshotSaveBase(environment: env, platform: host);
  if (base != null) {
    final profile = await newestOpenableProfile(
      base,
      lister: lister,
      modifiedAt: modifiedAt,
      platform: host,
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
  final envHome =
      _environmentValue(env, _homeVariable) ??
      _environmentValue(env, _windowsProfileVariable);
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
  p.Context path,
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
    final modified = modifiedAt(_join(path, entry.path, progressSaveName));
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

/// Joins [parent] and [child] with [path]'s separator for the host platform.
String _join(p.Context path, String parent, String child) {
  return path.join(_trimSeparators(parent), child);
}

String _baseName(String path) {
  var normalized = path.replaceAll('\\', '/');
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  final separator = normalized.lastIndexOf('/');
  return separator < 0 ? normalized : normalized.substring(separator + 1);
}
