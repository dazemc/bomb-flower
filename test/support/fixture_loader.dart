import 'dart:io';
import 'dart:typed_data';

/// Names of the scrubbed sample saves shipped in Longshot's `assets/saves/`.
const List<String> sampleSaveNames = <String>[
  'castle-gate',
  'kokiri-start',
  'market-entrance',
];

/// Files that make up one sample slot.
const List<String> sampleSaveFiles = <String>['progress.sav', 'caption.sav'];

/// Environment variable naming Longshot's read-only sample saves.
///
/// There is deliberately no default path: a checkout location belongs to the
/// machine that holds it, not to this repository. Local copies under
/// `.local-fixtures/` are used when the variable is unset.
const String longshotSavesRootEnvVar = 'BOMB_FLOWER_LONGSHOT_SAVES';

/// Message used by tests when the real sample saves are absent.
const String samplesUnavailableMessage =
    'Longshot sample saves are not available; run '
    '`dart run tool/make_fixtures.dart` from the repository root to copy '
    'them into .local-fixtures/ (gitignored).';

/// Directory that receives local copies of the sample saves.
///
/// This directory is gitignored and must never be committed.
Directory get fixturesDirectory =>
    Directory('${_repositoryRoot.path}/.local-fixtures');

/// Longshot's sample-save root from [longshotSavesRootEnvVar], or `null`.
///
/// Null means no source checkout was named; callers then rely on the local
/// `.local-fixtures/` copies and skip when those are absent too.
Directory? get sampleSourceDirectory {
  final override = Platform.environment[longshotSavesRootEnvVar]?.trim();
  return override == null || override.isEmpty ? null : Directory(override);
}

/// Whether at least one complete sample pair is available locally or in
/// Longshot's checkout.
bool get samplesAvailable => sampleSaveNames.any(_isSampleAvailable);

/// Loads `<name>/slot_00/<file>` from `.local-fixtures/`, copying it out of
/// Longshot's sample saves on first use.
///
/// Returns `null` when neither the local copy nor the Longshot source exists,
/// so callers can skip instead of failing. Successful reads are cached in
/// memory and later calls return the same buffer.
Future<Uint8List?> loadSample(String name, String file) async {
  final key = '$name/$file';
  final cached = _cache[key];
  if (cached != null) {
    return cached;
  }

  await _copySamplePair(name);
  final local = _localFile(name, file);
  if (!await local.exists()) {
    return null;
  }

  final bytes = Uint8List.fromList(await local.readAsBytes());
  _cache[key] = bytes;
  return bytes;
}

/// Copies one sample file into `.local-fixtures/`, returning the local file.
///
/// An existing non-empty local copy wins. Returns `null` when the source file
/// is absent.
Future<File?> copySample(String name, String file) async {
  final local = _localFile(name, file);
  if (await _isNonEmptyFile(local)) {
    return local;
  }

  final source = _sourceFile(name, file);
  if (source == null || !await _isNonEmptyFile(source)) {
    return null;
  }

  await local.parent.create(recursive: true);
  await source.copy(local.path);
  return local;
}

/// Copies every available sample pair into `.local-fixtures/`.
///
/// Returns the local files that exist after the copy, in sample/file order.
Future<List<File>> ensureSampleFixtures() async {
  final files = <File>[];
  for (final name in sampleSaveNames) {
    await _copySamplePair(name);
    for (final file in sampleSaveFiles) {
      final local = _localFile(name, file);
      if (await local.exists()) {
        files.add(local);
      }
    }
  }
  return files;
}

/// Absolute path of the repository root, found by walking up from the current
/// directory to the first `pubspec.yaml`.
Directory get _repositoryRoot {
  var directory = Directory.current.absolute;
  while (true) {
    if (File('${directory.path}/pubspec.yaml').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      return Directory.current.absolute;
    }
    directory = parent;
  }
}

final Map<String, Uint8List> _cache = <String, Uint8List>{};
final Map<String, Future<void>> _copyOperations = <String, Future<void>>{};

/// Ensures both slot files for [name] have been considered for copying.
///
/// Concurrent loads of the same sample share one copy operation.
Future<void> _copySamplePair(String name) {
  return _copyOperations.putIfAbsent(name, () async {
    for (final file in sampleSaveFiles) {
      await copySample(name, file);
    }
  });
}

File _localFile(String name, String file) =>
    File('${fixturesDirectory.path}/$name/slot_00/$file');

File? _sourceFile(String name, String file) {
  final root = sampleSourceDirectory;
  return root == null ? null : File('${root.path}/$name/slot_00/$file');
}

bool _isSampleAvailable(String name) => sampleSaveFiles.every(
  (file) =>
      _localFile(name, file).existsSync() ||
      (_sourceFile(name, file)?.existsSync() ?? false),
);

Future<bool> _isNonEmptyFile(File file) async =>
    await file.exists() && await file.length() > 0;
