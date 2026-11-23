import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level layering enforcement.
///
/// `dart analyze` cannot express layer boundaries and no custom lint package is
/// added. This test scans every import/export directive and reports the file
/// and line that violates the rule.
void main() {
  final directive = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );

  void checkLayer(String layer, Set<String> forbidden) {
    final directory = Directory('lib/$layer');
    if (!directory.existsSync()) {
      fail('Missing layer directory: ${directory.path}');
    }
    final files =
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final match in directive.allMatches(source)) {
        final uri = match.group(1)!;
        for (final bad in forbidden) {
          if (uri.contains(bad)) {
            final line =
                '\n'.allMatches(source.substring(0, match.start)).length + 1;
            fail(
              '${file.path}:$line: forbidden import "$uri" '
              '(layer $layer must not reference $bad)',
            );
          }
        }
      }
    }
  }

  test('domain is pure Dart and never imports UI, I/O, or state packages', () {
    checkLayer('domain', <String>{
      'package:flutter/',
      'package:flutter_bloc/',
      'package:bloc/',
      'package:material_ui/',
      'package:bitsdojo_window/',
      'package:equatable/',
      'dart:io',
      'dart:ui',
    });
  });

  test('data does not import UI or state-management packages', () {
    checkLayer('data', <String>{
      'package:flutter/',
      'package:flutter_bloc/',
      'package:bloc/',
      'package:material_ui/',
      'package:bitsdojo_window/',
    });
  });

  test('presentation does not import dart:io', () {
    checkLayer('presentation', <String>{'dart:io'});
  });
}
