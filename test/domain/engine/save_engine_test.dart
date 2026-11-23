import 'dart:typed_data';

import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/fixtures.dart';

final class MemorySlotSource implements SlotSource {
  MemorySlotSource({this.rootPath = '/save', Map<SaveSlotId, Uint8List>? files})
    : files = files ?? <SaveSlotId, Uint8List>{};

  final String rootPath;
  final Map<SaveSlotId, Uint8List> files;
  int reads = 0;
  int writes = 0;
  int writeAllCalls = 0;
  bool failWrite = false;
  bool corruptWrites = false;

  @override
  Future<Uint8List?> read(SaveSlotId slot) async {
    reads++;
    return files[slot];
  }

  @override
  Future<void> write(
    SaveSlotId slot,
    Uint8List bytes, {
    bool keepPreviousVersion = true,
  }) async {
    writes++;
    if (failWrite) {
      throw StateError('injected write failure');
    }
    files[slot] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeAll(
    Map<SaveSlotId, Uint8List> writesBySlot, {
    bool keepPreviousVersion = true,
  }) async {
    writeAllCalls++;
    for (final entry in writesBySlot.entries) {
      writes++;
      if (failWrite) {
        throw StateError('injected batch write failure');
      }
      final bytes = Uint8List.fromList(entry.value);
      if (corruptWrites) {
        bytes[0] ^= 0xff;
      }
      files[entry.key] = bytes;
    }
  }

  @override
  String pathFor(SaveSlotId slot) => '$rootPath/${slot.value}.sav';
}

final class MemoryOriginalStore implements OriginalStore {
  final Map<SaveSlotId, Uint8List> stored = <SaveSlotId, Uint8List>{};
  int ensureCalls = 0;
  int readCalls = 0;
  bool conflict = false;

  @override
  String get rootPath => '/save.bombflower-original';

  @override
  Future<void> ensure(
    Map<SaveSlotId, ByteRegion> originals,
    BackupPolicy policy,
  ) async {
    ensureCalls++;
    if (conflict) {
      throw const OriginalBackupException(
        ValidationCodes.backupConflict,
        'injected sidecar conflict',
      );
    }
    for (final entry in originals.entries) {
      stored[entry.key] = entry.value.materialize();
    }
  }

  @override
  Future<Uint8List?> read(SaveSlotId slot) async {
    readCalls++;
    return stored[slot];
  }

  @override
  Future<bool> verify(Map<SaveSlotId, ByteRegion> originals) async {
    for (final entry in originals.entries) {
      final storedBytes = stored[entry.key];
      if (storedBytes == null ||
          !bytesEqual(storedBytes, entry.value.materialize())) {
        return false;
      }
    }
    return true;
  }
}

final class FakeRecomputer implements IntegrityRecomputer {
  FakeRecomputer({this.verifyResult = true, this.canRecompute = true});

  bool verifyResult;
  bool canRecompute;
  int recomputeCalls = 0;
  int verifyCalls = 0;

  @override
  Uint8List? recompute(IntegritySpec spec, ByteRegion content) {
    recomputeCalls++;
    if (!canRecompute) {
      return null;
    }
    return Uint8List.fromList(<int>[0xab, 0xcd]);
  }

  @override
  bool? verify(IntegritySpec spec, ByteRegion content) {
    verifyCalls++;
    return verifyResult;
  }
}

bool bytesEqual(List<int> a, List<int> b) {
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

List<int> diffIndices(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  final result = <int>[];
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      result.add(i);
    }
  }
  return result;
}

SaveProject projectOf(ParseResult result) {
  switch (result) {
    case ParseOk(:final project):
      return project;
    case ParseUnverified(:final project):
      return project;
    case ParseUnsupported(:final reason):
      fail('Expected a project, got ParseUnsupported: $reason');
    case ParseCorrupt(:final reason):
      fail('Expected a project, got ParseCorrupt: $reason');
  }
}

({SaveEngine engine, SaveProject project}) openEngine({
  bool includeUnverified = false,
  bool includeUncited = false,
  List<IntegritySpec> integrity = const <IntegritySpec>[],
  IntegrityRecomputer? recomputer,
  Uint8List? progress,
  bool preserveUnknown = true,
  bool verifyIntegrity = true,
}) {
  final layout = testLayout(
    includeUnverified: includeUnverified,
    includeUncited: includeUncited,
    integrity: integrity,
  );
  final engine = SaveEngine(
    testFormat(
      includeUnverified: includeUnverified,
      includeUncited: includeUncited,
      integrity: integrity,
    ),
    integrityRecomputer: recomputer,
    clock: () => DateTime.utc(2026, 1, 1),
  );
  final result = engine.parse(
    rootPath: '/save',
    files: testFiles(layout: layout, progress: progress),
    layout: layout,
    detectedVersion: 7,
    preserveUnknown: preserveUnknown,
    verifyIntegrity: verifyIntegrity,
    projectId: 'project-1',
  );
  return (engine: engine, project: projectOf(result));
}

