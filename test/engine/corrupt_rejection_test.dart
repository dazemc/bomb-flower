/// Corrupt and wrong-sized `progress.sav` input must be rejected outright.
///
/// Every case is a real retail `progress.sav` mutated in one way, staged as a
/// parent root `.<case>/slot_00/progress.sav`, and opened through the
/// production `FileSaveRepository.open` — the same resolver, codec and engine
/// path the app uses. The two size cases are additionally handed to
/// `SaveEngine.parse` with the *pristine* layout, because that is where the
/// engine's `expectedLength` guard lives: the repository derives a layout from
/// the bytes it just decoded, so its `expectedLength` always equals those
/// bytes and cannot catch a length change on its own.
///
/// A rejection must carry no project. `ParseOk` and `ParseUnverified` are the
/// only results that do, so both are asserted absent.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/adapter/progress_layout_builder.dart';
import 'package:bomb_flower/data/adapter/progress_layout_resolver.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration/support/progress_chain.dart';
import '../integration/support/real_save_loader.dart';
import '../support/temp_roots.dart';

/// Scratch root for the mutated cases, under this file's unique `.tmp/` root.
late String corruptRoot;

/// Root of this file's pristine two-slot fixture copy.
late String fixtureRoot;

/// The real file every mutation starts from.
const String pristineSlot = 'slot_00';

void main() {
  late GameDataSchema schema;
  late Uint8List pristine;
  late Uint8List pristineOtherSlot;
  late LayoutDescriptor pristineLayout;
  late Directory fileRoot;

  setUpAll(() async {
    schema = await loadGameDataSchema();
    fileRoot = createTempRoot('engine/corrupt-rejection');
    corruptRoot = '${fileRoot.path}/corrupt';
    fixtureRoot = '${fileRoot.path}/real-save';
    _ensureFixtures();
    pristine = _read('$fixtureRoot/$pristineSlot/progress.sav');
    pristineOtherSlot = _read('$fixtureRoot/slot_01/progress.sav');
    pristineLayout = _projectOf(
      await createProgressRepository(schema).open(fixtureRoot),
    ).layout;
    expect(pristineLayout.slots, hasLength(2));
  });

  tearDownAll(() => removeTempRoot(fileRoot));

  group('corrupt input is rejected with no partial project', () {
    test('should reject 4 KiB of 0xFF with no magic', () async {
      final root = _stage('garbage-ff', List<int>.filled(4096, 0xFF));
      final detection = await _detector(schema).detect(root);
      // ignore: avoid_print
      print('REJECT garbage-ff detect -> $detection');

      final result = await createProgressRepository(schema).open(root);
      _expectRejected(result, 'garbage-ff');
    });

    test('should reject 4 KiB of deterministic pseudo-random bytes', () async {
      final bytes = <int>[for (var i = 0; i < 4096; i++) (i * 167 + 13) & 0xFF];
      final root = _stage('garbage-random', bytes);
      final result = await createProgressRepository(schema).open(root);
      _expectRejected(result, 'garbage-random');
    });

    test(
      'should reject a 100-byte file that carries only a valid magic',
      () async {
        final root = _stage('truncated-magic-100', pristine.sublist(0, 100));
        final detection = await _detector(schema).detect(root);
        // ignore: avoid_print
        print('REJECT truncated-magic-100 detect -> $detection');

        final result = await createProgressRepository(schema).open(root);
        _expectRejected(result, 'truncated-magic-100');
      },
    );

    test(
      'should reject a real file whose schema revision is not 2982123',
      () async {
        final bytes = Uint8List.fromList(pristine);
        _writeU32(bytes, 0x04, 2982124);
        final root = _stage('wrong-revision', bytes);
        final detection = await _detector(schema).detect(root);
        // ignore: avoid_print
        print('REJECT wrong-revision detect -> $detection');

        final result = await createProgressRepository(schema).open(root);
        _expectRejected(result, 'wrong-revision');
      },
    );
  });

  group('wrong size is rejected by the engine length guard', () {
    test(
      'should reject a real progress.sav with the last 4 bytes removed',
      () async {
        final bytes = pristine.sublist(0, pristine.length - 4);
        final root = _stage('truncated-tail', bytes);

        // The repository re-detects the layout from the short bytes, so its
        // layout agrees with them and it does not reject. Recorded, not fixed:
        // there is no authoritative file length (SAVE-FORMAT.md §2 documents
        // 120,572 for the three scrubbed samples; the retail slots are 122,852
        // and 122,940), so `expectedLength` can only come from a known layout.
        final detected = await createProgressRepository(schema).open(root);
        // ignore: avoid_print
        print(
          'OBSERVE truncated-tail repository.open -> ${_describe(detected)}',
        );

        final result = createProgressEngine().parse(
          rootPath: root,
          files: <SaveSlotId, ByteRegion>{
            SaveSlotId.progress(0): ByteRegion.fromBytes(bytes),
            SaveSlotId.progress(1): ByteRegion.fromBytes(pristineOtherSlot),
          },
          layout: pristineLayout,
          detectedVersion: 2982123,
        );
        _expectRejected(result, 'truncated-tail (pristine layout)');
        expect(result, isA<ParseCorrupt>());
        final corrupt = result as ParseCorrupt;
        expect(
          corrupt.reason,
          'slot_00/progress.sav is 122848 bytes; layout expects 122852',
        );
        expect(corrupt.at, const ByteSpan(0, 122848));
      },
    );

    test(
      'should reject a real progress.sav with 4 zero bytes appended',
      () async {
        final bytes = Uint8List.fromList(<int>[...pristine, 0, 0, 0, 0]);
        final root = _stage('appended-zeros', bytes);

        final detected = await createProgressRepository(schema).open(root);
        // ignore: avoid_print
        print(
          'OBSERVE appended-zeros repository.open -> ${_describe(detected)}',
        );

        final result = createProgressEngine().parse(
          rootPath: root,
          files: <SaveSlotId, ByteRegion>{
            SaveSlotId.progress(0): ByteRegion.fromBytes(bytes),
            SaveSlotId.progress(1): ByteRegion.fromBytes(pristineOtherSlot),
          },
          layout: pristineLayout,
          detectedVersion: 2982123,
        );
        _expectRejected(result, 'appended-zeros (pristine layout)');
        expect(result, isA<ParseCorrupt>());
        final corrupt = result as ParseCorrupt;
        expect(
          corrupt.reason,
          'slot_00/progress.sav is 122856 bytes; layout expects 122852',
        );
        expect(corrupt.at, const ByteSpan(0, 122856));
      },
    );
  });
}

