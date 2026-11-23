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

/// Default root of the real save tree (sixteen zeros).
const String defaultRealSavesRoot = '/home/daze/Games/0000000000000000';

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