void main() {
  group('parse/open', () {
    test('parses a complete project and records an open audit entry', () {
      final opened = openEngine();
      final project = opened.project;

      expect(project.projectId, 'project-1');
      expect(project.rootPath, '/save');
      expect(project.documents.length, 3);
      expect(project.originals.length, 3);
      expect(project.savedFingerprints.length, 3);
      expect(project.history.canUndo, isFalse);
      expect(project.editLog.records.length, 1);
      expect(project.editLog.records.single.kind, EditKind.open);
      expect(project.editLog.records.single.byteCount, 64 + 32 + 256);
      expect(project.dirty.isClean, isTrue);
    });

    test('open reads but never writes', () async {
      final layout = testLayout(includeUnverified: false);
      final source = MemorySlotSource(
        files: <SaveSlotId, Uint8List>{
          for (final entry in testFiles(layout: layout).entries)
            entry.key: entry.value.materialize(),
        },
      );
      final engine = SaveEngine(testFormat(includeUnverified: false));

      final result = await engine.open(
        rootPath: '/save',
        source: source,
        layout: layout,
        detectedVersion: 7,
      );

      expect(result, isA<ParseOk>());
      expect(source.reads, 3);
      expect(source.writes, 0);
      expect(source.writeAllCalls, 0);
    });

    test('reports unverified fields without failing the open', () {
      final opened = openEngine(includeUnverified: true);
      final engine = SaveEngine(testFormat(includeUnverified: true));
      final result = engine.parse(
        rootPath: '/save',
        files: testFiles(layout: testLayout(includeUnverified: true)),
        layout: testLayout(includeUnverified: true),
        detectedVersion: 7,
      );

      expect(result, isA<ParseUnverified>());
      expect((result as ParseUnverified).unverifiedFields, contains(unknownId));
      expect(opened.project.dirty.isClean, isTrue);
    });

    test('rejects unsupported versions without a project', () {
      final engine = SaveEngine(testFormat());
      final result = engine.parse(
        rootPath: '/save',
        files: testFiles(),
        detectedVersion: 8,
      );

      expect(result, isA<ParseUnsupported>());
      expect((result as ParseUnsupported).detectedVersion, 8);
    });

    test('rejects a missing slot as corrupt', () async {
      final layout = testLayout(includeUnverified: false);
      final source = MemorySlotSource(
        files: <SaveSlotId, Uint8List>{
          SaveSlotId.account: accountBytes(),
          progressSlot: progressBytes(),
        },
      );
      final engine = SaveEngine(testFormat(includeUnverified: false));

      final result = await engine.open(
        rootPath: '/save',
        source: source,
        layout: layout,
        detectedVersion: 7,
      );

      expect(result, isA<ParseCorrupt>());
      expect((result as ParseCorrupt).reason, contains('option.sav'));
      expect(source.writes, 0);
    });

    test('rejects a length that contradicts the layout', () {
      final layout = testLayout(includeUnverified: false);
      final engine = SaveEngine(testFormat(includeUnverified: false));
      final result = engine.parse(
        rootPath: '/save',
        files: testFiles(layout: layout, progress: Uint8List(255)),
        layout: layout,
        detectedVersion: 7,
      );

      expect(result, isA<ParseCorrupt>());
      expect((result as ParseCorrupt).reason, contains('255'));
    });

    test('diagnostic preserveUnknown=false opens but blocks export', () {
      final opened = openEngine(preserveUnknown: false);
      final result = opened.engine.validateResult(opened.project);

      expect(result.hasBlockingErrors, isTrue);
      expect(
        result.issues.any(
          (issue) =>
              issue.code == ValidationCodes.layoutUnsupported &&
              issue.message.contains('preserveUnknown'),
        ),
        isTrue,
      );
    });
  });

  group('apply', () {
    test('changes exactly the declared span and bumps revision once', () {
      final opened = openEngine();
      final before = opened.project.documents[progressSlot]!.snapshot;
      final updated = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final after = updated.documents[progressSlot]!.snapshot;

      expect(diffIndices(before.materialize(), after.materialize()), <int>[11]);
      expect(after.materialize()[10], 0);
      expect(after.materialize()[11], 42);
      expect(after.revision, before.revision + 1);
      expect(updated.dirty.hasUnsavedChanges, isTrue);
      expect(updated.dirty.differsFromOriginal, isTrue);
      expect(updated.dirty.changedFields, contains(healthId));
      expect(updated.dirty.dirtySlots, contains(progressSlot));
      expect(updated.dirty.changedByteCount, 1);
      expect(updated.history.canUndo, isTrue);
      expect(updated.editLog.last!.kind, EditKind.apply);
      expect(updated.editLog.last!.command, const SetScalar(healthId, 42));
      expect(updated.editLog.last!.byteCount, 1);
    });

    test('a no-op edit returns the same project instance', () {
      final opened = openEngine();
      final same = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 100),
      );

      expect(identical(same, opened.project), isTrue);
      expect(same.history.canUndo, isFalse);
      expect(same.editLog.records.length, 1);
    });

    test('SetBit changes one byte only', () {
      final opened = openEngine();
      final before = opened.project.documents[progressSlot]!.snapshot
          .materialize();
      final updated = opened.engine.apply(
        opened.project,
        const SetBit(flagsId, 7, true),
      );
      final after = updated.documents[progressSlot]!.snapshot.materialize();

      expect(diffIndices(before, after), <int>[20]);
      expect(after[20], 0x80);
    });

    test('SetEnum writes the raw choice', () {
      final opened = openEngine();
      final updated = opened.engine.apply(
        opened.project,
        const SetEnum(modeId, 'adult'),
      );

      expect(updated.documents[progressSlot]!.snapshot.materialize()[30], 2);
      expect(updated.dirty.changedFields, contains(modeId));
    });

    test('SetBytes is bounded by the field span', () {
      final opened = openEngine();
      final updated = opened.engine.apply(
        opened.project,
        SetBytes(
          nameId,
          target: const ByteSpan(40, 4),
          bytes: <int>[0x41, 0x42, 0x43, 0x00],
        ),
      );

      expect(
        updated.documents[progressSlot]!.snapshot.materialize().sublist(40, 44),
        <int>[0x41, 0x42, 0x43, 0x00],
      );
    });

    test('rejects every invalid command atomically (invariant d)', () {
      final opened = openEngine(includeUnverified: true);
      final project = opened.project;
      final before = project.documents[progressSlot]!.snapshot;
      final beforeBytes = before.materialize();
      final revision = before.revision;

      final attempts = <EditCommand>[
        const SetScalar(healthId, 101),
        const SetScalar(healthId, -1),
        const SetScalar(unknownId, 1),
        const SetBit(flagsId, 8, true),
        const SetBit(flagsId, -1, true),
        const SetEnum(modeId, 'missing'),
        SetBytes(nameId, target: const ByteSpan(48, 1), bytes: <int>[0]),
        SetBytes(nameId, target: const ByteSpan(40, 2), bytes: <int>[1]),
      ];

      for (final command in attempts) {
        expect(
          () => opened.engine.apply(project, command),
          throwsA(isA<FieldWriteException>()),
          reason: '$command must be rejected',
        );
        expect(
          project.documents[progressSlot]!.snapshot.materialize(),
          beforeBytes,
          reason: '$command must not change bytes',
        );
        expect(
          project.documents[progressSlot]!.snapshot.revision,
          revision,
          reason: '$command must not bump revision',
        );
        expect(
          project.history.canUndo,
          isFalse,
          reason: '$command must not touch history',
        );
      }
    });

    test('unknown fields are rejected with a stable code', () {
      final opened = openEngine();
      expect(
        () => opened.engine.apply(
          opened.project,
          const SetScalar(FieldId('missing'), 1),
        ),
        throwsA(
          isA<FieldWriteException>().having(
            (error) => error.code,
            'code',
            FieldWriteCodes.unknown,
          ),
        ),
      );
    });
  });

  group('undo and redo (invariant c)', () {
    test('undo restores byte-identical bytes and redo restores the edit', () {
      final opened = openEngine();
      final before = opened.project.documents[progressSlot]!.snapshot;
      final beforeBytes = before.materialize();
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final afterBytes = edited.documents[progressSlot]!.snapshot.materialize();

      final undone = opened.engine.undo(edited);
      final undoneSnapshot = undone.documents[progressSlot]!.snapshot;
      expect(undoneSnapshot.materialize(), beforeBytes);
      expect(undoneSnapshot.revision, greaterThan(before.revision));
      expect(undone.history.canRedo, isTrue);

      final redone = opened.engine.redo(undone);
      expect(
        redone.documents[progressSlot]!.snapshot.materialize(),
        afterBytes,
      );
      expect(
        redone.documents[progressSlot]!.snapshot.revision,
        greaterThan(undoneSnapshot.revision),
      );
    });

    test('a new edit clears redo', () {
      final opened = openEngine();
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final undone = opened.engine.undo(edited);
      expect(undone.history.canRedo, isTrue);

      final newEdit = opened.engine.apply(
        undone,
        const SetScalar(healthId, 43),
      );
      expect(newEdit.history.canRedo, isFalse);
      expect(newEdit.history.canUndo, isTrue);
    });

    test('undo with an empty history returns the same project', () {
      final opened = openEngine();
      expect(
        identical(opened.engine.undo(opened.project), opened.project),
        isTrue,
      );
      expect(
        identical(opened.engine.redo(opened.project), opened.project),
        isTrue,
      );
    });

    test('a transaction is one undo step', () {
      final opened = openEngine();
      final project = opened.project;
      project.history.beginTransaction('Two edits');
      var updated = opened.engine.apply(project, const SetScalar(healthId, 42));
      updated = opened.engine.apply(updated, const SetScalar(healthId, 43));

      expect(updated.history.canUndo, isFalse);
      expect(() => opened.engine.undo(updated), throwsStateError);

      updated.history.commitTransaction();
      expect(updated.history.changelist.length, 1);
      expect(updated.history.changelist.single.commands.length, 2);

      final undone = opened.engine.undo(updated);
      expect(undone.documents[progressSlot]!.snapshot.materialize()[11], 100);
    });

    test('transaction rollback restores the pre-group snapshot', () {
      final opened = openEngine();
      final project = opened.project;
      final beforeBytes = project.documents[progressSlot]!.snapshot
          .materialize();
      project.history.beginTransaction('Rollback me');
      final edited = opened.engine.apply(
        project,
        const SetScalar(healthId, 42),
      );
      final before = edited.history.rollbackTransaction();

      expect(before, isNotNull);
      final restored = opened.engine.restoreSnapshot(edited, before!);
      expect(
        restored.documents[progressSlot]!.snapshot.materialize(),
        beforeBytes,
      );
      expect(restored.history.canUndo, isFalse);
    });
  });

  group('dirty state', () {
    test('open is clean, edit dirties both badges, undo cleans them', () {
      final opened = openEngine();
      expect(opened.project.dirty, DirtyState.clean);

      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      expect(edited.dirty.hasUnsavedChanges, isTrue);
      expect(edited.dirty.differsFromOriginal, isTrue);
      expect(edited.dirty.changedFieldCount, 1);
      expect(edited.dirty.changedByteCount, 1);

      final undone = opened.engine.undo(edited);
      expect(undone.dirty.hasUnsavedChanges, isFalse);
      expect(undone.dirty.differsFromOriginal, isFalse);
      expect(undone.dirty.changedFields, isEmpty);
    });

    test('reset returns to the original and records a synthetic entry', () {
      final opened = openEngine();
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final reset = opened.engine.resetSlotInMemory(edited, progressSlot);

      expect(reset.documents[progressSlot]!.snapshot.materialize()[11], 100);
      expect(reset.dirty.differsFromOriginal, isFalse);
      expect(reset.history.canUndo, isTrue);
      expect(reset.history.changelist.last.commands, isEmpty);
      expect(reset.editLog.last!.kind, EditKind.reset);
    });

    test('reset with clearHistory cannot be undone', () {
      final opened = openEngine();
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final reset = opened.engine.resetSlotInMemory(
        edited,
        progressSlot,
        clearHistory: true,
      );

      expect(reset.history.canUndo, isFalse);
      expect(reset.history.canRedo, isFalse);
      expect(reset.documents[progressSlot]!.snapshot.materialize()[11], 100);
    });

    test('changedSpans coalesces contiguous differences', () {
      final opened = openEngine();
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );

      expect(edited.changedSpans(progressSlot), <ByteSpan>[
        const ByteSpan(11, 1),
      ]);
    });
  });

  group('validation', () {
    ({SaveEngine engine, SaveProject project}) openRangeField(
      FieldDescriptor descriptor,
      Uint8List bytes,
    ) {
      final layout = LayoutDescriptor('range', 7, <SaveSlotLayout>[
        SaveSlotLayout(progressSlot, 'slot_00/progress.sav', <FieldDescriptor>[
          descriptor,
        ], expectedLength: 256),
      ]);
      final engine = SaveEngine(
        SaveFormat('range', 'Range', <LayoutDescriptor>[layout]),
      );
      final result = engine.parse(
        rootPath: '/save',
        files: <SaveSlotId, ByteRegion>{
          progressSlot: ByteRegion.fromBytes(bytes),
        },
        layout: layout,
        detectedVersion: 7,
      );
      return (engine: engine, project: projectOf(result));
    }

    test('a signed Int field holding -1 is inside its declared range', () {
      const descriptor = FieldDescriptor(
        FieldId('progress.signed'),
        progressSlot,
        'Signed',
        FieldKind.integer,
        ByteSpan(70, 4),
        FieldConfidence.verified,
        'test/domain/engine/save_engine_test.dart',
        endianness: Endian.little,
        min: -2147483648,
        max: 2147483647,
      );
      final bytes = progressBytes()
        ..setRange(70, 74, <int>[0xff, 0xff, 0xff, 0xff]);
      final opened = openRangeField(descriptor, bytes);

      expect(
        opened.engine
            .validateResult(opened.project)
            .issues
            .where(
              (issue) =>
                  issue.code == ValidationCodes.fieldOutOfRange &&
                  issue.field == descriptor.id,
            ),
        isEmpty,
      );
    });

    test('the same bytes on an unsigned field are still out of range', () {
      const descriptor = FieldDescriptor(
        FieldId('progress.unsigned'),
        progressSlot,
        'Unsigned',
        FieldKind.integer,
        ByteSpan(70, 4),
        FieldConfidence.verified,
        'test/domain/engine/save_engine_test.dart',
        endianness: Endian.little,
        min: 0,
        max: 100,
      );
      final bytes = progressBytes()
        ..setRange(70, 74, <int>[0xff, 0xff, 0xff, 0xff]);
      final opened = openRangeField(descriptor, bytes);

      expect(
        opened.engine
            .validateResult(opened.project)
            .issues
            .where(
              (issue) =>
                  issue.code == ValidationCodes.fieldOutOfRange &&
                  issue.field == descriptor.id,
            )
            .single
            .message,
        contains('4294967295'),
      );
    });

    test('valid verified project has no blocking issues', () {
      final opened = openEngine();
      expect(
        opened.engine.validateResult(opened.project).hasBlockingErrors,
        isFalse,
      );
    });

    test('unverified fields are warnings, not blockers', () {
      final opened = openEngine(includeUnverified: true);
      final result = opened.engine.validateResult(opened.project);

      expect(result.hasBlockingErrors, isFalse);
      expect(
        result.issues.any(
          (issue) =>
              issue.code == ValidationCodes.fieldUnverified &&
              issue.severity == Severity.warning &&
              issue.field == unknownId,
        ),
        isTrue,
      );
    });

    test('a verified field without a citation is a blocking error', () {
      final opened = openEngine(includeUncited: true);
      final result = opened.engine.validateResult(opened.project);

      expect(result.hasBlockingErrors, isTrue);
      expect(
        result.issues.any(
          (issue) =>
              issue.code == ValidationCodes.fieldUnverified &&
              issue.field == const FieldId('player.uncited'),
        ),
        isTrue,
      );
    });

    test('a version mismatch is blocking', () {
      final opened = openEngine();
      final project = SaveProject(
        opened.project.projectId,
        opened.project.rootPath,
        opened.project.backupPath,
        opened.project.layout,
        6,
        opened.project.originals,
        opened.project.documents,
        opened.project.savedFingerprints,
        opened.project.history,
        opened.project.editLog,
      );

      expect(
        opened.engine
            .validate(project)
            .any((issue) => issue.code == ValidationCodes.layoutUnsupported),
        isTrue,
      );
    });

    test('an invalid field span is blocking', () {
      final layout = LayoutDescriptor('bad', 7, <SaveSlotLayout>[
        SaveSlotLayout(progressSlot, 'slot_00/progress.sav', <FieldDescriptor>[
          const FieldDescriptor(
            healthId,
            progressSlot,
            'Bad',
            FieldKind.integer,
            ByteSpan(10, 300),
            FieldConfidence.verified,
            'test',
          ),
        ], expectedLength: 256),
      ]);
      final engine = SaveEngine(
        SaveFormat('bad', 'Bad', <LayoutDescriptor>[layout]),
      );
      final result = engine.parse(
        rootPath: '/save',
        files: <SaveSlotId, ByteRegion>{
          progressSlot: ByteRegion.fromBytes(progressBytes()),
        },
        layout: layout,
        detectedVersion: 7,
      );
      final project = projectOf(result);

      expect(
        engine
            .validate(project)
            .any((issue) => issue.code == ValidationCodes.fieldSpanInvalid),
        isTrue,
      );
    });

    test('an edit touching unconfirmed integrity blocks export', () {
      final opened = openEngine(integrity: <IntegritySpec>[testIntegrity()]);
      final unedited = opened.engine.validateResult(opened.project);
      expect(unedited.hasBlockingErrors, isFalse);

      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final result = opened.engine.validateResult(edited);

      expect(result.hasBlockingErrors, isTrue);
      expect(
        result.issues.any(
          (issue) =>
              issue.code == ValidationCodes.integrityUnconfirmed &&
              issue.severity == Severity.error,
        ),
        isTrue,
      );
      expect(
        opened.engine
            .planExport(
              edited,
              destinationRoot: '/save',
              mode: ExportMode.saveInPlace,
            )
            .isSafe,
        isFalse,
      );
    });

    test('a confirmed scheme with a recomputer patches only its region', () {
      final recomputer = FakeRecomputer();
      final opened = openEngine(
        integrity: <IntegritySpec>[
          testIntegrity(confidence: FieldConfidence.verified),
        ],
        recomputer: recomputer,
      );
      final before = opened.project.documents[progressSlot]!.snapshot
          .materialize();
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final after = edited.documents[progressSlot]!.snapshot.materialize();

      expect(recomputer.recomputeCalls, 1);
      expect(after.sublist(250, 252), <int>[0xab, 0xcd]);
      expect(diffIndices(before, after), <int>[11, 250, 251]);
      expect(opened.engine.validateResult(edited).hasBlockingErrors, isFalse);
    });

    test('a recomputer that cannot produce bytes blocks export', () {
      final opened = openEngine(
        integrity: <IntegritySpec>[
          testIntegrity(confidence: FieldConfidence.verified),
        ],
        recomputer: FakeRecomputer(canRecompute: false),
        verifyIntegrity: false,
      );
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final result = opened.engine.validateResult(edited);

      expect(result.hasBlockingErrors, isTrue);
      expect(
        result.issues.any(
          (issue) => issue.code == ValidationCodes.integrityUnconfirmed,
        ),
        isTrue,
      );
    });

    test('a failed integrity verification is blocking', () {
      final opened = openEngine(
        integrity: <IntegritySpec>[
          testIntegrity(confidence: FieldConfidence.verified),
        ],
        recomputer: FakeRecomputer(verifyResult: false),
        verifyIntegrity: false,
      );
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );

      expect(
        opened.engine
            .validate(edited)
            .any((issue) => issue.code == ValidationCodes.checksumMismatch),
        isTrue,
      );
    });

    test('root and backup path collision is blocking', () {
      final opened = openEngine();
      final project = SaveProject(
        opened.project.projectId,
        '/save',
        '/save',
        opened.project.layout,
        opened.project.detectedVersion,
        opened.project.originals,
        opened.project.documents,
        opened.project.savedFingerprints,
        opened.project.history,
        opened.project.editLog,
      );

      expect(
        opened.engine
            .validate(project)
            .any((issue) => issue.code == ValidationCodes.pathConflict),
        isTrue,
      );
    });
  });

  group('export planning', () {
    test('in-place plan writes current documents', () {
      final opened = openEngine();
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final plan = opened.engine.planExport(
        edited,
        destinationRoot: '/save',
        mode: ExportMode.saveInPlace,
      );

      expect(plan.isSafe, isTrue);
      expect(plan.slots, <SaveSlotId>{
        SaveSlotId.account,
        SaveSlotId.options,
        progressSlot,
      });
      expect(plan.writes[progressSlot]!.materialize()[11], 42);
      expect(plan.requiresIntegrityRecompute, isFalse);
    });

    test('in-place destination must equal the open root', () {
      final opened = openEngine();
      final plan = opened.engine.planExport(
        opened.project,
        destinationRoot: '/elsewhere',
        mode: ExportMode.saveInPlace,
      );

      expect(plan.isSafe, isFalse);
      expect(
        plan.blockingIssues.any(
          (issue) => issue.code == ValidationCodes.pathConflict,
        ),
        isTrue,
      );
    });

    test('save-as rejects overlapping destinations', () {
      final opened = openEngine();
      for (final destination in <String>[
        '/save',
        '/save.bombflower-original',
        '/save/slot_00',
        '',
      ]) {
        final plan = opened.engine.planExport(
          opened.project,
          destinationRoot: destination,
          mode: ExportMode.saveAs,
        );
        expect(plan.isSafe, isFalse, reason: destination);
      }
    });

    test('duplicate plans the original bytes, not edits', () {
      final opened = openEngine();
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final plan = opened.engine.planExport(
        edited,
        destinationRoot: '/duplicate',
        mode: ExportMode.duplicate,
      );

      expect(plan.isSafe, isTrue);
      expect(plan.writes[progressSlot]!.materialize()[11], 100);
    });
  });

  group('export', () {
    test(
      'writes atomically through the ports and updates saved state',
      () async {
        final opened = openEngine();
        final edited = opened.engine.apply(
          opened.project,
          const SetScalar(healthId, 42),
        );
        final source = MemorySlotSource(
          files: <SaveSlotId, Uint8List>{
            for (final entry in testFiles(
              layout: testLayout(includeUnverified: false),
            ).entries)
              entry.key: entry.value.materialize(),
          },
        );
        final originals = MemoryOriginalStore();
        final plan = opened.engine.planExport(
          edited,
          destinationRoot: '/save',
          mode: ExportMode.saveInPlace,
        );

        final result = await opened.engine.export(
          plan,
          source: source,
          originals: originals,
        );

        expect(result.succeeded, isTrue);
        expect(source.writeAllCalls, 1);
        expect(originals.ensureCalls, 1);
        expect(result.writtenPaths.length, 3);
        expect(result.fingerprints.length, 3);
        expect(result.fingerprints[progressSlot], isNotNull);
        expect(result.project, isNotNull);
        expect(result.project!.dirty.hasUnsavedChanges, isFalse);
        expect(result.project!.dirty.differsFromOriginal, isTrue);
        expect(result.project!.editLog.last!.kind, EditKind.save);
        expect(source.files[progressSlot]![11], 42);
      },
    );

    test('refuses before writing when validation blocks', () async {
      final opened = openEngine(preserveUnknown: false);
      final source = MemorySlotSource();
      final originals = MemoryOriginalStore();
      final plan = opened.engine.planExport(
        opened.project,
        destinationRoot: '/save',
        mode: ExportMode.saveInPlace,
      );

      final result = await opened.engine.export(
        plan,
        source: source,
        originals: originals,
      );

      expect(result.succeeded, isFalse);
      expect(source.writeAllCalls, 0);
      expect(originals.ensureCalls, 0);
      expect(result.issues, isNotEmpty);
    });

    test('refuses before writing on a sidecar conflict', () async {
      final opened = openEngine();
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final source = MemorySlotSource();
      final originals = MemoryOriginalStore()..conflict = true;
      final plan = opened.engine.planExport(
        edited,
        destinationRoot: '/save',
        mode: ExportMode.saveInPlace,
      );

      final result = await opened.engine.export(
        plan,
        source: source,
        originals: originals,
      );

      expect(result.succeeded, isFalse);
      expect(source.writeAllCalls, 0);
      expect(
        result.issues.any(
          (issue) => issue.code == ValidationCodes.backupConflict,
        ),
        isTrue,
      );
    });

    test('reports a failed write as write.verify_failed', () async {
      final opened = openEngine();
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final source = MemorySlotSource()..failWrite = true;
      final plan = opened.engine.planExport(
        edited,
        destinationRoot: '/save',
        mode: ExportMode.saveInPlace,
      );

      final result = await opened.engine.export(
        plan,
        source: source,
        originals: MemoryOriginalStore(),
      );

      expect(result.succeeded, isFalse);
      expect(
        result.issues.any(
          (issue) => issue.code == ValidationCodes.writeVerifyFailed,
        ),
        isTrue,
      );
    });

    test('post-write byte verification catches a corrupting writer', () async {
      final opened = openEngine();
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final source = MemorySlotSource()..corruptWrites = true;
      final plan = opened.engine.planExport(
        edited,
        destinationRoot: '/save',
        mode: ExportMode.saveInPlace,
      );

      final result = await opened.engine.export(
        plan,
        source: source,
        originals: MemoryOriginalStore(),
      );

      expect(result.succeeded, isFalse);
      expect(
        result.issues.any(
          (issue) => issue.code == ValidationCodes.writeVerifyFailed,
        ),
        isTrue,
      );
    });

    test(
      'save-as refuses an existing destination unless overwrite is explicit',
      () async {
        final opened = openEngine();
        final source = MemorySlotSource(
          files: <SaveSlotId, Uint8List>{progressSlot: progressBytes()},
        );
        final plan = opened.engine.planExport(
          opened.project,
          destinationRoot: '/other',
          mode: ExportMode.saveAs,
        );

        final refused = await opened.engine.export(
          plan,
          source: source,
          originals: MemoryOriginalStore(),
        );
        expect(refused.succeeded, isFalse);
        expect(source.writeAllCalls, 0);

        final accepted = await opened.engine.export(
          plan,
          source: source,
          originals: MemoryOriginalStore(),
          allowOverwrite: true,
        );
        expect(accepted.succeeded, isTrue);
      },
    );
  });

  group('reset and duplicate', () {
    test('reset restores sidecar original bytes and can be undone', () async {
      final opened = openEngine();
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final source = MemorySlotSource(
        files: <SaveSlotId, Uint8List>{
          for (final entry in testFiles(
            layout: testLayout(includeUnverified: false),
          ).entries)
            entry.key: entry.value.materialize(),
        },
      );
      source.files[progressSlot] = edited.documents[progressSlot]!.snapshot
          .materialize();
      final originals = MemoryOriginalStore();

      final reset = await opened.engine.reset(
        edited,
        progressSlot,
        source: source,
        originals: originals,
      );

      expect(source.files[progressSlot]![11], 100);
      expect(reset.documents[progressSlot]!.snapshot.materialize()[11], 100);
      expect(originals.ensureCalls, 1);
      expect(reset.history.canUndo, isTrue);
      expect(reset.editLog.last!.kind, EditKind.reset);
    });

    test(
      'reset refuses a sidecar that does not match the open original',
      () async {
        final opened = openEngine();
        final source = MemorySlotSource();
        final originals = MemoryOriginalStore()
          ..stored[progressSlot] = Uint8List(256);

        expect(
          () => opened.engine.reset(
            opened.project,
            progressSlot,
            source: source,
            originals: originals,
          ),
          throwsA(isA<OriginalBackupException>()),
        );
        expect(source.writes, 0);
      },
    );

    test('reset with clearHistory empties undo', () async {
      final opened = openEngine();
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final source = MemorySlotSource(
        files: <SaveSlotId, Uint8List>{
          progressSlot: edited.documents[progressSlot]!.snapshot.materialize(),
        },
      );
      final originals = MemoryOriginalStore();

      final reset = await opened.engine.reset(
        edited,
        progressSlot,
        source: source,
        originals: originals,
        clearHistory: true,
      );

      expect(reset.history.canUndo, isFalse);
      expect(source.files[progressSlot]![11], 100);
    });

    test('duplicate copies original bytes, not edits', () async {
      final opened = openEngine();
      final edited = opened.engine.apply(
        opened.project,
        const SetScalar(healthId, 42),
      );
      final destination = MemorySlotSource(rootPath: '/duplicate');
      final originals = MemoryOriginalStore();

      final result = await opened.engine.duplicate(
        edited,
        progressSlot,
        destinationRoot: '/duplicate',
        destination: destination,
        originals: originals,
      );

      expect(result.succeeded, isTrue);
      expect(destination.files[progressSlot]![11], 100);
      expect(destination.files[progressSlot]![11], isNot(42));
      expect(result.writtenPaths[progressSlot], '/duplicate/slot_00.sav');
      expect(result.fingerprints[progressSlot], Fnv1a.hash32(progressBytes()));
      expect(originals.ensureCalls, 1);
    });

    test(
      'duplicate refuses an existing destination without explicit overwrite',
      () async {
        final opened = openEngine();
        final destination = MemorySlotSource(
          rootPath: '/duplicate',
          files: <SaveSlotId, Uint8List>{progressSlot: progressBytes()},
        );

        final refused = await opened.engine.duplicate(
          opened.project,
          progressSlot,
          destinationRoot: '/duplicate',
          destination: destination,
          originals: MemoryOriginalStore(),
        );
        expect(refused.succeeded, isFalse);

        final accepted = await opened.engine.duplicate(
          opened.project,
          progressSlot,
          destinationRoot: '/duplicate',
          destination: destination,
          originals: MemoryOriginalStore(),
          allowOverwrite: true,
        );
        expect(accepted.succeeded, isTrue);
      },
    );
  });
}
