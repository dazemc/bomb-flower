import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/engine/engine.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/core/fixtures.dart';

final class FakeSaveRepository implements SaveRepository {
  FakeSaveRepository(this.project);

  SaveProject project;
  ParseResult? openResult;
  ExportResult? exportResult;
  bool throwOnOpen = false;
  bool throwOnReset = false;
  int openCalls = 0;
  int writeExportCalls = 0;
  int resetCalls = 0;
  int duplicateCalls = 0;
  bool lastAllowOverwrite = false;
  ExportPlan? lastPlan;

  @override
  Future<ParseResult> open(
    String rootPath, {
    bool preserveUnknown = true,
    bool verifyIntegrity = true,
  }) async {
    openCalls++;
    if (throwOnOpen) {
      throw StateError('injected open failure');
    }
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
    lastAllowOverwrite = allowOverwrite;
    final injected = exportResult;
    if (injected != null) {
      return injected;
    }
    return ExportResult(
      succeeded: true,
      project: plan.project,
      writtenPaths: <SaveSlotId, String>{
        for (final entry in plan.writes.entries)
          entry.key:
              '${plan.destinationRoot}/'
              '${plan.project.layout.slot(entry.key)!.relativePath}',
      },
      fingerprints: <SaveSlotId, int>{
        for (final entry in plan.writes.entries)
          entry.key: entry.value.fingerprint,
      },
    );
  }

  @override
  Future<SaveProject> reset(
    SaveProject project,
    SaveSlotId slot, {
    bool clearHistory = false,
  }) async {
    resetCalls++;
    if (throwOnReset) {
      throw const OriginalBackupException(
        ValidationCodes.backupConflict,
        'injected sidecar failure',
      );
    }
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
    lastAllowOverwrite = allowOverwrite;
    return ExportResult(
      succeeded: true,
      writtenPaths: <SaveSlotId, String>{
        slot: '$destinationRoot/slot_00/progress.sav',
      },
      fingerprints: <SaveSlotId, int>{slot: 7},
      project: project,
    );
  }
}

final class FakeLayoutResolver {
  FakeLayoutResolver(this.layout);

  final LayoutDescriptor layout;
  int calls = 0;
  bool unsupported = false;

  Future<LayoutSelection?> resolve(String rootPath) async {
    calls++;
    if (unsupported) {
      return null;
    }
    return LayoutSelection(layout, 7);
  }
}

({SaveEngine engine, SaveProject project, FakeSaveRepository repository})
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
    repository: FakeSaveRepository(project),
  );
}

({
  SaveSessionCubit cubit,
  FakeSaveRepository repository,
  FakeLayoutResolver resolver,
})
buildCubit() {
  final session = buildSession();
  final layout = session.project.layout;
  final resolver = FakeLayoutResolver(layout);
  final cubit = SaveSessionCubit(
    engine: session.engine,
    repository: session.repository,
    resolveLayout: resolver.resolve,
  );
  return (cubit: cubit, repository: session.repository, resolver: resolver);
}

void disposeCubit(SaveSessionCubit cubit) {
  addTearDown(() async {
    if (!cubit.isClosed) {
      await cubit.close(force: true);
    }
  });
}

SaveSessionReady ready(SaveSessionCubit cubit) {
  final state = cubit.state;
  expect(state, isA<SaveSessionReady>());
  return state as SaveSessionReady;
}

SaveSessionError errorState(SaveSessionCubit cubit) {
  final state = cubit.state;
  expect(state, isA<SaveSessionError>());
  return state as SaveSessionError;
}

