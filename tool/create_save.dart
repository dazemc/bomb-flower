/// Creates a schema-default `slot_00` save pair from the command line.
///
/// Run from the repository root, because `assets/schema/gamedata_110.json` is
/// resolved relative to the current working directory:
///
/// ```sh
/// dart run tool/create_save.dart --out /tmp/new-save
/// ```
///
/// The tool builds the bytes, writes them through [NewSaveWriter], then decodes
/// both files with the production codecs and prints the result. A decode
/// failure is reported after the files exist, with a non-zero exit code, so a
/// caller can inspect them.
library;

import 'dart:io';

import 'package:bomb_flower/data/codec/caption_codec.dart';
import 'package:bomb_flower/data/codec/progress_codec.dart';
import 'package:bomb_flower/data/newsave/new_save_writer.dart';
import 'package:bomb_flower/domain/core/fingerprint.dart';
import 'package:bomb_flower/domain/newsave/new_save_builder.dart';
import 'package:bomb_flower/domain/newsave/new_save_spec.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';

const String _schemaPath = 'assets/schema/gamedata_110.json';

const String _usage =
    '''
Usage: dart run tool/create_save.dart --out <dir> [options]

Creates <dir>/slot_00/progress.sav and <dir>/slot_00/caption.sav from the
GameData schema defaults. Run from the repository root so
$_schemaPath resolves.

Options:
  --out <dir>              Destination root (required).
  --preset <name>          Save preset; the only preset is schemaDefaults.
  --profile-name <name>    Rejected until a verified schema field exists
                           (profile_name_unavailable); never ignored.
  --x <n> --y <n> --z <n>  Start position; all three are required together.
  --no-screenshot          Build a caption without a screenshot.
  --allow-overwrite        Write into a non-empty directory, keeping .bak files.
  -h, --help               Show this help.

Exit codes: 0 success; 1 write or decode failure; 2 usage, schema, build, or
non-empty destination without --allow-overwrite.''';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }

  final _Options options;
  try {
    options = _parse(args);
  } on _UsageError catch (error) {
    stderr.writeln('create_save: ${error.message}');
    stderr.writeln('');
    stderr.writeln(_usage);
    exitCode = 2;
    return;
  }

  final GameDataSchema schema;
  try {
    schema = GameDataSchema.fromJsonString(
      await File(_schemaPath).readAsString(),
    );
  } on FileSystemException catch (error) {
    stderr.writeln(
      'create_save: could not read $_schemaPath (${error.message}); '
      'run this tool from the repository root.',
    );
    exitCode = 2;
    return;
  } on FormatException catch (error) {
    stderr.writeln('create_save: $_schemaPath is invalid: ${error.message}');
    exitCode = 2;
    return;
  }

  final NewSaveBuild build;
  try {
    final presetSpec = NewSaveSpec.preset(
      options.preset,
      profileName: options.profileName,
      startPosition: options.startPosition,
    );
    final spec = options.createCaptionScreenshot
        ? presetSpec
        : NewSaveSpec(
            scene: presetSpec.scene,
            mapPath: presetSpec.mapPath,
            profileName: presetSpec.profileName,
            startPosition: presetSpec.startPosition,
            createCaptionScreenshot: false,
          );
    build = NewSaveBuilder.build(schema: schema, spec: spec);
  } on NewSaveBuildException catch (error) {
    stderr.writeln('create_save: ${error.message}');
    exitCode = 2;
    return;
  }

  final NewSaveWriteResult written;
  try {
    written = await NewSaveWriter().write(
      rootDirectory: options.out,
      build: build,
      allowOverwrite: options.allowOverwrite,
    );
  } on NewSaveWriteException catch (error) {
    stderr.writeln('create_save: ${error.message}');
    exitCode = error.code == NewSaveWriteException.destinationNotEmpty ? 2 : 1;
    return;
  } on FileSystemException catch (error) {
    stderr.writeln('create_save: ${error.message}');
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'progress.sav ${build.progressBytes.length} bytes '
    'fnv1a32=0x${Fnv1a.hex32(Fnv1a.hash32(build.progressBytes))}',
  );
  stdout.writeln(
    'caption.sav ${build.captionBytes.length} bytes '
    'fnv1a32=0x${Fnv1a.hex32(Fnv1a.hash32(build.captionBytes))}',
  );
  stdout.writeln(
    'records=${build.recordCount} fields=${build.fieldCount} '
    'sentinels=${build.sentinelCount} '
    'dataOffset=0x${build.dataOffset.toRadixString(16).padLeft(8, '0')}',
  );
  final sectionIds = build.sectionCounts.keys.toList()..sort();
  for (final typeId in sectionIds) {
    final count = build.sectionCounts[typeId] ?? 0;
    if (count == 0) {
      continue;
    }
    stdout.writeln('section $typeId count=$count');
  }
  stdout.writeln('slot_00 ${File(written.progressPath).parent.path}');
  stdout.writeln('progress ${written.progressPath}');
  stdout.writeln('caption ${written.captionPath}');

  var corrupt = 0;
  var unsupported = 0;
  var failures = 0;

  final progress = ProgressCodec.decode(build.progressBytes);
  if (progress is ProgressDecodeOk) {
    stdout.writeln(
      'progress decode=ok fields=${progress.save.fieldCount} '
      'sections=${progress.save.sections.length}',
    );
  } else {
    failures++;
    if (progress is ProgressDecodeCorrupt) {
      corrupt++;
    } else if (progress is ProgressDecodeUnsupported) {
      unsupported++;
    }
    stderr.writeln(progress.toString());
  }

  final caption = CaptionCodec.decode(build.captionBytes);
  if (caption is CaptionDecodeOk) {
    stdout.writeln(
      'caption decode=ok scene=${caption.save.sceneName} '
      'map=${caption.save.mapPath} jpeg=${caption.save.jpegBytes.length} bytes',
    );
  } else {
    failures++;
    if (caption is CaptionDecodeCorrupt) {
      corrupt++;
    } else if (caption is CaptionDecodeUnsupported) {
      unsupported++;
    }
    stderr.writeln(caption.toString());
  }

  stdout.writeln('corrupt=$corrupt unsupported=$unsupported');
  if (failures > 0) {
    exitCode = 1;
  }
}

