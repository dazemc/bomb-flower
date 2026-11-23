/// Audit undo-09: undo/redo ordering, dirty-badge lifecycle, bounded history.
///
/// Prior coverage this file deliberately extends rather than repeats:
/// * `test/domain/engine/save_engine_test.dart:462-621` already covers a
///   synthetic one-byte layout with a single field: undo restores bytes, redo
///   reapplies, a new edit clears redo, an empty stack returns the same
///   instance, transactions collapse, and one field's dirty badges toggle.
/// * `test/audit/real_save_roundtrip_test.dart:258-312` already covers one
///   real field through edit -> undo -> redo.
///
/// Added here: two distinct fields with ordered multi-step undo/redo, the
/// unsaved badge staying true while any edit remains, empty-stack no-ops
/// leaving the dirty state identical, a save that clears `hasUnsavedChanges`
/// while `differsFromOriginal` and the values survive, and the real
/// bounded-history cap plus its eviction behaviour.
///
/// The state machine driven here is `SaveSessionController`
/// (`lib/domain/engine/save_session.dart`) over `createProgressRepository` and
/// `createProgressEngine` — the same pure controller that
/// `lib/presentation/bloc/save_session/save_session_cubit.dart` wraps.
///
/// Coalescing trap ([EditHistory.record], `lib/domain/core/edit_history.dart`):
/// two edits to the SAME field and command type inside the default 400 ms
/// window merge into one history entry. Every multi-edit sequence in this file
/// targets DISTINCT fields, which `_CoalesceKey` (field + command type) never
/// merges, so the undo counts below are exact without calling `seal()`.
library;

import 'dart:io';

import 'package:bomb_flower/data/newsave/new_save_writer.dart';
import 'package:bomb_flower/domain/core/core.dart' hide ByteRegion;
import 'package:bomb_flower/domain/engine/save_session.dart';
import 'package:bomb_flower/domain/newsave/new_save_builder.dart';
import 'package:bomb_flower/domain/newsave/new_save_spec.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration/support/progress_chain.dart';
import '../support/byte_assert.dart';

/// Parent of the per-test synthetic saves; rebuilt by each test.
const String fixtureParent = '.tmp/audit/undo-redo-dirty';

/// `PlayerStatus.CurrentRupee` — Int, verified, editable.
const FieldId rupeeFieldId = FieldId('progress.a77921d7');

/// `PlayerStatus.IsDefenseUP` — Bool, verified, editable, default `false`.
const FieldId defenseFieldId = FieldId('progress.56bbe07c');