Future<List<SaveSessionUiState>> recordStates(SaveSessionCubit cubit) async {
  final states = <SaveSessionUiState>[];
  final subscription = cubit.stream.listen(states.add);
  addTearDown(subscription.cancel);
  return states;
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('SaveSessionCubit open', () {
    test('starts closed', () {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      expect(harness.cubit.state, isA<SaveSessionClosed>());
      expect(harness.cubit.isEnabled, isTrue);
    });

    test('opens a project and exposes slots and validation', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);

      await harness.cubit.openPath('/save');

      final state = ready(harness.cubit);
      expect(state.project.path, '/save');
      expect(state.project.slots.length, 3);
      expect(state.project.slots.where((slot) => slot.isOpen).length, 3);
      expect(state.project.activeSlot, progressSlot);
      expect(state.project.validationSummary, 'No validation issues');
      expect(state.project.statusMessage, contains('Opened /save'));
      expect(state.project.hasUnsavedChanges, isFalse);
      expect(harness.repository.openCalls, 1);
      expect(harness.resolver.calls, 1);
    });

    test('a null layout resolver yields unsupported, not a crash', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      harness.resolver.unsupported = true;

      await harness.cubit.openPath('/mystery');

      final error = errorState(harness.cubit);
      expect(error.kind, SaveSessionErrorKind.unsupportedLayout);
      expect(error.recoverable, isFalse);
      expect(error.details, contains('/mystery'));
      expect(error.details, contains('returned no layout'));
      expect(harness.repository.openCalls, 0);
    });

    test('maps ParseUnsupported to a friendly error with details', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      harness.repository.openResult = const ParseUnsupported(
        'layout 9 is newer than supported 7',
        detectedVersion: 9,
      );

      await harness.cubit.openPath('/future');

      final error = errorState(harness.cubit);
      expect(error.kind, SaveSessionErrorKind.unsupportedLayout);
      expect(error.message, isNot(contains('Exception')));
      expect(error.details, contains('newer than supported'));
      expect(error.details, contains('detected layout version 9'));
      expect(error.details, contains('/future'));
    });

    test('maps ParseCorrupt to a damaged-save error with details', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      harness.repository.openResult = const ParseCorrupt(
        'slot_00/progress.sav is 12 bytes; layout expects 256',
        at: ByteSpan(0, 12),
      );

      await harness.cubit.openPath('/broken');

      final error = errorState(harness.cubit);
      expect(error.kind, SaveSessionErrorKind.corruptSave);
      expect(error.details, contains('layout expects 256'));
      expect(error.details, contains('ByteSpan(offset: 0, length: 12)'));
    });

    test(
      'a throwing repository becomes an ioFailure, not an exception',
      () async {
        final harness = buildCubit();
        disposeCubit(harness.cubit);
        harness.repository.throwOnOpen = true;

        await harness.cubit.openPath('/save');

        final error = errorState(harness.cubit);
        expect(error.kind, SaveSessionErrorKind.ioFailure);
        expect(error.details, contains('injected open failure'));
      },
    );

    test('refuses to replace a dirty session', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      await harness.cubit.openPath('/save');
      harness.cubit.edit(const SetScalar(healthId, 42));

      await harness.cubit.openPath('/other');

      final error = errorState(harness.cubit);
      expect(error.kind, SaveSessionErrorKind.refused);
      expect(error.message, contains('Save or close'));
      expect(harness.repository.openCalls, 1);
      expect(error.project?.path, '/save');
    });
  });

  group('SaveSessionCubit openProject', () {
    test('is null while disabled and before a folder opens', () {
      final disabled = SaveSessionCubit.disabled();
      addTearDown(() async {
        if (!disabled.isClosed) {
          await disabled.close();
        }
      });
      expect(disabled.openProject, isNull);

      final harness = buildCubit();
      disposeCubit(harness.cubit);
      expect(harness.cubit.openProject, isNull);
    });

    test('exposes the domain project after openPath', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);

      await harness.cubit.openPath('/save');

      final project = harness.cubit.openProject;
      expect(project, isNotNull);
      expect(project!.rootPath, '/save');
    });

    test('reflects an edit and the undo that follows it', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      await harness.cubit.openPath('/save');

      IntValue health() =>
          harness.cubit.openProject!
                  .document(progressSlot)!
                  .field(healthId)!
                  .value
              as IntValue;

      expect(health().value, 100);

      harness.cubit.edit(const SetScalar(healthId, 42));
      expect(health().value, 42);

      harness.cubit.undo();
      expect(health().value, 100);
    });
  });

  group('SaveSessionCubit edits', () {
    test('tracks dirty fields and slot summaries after an edit', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      await harness.cubit.openPath('/save');

      harness.cubit.edit(const SetScalar(healthId, 42));

      final project = ready(harness.cubit).project;
      expect(project.hasUnsavedChanges, isTrue);
      expect(project.changedFieldCount, 1);
      expect(project.changedByteCount, 1);
      expect(project.canUndo, isTrue);
      expect(project.activeSlot, progressSlot);
      final slot = project.slots.firstWhere(
        (candidate) => candidate.id == progressSlot,
      );
      expect(slot.isDirty, isTrue);
      expect(slot.changedFieldCount, 1);
    });

    test('undo and redo update canUndo/canRedo and the field count', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      await harness.cubit.openPath('/save');
      harness.cubit.edit(const SetScalar(healthId, 42));
      expect(ready(harness.cubit).project.canUndo, isTrue);
      expect(ready(harness.cubit).project.canRedo, isFalse);

      harness.cubit.undo();

      final afterUndo = ready(harness.cubit).project;
      expect(afterUndo.canUndo, isFalse);
      expect(afterUndo.canRedo, isTrue);
      expect(afterUndo.changedFieldCount, 0);

      harness.cubit.redo();

      final afterRedo = ready(harness.cubit).project;
      expect(afterRedo.canUndo, isTrue);
      expect(afterRedo.canRedo, isFalse);
      expect(afterRedo.changedFieldCount, 1);
    });

    test('an invalid edit reports editRefused and keeps the project', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      await harness.cubit.openPath('/save');

      harness.cubit.edit(const SetScalar(healthId, 999));

      final error = errorState(harness.cubit);
      expect(error.kind, SaveSessionErrorKind.editRefused);
      expect(error.details, contains('maximum'));
      expect(error.recoverable, isTrue);
      expect(error.project, isNotNull);
    });

    test('validate and refreshValidation keep the ready state', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      await harness.cubit.openPath('/save');

      harness.cubit.validate();
      expect(
        ready(harness.cubit).project.statusMessage,
        'Validation refreshed',
      );
      harness.cubit.refreshValidation();
      expect(
        ready(harness.cubit).project.statusMessage,
        'Validation refreshed',
      );
    });
  });

  group('SaveSessionCubit export', () {
    test('save emits saving then saved with written paths', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      await harness.cubit.openPath('/save');
      harness.cubit.edit(const SetScalar(healthId, 42));
      final states = await recordStates(harness.cubit);

      await harness.cubit.save();
      await settle();

      expect(states.whereType<SaveSessionSaving>(), isNotEmpty);
      final state = harness.cubit.state;
      expect(state, isA<SaveSessionSaved>());
      final saved = state as SaveSessionSaved;
      expect(saved.mode, ExportMode.saveInPlace);
      expect(saved.path, '/save');
      expect(saved.written, isNotEmpty);
      expect(saved.written.map((write) => write.slot), contains(progressSlot));
      expect(
        saved.written.firstWhere((write) => write.slot == progressSlot).path,
        '/save/slot_00/progress.sav',
      );
      expect(saved.written.first.fingerprint, isNotNull);
      expect(harness.repository.writeExportCalls, 1);
      expect(harness.repository.lastPlan!.mode, ExportMode.saveInPlace);
      expect(harness.repository.lastAllowOverwrite, isFalse);
    });

    test('save failure keeps the project and carries issue details', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      await harness.cubit.openPath('/save');
      harness.repository.exportResult = ExportResult.blocked(<ValidationIssue>[
        ValidationIssue(
          Severity.error,
          ValidationCodes.integrityUnconfirmed,
          'Edit touches unconfirmed integrity scheme test-scheme',
          progressSlot,
          remedy: 'Revert the edit',
        ),
      ]);

      await harness.cubit.save();

      final error = errorState(harness.cubit);
      expect(error.kind, SaveSessionErrorKind.refused);
      expect(error.recoverable, isTrue);
      expect(error.project, isNotNull);
      expect(error.details, contains('integrity.unconfirmed'));
      expect(error.details, contains('Revert the edit'));
      expect(harness.repository.writeExportCalls, 1);
    });

    test('saveAs refuses the open root and records the destination', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      await harness.cubit.openPath('/save');

      await harness.cubit.saveAs('/save/');
      expect(errorState(harness.cubit).kind, SaveSessionErrorKind.refused);
      expect(harness.repository.writeExportCalls, 0);

      await harness.cubit.saveAs('/other');
      final saved = harness.cubit.state as SaveSessionSaved;
      expect(saved.mode, ExportMode.saveAs);
      expect(saved.path, '/other');
      expect(saved.written.first.path, startsWith('/other/'));
      expect(harness.repository.lastPlan!.mode, ExportMode.saveAs);
    });

    test('overwrite is only forwarded after the explicit flag', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      await harness.cubit.openPath('/save');

      await harness.cubit.saveAs('/existing');
      expect(harness.repository.lastAllowOverwrite, isFalse);

      await harness.cubit.saveAs('/existing', overwrite: true);
      expect(harness.repository.lastAllowOverwrite, isTrue);
    });

    test('duplicate reports one written slot', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      await harness.cubit.openPath('/save');

      await harness.cubit.duplicate('/copy', slot: progressSlot);

      final saved = harness.cubit.state as SaveSessionSaved;
      expect(saved.mode, ExportMode.duplicate);
      expect(saved.written.single.slot, progressSlot);
      expect(saved.written.single.fingerprint, 7);
      expect(harness.repository.duplicateCalls, 1);
    });

    test('reset requires confirmation and reports the result', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      await harness.cubit.openPath('/save');

      await harness.cubit.reset(slot: progressSlot);
      expect(errorState(harness.cubit).kind, SaveSessionErrorKind.refused);
      expect(harness.repository.resetCalls, 0);

      await harness.cubit.reset(slot: progressSlot, confirm: true);
      expect(harness.repository.resetCalls, 1);
      expect(ready(harness.cubit).project.statusMessage, contains('Restored'));
    });

    test('a throwing reset becomes a friendly error', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      await harness.cubit.openPath('/save');
      harness.repository.throwOnReset = true;

      await harness.cubit.reset(slot: progressSlot, confirm: true);

      final error = errorState(harness.cubit);
      expect(error.kind, SaveSessionErrorKind.refused);
      expect(error.details, contains('injected sidecar failure'));
    });
  });

  group('SaveSessionCubit close guard', () {
    test('close on a dirty project blocks and keeps the project', () async {
      final harness = buildCubit();
      await harness.cubit.openPath('/save');
      harness.cubit.edit(const SetScalar(healthId, 42));

      await harness.cubit.close();

      final state = harness.cubit.state;
      expect(state, isA<SaveSessionPendingDiscard>());
      final pending = state as SaveSessionPendingDiscard;
      expect(pending.project.changedFieldCount, 1);
      expect(harness.cubit.isClosed, isFalse);
      expect(harness.repository.writeExportCalls, 0);

      harness.cubit.confirmDiscard();
      await settle();
      expect(harness.cubit.state, isA<SaveSessionClosed>());
      expect(harness.cubit.isClosed, isTrue);
    });

    test('cancelDiscard returns to the editor', () async {
      final harness = buildCubit();
      disposeCubit(harness.cubit);
      await harness.cubit.openPath('/save');
      harness.cubit.edit(const SetScalar(healthId, 42));
      await harness.cubit.close();
      expect(harness.cubit.state, isA<SaveSessionPendingDiscard>());

      harness.cubit.cancelDiscard();

      expect(ready(harness.cubit).project.changedFieldCount, 1);
    });

    test('force close discards explicitly', () async {
      final harness = buildCubit();
      await harness.cubit.openPath('/save');
      harness.cubit.edit(const SetScalar(healthId, 42));

      await harness.cubit.close(force: true);

      expect(harness.cubit.state, isA<SaveSessionClosed>());
      expect(harness.cubit.isClosed, isTrue);
    });

    test('close on a clean project closes immediately', () async {
      final harness = buildCubit();
      await harness.cubit.openPath('/save');

      await harness.cubit.close();

      expect(harness.cubit.state, isA<SaveSessionClosed>());
      expect(harness.cubit.isClosed, isTrue);
    });
  });

  group('SaveSessionCubit disabled', () {
    test('never throws and reports disabled for every action', () async {
      final cubit = SaveSessionCubit.disabled();
      addTearDown(() async {
        if (!cubit.isClosed) {
          await cubit.close();
        }
      });

      await cubit.openPath('/save');
      expect(errorState(cubit).kind, SaveSessionErrorKind.disabled);

      await cubit.save();
      expect(errorState(cubit).kind, SaveSessionErrorKind.disabled);

      cubit.edit(const SetScalar(healthId, 1));
      expect(errorState(cubit).kind, SaveSessionErrorKind.disabled);
      expect(cubit.isEnabled, isFalse);
    });
  });
}
