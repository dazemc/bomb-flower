/// Discovery of a real, played Ocarina of Time `progress.sav` save.
///
/// The save itself is read-only input: this helper only lists directories and
/// never copies, writes, or creates anything. The opt-in integration test and
/// the `--real` mode of `tool/make_fixtures.dart` share the same discovery so
/// both see the same slots in the same order.
library;

import 'dart:io';

/// Environment override for the root of the real save tree.
const String realSavesRootEnvVar = 'BOMB_FLOWER_REAL_SAVES';

/// Default root of the Longshot sample tree under `$HOME` (sixteen zeros).
///
/// Derived from `HOME` rather than committed as an absolute developer path;
/// the account directory below it is [realSaveAccountDirectoryName].
String get defaultRealSavesRoot => '$_homeDirectory/Games/0000000000000000';

/// Retail user-data tree under `$HOME`: slots live at
/// `<root>/<hex id>/slot_NN/progress.sav`.
String get retailSavesRoot => '$_homeDirectory/.local/share/longshot/save';

/// The account directory that holds the `slot_00` .. `slot_05` folders.
const String realSaveAccountDirectoryName = '0400486024DEC000';

/// Resolved real-save root, honouring [realSavesRootEnvVar].
///
/// An absent or empty override falls back to [defaultRealSavesRoot].
Directory get realSavesRoot {
  final override = Platform.environment[realSavesRootEnvVar];
  return Directory(
    override == null || override.isEmpty ? defaultRealSavesRoot : override,
  );
}

/// Every `<account>/slot_*` directory under [root], ordered by name.
///
/// Matching is structural, not name-guessed: a directory whose own name starts
/// with `slot_` and whose parent is named [realSaveAccountDirectoryName]. The
/// result is sorted by directory name (`slot_00` .. `slot_05`) and ties are
/// broken by full path. A root that does not exist yields an empty list
/// instead of throwing.
List<Directory> discoverRealSlots([Directory? root]) {
  final searchRoot = root ?? realSavesRoot;
  if (!searchRoot.existsSync()) {
    return const <Directory>[];
  }

  final slots = <Directory>[];
  for (final entry in searchRoot.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entry is! Directory) {
      continue;
    }
    final name = _basename(entry.path);
    if (!name.startsWith('slot_')) {
      continue;
    }
    if (_basename(entry.parent.path) != realSaveAccountDirectoryName) {
      continue;
    }
    slots.add(entry);
  }

  slots.sort((left, right) {
    final byName = _basename(left.path).compareTo(_basename(right.path));
    return byName != 0 ? byName : left.path.compareTo(right.path);
  });
  return slots;
}

/// A skip reason when no real save is available, or `null` when one is.
///
/// The message names the resolved root and the override variable so a skipped
/// run explains exactly what is missing and how to point the test at a save.
String? realSaveSkipReason({Directory? root, List<Directory>? slots}) {
  final resolvedRoot = root ?? realSavesRoot;
  final discovered = slots ?? discoverRealSlots(resolvedRoot);
  if (discovered.isNotEmpty) {
    return null;
  }
  return 'No real save found at ${resolvedRoot.path}; set '
      '$realSavesRootEnvVar or place a save at the default path '
      '($defaultRealSavesRoot).';
}

/// Outcome of [resolveRealSaves].
///
/// Three states, because "no save present" and "the override points at the
/// wrong place" need different handling: the first may skip, the second must
/// fail so a developer never mistakes a green run for coverage.
sealed class RealSaveResolution {
  const RealSaveResolution();
}

/// At least one `slot_NN` directory holding `progress.sav` was found.
final class RealSaveFound extends RealSaveResolution {
  const RealSaveFound(this.slots);

  /// The `slot_NN` directories themselves, sorted by path.
  final List<Directory> slots;
}

/// No override was set and no candidate root holds a slot (a cold clone).
final class RealSaveAbsent extends RealSaveResolution {
  const RealSaveAbsent({required this.reason, required this.candidates});

  /// A `SKIPPED, NOT PASSED:` explanation naming every path that was tried.
  final String reason;

  /// The candidate roots that were searched, in order.
  final List<String> candidates;
}

/// The override was set but resolved to no slot: a misconfiguration.
final class RealSaveMisconfigured extends RealSaveResolution {
  const RealSaveMisconfigured({
    required this.reason,
    required this.overrideValue,
  });

  /// A `MISCONFIGURED:` explanation naming the variable and its value.
  final String reason;