/// The production detector, exposed so a detection reason can be quoted.
ProgressLayoutResolver _detector(GameDataSchema schema) =>
    ProgressLayoutResolver(ProgressLayoutBuilder(schema));

/// Writes `<corruptRoot>/<name>/slot_00/progress.sav` and returns the root.
String _stage(String name, List<int> bytes) {
  final root = '$corruptRoot/$name';
  final file = File('$root/$pristineSlot/progress.sav')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  expect(file.existsSync(), isTrue);
  return root;
}

/// Renders a parse result with its exact rejection reason.
String _describe(ParseResult result) => switch (result) {
  ParseOk() => 'ParseOk(project)',
  ParseUnverified(:final unverifiedFields) =>
    'ParseUnverified(project, ${unverifiedFields.length} unverified fields)',
  ParseUnsupported(:final reason) => 'ParseUnsupported($reason)',
  ParseCorrupt(:final reason, :final at) => 'ParseCorrupt($reason, at: $at)',
};

/// Asserts [result] is a rejection, prints its exact text, and proves it holds
/// no project.
void _expectRejected(ParseResult result, String label) {
  final description = _describe(result);
  // ignore: avoid_print
  print('REJECT $label -> $description');
  expect(
    result,
    isNot(isA<ParseOk>()),
    reason: '$label must not open: $description',
  );
  expect(
    result,
    isNot(isA<ParseUnverified>()),
    reason: '$label must not open: $description',
  );
  expect(
    result,
    anyOf(isA<ParseCorrupt>(), isA<ParseUnsupported>()),
    reason: '$label must be rejected, got $description',
  );
}

/// Copies the two pristine real slots into this file's own fixture root.
///
/// The source is the read-only retail/Longshot save tree, resolved through
/// [resolveRealSaves] so no absolute home path is hardcoded. A missing slot
/// fails rather than skipping: these tests never had a skip branch.
void _ensureFixtures() {
  final resolution = resolveRealSaves();
  if (resolution is RealSaveMisconfigured) {
    fail(resolution.reason);
  }
  if (resolution is! RealSaveFound) {
    fail(
      'no real save found, so the two-slot fixture cannot be staged at '
      '$fixtureRoot; set $realSavesRootEnvVar or place a save at the default '
      'path ($defaultRealSavesRoot)',
    );
  }
  for (final slot in <String>[pristineSlot, 'slot_01']) {
    final target = File('$fixtureRoot/$slot/progress.sav');
    final source = _sourceSlot(resolution, slot);
    if (source == null) {
      fail(
        'the resolved slots '
        '${resolution.slots.map((directory) => directory.path).toList()} '
        'contain no $slot to stage at ${target.path}',
      );
    }
    target.parent.createSync(recursive: true);
    File('${source.path}/progress.sav').copySync(target.path);
  }
}

/// The resolved slot directory whose own name is [slot].
Directory? _sourceSlot(RealSaveFound found, String slot) {
  for (final directory in found.slots) {
    final segments = directory.uri.pathSegments.where(
      (segment) => segment.isNotEmpty,
    );
    if (segments.isNotEmpty && segments.last == slot) {
      return directory;
    }
  }
  return null;
}

Uint8List _read(String path) =>
    Uint8List.fromList(File(path).readAsBytesSync());

/// Writes a little-endian u32 at [offset].
void _writeU32(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
  bytes[offset + 2] = (value >> 16) & 0xFF;
  bytes[offset + 3] = (value >> 24) & 0xFF;
}

/// The project of an accepted open, or a failure naming the rejection.
SaveProject _projectOf(ParseResult result) => switch (result) {
  ParseOk(:final project) => project,
  ParseUnverified(:final project) => project,
  _ => fail('open failed: ${_describe(result)}'),
};
