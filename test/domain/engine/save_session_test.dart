import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/fixtures.dart';

final class FakeRepository implements SaveRepository {
  FakeRepository(this.project);

  final SaveProject project;
  ParseResult? openResult;
  bool failExport = false;
  int openCalls = 0;
  int writeExportCalls = 0;
  int resetCalls = 0;
  int duplicateCalls = 0;
  ExportPlan? lastPlan;

  @override
  Future<ParseResult> open(
    String rootPath, {
    bool preserveUnknown = true,
    bool verifyIntegrity = true,
  }) async {
    openCalls++;
    return openResult ?? ParseOk(project);
  }

  @override
  Future<void> ensureOriginalBackup(
    SaveProject project,
    BackupPolicy policy,
  ) async {}

  @override
  Future<ExportResult> writeExport(
    ExportPlan plan, {
    bool allowOverwrite = false,
  }) async {
    writeExportCalls++;
    lastPlan = plan;
    if (failExport) {
      return const ExportResult(succeeded: false, error: 'injected');
    }
    return ExportResult(succeeded: true, project: plan.project);
  }

  @override
  Future<SaveProject> reset(
    SaveProject project,
    SaveSlotId slot, {
    bool clearHistory = false,
  }) async {
    resetCalls++;
    return project;
  }

  @override
  Future<ExportResult> duplicate(
    SaveProject project,
    SaveSlotId slot, {
    required String destinationRoot,
    BackupPolicy policy = BackupPolicy.standard,
    bool allowOverwrite = false,
  }) async {
    duplicateCalls++;
    return ExportResult(
      succeeded: true,
      writtenPaths: <SaveSlotId, String>{
        slot: '$destinationRoot/${slot.value}.sav',
      },
      fingerprints: <SaveSlotId, int>{slot: 1},
      project: project,
    );
  }
}

({SaveEngine engine, SaveProject project, FakeRepository repository})
buildSession() {
  final layout = testLayout(includeUnverified: false);
  final engine = SaveEngine(testFormat(includeUnverified: false));
  final result = engine.parse(
    rootPath: '/save',
    files: testFiles(layout: layout),
    layout: layout,
    detectedVersion: 7,
  );
  final project = switch (result) {
    ParseOk(:final project) => project,
    _ => throw StateError('Fixture did not open'),
  };
  return (
    engine: engine,
    project: project,
    repository: FakeRepository(project),
  );
}

