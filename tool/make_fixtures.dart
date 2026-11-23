/// Dev-only fixture preparation tool. Not part of the app or CI.
///
/// Usage, from the repository root:
///
/// ```sh
/// dart run tool/make_fixtures.dart
/// dart run tool/make_fixtures.dart --real [--label=<name>]
/// ```
///
/// With no arguments it copies the scrubbed Longshot sample saves into
/// `.local-fixtures/`, which is gitignored, and prints a path/size/fingerprint
/// table. With `--real` it copies the slots of the real, played save
/// (`BOMB_FLOWER_REAL_SAVES`, else the default root) into
/// `.local-fixtures/real/<label>/slot_NN/` and verifies every copy with
/// `diff -r`. The copies are local test inputs and must never be committed.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../test/integration/support/real_save_loader.dart';
import '../test/support/fixture_loader.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--real')) {
    await _copyRealSaves(args);
    return;
  }

  stdout.writeln('Bomb Flower sample fixture preparation (dev tool)');
  final source = sampleSourceDirectory;
  stdout.writeln(
    'Source: ${source.path}${source.existsSync() ? '' : ' (absent)'}',
  );
  stdout.writeln('Local cache: ${fixturesDirectory.path}');

  final files = await ensureSampleFixtures();
  if (files.isEmpty) {
    stderr.writeln('');
    stderr.writeln(
      'Samples absent: no sample saves found at ${source.path} or '
      '${fixturesDirectory.path}.',
    );
    stderr.writeln(
      'Expected <name>/slot_00/{progress,caption}.sav for: '
      '${sampleSaveNames.join(', ')}.',
    );
    exitCode = 1;
    return;
  }

  final rows = <List<String>>[
    <String>['path', 'bytes', 'fnv1a32', 'head16(base64)', 'tail16(base64)'],
  ];
  var payloadBytes = 0;

  for (final file in files) {
    final bytes = Uint8List.fromList(await file.readAsBytes());
    payloadBytes += bytes.length;
    rows.add(<String>[
      _displayPath(file),
      '${bytes.length}',
      _fnv1a32(bytes),
      base64Encode(_head(bytes)),
      base64Encode(_tail(bytes)),
    ]);
  }

  final widths = <int>[
    for (var column = 0; column < rows.first.length; column++)
      rows.fold<int>(
        rows.first[column].length,
        (width, row) => math.max(width, row[column].length),
      ),
  ];
  String formatRow(List<String> row) => <String>[
    for (var column = 0; column < row.length; column++)
      row[column].padRight(widths[column]),
  ].join('  ').trimRight();

  stdout.writeln(
    'Found ${files.length} file(s) across ${sampleSaveNames.length} sample '
    'name(s), $payloadBytes bytes total.',
  );
  stdout.writeln('');
  stdout.writeln(formatRow(rows.first));
  stdout.writeln(widths.map((width) => '-' * width).join('  '));
  for (final row in rows.skip(1)) {
    stdout.writeln(formatRow(row));
  }
  stdout.writeln('');
  stdout.writeln(
    'sha256 is unavailable without adding a dependency; fnv1a32 plus the '
    'first/last 16 bytes identify local copies.',
  );
  stdout.writeln(
    'Copies live under gitignored .local-fixtures/ and are never committed.',
  );
}