void main() {
  late GameDataSchema schema;

  setUpAll(() async {
    schema = await loadGameDataSchema();
  });

  /// Builds a fresh schema-default save (Life 12, MaxLife 12, Rupee 0) and
  /// returns its root. Deleting both the root and its sidecar first keeps one
  /// test's export from leaking into the next.
  Future<String> buildFreshSave(String name) async {
    final root = '$fixtureParent/$name';
    final directory = Directory(root);
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
    final sidecar = Directory('$root.bombflower-original');
    if (sidecar.existsSync()) {
      sidecar.deleteSync(recursive: true);
    }
    final build = NewSaveBuilder.build(
      schema: schema,
      spec: NewSaveSpec.preset(NewSavePreset.schemaDefaults),
    );
    await NewSaveWriter().write(rootDirectory: root, build: build);
    return root;
  }

  /// Opens a fresh save through the production repository and the pure
  /// session controller.
  Future<({String root, SaveSessionController controller})> openSession(
    String name,
  ) async {
    final root = await buildFreshSave(name);
    final controller = SaveSessionController(
      engine: createProgressEngine(),
      repository: createProgressRepository(schema),
    );
    await controller.open(root);
    expect(controller.state.status, SessionStatus.ready);
    expect(controller.state.project, isNotNull);
    return (root: root, controller: controller);
  }

  group('SaveSessionController open, edit, undo, redo', () {
    test(
      'should open clean and report one changed field after a Life edit',
      () async {
        final controller = (await openSession('single')).controller;
        final opened = projectOf(controller);

        expect(opened.dirty.isClean, isTrue);
        expect(opened.dirty.differsFromOriginal, isFalse);
        expect(controller.state.canUndo, isFalse);
        expect(controller.state.canRedo, isFalse);
        expect(fieldInt(opened, lifeFieldId), 12);

        controller.edit(const SetScalar(lifeFieldId, 16));
        final edited = projectOf(controller);
        expect(fieldInt(edited, lifeFieldId), 16);
        expect(edited.dirty.hasUnsavedChanges, isTrue);
        expect(edited.dirty.differsFromOriginal, isTrue);
        expect(edited.dirty.changedFieldCount, 1);
        expect(controller.state.canUndo, isTrue);
        expect(controller.state.canRedo, isFalse);
        expect(controller.state.canSave, isTrue);
        chainLog(
          'edit Life 12->16 dirty=${edited.dirty.hasUnsavedChanges} '
          'canUndo=${controller.state.canUndo}',
        );
      },
    );

    test(
      'should restore the opened bytes and clear both badges on undo',
      () async {
        final controller = (await openSession('undo')).controller;
        final openedBytes = projectOf(controller)
            .document(progressSlotId)!
            .snapshot
            .materialize();

        controller.edit(const SetScalar(lifeFieldId, 16));
        controller.undo();

        final undone = projectOf(controller);
        expect(fieldInt(undone, lifeFieldId), 12);
        expect(undone.dirty.hasUnsavedChanges, isFalse);
        expect(undone.dirty.isClean, isTrue);
        expect(undone.dirty.differsFromOriginal, isFalse);
        expect(controller.state.canUndo, isFalse);
        expect(controller.state.canRedo, isTrue);
        expect(controller.state.canSave, isFalse);
        expectByteIdentical(
          openedBytes,
          undone.document(progressSlotId)!.snapshot.materialize(),
          reason: 'undo must reinstall the opened snapshot byte for byte',
        );
        chainLog(
          'undo Life -> 12 dirty=${undone.dirty.hasUnsavedChanges} '
          'canRedo=${controller.state.canRedo} bytes identical to open',
        );
      },
    );

    test('should reapply the Life edit and flag it unsaved on redo', () async {
      final controller = (await openSession('redo')).controller;
      controller.edit(const SetScalar(lifeFieldId, 16));
      controller.undo();
      controller.redo();

      final redone = projectOf(controller);
      expect(fieldInt(redone, lifeFieldId), 16);
      expect(redone.dirty.hasUnsavedChanges, isTrue);
      expect(redone.dirty.differsFromOriginal, isTrue);
      expect(redone.dirty.changedFieldCount, 1);
      expect(controller.state.canUndo, isTrue);
      expect(controller.state.canRedo, isFalse);
      chainLog(
        'redo Life -> 16 dirty=${redone.dirty.hasUnsavedChanges} '
        'canRedo=${controller.state.canRedo}',
      );
    });
  });

  group('ordered undo and redo over two distinct fields', () {
    test(
      'should unwind and replay Life and rupee one entry at a time',
      () async {
        final controller = (await openSession('two-fields')).controller;
        controller.edit(const SetScalar(lifeFieldId, 16));
        controller.edit(const SetScalar(rupeeFieldId, 42));

        var project = projectOf(controller);
        expect(fieldInt(project, lifeFieldId), 16);
        expect(fieldInt(project, rupeeFieldId), 42);
        expect(project.history.undoStack.length, 2);

        // Undo #1 removes the newest edit (rupee); Life still carries an edit,
        // so the unsaved badge must stay set and one undo must remain.
        controller.undo();
        project = projectOf(controller);
        expect(fieldInt(project, rupeeFieldId), 0);
        expect(fieldInt(project, lifeFieldId), 16);
        expect(project.dirty.hasUnsavedChanges, isTrue);
        expect(project.dirty.changedFieldCount, 1);
        expect(controller.state.canUndo, isTrue);

        // Undo #2 removes the Life edit: back to the opened state.
        controller.undo();
        project = projectOf(controller);
        expect(fieldInt(project, lifeFieldId), 12);
        expect(project.dirty.hasUnsavedChanges, isFalse);
        expect(project.dirty.differsFromOriginal, isFalse);
        expect(controller.state.canUndo, isFalse);
        expect(controller.state.canRedo, isTrue);

        // Redo is LIFO, so the most recently undone edit returns first: Life is
        // edit #1 and rupee is edit #2, i.e. the pair replays in application
        // order (Life, then rupee) across the two redo calls.
        controller.redo();
        project = projectOf(controller);
        expect(fieldInt(project, lifeFieldId), 16);
        expect(fieldInt(project, rupeeFieldId), 0);
        expect(project.dirty.hasUnsavedChanges, isTrue);

        controller.redo();
        project = projectOf(controller);
        expect(fieldInt(project, rupeeFieldId), 42);
        expect(fieldInt(project, lifeFieldId), 16);
        expect(project.dirty.hasUnsavedChanges, isTrue);
        expect(controller.state.canRedo, isFalse);
        chainLog(
          'two fields: undo rupee->0 (Life 16, dirty true), undo Life->12 '
          '(clean), redo Life->16, redo rupee->42',
        );
      },
    );
  });

  group('empty undo and redo stacks', () {
    test(
      'should leave project and dirty state untouched when undo is empty',
      () async {
        final controller = (await openSession('empty-undo')).controller;
        final before = projectOf(controller);
        final dirtyBefore = before.dirty;

        controller.undo();

        final after = projectOf(controller);
        expect(identical(after, before), isTrue);
        expect(after.dirty, dirtyBefore);
        expect(after.dirty.isClean, isTrue);
        expect(controller.state.canUndo, isFalse);
        expect(controller.state.canRedo, isFalse);
        expect(fieldInt(after, lifeFieldId), 12);
        chainLog('empty undo: project identical, dirty ${after.dirty}');
      },
    );

    test(
      'should leave project and dirty state untouched when redo is empty',
      () async {
        final controller = (await openSession('empty-redo')).controller;
        final before = projectOf(controller);
        final dirtyBefore = before.dirty;

        controller.redo();

        final after = projectOf(controller);
        expect(identical(after, before), isTrue);
        expect(after.dirty, dirtyBefore);
        expect(after.dirty.isClean, isTrue);
        expect(controller.state.canUndo, isFalse);
        expect(controller.state.canRedo, isFalse);
        expect(fieldInt(after, lifeFieldId), 12);
        chainLog('empty redo: project identical, dirty ${after.dirty}');
      },
    );
  });

  group('saving through the controller', () {
    test(
      'should clear the unsaved badge but keep the edit and history',
      () async {
        final session = await openSession('save');
        final controller = session.controller;
        controller.edit(const SetScalar(lifeFieldId, 16));
        expect(projectOf(controller).dirty.hasUnsavedChanges, isTrue);
        expect(projectOf(controller).dirty.differsFromOriginal, isTrue);

        await controller.save();

        final saved = projectOf(controller);
        expect(controller.state.status, SessionStatus.saved);
        expect(saved.dirty.hasUnsavedChanges, isFalse);
        expect(saved.dirty.isClean, isTrue);
        // Saving advances the saved baseline only; the opened original is still
        // Life 12, and the edit itself is still in the undo history.
        expect(saved.dirty.differsFromOriginal, isTrue);
        expect(saved.dirty.changedFieldCount, 1);
        expect(fieldInt(saved, lifeFieldId), 16);
        expect(saved.history.canUndo, isTrue);

        final disk = File('${session.root}/slot_00/progress.sav')
            .readAsBytesSync();
        expect(hexU32(disk, lifeValueOffset(schema)), '10 00 00 00');
        chainLog(
          'save: unsaved=false differsFromOriginal=true canUndo=true '
          'disk Life=${hexU32(disk, lifeValueOffset(schema))}',
        );
      },
    );
  });

  group('EditHistory bounded depth', () {
    test('should install the production 100-entry default on parse', () async {
      final controller = (await openSession('depth-default')).controller;
      final project = projectOf(controller);

      expect(project.history.undoStack.maxDepth, 100);
      expect(project.history.redoStack.maxDepth, 100);
      expect(project.history.undoStack.length, 0);
      chainLog(
        'parsed project history depth='
        '${project.history.undoStack.maxDepth}',
      );
    });

    test('should evict the oldest entry at maxDepth 3 and keep it applied', () async {
      final controller = (await openSession('depth-evict')).controller;
      final engine = createProgressEngine();
      // Mirrors `SaveEngine._copyProject` (save_engine.dart:1362-1381): every
      // parsed field, with `history` swapped for a bounded instance so the real
      // eviction path in `HistoryStack.push` is exercised.
      final bounded = _withHistory(
        projectOf(controller),
        EditHistory(maxDepth: 3),
      );

      // Four distinct fields: Life, rupee, MaxLife, defense. Distinct fields
      // never coalesce, so each `apply` pushes exactly one entry.
      final commands = <EditCommand>[
        const SetScalar(lifeFieldId, 16),
        const SetScalar(rupeeFieldId, 42),
        const SetScalar(maxLifeFieldId, 16),
        const SetScalar(defenseFieldId, 1),
      ];
      var project = bounded;
      for (var i = 0; i < commands.length; i++) {
        final next = engine.apply(project, commands[i]);
        expect(
          identical(next, project),
          isFalse,
          reason: 'edit $i was a no-op; eviction needs four real edits',
        );
        project = next;
      }

      expect(project.history.undoStack.maxDepth, 3);
      expect(project.history.undoStack.length, 3);
      expect(
        project.history.changelist.map((entry) => entry.command).toList(),
        <EditCommand?>[commands[1], commands[2], commands[3]],
      );
      chainLog(
        'maxDepth=3 after ${commands.length} edits: '
        'undo=${project.history.undoStack.length} '
        'oldest kept=${project.history.changelist.first.label}',
      );

      for (var i = 0; i < 3; i++) {
        project = engine.undo(project);
      }

      expect(project.history.canUndo, isFalse);
      // The evicted Life edit is permanently applied and cannot be undone.
      expect(fieldInt(project, lifeFieldId), 16);
      expect(fieldInt(project, rupeeFieldId), 0);
      expect(fieldInt(project, maxLifeFieldId), 12);
      expect(project.dirty.changedFieldCount, 1);
      expect(project.dirty.changedFields, <FieldId>{lifeFieldId});
      expect(project.dirty.hasUnsavedChanges, isTrue);
      chainLog(
        'three undos: canUndo=false Life=16 (evicted, still applied) '
        'dirty=${project.dirty.hasUnsavedChanges} '
        'changedFields=${project.dirty.changedFieldCount}',
      );
    });
  });
}

/// The open project, failing loudly when the session has none.
SaveProject projectOf(SaveSessionController controller) {
  final project = controller.state.project;
  expect(project, isNotNull, reason: 'session has no open project');
  return project!;
}

/// Returns [project] with [history] installed and no other field changed.
///
/// This is the test-local mirror of `SaveEngine._copyProject`
/// (`lib/domain/engine/save_engine.dart:1362-1381`), which is private; every
/// field of the parsed project is carried over verbatim.
SaveProject _withHistory(SaveProject project, EditHistory history) =>
    SaveProject(
      project.projectId,
      project.rootPath,
      project.backupPath,
      project.layout,
      project.detectedVersion,
      project.originals,
      project.documents,
      project.savedFingerprints,
      history,
      project.editLog,
      savedSnapshots: project.savedSnapshots,
      preserveUnknown: project.preserveUnknown,
    );
