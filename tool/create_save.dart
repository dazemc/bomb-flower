/// Creates a save from the command line.
///
/// Two modes:
///
/// - **Template mode** (`--template <slotDir>`, recommended) clones a save slot
///   the game already accepts and rewrites only the value word or name slot of
///   an explicitly requested override. The file length is never changed. The
///   output folder is always `slot_00` unless `--slot-name` overrides it; the
///   template folder's own name never reaches the output.
/// - **Synthesised mode** (`--out <dir>`, no `--template`) builds a
///   schema-default save. It is experimental, not game-verified, and not the
///   recommended path.
///
/// Run from the repository root for synthesised mode, because
/// `assets/schema/gamedata_110.json` is resolved relative to the current working
/// directory. Template mode does not read the schema.
///
/// ```sh
/// dart run tool/create_save.dart --template /path/to/slot_00 --out /tmp/clone
/// dart run tool/create_save.dart --template /path/to/slot_00 --out /tmp/clone \
///     --slot-name slot_07
/// dart run tool/create_save.dart --out /tmp/new-save
/// ```
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/codec/caption_codec.dart';
import 'package:bomb_flower/data/codec/progress_codec.dart';
import 'package:bomb_flower/data/io/atomic_file_writer.dart';
import 'package:bomb_flower/data/newsave/new_save_writer.dart';
import 'package:bomb_flower/domain/core/fingerprint.dart';
import 'package:bomb_flower/domain/newsave/new_save_builder.dart';
import 'package:bomb_flower/domain/newsave/new_save_spec.dart';
import 'package:bomb_flower/domain/newsave/template_clone.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';

const String _schemaPath = 'assets/schema/gamedata_110.json';

const String _defaultSlotName = 'slot_00';

final RegExp _slotNamePattern = RegExp(r'^slot_\d{2}$');

const String _experimentalWarning =
    'create_save: WARNING: synthesised-defaults mode is experimental, not '
    'game-verified, and has crashed the game in testing (SIGSEGV on load with '
    'a real caption; not listed with our caption). Template mode is '
    'recommended: pass --template <slotDir> to clone a save the game accepts.';

const String _usage =
    '''
Usage:
  dart run tool/create_save.dart --template <slotDir> --out <dir> [options]
  dart run tool/create_save.dart --out <dir> [options]   (experimental)

Template mode (recommended) clones a save slot the game already accepts and
patches only the fields you name. Each override rewrites one value word or name
slot in place, so the file length never changes. It does not read the schema.
It writes <dir>/slot_00/ by default; the template folder's own name is never
used, and --slot-name overrides the folder name.

Synthesised mode builds <dir>/slot_00/progress.sav and caption.sav from the
GameData schema defaults. It is experimental, is not game-verified, and has
crashed the game in testing. Run it from the repository root so
$_schemaPath resolves.

Options:
  --template <slotDir>     Clone this slot (the directory holding progress.sav
                           and caption.sav). Recommended.
  --out <dir>              Destination root (required in both modes). Template
                           mode writes <dir>/slot_00/ (or <dir>/<slot-name>/)
                           and refuses a non-empty <dir>.
  --slot-name <name>       Template mode only. Name the output folder; must
                           match slot_NN (two digits, e.g. slot_00). Defaults
                           to slot_00.
  --scene <name>           Template mode: override the caption scene name; at
                           most 63 printable ASCII characters.
  --map <path>             Template mode: override the caption map path.
  --life <n>               Template mode: override PlayerStatus.Life; must
                           satisfy 0 < n <= MaxLife.
  --preset <name>          Synthesised mode only. The only value is
                           schemaDefaults.
  --profile-name <name>    Synthesised mode only; rejected with
                           profile_name_unavailable.
  --x <n> --y <n> --z <n>  Synthesised mode only; all three required together.
  --no-screenshot          Synthesised mode only; write FF D8 FF D9.
  --allow-overwrite        Synthesised mode only; keep .bak files. Template
                           mode always refuses a non-empty destination.
  -h, --help               Show this help.

Template mode cannot be combined with --preset, --profile-name, --x/--y/--z,
--no-screenshot or --allow-overwrite. --max-life, --rotation and
--include-profile-files are not supported at all: cloneSaveTemplate accepts
only --scene, --map and --life.

Exit codes: 0 success; 1 write, verification or decode failure; 2 usage,
template, override, schema, build, or non-empty-destination failure.''';

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

  if (options.template != null) {
    await _runTemplate(options);
    return;
  }

  await _runSynthesised(options);
}

