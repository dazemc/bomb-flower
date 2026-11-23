/// Dev-only fixture preparation tool. Not part of the app or CI.
///
/// Usage, from the repository root:
///
/// ```sh
/// dart run tool/make_fixtures.dart
/// ```
///
/// Copies the scrubbed Longshot sample saves into `.local-fixtures/`, which is
/// gitignored, and prints a path/size/fingerprint table. The copies are local
/// test inputs and must never be committed.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../test/support/fixture_loader.dart';

Future<void> main() async {
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