void main() {
  group('SaveSessionController', () {
    test('opens a project and emits ready', () async {
      final session = buildSession();
      final controller = SaveSessionController(
        engine: session.engine,
        repository: session.repository,
      );
      final states = <SaveSessionState>[];
      controller.addListener(states.add);

      await controller.open('/save');

      expect(session.repository.openCalls, 1);
      expect(controller.state.status, SessionStatus.ready);
      expect(controller.state.project, isNotNull);
      expect(states.map((state) => state.status), <SessionStatus>[
        SessionStatus.opening,
        SessionStatus.ready,
      ]);
      expect(controller.state.issues, isEmpty);
    });

    test('an open failure preserves the previous project', () async {
      final session = buildSession();
      final controller = SaveSessionController(
        engine: session.engine,
        repository: session.repository,
      );
      await controller.open('/save');
      final previous = controller.state.project;
      session.repository.openResult = const ParseCorrupt('bad folder');

      await controller.open('/bad');

      expect(controller.state.status, SessionStatus.error);
      expect(controller.state.project, previous);
      expect(controller.state.error, contains('bad folder'));
    });

    test('valid edits update state and invalid edits preserve it', () async {
      final session = buildSession();
      final controller = SaveSessionController(
        engine: session.engine,
        repository: session.repository,
      );
      await controller.open('/save');

      controller.edit(const SetScalar(healthId, 42));
      final edited = controller.state.project!;
      expect(edited.dirty.hasUnsavedChanges, isTrue);
      expect(controller.state.canUndo, isTrue);

      controller.edit(const SetScalar(healthId, 999));
      expect(controller.state.project, edited);
      expect(controller.state.error, isNotNull);
      expect(
        controller.state.project!.documents[progressSlot]!.snapshot
            .materialize()[11],
        42,
      );
    });

    test(
      'undo, redo, and transaction rollback flow through the engine',
      () async {
        final session = buildSession();
        final controller = SaveSessionController(
          engine: session.engine,
          repository: session.repository,
        );
        await controller.open('/save');
        final original = controller
            .state
            .project!
            .documents[progressSlot]!
            .snapshot
            .materialize();

        controller.edit(const SetScalar(healthId, 42));
        controller.undo();
        expect(
          controller.state.project!.documents[progressSlot]!.snapshot
              .materialize(),
          original,
        );
        expect(controller.state.canRedo, isTrue);

        controller.redo();
        expect(
          controller.state.project!.documents[progressSlot]!.snapshot
              .materialize()[11],
          42,
        );

        controller.beginTransaction('Group');
        controller.edit(const SetScalar(healthId, 43));
        controller.rollbackTransaction();
        expect(
          controller.state.project!.documents[progressSlot]!.snapshot
              .materialize()[11],
          42,
        );
        expect(controller.state.canUndo, isTrue);

        controller.undo();
        expect(
          controller.state.project!.documents[progressSlot]!.snapshot
              .materialize(),
          original,
        );
      },
    );

    test(
      'save commits an open transaction and delegates to the repository',
      () async {
        final session = buildSession();
        final controller = SaveSessionController(
          engine: session.engine,
          repository: session.repository,
        );
        await controller.open('/save');
        controller.beginTransaction('Group');
        controller.edit(const SetScalar(healthId, 42));

        await controller.save();

        expect(session.repository.writeExportCalls, 1);
        expect(session.repository.lastPlan!.mode, ExportMode.saveInPlace);
        expect(controller.state.status, SessionStatus.saved);
        expect(controller.state.project!.history.inTransaction, isFalse);
        expect(
          controller.state.project!.history.changelist.single.commands.length,
          1,
        );
      },
    );

    test('save-as and duplicate pass the destination through', () async {
      final session = buildSession();
      final controller = SaveSessionController(
        engine: session.engine,
        repository: session.repository,
      );
      await controller.open('/save');

      await controller.saveAs('/other');
      expect(session.repository.lastPlan!.destinationRoot, '/other');
      expect(session.repository.lastPlan!.mode, ExportMode.saveAs);

      await controller.duplicate('/duplicate', slot: progressSlot);
      expect(session.repository.duplicateCalls, 1);
      expect(controller.state.status, SessionStatus.saved);
    });

    test('reset delegates for the requested slot', () async {
      final session = buildSession();
      final controller = SaveSessionController(
        engine: session.engine,
        repository: session.repository,
      );
      await controller.open('/save');

      await controller.reset(slot: progressSlot, clearHistory: true);
      expect(session.repository.resetCalls, 1);
    });

    test('events dispatch to the matching operation', () async {
      final session = buildSession();
      final controller = SaveSessionController(
        engine: session.engine,
        repository: session.repository,
      );

      await controller.dispatch(const OpenSaveRequested('/save'));
      expect(controller.state.status, SessionStatus.ready);

      controller.dispatch(const FieldEditRequested(SetScalar(healthId, 42)));
      expect(controller.state.project!.dirty.hasUnsavedChanges, isTrue);

      controller.dispatch(const UndoRequested());
      expect(controller.state.canRedo, isTrue);

      controller.dispatch(const RedoRequested());
      expect(controller.state.canUndo, isTrue);

      controller.dispatch(const ValidateRequested());
      expect(controller.state.issues, isNotNull);

      controller.dispatch(const CloseRequested());
      expect(controller.state.status, SessionStatus.closed);
      expect(controller.state.project, isNull);
    });

    test('close never writes', () async {
      final session = buildSession();
      final controller = SaveSessionController(
        engine: session.engine,
        repository: session.repository,
      );
      await controller.open('/save');
      controller.close();
      expect(session.repository.writeExportCalls, 0);
      expect(controller.state.project, isNull);
    });
  });
}
