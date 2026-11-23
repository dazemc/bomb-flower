/// Why a save was rejected must reach the user, per cause.
///
/// Every rejection case is the same real retail `progress.sav` mutated in one
/// way and staged under the gitignored `.tmp/` tree, then opened through the
/// production wiring (`ProgressLayoutResolver` → `FileSaveRepository` →
/// `SaveSessionCubit`, exactly as `lib/main.dart` builds it).
///
/// A truncated container, a wrong revision and a non-save folder are three
/// different failures; each must produce its own message and its own detail,
/// and none may claim the folder is merely "not wired yet".
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/adapter/progress_layout_builder.dart';
import 'package:bomb_flower/data/adapter/progress_layout_resolver.dart';
import 'package:bomb_flower/data/io/file_save_repository.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration/support/progress_chain.dart';

/// Root of the pristine two-slot fixture.
const String fixtureRoot = '.tmp/rt';

/// Scratch root for the mutated cases.
const String caseRoot = '.tmp/rt/reject-reason';

/// The read-only retail save tree. Never written; only copied out of.
const String realSaveRoot =
    '/home/daze/.local/share/longshot/save/5a3c9e1f0b7d24680000000000000001';

/// The real file every mutation starts from.
const String pristineSlot = 'slot_00';

void main() {
  late GameDataSchema schema;
  late Uint8List pristine;

  setUpAll(() async {
    schema = await loadGameDataSchema();
    _ensureFixtures();
    pristine = _read('$fixtureRoot/$pristineSlot/progress.sav');
  });

  group('SaveSessionCubit rejection reason', () {
    test('should report a truncated file as corrupt with the codec reason', () async {
      final root = _stage('truncated', pristine.sublist(0, 100));
      final cubit = await _open(root, schema);
      addTearDown(() => cubit.close(force: true));

      final error = _error(cubit);
      expect(error.kind, SaveSessionErrorKind.corruptSave);
      expect(error.message, 'This save folder is damaged or incomplete.');
      expect(
        error.details,
        contains(
          'the data offset 95704 points past the end of the 100-byte buffer',
        ),
        reason: 'the codec reason must survive, not be collapsed to a category',
      );
      expect(error.details, contains('$root/$pristineSlot/progress.sav'));
      expect(error.details, contains('Folder: $root'));
    });

    test('should report a wrong revision with both version numbers', () async {
      final root = _stage('revision', _wrongRevision(pristine));
      final cubit = await _open(root, schema);
      addTearDown(() => cubit.close(force: true));

      final error = _error(cubit);
      expect(error.kind, SaveSessionErrorKind.unsupportedLayout);
      expect(
        error.message,
        'This save uses a game version this build does not support.',
      );
      expect(error.details, contains('layout revision 2982124'));
      expect(error.details, contains('2982123'));
      expect(error.details, contains('Folder: $root'));
    });

    test('should report a non-save with the magic it read', () async {
      final root = _stage('not-a-save', List<int>.filled(4096, 0xFF));
      final cubit = await _open(root, schema);
      addTearDown(() => cubit.close(force: true));

      final error = _error(cubit);
      expect(error.kind, SaveSessionErrorKind.unsupportedLayout);
      expect(error.message, 'This folder does not contain a save.');
      expect(
        error.details,
        contains(
          'the magic at 0x0 is 0xffffffff; expected 0x01020304',
        ),
      );
      expect(error.details, contains('Folder: $root'));
    });

    test('should give each cause a distinct message and detail', () async {
      final truncated = await _reject(
        'distinct-truncated',
        pristine.sublist(0, 100),
        schema,
      );
      final revision = await _reject(
        'distinct-revision',
        _wrongRevision(pristine),
        schema,
      );
      final notASave = await _reject(
        'distinct-not-a-save',
        List<int>.filled(4096, 0xFF),
        schema,
      );

      final errors = <SaveSessionError>[truncated, revision, notASave];
      expect(
        errors.map((error) => error.message).toSet(),
        hasLength(3),
        reason: 'three causes need three messages',
      );
      expect(
        errors.map((error) => error.details).toSet(),
        hasLength(3),
        reason: 'three causes need three details',
      );
      expect(
        errors.every((error) => !error.details!.contains('not wired')),
        isTrue,
        reason: 'the false "not wired yet" detail is gone',
      );
    });

    test('should still open a valid save unchanged', () async {
      final cubit = await _open(fixtureRoot, schema);
      addTearDown(() => cubit.close(force: true));

      expect(
        cubit.state,
        isA<SaveSessionReady>(),
        reason: 'a valid fixture must open: ${cubit.state}',
      );
      expect(cubit.openProject, isNotNull);
      expect(cubit.openProject!.layout.slots, hasLength(2));
      expect(
        cubit.lastOpenResult,
        anyOf(isA<ParseOk>(), isA<ParseUnverified>()),
      );
    });
  });
}

/// Builds the production session over [schema] and opens [root].
Future<SaveSessionCubit> _open(String root, GameDataSchema schema) async {
  final engine = createProgressEngine();
  final resolver = ProgressLayoutResolver(ProgressLayoutBuilder(schema));
  final cubit = SaveSessionCubit(
    engine: engine,
    repository: FileSaveRepository(
      engine: engine,
      resolveLayout: resolver.call,
    ),
    resolveLayout: resolver.call,
  );
  await cubit.openPath(root);
  return cubit;
}

/// Opens one rejection case, asserts it failed, and returns the error.
Future<SaveSessionError> _reject(
  String name,
  List<int> bytes,
  GameDataSchema schema,
) async {
  final root = _stage(name, bytes);
  final cubit = await _open(root, schema);
  try {
    return _error(cubit);
  } finally {
    await cubit.close(force: true);
  }
}

/// The single error state, or a failure naming what was emitted instead.
SaveSessionError _error(SaveSessionCubit cubit) {
  final state = cubit.state;
  expect(state, isA<SaveSessionError>(), reason: 'expected an error: $state');
  return state as SaveSessionError;
}

/// Writes `<caseRoot>/<name>/slot_00/progress.sav` and returns the root.
String _stage(String name, List<int> bytes) {
  final root = '$caseRoot/$name';
  final directory = Directory(root);
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
  final file = File('$root/$pristineSlot/progress.sav')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  expect(file.existsSync(), isTrue);
  return root;
}

/// Copies the pristine slots into `.tmp/rt/` when absent.
void _ensureFixtures() {
  for (final slot in <String>[pristineSlot, 'slot_01']) {
    final target = File('$fixtureRoot/$slot/progress.sav');
    if (target.existsSync()) {
      continue;
    }
    final source = File('$realSaveRoot/$slot/progress.sav');
    if (!source.existsSync()) {
      fail(
        'no fixture at ${target.path} and no read-only source at '
        '${source.path}; copy a real progress.sav into ${target.parent.path}',
      );
    }
    target.parent.createSync(recursive: true);
    source.copySync(target.path);
  }
}

/// A copy of [bytes] with the schema revision replaced by `2982124`.
Uint8List _wrongRevision(Uint8List bytes) {
  final copy = Uint8List.fromList(bytes);
  _writeU32(copy, 0x04, 2982124);
  return copy;
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
