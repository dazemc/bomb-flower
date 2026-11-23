/// End-to-end check of the template-mode output folder name.
///
/// The game expects a slot directory called `slot_NN`. Cloning a template
/// folder with an arbitrary basename must still write `<out>/slot_00/`, so the
/// template's own folder name cannot leak through. `--slot-name` is the only
/// override, and synthesised mode keeps its implicit `slot_00`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/synthetic_caption.dart';
import '../support/synthetic_progress.dart';

Future<ProcessResult> _runCreateSave(List<String> arguments) {
  return Process.run('dart', <String>[
    'run',
    'tool/create_save.dart',
    ...arguments,
  ], workingDirectory: Directory.current.path);
}

void main() {
  test('template basename does not become the output folder', () async {
    final temp = await Directory.systemTemp.createTemp('create-save-slot-');
    addTearDown(() async {
      if (temp.existsSync()) {
        await temp.delete(recursive: true);
      }
    });

    final template = Directory('${temp.path}/my-weird-template')
      ..createSync(recursive: true);
    File('${template.path}/progress.sav')
        .writeAsBytesSync(buildSyntheticProgress());
    File('${template.path}/caption.sav')
        .writeAsBytesSync(buildSyntheticCaption());

    final out = '${temp.path}/default-out';
    final run = await _runCreateSave(<String>[
      '--template',
      template.path,
      '--out',
      out,
    ]);

    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');

    final slot = Directory('$out/slot_00');
    expect(File('${slot.path}/progress.sav').existsSync(), isTrue);
    expect(File('${slot.path}/caption.sav').existsSync(), isTrue);
    expect(
      Directory('$out/my-weird-template').existsSync(),
      isFalse,
      reason: 'the template folder name must not leak into the output',
    );
    expect(
      run.stdout,
      contains('slot_00/progress.sav'),
      reason: 'the printed path must name the folder actually written',
    );

    final overrideOut = '${temp.path}/override-out';
    final override = await _runCreateSave(<String>[
      '--template',
      template.path,
      '--out',
      overrideOut,
      '--slot-name',
      'slot_07',
    ]);

    expect(
      override.exitCode,
      0,
      reason: '${override.stdout}\n${override.stderr}',
    );
    expect(
      File('$overrideOut/slot_07/progress.sav').existsSync(),
      isTrue,
      reason: '--slot-name slot_07 must name the written folder',
    );
  });
}