/// Copies the real played save's slots into `.local-fixtures/real/<label>/`.
///
/// Every copy is verified with `diff -r`; a mismatch prints the diff and sets
/// the exit code instead of reporting success. Destination paths are always
/// under [fixturesDirectory].
Future<void> _copyRealSaves(List<String> args) async {
  final sourceRoot = realSavesRoot;
  final slots = discoverRealSlots(sourceRoot);
  if (slots.isEmpty) {
    stderr.writeln(
      'No real save found at ${sourceRoot.path}; set $realSavesRootEnvVar or '
      'place a save at the default path ($defaultRealSavesRoot).',
    );
    exitCode = 1;
    return;
  }

  final label = _parseLabel(args) ?? _basename(sourceRoot.path);
  if (!_isSafeLabel(label)) {
    stderr.writeln(
      'Invalid --label "$label": it must be a single path segment.',
    );
    exitCode = 1;
    return;
  }
  final destinationRoot = Directory('${fixturesDirectory.path}/real/$label');

  stdout.writeln('Bomb Flower real save copy (dev tool)');
  stdout.writeln('Source root: ${sourceRoot.path}');
  stdout.writeln('Destination: ${destinationRoot.path}');
  stdout.writeln('');

  final rows = <List<String>>[
    <String>['source slot', 'destination', 'bytes', 'fnv1a32', 'diff'],
  ];
  var failures = 0;

  for (final sourceSlot in slots) {
    final slotName = _basename(sourceSlot.path);
    final destinationSlot = Directory('${destinationRoot.path}/$slotName');
    if (destinationSlot.existsSync()) {
      destinationSlot.deleteSync(recursive: true);
    }
    destinationSlot.createSync(recursive: true);

    File? copiedProgress;
    for (final entry in sourceSlot.listSync(followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.sav')) {
        continue;
      }
      final name = _basename(entry.path);
      final copy = File('${destinationSlot.path}/$name');
      entry.copySync(copy.path);
      if (name == 'progress.sav') {
        copiedProgress = copy;
      }
    }

    final diff = await Process.run('diff', <String>[
      '-r',
      sourceSlot.path,
      destinationSlot.path,
    ]);
    final identical = diff.exitCode == 0;
    if (!identical) {
      failures++;
      stdout.writeln('diff -r ${sourceSlot.path} ${destinationSlot.path}');
      final output = '${diff.stdout}${diff.stderr}'.trimRight();
      if (output.isNotEmpty) {
        stdout.writeln(output);
      }
      stdout.writeln(
        'diff -r FAILED for $slotName (exit ${diff.exitCode})',
      );
      exitCode = 1;
    }

    final bytes = copiedProgress == null
        ? Uint8List(0)
        : Uint8List.fromList(copiedProgress.readAsBytesSync());
    rows.add(<String>[
      sourceSlot.path,
      destinationSlot.path,
      '${bytes.length}',
      _fnv1a32(bytes),
      identical ? 'identical' : 'FAILED',
    ]);
  }

  final widths = <int>[
    for (var column = 0; column < rows.first.length; column++)
      rows.fold<int>(
        rows.first[column].length,
        (width, row) => math.max(width, row[column].length),
      ),
  ];
  String formatRow(List<String> row) => <String>[
    for (var column = 0; column < row.length; column++)
      row[column].padRight(widths[column]),
  ].join('  ').trimRight();

  stdout.writeln(formatRow(rows.first));
  stdout.writeln(widths.map((width) => '-' * width).join('  '));
  for (final row in rows.skip(1)) {
    stdout.writeln(formatRow(row));
  }
  stdout.writeln('');
  if (failures > 0) {
    stdout.writeln('$failures slot(s) failed the diff -r check.');
  }
  stdout.writeln(
    'Copies live under gitignored .local-fixtures/ and are never committed.',
  );
}

/// `--label=<name>` or `--label <name>`, or `null` when not supplied.
String? _parseLabel(List<String> args) {
  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    if (arg == '--label') {
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        return null;
      }
      final value = args[index + 1].trim();
      return value.isEmpty ? null : value;
    }
    if (arg.startsWith('--label=')) {
      final value = arg.substring('--label='.length).trim();
      return value.isEmpty ? null : value;
    }
  }
  return null;
}

/// Whether [label] is a single, non-traversing path segment.
bool _isSafeLabel(String label) =>
    label != '.' &&
    label != '..' &&
    !label.contains('/') &&
    !label.contains('\\');

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

/// FNV-1a 32-bit fingerprint, printed as 8 lower-case hex digits.
String _fnv1a32(Uint8List bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

Uint8List _head(Uint8List bytes) =>
    bytes.sublist(0, math.min(16, bytes.length));

Uint8List _tail(Uint8List bytes) =>
    bytes.sublist(math.max(0, bytes.length - 16));

String _displayPath(File file) {
  final rootPrefix = '${fixturesDirectory.parent.path}/';
  return file.path.startsWith(rootPrefix)
      ? file.path.substring(rootPrefix.length)
      : file.path;
}
