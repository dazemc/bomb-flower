/// End-to-end badge proof through the production bloc layer (final-15-A3).
///
/// `test/audit/undo_redo_dirty_test.dart` drives the pure
/// `SaveSessionController`; this file drives `SaveSessionCubit`, the only route
/// from the UI to the engine, wired exactly as `lib/main.dart` wires it:
/// `SaveEngine` + `FileSaveRepository(resolveLayout:)` +
/// `ProgressLayoutResolver(ProgressLayoutBuilder(schema))`.
///
/// The fixture is copied to this run's own unique `.tmp/` root so the scrubbed
/// sample under `.local-fixtures/` is never written to and a concurrent run
/// cannot delete it. Every step prints one `[e2e]` line carrying the measured
/// badge tuple, and asserts the same values.
///
/// Coalescing trap (`EditHistory.record`): two `SetScalar` commands on the SAME
/// field inside 400 ms merge into one entry. The two edits here target DISTINCT
/// fields, and `EditHistory.undo()` resets coalescing, so the undo counts are
/// exact without calling `seal()`.
library;

import 'dart:io';

import 'package:bomb_flower/data/adapter/progress_layout_builder.dart';
import 'package:bomb_flower/data/adapter/progress_layout_resolver.dart';
import 'package:bomb_flower/data/io/file_save_repository.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration/support/progress_chain.dart';
import '../support/fixture_loader.dart';
import '../support/temp_roots.dart';

/// Scrubbed sample the chain opens.
const String _fixtureName = 'kokiri-start';

/// Scratch space for this run, under a unique gitignored `.tmp/` root.
late String _scratchRoot;

/// The full badge tuple read from the emitted `SaveProjectUi`.
typedef _Badges = ({
  bool differs,
  bool dirty,
  int fields,
  int bytes,
  bool undo,
  bool redo,
  bool canSave,
});