Future<void> _runTemplate(_Options options) async {
  final slotDirectory = options.template!;
  final progressPath = _join(slotDirectory, 'progress.sav');
  final captionPath = _join(slotDirectory, 'caption.sav');

  final Uint8List progress;
  final Uint8List caption;
  try {
    progress = File(progressPath).readAsBytesSync();
    caption = File(captionPath).readAsBytesSync();
  } on FileSystemException catch (error) {
    stderr.writeln(
      'create_save: template slot $slotDirectory must contain a readable '
      'progress.sav and caption.sav (${error.message})',
    );
    exitCode = 2;
    return;
  }

  final outType = FileSystemEntity.typeSync(options.out, followLinks: false);
  if (outType == FileSystemEntityType.file ||
      outType == FileSystemEntityType.link) {
    stderr.writeln(
      'create_save: ${options.out} exists and is not a directory; template '
      'mode needs a new or empty destination directory',
    );
    exitCode = 2;
    return;
  }
  if (outType == FileSystemEntityType.directory) {
    final existing = Directory(options.out).listSync();
    if (existing.isNotEmpty) {
      stderr.writeln(
        'create_save: ${options.out} is not empty; template mode never '
        'overwrites, so choose a new destination directory',
      );
      exitCode = 2;
      return;
    }
  }

  final TemplateCloneResult clone;
  try {
    clone = cloneSaveTemplate(
      progress: progress,
      caption: caption,
      sceneName: options.scene,
      mapPath: options.mapPath,
      life: options.life,
    );
  } on ArgumentError catch (error) {
    final parameter = error.name;
    stderr.writeln(
      'create_save: ${error.message}'
      '${parameter == null ? '' : ' (parameter: $parameter)'}',
    );
    exitCode = 2;
    return;
  }

  final slotName = options.slotName;
  final targetDirectory = _join(options.out, slotName);
  final targetProgress = _join(targetDirectory, 'progress.sav');
  final targetCaption = _join(targetDirectory, 'caption.sav');

  try {
    await AtomicFileWriter(fsyncDirectory: false).writeAll(<String, List<int>>{
      targetProgress: clone.progressBytes,
      targetCaption: clone.captionBytes,
    }, keepPreviousVersion: false);
  } on AtomicWriteException catch (error) {
    stderr.writeln('create_save: ${error.message}');
    exitCode = 1;
    return;
  } on FileSystemException catch (error) {
    stderr.writeln('create_save: ${error.message}');
    exitCode = 1;
    return;
  }

  final Uint8List writtenProgress;
  final Uint8List writtenCaption;
  try {
    writtenProgress = File(targetProgress).readAsBytesSync();
    writtenCaption = File(targetCaption).readAsBytesSync();
  } on FileSystemException catch (error) {
    stderr.writeln(
      'create_save: could not read back a written file: ${error.message}',
    );
    exitCode = 1;
    return;
  }

  stdout.writeln(
    '$slotName/progress.sav ${writtenProgress.length} bytes '
    'fnv1a32=0x${Fnv1a.hex32(Fnv1a.hash32(writtenProgress))} '
    'identical-to-template='
    '${_bytesEqual(writtenProgress, progress) ? 'yes' : 'no'}',
  );
  stdout.writeln(
    '$slotName/caption.sav ${writtenCaption.length} bytes '
    'fnv1a32=0x${Fnv1a.hex32(Fnv1a.hash32(writtenCaption))} '
    'identical-to-template='
    '${_bytesEqual(writtenCaption, caption) ? 'yes' : 'no'}',
  );

  for (final (start, end) in clone.changedSpans) {
    stdout.writeln('changed span $start..$end');
  }

  var corrupt = 0;
  var unsupported = 0;
  var failures = 0;

  final progressDecoded = ProgressCodec.decode(writtenProgress);
  if (progressDecoded is ProgressDecodeOk) {
    stdout.writeln(
      'progress decode=ok fields=${progressDecoded.save.fieldCount} '
      'sections=${progressDecoded.save.sections.length} '
      'length=${writtenProgress.length}',
    );
  } else {
    failures++;
    if (progressDecoded is ProgressDecodeCorrupt) {
      corrupt++;
    } else if (progressDecoded is ProgressDecodeUnsupported) {
      unsupported++;
    }
    stderr.writeln(progressDecoded.toString());
  }

  final captionDecoded = CaptionCodec.decode(writtenCaption);
  if (captionDecoded is CaptionDecodeOk) {
    stdout.writeln(
      'caption decode=ok scene=${captionDecoded.save.sceneName} '
      'map=${captionDecoded.save.mapPath} '
      'jpeg=${captionDecoded.save.jpegBytes.length} bytes',
    );
  } else {
    failures++;
    if (captionDecoded is CaptionDecodeCorrupt) {
      corrupt++;
    } else if (captionDecoded is CaptionDecodeUnsupported) {
      unsupported++;
    }
    stderr.writeln(captionDecoded.toString());
  }

  stdout.writeln('corrupt=$corrupt unsupported=$unsupported');
  if (failures > 0) {
    exitCode = 1;
  }
}

Future<void> _runSynthesised(_Options options) async {
  stderr.writeln(_experimentalWarning);

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
    required this.template,
    required this.preset,
    required this.profileName,
    required this.startPosition,
    required this.createCaptionScreenshot,
    required this.allowOverwrite,
    required this.scene,
    required this.mapPath,
    required this.life,
    required this.slotName,
  });

  final String out;
  final String? template;
  final NewSavePreset preset;
  final String? profileName;
  final SavePosition? startPosition;
  final bool createCaptionScreenshot;
  final bool allowOverwrite;
  final String? scene;
  final String? mapPath;
  final int? life;
  final String slotName;
}