/// Parsed command-line options.
final class _Options {
  const _Options({
    required this.out,
    required this.preset,
    required this.profileName,
    required this.startPosition,
    required this.createCaptionScreenshot,
    required this.allowOverwrite,
  });

  final String out;
  final NewSavePreset preset;
  final String? profileName;
  final SavePosition? startPosition;
  final bool createCaptionScreenshot;
  final bool allowOverwrite;
}

/// A command-line mistake that maps to exit code 2.
final class _UsageError implements Exception {
  const _UsageError(this.message);

  final String message;
}

_Options _parse(List<String> args) {
  String? out;
  var presetName = NewSavePreset.schemaDefaults.name;
  String? profileName;
  double? x;
  double? y;
  double? z;
  var createCaptionScreenshot = true;
  var allowOverwrite = false;

  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == '--out') {
      index++;
      out = _requireValue(args, index, argument);
    } else if (argument == '--preset') {
      index++;
      presetName = _requireValue(args, index, argument);
    } else if (argument == '--profile-name') {
      index++;
      profileName = _requireValue(args, index, argument);
    } else if (argument == '--x') {
      index++;
      x = _requireFiniteDouble(args, index, argument);
    } else if (argument == '--y') {
      index++;
      y = _requireFiniteDouble(args, index, argument);
    } else if (argument == '--z') {
      index++;
      z = _requireFiniteDouble(args, index, argument);
    } else if (argument == '--no-screenshot') {
      createCaptionScreenshot = false;
    } else if (argument == '--allow-overwrite') {
      allowOverwrite = true;
    } else if (argument.startsWith('-')) {
      throw _UsageError('unknown option $argument');
    } else {
      throw _UsageError('unexpected argument $argument');
    }
  }

  if (out == null || out.trim().isEmpty) {
    throw const _UsageError('--out <dir> is required');
  }

  final coordinateCount = <double?>[x, y, z].where((value) {
    return value != null;
  }).length;
  if (coordinateCount != 0 && coordinateCount != 3) {
    throw const _UsageError('--x, --y and --z must be supplied together');
  }
  final startPosition = coordinateCount == 3
      ? SavePosition(x: x!, y: y!, z: z!)
      : null;

  final NewSavePreset preset;
  try {
    preset = NewSavePreset.values.byName(presetName);
  } on ArgumentError {
    final names = NewSavePreset.values.map((value) => value.name).join(', ');
    throw _UsageError('unknown preset "$presetName"; expected one of: $names');
  }

  return _Options(
    out: out,
    preset: preset,
    profileName: profileName,
    startPosition: startPosition,
    createCaptionScreenshot: createCaptionScreenshot,
    allowOverwrite: allowOverwrite,
  );
}

String _requireValue(List<String> args, int index, String flag) {
  if (index >= args.length || args[index].startsWith('--')) {
    throw _UsageError('$flag needs a value');
  }
  return args[index];
}

double _requireFiniteDouble(List<String> args, int index, String flag) {
  final raw = _requireValue(args, index, flag);
  final value = double.tryParse(raw);
  if (value == null || !value.isFinite) {
    throw _UsageError('$flag needs a finite number, got "$raw"');
  }
  return value;
}