void main() {
  late GameDataSchema schema;

  final fixturePath =
      '${fixturesDirectory.path}/$_fixtureName/slot_00/progress.sav';
  final skipReason = File(fixturePath).existsSync()
      ? null
      : 'SKIPPED, NOT PASSED: $fixturePath is missing, so this test did not '
            'run. Run `dart run tool/make_fixtures.dart` from the repository '
            'root, then re-run. A green suite that reports ~N > 0 is not full '
            'e2e coverage.';

  setUpAll(() async {
    schema = await loadGameDataSchema();
  });

  test(
    'cubit badges track dirty, undo/redo and save on a fixture copy',
    () async {
      final fixtureSlot = Directory(
        '${fixturesDirectory.path}/$_fixtureName/slot_00',
      );

      // Fresh copy every run: no state, sidecar or `.bak` from a previous test.
      final scratch = createTempRoot('e2e/cubit-session');
      _scratchRoot = '${scratch.path}/session';
      addTearDown(() => removeTempRoot(scratch));
      Directory('$_scratchRoot/slot_00').createSync(recursive: true);
      for (final entity in fixtureSlot.listSync(followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final name = entity.uri.pathSegments.last;
        entity.copySync('$_scratchRoot/slot_00/$name');
      }
      stdout.writeln(
        '[e2e] copied $_fixtureName/slot_00 -> $_scratchRoot/slot_00',
      );

      final cubit = _buildCubit(schema);
      addTearDown(() => cubit.close(force: true));

      await cubit.openPath(_scratchRoot);
      expect(cubit.state, isA<SaveSessionReady>());
      final lifeBefore = _fieldValue(cubit, lifeFieldId);
      final maxLifeBefore = _fieldValue(cubit, maxLifeFieldId);
      final maxLifeEdit = maxLifeBefore == 24 ? 28 : 24;
      final lifeEditBytes = _differingBytes(lifeBefore, 20);
      final maxLifeEditBytes = _differingBytes(maxLifeBefore, maxLifeEdit);
      expect(lifeEditBytes, greaterThan(0));
      expect(maxLifeEditBytes, greaterThan(0));

      // Step 0: open. A freshly opened project is clean and has no history.
      var step = _emitStep('open', cubit);
      _expectBadges(
        step,
        label: 'open',
        differs: false,
        dirty: false,
        fields: 0,
        bytes: 0,
        undo: false,
        redo: false,
        canSave: false,
      );
      expect(_projectBadges(cubit).activeSlot, progressSlotId);
      _expectSlot(cubit, label: 'open', isDirty: false, fields: 0, bytes: 0);

      // Step 1: edit A — Life. One field, one byte for 12 -> 20.
      cubit.edit(const SetScalar(lifeFieldId, 20));
      expect(cubit.state, isA<SaveSessionReady>());
      step = _emitStep('edit-A-life', cubit);
      _expectBadges(
        step,
        label: 'edit A',
        differs: true,
        dirty: true,
        fields: 1,
        bytes: lifeEditBytes,
        undo: true,
        redo: false,
        canSave: true,
      );
      expect(step.bytes, lifeEditBytes);
      expect(_fieldValue(cubit, lifeFieldId), 20);
      expect(_fieldValue(cubit, maxLifeFieldId), maxLifeBefore);
      _expectSlot(
        cubit,
        label: 'edit A',
        isDirty: true,
        fields: 1,
        bytes: lifeEditBytes,
      );

      // Step 2: edit B — MaxLife, a distinct field, so no coalescing.
      cubit.edit(SetScalar(maxLifeFieldId, maxLifeEdit));
      step = _emitStep('edit-B-maxlife', cubit);
      _expectBadges(
        step,
        label: 'edit B',
        differs: true,
        dirty: true,
        fields: 2,
        bytes: lifeEditBytes + maxLifeEditBytes,
        undo: true,
        redo: false,
        canSave: true,
      );
      expect(_fieldValue(cubit, lifeFieldId), 20);
      expect(_fieldValue(cubit, maxLifeFieldId), maxLifeEdit);
      _expectSlot(
        cubit,
        label: 'edit B',
        isDirty: true,
        fields: 2,
        bytes: lifeEditBytes + maxLifeEditBytes,
      );

      // Step 3: undo B. A is still applied, so both stacks hold work.
      cubit.undo();
      step = _emitStep('undo-B', cubit);
      _expectBadges(
        step,
        label: 'undo B',
        differs: true,
        dirty: true,
        fields: 1,
        bytes: lifeEditBytes,
        undo: true,
        redo: true,
        canSave: true,
      );
      expect(_fieldValue(cubit, maxLifeFieldId), maxLifeBefore);
      expect(_fieldValue(cubit, lifeFieldId), 20);

      // Step 4: undo A. Back to the opened bytes: both dirty badges clear and
      // the undo stack empties while redo holds both entries.
      cubit.undo();
      step = _emitStep('undo-A', cubit);
      _expectBadges(
        step,
        label: 'undo A',
        differs: false,
        dirty: false,
        fields: 0,
        bytes: 0,
        undo: false,
        redo: true,
        canSave: false,
      );
      expect(_fieldValue(cubit, lifeFieldId), lifeBefore);
      expect(_fieldValue(cubit, maxLifeFieldId), maxLifeBefore);
      _expectSlot(cubit, label: 'undo A', isDirty: false, fields: 0, bytes: 0);

      // Step 5: undo on the empty stack is a no-op: the cubit returns before
      // emitting, so even the state instance stays identical.
      final noopState = cubit.state;
      final noopBefore = _emitStep('undo-empty', cubit);
      cubit.undo();
      final noopAfter = _emitStep('undo-empty-noop', cubit);
      expect(
        identical(cubit.state, noopState),
        isTrue,
        reason: 'undo() on an empty stack must not emit a new state',
      );
      expect(noopAfter, noopBefore);

      // Step 6: redo A.
      cubit.redo();
      step = _emitStep('redo-A', cubit);
      _expectBadges(
        step,
        label: 'redo A',
        differs: true,
        dirty: true,
        fields: 1,
        bytes: lifeEditBytes,
        undo: true,
        redo: true,
        canSave: true,
      );
      expect(_fieldValue(cubit, lifeFieldId), 20);
      expect(_fieldValue(cubit, maxLifeFieldId), maxLifeBefore);

      // Step 7: redo B. The redo stack empties; both edits are applied again.
      cubit.redo();
      step = _emitStep('redo-B', cubit);
      _expectBadges(
        step,
        label: 'redo B',
        differs: true,
        dirty: true,
        fields: 2,
        bytes: lifeEditBytes + maxLifeEditBytes,
        undo: true,
        redo: false,
        canSave: true,
      );
      expect(_fieldValue(cubit, lifeFieldId), 20);
      expect(_fieldValue(cubit, maxLifeFieldId), maxLifeEdit);

      // Step 8: save in place.
      await cubit.save();
      expect(cubit.state, isA<SaveSessionSaved>());
      final savedState = cubit.state as SaveSessionSaved;
      expect(savedState.mode, ExportMode.saveInPlace);
      expect(savedState.path, _scratchRoot);
      expect(savedState.statusMessage, startsWith('Saved to '));
      expect(savedState.written, isNotEmpty);
      expect(
        savedState.written.map((write) => write.slot.value),
        contains(progressSlotId.value),
      );
      final progressWrite = savedState.written.firstWhere(
        (write) => write.slot == progressSlotId,
      );
      expect(progressWrite.path, '$_scratchRoot/slot_00/progress.sav');

      step = _emitStep('save', cubit);
      // Measured, not assumed: saveInPlace preserves the edit history
      // (`SaveEngine._projectAfterExport` copies the project and only advances
      // savedFingerprints/savedSnapshots), so `canUndo` stays true after a save.
      // `test/audit/undo_redo_dirty_test.dart:294` asserts the same for the
      // controller. The task brief expected false here; the code and that test
      // both say true.
      _expectBadges(
        step,
        label: 'save',
        differs: true,
        dirty: false,
        fields: 2,
        bytes: lifeEditBytes + maxLifeEditBytes,
        undo: true,
        redo: false,
        canSave: false,
      );
      expect(_fieldValue(cubit, lifeFieldId), 20);
      expect(_fieldValue(cubit, maxLifeFieldId), maxLifeEdit);
      _expectSlot(
        cubit,
        label: 'save',
        isDirty: false,
        fields: 2,
        bytes: lifeEditBytes + maxLifeEditBytes,
      );

      // The written bytes really carry both values.
      final disk = File('$_scratchRoot/slot_00/progress.sav').readAsBytesSync();
      final lifeOffset = lifeValueOffset(schema);
      final maxLifeOffset = _valueOffset(schema, 'PlayerStatus.MaxLife');
      expect(hexU32(disk, lifeOffset), _hex32(20));
      expect(hexU32(disk, maxLifeOffset), _hex32(maxLifeEdit));
      stdout.writeln(
        '[e2e] disk life@0x${lifeOffset.toRadixString(16)}='
        '${hexU32(disk, lifeOffset)} '
        'maxlife@0x${maxLifeOffset.toRadixString(16)}='
        '${hexU32(disk, maxLifeOffset)}',
      );

      // A fresh production cubit decodes the same values from disk.
      final reopened = _buildCubit(schema);
      addTearDown(() => reopened.close(force: true));
      await reopened.openPath(_scratchRoot);
      expect(reopened.state, isA<SaveSessionReady>());
      final reopenStep = _emitStep('reopen', reopened);
      expect(reopenStep.differs, isFalse);
      expect(reopenStep.dirty, isFalse);
      expect(reopenStep.fields, 0);
      expect(reopenStep.undo, isFalse);
      expect(_fieldValue(reopened, lifeFieldId), 20);
      expect(_fieldValue(reopened, maxLifeFieldId), maxLifeEdit);

      // Step 9: an edit after undo CLEARS redo. Undo B first so a redo entry
      // exists, then re-apply B; the new edit must drop the redo stack.
      cubit.undo();
      final afterSaveUndo = _emitStep('undo-after-save', cubit);
      expect(afterSaveUndo.fields, 1);
      expect(afterSaveUndo.redo, isTrue);
      cubit.edit(SetScalar(maxLifeFieldId, maxLifeEdit));
      final afterUndoEdit = _emitStep('edit-after-undo', cubit);
      expect(afterUndoEdit.fields, 2);
      expect(afterUndoEdit.undo, isTrue);
      expect(
        afterUndoEdit.redo,
        isFalse,
        reason: 'a new edit must clear the redo stack',
      );
      expect(_fieldValue(cubit, maxLifeFieldId), maxLifeEdit);
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// Builds the cubit exactly as `lib/main.dart` does.
SaveSessionCubit _buildCubit(GameDataSchema schema) {
  final engine = createProgressEngine();
  final resolver = ProgressLayoutResolver(ProgressLayoutBuilder(schema));
  return SaveSessionCubit(
    engine: engine,
    repository: FileSaveRepository(
      engine: engine,
      resolveLayout: resolver.call,
    ),
    resolveLayout: resolver.call,
  );
}

/// The project carried by the current cubit state, failing loudly when absent.
SaveProjectUi _projectBadges(SaveSessionCubit cubit) {
  final project = _projectOf(cubit.state);
  expect(project, isNotNull, reason: 'state ${cubit.state} carries no project');
  return project!;
}

/// The `SaveProjectUi` carried by [state], or `null` for closed/opening.
SaveProjectUi? _projectOf(SaveSessionUiState state) => switch (state) {
  SaveSessionReady(:final project) => project,
  SaveSessionSaving(:final project) => project,
  SaveSessionSaved(:final project) => project,
  SaveSessionError(:final project) => project,
  SaveSessionPendingDiscard(:final project) => project,
  SaveSessionOpening() => null,
  SaveSessionClosed() => null,
};

/// Reads the full badge tuple and prints one `[e2e]` evidence line.
_Badges _emitStep(String name, SaveSessionCubit cubit) {
  final project = _projectBadges(cubit);
  final life = _fieldValue(cubit, lifeFieldId);
  final maxLife = _fieldValue(cubit, maxLifeFieldId);
  final badges = (
    differs: project.differsFromOriginal,
    dirty: project.hasUnsavedChanges,
    fields: project.changedFieldCount,
    bytes: project.changedByteCount,
    undo: project.canUndo,
    redo: project.canRedo,
    canSave: project.canSave,
  );
  stdout.writeln(
    '[e2e] step=$name dirty=${badges.dirty} fields=${badges.fields} '
    'bytes=${badges.bytes} undo=${badges.undo} redo=${badges.redo} '
    'life=$life maxlife=$maxLife',
  );
  return badges;
}

/// Asserts every member of [actual] against the expected badge tuple.
void _expectBadges(
  _Badges actual, {
  required String label,
  required bool differs,
  required bool dirty,
  required int fields,
  required int bytes,
  required bool undo,
  required bool redo,
  required bool canSave,
}) {
  expect(actual.differs, differs, reason: '$label: differsFromOriginal');
  expect(actual.dirty, dirty, reason: '$label: hasUnsavedChanges');
  expect(actual.fields, fields, reason: '$label: changedFieldCount');
  expect(actual.bytes, bytes, reason: '$label: changedByteCount');
  expect(actual.undo, undo, reason: '$label: canUndo');
  expect(actual.redo, redo, reason: '$label: canRedo');
  expect(actual.canSave, canSave, reason: '$label: canSave');
}

/// Asserts the progress slot's own badge row.
void _expectSlot(
  SaveSessionCubit cubit, {
  required String label,
  required bool isDirty,
  required int fields,
  required int bytes,
}) {
  final project = _projectBadges(cubit);
  final slot = project.slots.firstWhere((row) => row.id == progressSlotId);
  expect(slot.isDirty, isDirty, reason: '$label: slot isDirty');
  expect(slot.changedFieldCount, fields, reason: '$label: slot fields');
  expect(slot.changedByteCount, bytes, reason: '$label: slot bytes');
}

/// The decoded integer value of [fieldId] in the cubit's open project.
int _fieldValue(SaveSessionCubit cubit, FieldId fieldId) {
  final project = cubit.openProject;
  expect(project, isNotNull, reason: 'the cubit has no open project');
  return fieldInt(project!, fieldId);
}

/// Value offset of a named u32 field: `0x28 + 8 * recordIndex + 4`.
int _valueOffset(GameDataSchema schema, String name) {
  final index = schema.byNameOnDisk(name)?.recordIndex;
  if (index == null) {
    throw StateError('schema has no on-disk $name record');
  }
  return 0x28 + 8 * index + 4;
}

/// The four little-endian bytes of [value], as `0c 00 00 00`.
String _hex32(int value) => <String>[
  for (var index = 0; index < 4; index++)
    ((value >> (index * 8)) & 0xff).toRadixString(16).padLeft(2, '0'),
].join(' ');

/// How many of the four little-endian bytes differ between [a] and [b].
///
/// The dirty byte count measures differing bytes, not the touched field width.
int _differingBytes(int a, int b) {
  var count = 0;
  for (var shift = 0; shift < 32; shift += 8) {
    if (((a >> shift) & 0xff) != ((b >> shift) & 0xff)) {
      count++;
    }
  }
  return count;
}