/// A command-line mistake that maps to exit code 2.
final class _UsageError implements Exception {
  const _UsageError(this.message);

  final String message;
}

_Options _parse(List<String> args) {
  String? out;
  String? template;
  var presetName = NewSavePreset.schemaDefaults.name;
  var presetProvided = false;
  String? profileName;
  double? x;
  double? y;
  double? z;
  var createCaptionScreenshot = true;
  var allowOverwrite = false;
  String? scene;
  String? mapPath;
  int? life;
  String? slotName;

  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == '--out') {
      index++;
      out = _requireValue(args, index, argument);
    } else if (argument == '--template') {
      index++;
      template = _requireValue(args, index, argument);
    } else if (argument == '--preset') {
      index++;
      presetName = _requireValue(args, index, argument);
      presetProvided = true;
    } else if (argument == '--profile-name') {
      index++;
      profileName = _requireValue(args, index, argument);
    } else if (argument == '--scene') {
      index++;
      scene = _requireValue(args, index, argument);
    } else if (argument == '--map') {
      index++;
      mapPath = _requireValue(args, index, argument);
    } else if (argument == '--life') {
      index++;
      life = _requireInt(args, index, argument);
    } else if (argument == '--slot-name') {
      index++;
      slotName = _requireValue(args, index, argument);
    } else if (argument == '--max-life' ||
        argument == '--rotation' ||
        argument == '--include-profile-files') {
      throw _UsageError(
        '$argument is not supported: cloneSaveTemplate accepts only the scene, '
        'map and life overrides, and synthesised mode has no equivalent',
      );
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

  if (template != null) {
    if (presetProvided) {
      throw const _UsageError(
        '--template cannot be combined with --preset; template mode does not '
        'use a synthesised preset',
      );
    }
    if (profileName != null) {
      throw const _UsageError(
        '--template cannot be combined with --profile-name; no verified field '
        'carries a profile name',
      );
    }
    if (startPosition != null) {
      throw const _UsageError(
        '--x, --y and --z are synthesised-mode only; template mode can '
        'override only --scene, --map and --life',
      );
    }
    if (!createCaptionScreenshot) {
      throw const _UsageError(
        '--template cannot be combined with --no-screenshot; a template keeps '
        'its own caption JPEG and an override never touches it',
      );
    }
    if (allowOverwrite) {
      throw const _UsageError(
        '--template cannot be combined with --allow-overwrite; template mode '
        'always refuses a non-empty destination',
      );
    }
    if (slotName != null && !_slotNamePattern.hasMatch(slotName)) {
      throw _UsageError(
        '--slot-name must match slot_NN with exactly two digits (for example '
        'slot_00); got "$slotName"',
      );
    }
  } else {
    if (slotName != null) {
      throw const _UsageError(
        '--slot-name requires --template; synthesised mode already writes '
        'slot_00',
      );
    }
    if (scene != null || mapPath != null || life != null) {
      throw const _UsageError(
        '--scene, --map and --life require --template; synthesised mode has no '
        'template to override',
      );
    }
  }

  final NewSavePreset preset;
  try {
    preset = NewSavePreset.values.byName(presetName);
  } on ArgumentError {
    final names = NewSavePreset.values.map((value) => value.name).join(', ');
    throw _UsageError('unknown preset "$presetName"; expected one of: $names');
  }

  return _Options(
    out: out,
    template: template,
    preset: preset,
    profileName: profileName,
    startPosition: startPosition,
    createCaptionScreenshot: createCaptionScreenshot,
    allowOverwrite: allowOverwrite,
    scene: scene,
    mapPath: mapPath,
    life: life,
    slotName: slotName ?? _defaultSlotName,
  );
}

String _requireValue(List<String> args, int index, String flag) {
  if (index >= args.length || args[index].startsWith('--')) {
    throw _UsageError('$flag needs a value');
  }
  return args[index];
}

int _requireInt(List<String> args, int index, String flag) {
  final raw = _requireValue(args, index, flag);
  final value = int.tryParse(raw);
  if (value == null) {
    throw _UsageError('$flag needs an integer, got "$raw"');
  }
  return value;
}

double _requireFiniteDouble(List<String> args, int index, String flag) {
  final raw = _requireValue(args, index, flag);
  final value = double.tryParse(raw);
  if (value == null || !value.isFinite) {
    throw _UsageError('$flag needs a finite number, got "$raw"');
  }
  return value;
}

String _join(String directory, String name) {
  final hasSeparator =
      directory.endsWith(Platform.pathSeparator) || directory.endsWith('/');
  return hasSeparator
      ? '$directory$name'
      : '$directory${Platform.pathSeparator}$name';
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