  /// The ineffective `BOMB_FLOWER_REAL_SAVES` value.
  final String overrideValue;
}

/// Resolves the real-save slots in this order, first hit wins:
///
/// 1. `BOMB_FLOWER_REAL_SAVES`, which is authoritative: if it is set and yields
///    no slot the result is [RealSaveMisconfigured], never a skip.
/// 2. [retailSavesRoot], the retail user-data tree.
/// 3. [defaultRealSavesRoot], the Longshot sample tree.
///
/// Discovery accepts both tree shapes: a slot is any directory named
/// `slot_NN` (not `slot_N` guessing, not a parent-name filter) that directly
/// contains `progress.sav`, at most four directory levels below a candidate
/// root. Links are never followed. [candidates] and [overrideValue] exist so a
/// test can exercise the absent and misconfigured branches without depending
/// on what this machine happens to have installed.
RealSaveResolution resolveRealSaves({
  String? overrideValue,
  List<String>? candidates,
}) {
  final environmentValue =
      overrideValue ?? Platform.environment[realSavesRootEnvVar];
  if (environmentValue != null && environmentValue.isNotEmpty) {
    final slots = _discoverSlotsUnder(Directory(environmentValue));
    if (slots.isNotEmpty) {
      return RealSaveFound(slots);
    }
    return RealSaveMisconfigured(
      reason:
          'MISCONFIGURED: $realSavesRootEnvVar=$environmentValue contains no '
          'slot_NN/progress.sav — refusing to skip, because an explicit '
          'override that does not work must not pass silently.',
      overrideValue: environmentValue,
    );
  }

  final tried = candidates ?? <String>[retailSavesRoot, defaultRealSavesRoot];
  for (final candidate in tried) {
    final slots = _discoverSlotsUnder(Directory(candidate));
    if (slots.isNotEmpty) {
      return RealSaveFound(slots);
    }
  }
  return RealSaveAbsent(
    reason: _absentReason(tried),
    candidates: List<String>.unmodifiable(tried),
  );
}

/// The cold-clone skip text. It must never read as coverage.
String _absentReason(List<String> candidates) {
  final tried = candidates.map((path) => '  - $path').join('\n');
  return 'SKIPPED, NOT PASSED: no real save found, so this test did not run. '
      'Tried:\n$tried\n'
      'Copy a real slot_NN/progress.sav into one of those roots, or set '
      '$realSavesRootEnvVar=/path/to/root. A green run with ~N > 0 is not '
      'coverage: this test did not execute.';
}

/// Directory levels below a candidate root to search. Candidate 3 nests the
/// slot three levels down (`<hex id>/<account>/slot_NN`), candidate 2 two, so
/// four leaves headroom without ever walking a home directory.
const int _maxSlotDepth = 4;

final RegExp _slotDirectoryName = RegExp(r'^slot_\d+$');

/// Every slot directory under [root], bounded by [_maxSlotDepth].
List<Directory> _discoverSlotsUnder(Directory root) {
  if (!root.existsSync()) {
    return const <Directory>[];
  }
  final slots = <Directory>[];
  if (_isSlotDirectory(root)) {
    slots.add(root);
  }

  void walk(Directory directory, int depth) {
    if (depth >= _maxSlotDepth) {
      return;
    }
    List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final entry in entries) {
      if (entry is! Directory) {
        continue;
      }
      if (_isSlotDirectory(entry)) {
        slots.add(entry);
      } else {
        walk(entry, depth + 1);
      }
    }
  }

  walk(root, 0);
  slots.sort((left, right) => left.path.compareTo(right.path));
  return slots;
}

/// A directory is a slot only when its own name matches and the save exists.
bool _isSlotDirectory(Directory directory) =>
    _slotDirectoryName.hasMatch(_basename(directory.path)) &&
    File('${directory.path}/progress.sav').existsSync();

/// `$HOME`, or the empty string when it is not exported.
String get _homeDirectory => Platform.environment['HOME'] ?? '';

/// Final path segment of [path], ignoring a trailing separator.
String _basename(String path) {
  var end = path.length;
  while (end > 0 && (path[end - 1] == '/' || path[end - 1] == '\\')) {
    end--;
  }
  final trimmed = path.substring(0, end);
  final separator = trimmed.lastIndexOf(RegExp(r'[/\\]'));
  return separator < 0 ? trimmed : trimmed.substring(separator + 1);
}
