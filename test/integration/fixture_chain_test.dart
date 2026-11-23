/// End-to-end (no UI) chain over the real and synthetic save formats:
/// open → read → edit Life → undo → redo → save-as → reopen → exact diff.
///
/// The real-fixture group is skipped when the scrubbed Longshot samples are
/// unavailable. The synthetic and corrupt groups always run.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/adapter/progress_layout_builder.dart';
import 'package:bomb_flower/data/adapter/progress_layout_resolver.dart';
import 'package:bomb_flower/data/adapter/progress_repository.dart';
import 'package:bomb_flower/data/codec/progress_codec.dart';
import 'package:bomb_flower/data/io/sidecar_backup.dart';
import 'package:bomb_flower/data/newsave/new_save_writer.dart';
import 'package:bomb_flower/domain/core/core.dart' hide ByteRegion;
import 'package:bomb_flower/domain/engine/save_engine.dart';
import 'package:bomb_flower/domain/newsave/new_save_builder.dart';
import 'package:bomb_flower/domain/newsave/new_save_spec.dart';
import 'package:bomb_flower/domain/save/progress_layout.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/byte_assert.dart';
import '../support/fixture_loader.dart';
import 'support/progress_chain.dart';

/// One scrubbed sample folder from Longshot's `assets/saves/`.
const String realFixtureName = 'kokiri-start';

void main() {
  late GameDataSchema schema;

  setUpAll(() async {
    schema = await loadGameDataSchema();
    if (samplesAvailable) {
      await ensureSampleFixtures();
    }
  });

  test(
    'real fixture: open, edit Life, undo, redo, save-as and reopen',
    () async {
      final fixtureRoot = Directory(
        '${fixturesDirectory.path}/$realFixtureName',
      );
      final sourceSlot = Directory('${fixtureRoot.path}/slot_00');
      final sourceProgress = File('${sourceSlot.path}/progress.sav');
      final sourceCaption = File('${sourceSlot.path}/caption.sav');
      final originalProgress = Uint8List.fromList(
        await sourceProgress.readAsBytes(),
      );
      final originalCaption = Uint8List.fromList(
        await sourceCaption.readAsBytes(),
      );
      final progressStatBefore = await sourceProgress.stat();
      final captionStatBefore = await sourceCaption.stat();
      final listingBefore = directoryEntries(sourceSlot);
      final sourceSidecar = Directory(
        '${fixtureRoot.path}.bombflower-original',
      );
      final sourceSidecarBefore = sourceSidecar.existsSync();

      final engine = createProgressEngine();
      final repo = createProgressRepository(schema);

      // Stock production wiring: the real sample stores its caption at
      // slot_00/caption.sav and the factory's resolver must find it there.
      final stockOpen = await ProgressSaveRepositoryFactory(
        schema: schema,
      ).create(fixtureRoot.path).open(fixtureRoot.path);
      chainLog(
        'stock ProgressSaveRepositoryFactory.open -> '
        '${describeParseResult(stockOpen)}',
      );
      expect(stockOpen, isA<ParseUnverified>());

      final open = await repo.open(fixtureRoot.path);
      chainLog('open -> ${describeParseResult(open)} at ${fixtureRoot.path}');
      expect(open, isA<ParseUnverified>());
      final project = (open as ParseUnverified).project;
      expect(open.unverifiedFields, isNotEmpty);

      final document = project.document(progressSlotId);
      expect(document, isNotNull);
      expect(document!.slot, progressSlotId);
      final layout = project.slotLayout(progressSlotId);
      expect(layout, isNotNull);
      expect(layout!.relativePath, 'slot_00/progress.sav');
      expect(layout.fields, hasLength(11925));

      final originalBytes = document.snapshot.materialize();
      expect(originalBytes, hasLength(ProgressLayout.sampleFileLength));
      expect(progressRecordCount(originalBytes), 11958);
      expectByteIdentical(
        originalProgress,
        originalBytes,
        reason: 'open must expose the file bytes unchanged',
      );

      expect(
        document.field(lifeFieldId)!.value,
        const IntValue(12),
        reason: 'PlayerStatus.Life default in the sample',
      );
      expect(
        document.field(maxLifeFieldId)!.value,
        const IntValue(12),
        reason: 'PlayerStatus.MaxLife default in the sample',
      );
      expect(
        document.field(sequenceFieldId)!.value,
        const StringValue('KokiriForest_Child'),
      );

      final lifeOffset = lifeValueOffset(schema);
      expect(hexU32(originalBytes, lifeOffset), '0c 00 00 00');
      chainLog(
        'read Life=12 MaxLife=12 Sequence=KokiriForest_Child '
        'fields=11925 records=11958 bytes=${originalBytes.length} '
        'lifeOffset=0x${lifeOffset.toRadixString(16)}',
      );

      final redone = _applyLifeEditChain(
        engine: engine,
        project: project,
        original: originalBytes,
        lifeOffset: lifeOffset,
      );

      final destination = createTempDirectory(
        'bomb-flower-chain-saveas-',
      );
      final plan = engine.planExport(
        redone,
        destinationRoot: destination.path,
        mode: ExportMode.saveAs,
      );
      expect(plan.isSafe, isTrue, reason: plan.blockingIssues.join('; '));
      final result = await repo.writeExport(plan);
      expect(result.succeeded, isTrue, reason: _exportFailure(result));
      chainLog(
        'save-as -> ${destination.path} slots='
        '${result.writtenPaths.keys.map((slot) => slot.value).join(',')}',
      );

      // The source root must be untouched: bytes, mtimes, slot listing, and no
      // sidecar of its own.
      expectByteIdentical(
        originalProgress,
        Uint8List.fromList(await sourceProgress.readAsBytes()),
        reason: 'save-as must not rewrite source/progress.sav',
      );
      expectByteIdentical(
        originalCaption,
        Uint8List.fromList(await sourceCaption.readAsBytes()),
        reason: 'save-as must not rewrite source/caption.sav',
      );
      expect(
        (await sourceProgress.stat()).modified,
        progressStatBefore.modified,
        reason: 'save-as must not touch progress.sav mtime',
      );
      expect(
        (await sourceCaption.stat()).modified,
        captionStatBefore.modified,
        reason: 'save-as must not touch caption.sav mtime',
      );
      expect(directoryEntries(sourceSlot), listingBefore);
      expect(sourceSidecar.existsSync(), sourceSidecarBefore);
      chainLog(
        'source untouched: bytes/mtime/listing unchanged, '
        'no ${fixtureRoot.path}.bombflower-original',
      );

      // Save-as writes its own sidecar. The engine stores the *exported*
      // payload there (not the pre-edit original); the in-place test below
      // proves the pre-edit-original contract separately.
      final destinationSidecar = SidecarBackup(
        saveRoot: destination.path,
        layout: project.layout,
      );
      expect(destinationSidecar.inspect(), SidecarStatus.ready);
      final sidecarProgress = await destinationSidecar.read(progressSlotId);
      expect(sidecarProgress, isNotNull);
      final exported = Uint8List.fromList(
        await File('${destination.path}/slot_00/progress.sav').readAsBytes(),
      );
      expectByteIdentical(
        exported,
        sidecarProgress!,
        reason: 'save-as sidecar holds the exported payload',
      );
      expectByteIdentical(
        originalCaption,
        Uint8List.fromList(
          await File('${destination.path}/slot_00/caption.sav').readAsBytes(),
        ),
        reason: 'the unedited caption slot is exported byte for byte',
      );
      chainLog(
        'save-as sidecar ${destinationSidecar.rootPath} READY and byte-equal '
        'to the exported progress payload',
      );

      await _assertExportedChain(
        schema: schema,
        destination: destination,
        original: originalBytes,
        expectedLength: ProgressLayout.sampleFileLength,
        lifeOffset: lifeOffset,
      );
    },
    skip: samplesAvailable ? null : samplesUnavailableMessage,
  );

  test('synthetic new save runs the same chain at 120,572 bytes', () async {
    final root = createTempDirectory('bomb-flower-chain-synthetic-');
    final build = NewSaveBuilder.build(
      schema: schema,
      spec: NewSaveSpec.preset(NewSavePreset.schemaDefaults),
    );
    await NewSaveWriter().write(rootDirectory: root.path, build: build);

    expect(build.progressBytes, hasLength(120572));
    expect(build.dataOffset, 95704);
    expect(build.fieldCount, 11925);
    expect(build.recordCount, 11958);
    expect(build.sentinelCount, ProgressLayout.sentinelCount);
    chainLog(
      'synthetic build bytes=${build.progressBytes.length} '
      'dataOffset=0x${build.dataOffset.toRadixString(16)} '
      'fields=${build.fieldCount} records=${build.recordCount} '
      'sentinels=${build.sentinelCount}',
    );

    final original = Uint8List.fromList(
      await File('${root.path}/slot_00/progress.sav').readAsBytes(),
    );
    expect(progressRecordCount(original), 11958);

    final engine = createProgressEngine();
    final repo = createProgressRepository(schema);
    final open = await repo.open(root.path);
    chainLog('synthetic open -> ${describeParseResult(open)} at ${root.path}');
    expect(open, isA<ParseUnverified>());
    final project = (open as ParseUnverified).project;
    expect(fieldInt(project, lifeFieldId), 12);
    expect(fieldInt(project, maxLifeFieldId), 12);

    final lifeOffset = lifeValueOffset(schema);
    expect(hexU32(original, lifeOffset), '0c 00 00 00');

    final redone = _applyLifeEditChain(
      engine: engine,
      project: project,
      original: original,
      lifeOffset: lifeOffset,
    );

    final destination = createTempDirectory(
      'bomb-flower-chain-synthetic-saveas-',
    );
    final plan = engine.planExport(
      redone,
      destinationRoot: destination.path,
      mode: ExportMode.saveAs,
    );
    expect(plan.isSafe, isTrue, reason: plan.blockingIssues.join('; '));
    final result = await repo.writeExport(plan);
    expect(result.succeeded, isTrue, reason: _exportFailure(result));
    chainLog('synthetic save-as -> ${destination.path}');

    await _assertExportedChain(
      schema: schema,
      destination: destination,
      original: original,
      expectedLength: build.progressBytes.length,
      lifeOffset: lifeOffset,
    );
  });

  test('in-place save keeps the pre-edit original in the sidecar', () async {
    final root = createTempDirectory('bomb-flower-chain-in-place-');
    final build = NewSaveBuilder.build(
      schema: schema,
      spec: NewSaveSpec.preset(NewSavePreset.schemaDefaults),
    );
    await NewSaveWriter().write(rootDirectory: root.path, build: build);
    final progressFile = File('${root.path}/slot_00/progress.sav');
    final original = Uint8List.fromList(await progressFile.readAsBytes());

    final engine = createProgressEngine();
    final repo = createProgressRepository(schema);
    final project = _projectOf(await repo.open(root.path), 'open synthetic root');
    final edited = engine.apply(project, const SetScalar(lifeFieldId, 16));
    final editedBytes = edited
        .document(progressSlotId)!
        .snapshot
        .materialize();
    final lifeOffset = lifeValueOffset(schema);
    expect(hexU32(editedBytes, lifeOffset), '10 00 00 00');

    final plan = engine.planExport(
      edited,
      destinationRoot: root.path,
      mode: ExportMode.saveInPlace,
    );
    expect(plan.isSafe, isTrue, reason: plan.blockingIssues.join('; '));
    final result = await repo.writeExport(plan);
    expect(result.succeeded, isTrue, reason: _exportFailure(result));

    expectByteIdentical(
      editedBytes,
      Uint8List.fromList(await progressFile.readAsBytes()),
      reason: 'in-place save writes the edited bytes',
    );

    final sidecar = SidecarBackup(saveRoot: root.path, layout: project.layout);
    expect(sidecar.inspect(), SidecarStatus.ready);
    final stored = await sidecar.read(progressSlotId);
    expect(stored, isNotNull);
    expectByteIdentical(
      original,
      stored!,
      reason: 'in-place sidecar must hold the open-time original bytes',
    );
    expect(hexU32(stored, lifeOffset), '0c 00 00 00');
    chainLog(
      'in-place sidecar ${sidecar.rootPath} READY holds pre-edit original '
      '(Life 12); progress.sav now holds Life 16',
    );
  });

  test('corrupt inputs are rejected with typed results and no writes', () async {
    final build = NewSaveBuilder.build(
      schema: schema,
      spec: NewSaveSpec.preset(NewSavePreset.schemaDefaults),
    );
    final valid = build.progressBytes;
    final caption = build.captionBytes;
    final builder = ProgressLayoutBuilder(schema);
    final resolver = ProgressLayoutResolver(builder);

    // Truncated: header only, the record stream is missing.
    final truncated = Uint8List.sublistView(valid, 0, 20);
    final truncatedDecode = ProgressCodec.decode(truncated);
    expect(truncatedDecode, isA<ProgressDecodeTruncated>());
    expect((truncatedDecode as ProgressDecodeTruncated).length, 20);

    final truncatedRoot = createTempDirectory('bomb-flower-chain-truncated-');
    await _writeSlot(truncatedRoot, truncated, caption);
    final truncatedDetect = await resolver.detect(truncatedRoot.path);
    expect(truncatedDetect, isA<SaveCorrupt>());
    final truncatedOpen = await createProgressRepository(
      schema,
    ).open(truncatedRoot.path);
    expect(truncatedOpen, isA<ParseUnsupported>());
    _expectNoWrites(truncatedRoot, progressLength: 20);
    chainLog(
      'truncated 20 bytes -> ${truncatedDecode.runtimeType}, '
      'detect=${truncatedDetect.runtimeType}, '
      'open=${describeParseResult(truncatedOpen)}, writes=0',
    );

    // Wrong revision: magic is right, the u32 at 0x04 is not.
    final wrongRevision = Uint8List.fromList(valid);
    _setU32(wrongRevision, ProgressLayout.revisionOffset, 1);
    final revisionDecode = ProgressCodec.decode(wrongRevision);
    expect(revisionDecode, isA<ProgressRevisionMismatch>());
    expect((revisionDecode as ProgressRevisionMismatch).revision, 1);

    final revisionRoot = createTempDirectory('bomb-flower-chain-revision-');
    await _writeSlot(revisionRoot, wrongRevision, caption);
    final revisionDetect = await resolver.detect(revisionRoot.path);
    expect(revisionDetect, isA<SaveUnsupportedRevision>());
    expect((revisionDetect as SaveUnsupportedRevision).detected, 1);
    final revisionOpen = await createProgressRepository(
      schema,
    ).open(revisionRoot.path);
    expect(revisionOpen, isA<ParseUnsupported>());
    _expectNoWrites(revisionRoot, progressLength: wrongRevision.length);
    chainLog(
      'revision u32@0x04=1 -> ${revisionDecode.runtimeType}, '
      'detect=${revisionDetect.runtimeType}, '
      'open=${describeParseResult(revisionOpen)}, writes=0',
    );

    // Detection must also refuse a magic that is not a progress.sav at all.
    final notASave = Uint8List.fromList(valid);
    notASave[0] = 0;
    final notASaveRoot = createTempDirectory('bomb-flower-chain-notasave-');
    await _writeSlot(notASaveRoot, notASave, caption);
    final notASaveDecode = ProgressCodec.decode(notASave);
    expect(notASaveDecode, isA<ProgressBadMagic>());
    final notASaveDetect = await resolver.detect(notASaveRoot.path);
    expect(notASaveDetect, isA<SaveNotASave>());
    expect(
      (notASaveDetect as SaveNotASave).magic,
      isNot(ProgressLayout.magicValue),
    );
    _expectNoWrites(notASaveRoot, progressLength: notASave.length);
    chainLog(
      'bad magic -> ${notASaveDecode.runtimeType}, '
      'detect=${notASaveDetect.runtimeType}, writes=0',
    );
  });
}

/// Applies the shared edit → undo → redo assertions and returns the redone
/// project (Life 16, dirty against the opened original).
SaveProject _applyLifeEditChain({
  required SaveEngine engine,
  required SaveProject project,
  required Uint8List original,
  required int lifeOffset,
}) {
  final edited = engine.apply(project, const SetScalar(lifeFieldId, 16));
  final editedBytes = edited.document(progressSlotId)!.snapshot.materialize();

  expect(edited.dirty.hasUnsavedChanges, isTrue);
  expect(edited.dirty.differsFromOriginal, isTrue);
  expect(edited.dirty.changedFieldCount, 1);
  // Measured: the dirty summary counts differing bytes, not the touched field
  // width. 12 (0x0c) -> 16 (0x10) flips one byte.
  expect(edited.dirty.changedByteCount, 1);
  expect(hexU32(editedBytes, lifeOffset), '10 00 00 00');
  expectOnlyRegionsChanged(
    original,
    editedBytes,
    <ByteRegion>[
      ByteRegion(lifeOffset, lifeOffset + 4, 'PlayerStatus.Life'),
    ],
    reason: 'editing Life may only touch its 4-byte value',
  );
  final editedDiff = ByteRegionDiff.diff(original, editedBytes);
  expect(editedDiff.runs, hasLength(1));
  expect(editedDiff.runs.single.start, lifeOffset);
  expect(editedDiff.runs.single.length, 1);
  chainLog(
    'edit Life 12->16 dirty=fields:${edited.dirty.changedFieldCount},'
    'bytes:${edited.dirty.changedByteCount} '
    'value@0x${lifeOffset.toRadixString(16)}=${hexU32(editedBytes, lifeOffset)}',
  );

  final undone = engine.undo(edited);
  final undoneBytes = undone.document(progressSlotId)!.snapshot.materialize();
  expect(fieldInt(undone, lifeFieldId), 12);
  expect(undone.dirty.hasUnsavedChanges, isFalse);
  expect(undone.dirty.differsFromOriginal, isFalse);
  expectByteIdentical(
    original,
    undoneBytes,
    reason: 'undo must restore the opened bytes exactly',
  );
  chainLog('undo Life=12 dirty=false bytes identical');

  final redone = engine.redo(undone);
  expect(fieldInt(redone, lifeFieldId), 16);
  expect(redone.dirty.hasUnsavedChanges, isTrue);
  chainLog('redo Life=16 dirty=true');
  return redone;
}

/// Reopens [destination] and asserts the exported chain: length, Life/MaxLife,
/// the exact Life-only diff, and preserved sentinels/footer.
Future<SaveProject> _assertExportedChain({
  required GameDataSchema schema,
  required Directory destination,
  required Uint8List original,
  required int expectedLength,
  required int lifeOffset,
}) async {
  final exported = Uint8List.fromList(
    await File('${destination.path}/slot_00/progress.sav').readAsBytes(),
  );
  expect(exported, hasLength(expectedLength));
  expect(progressRecordCount(exported), 11958);

  final reopened = await createProgressRepository(schema).open(destination.path);
  final reopenedProject = _projectOf(reopened, 'reopen export');
  expect(fieldInt(reopenedProject, maxLifeFieldId), 12);
  expect(fieldInt(reopenedProject, lifeFieldId), 16);

  final diff = ByteRegionDiff.diff(original, exported);
  expect(diff.runs, hasLength(1), reason: 'only the Life value may differ');
  final run = diff.runs.single;
  final lifeRegion = ByteRegion(lifeOffset, lifeOffset + 4, 'PlayerStatus.Life');
  expect(run.start, lifeOffset);
  // Measured: one byte differs (0x0c -> 0x10); the field region is 4 bytes and
  // fully contains the run.
  expect(run.length, 1);
  expect(lifeRegion.contains(run.start), isTrue);
  expect(lifeRegion.contains(run.end - 1), isTrue);
  expect(hexU32(original, lifeOffset), '0c 00 00 00');
  expect(hexU32(exported, lifeOffset), '10 00 00 00');
  chainLog(
    'reopen ${describeParseResult(reopened)} len=${exported.length} '
    'Life=16 MaxLife=12 diff=0x${lifeOffset.toRadixString(16)}'
    '+${run.length} original=${hexU32(original, lifeOffset)} '
    'export=${hexU32(exported, lifeOffset)}',
  );

  final originalSentinels = progressSentinels(original);
  final exportedSentinels = progressSentinels(exported);
  expect(exportedSentinels, hasLength(ProgressLayout.sentinelCount));
  for (var index = 0; index < exportedSentinels.length; index++) {
    expect(exportedSentinels[index].key, 0);
    expect(exportedSentinels[index].value, index + 1);
  }
  expect(exportedSentinels, orderedEquals(originalSentinels));

  final originalFooter = progressFooter(original);
  final exportedFooter = progressFooter(exported);
  expect(exportedFooter.key, ProgressLayout.footerKey);
  expect(exportedFooter.value, ProgressLayout.footerValue);
  expect(exportedFooter, originalFooter);
  chainLog(
    'preserved ${exportedSentinels.length} sentinels {0,1..32} and footer '
    'key=0x${exportedFooter.key.toRadixString(16)} '
    'value=0x${exportedFooter.value.toRadixString(16)}',
  );

  return reopenedProject;
}

/// Extracts the project from a project-bearing parse result, failing otherwise.
SaveProject _projectOf(ParseResult result, String label) => switch (result) {
  ParseOk(:final project) => project,
  ParseUnverified(:final project) => project,
  _ => fail('$label failed: ${describeParseResult(result)}'),
};

/// Creates a temporary directory that teardown removes, including its sidecar.
Directory createTempDirectory(String prefix) {
  final directory = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() => _deleteTree(directory.path));
  return directory;
}

void _deleteTree(String path) {
  for (final suffix in const <String>['', '.bombflower-original']) {
    final directory = Directory('$path$suffix');
    if (!directory.existsSync()) {
      continue;
    }
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort: a leftover temp directory never affects assertions.
    }
  }
}

Future<void> _writeSlot(
  Directory root,
  Uint8List progress,
  Uint8List caption,
) async {
  final slot = Directory('${root.path}/slot_00');
  await slot.create(recursive: true);
  await File('${slot.path}/progress.sav').writeAsBytes(progress);
  await File('${slot.path}/caption.sav').writeAsBytes(caption);
}

void _setU32(Uint8List bytes, int offset, int value) {
  for (var index = 0; index < 4; index++) {
    bytes[offset + index] = (value >> (index * 8)) & 0xff;
  }
}

/// Asserts a refused open left no backup, sidecar, pending manifest, or
/// destination directory behind.
void _expectNoWrites(Directory root, {required int progressLength}) {
  final slot = Directory('${root.path}/slot_00');
  expect(directoryEntries(slot), <String>['caption.sav', 'progress.sav'],
      reason: 'a refused open must not create .bak or temp files');
  expect(File('${slot.path}/progress.sav').lengthSync(), progressLength);
  expect(Directory('${root.path}.bombflower-original').existsSync(), isFalse);
  expect(File('${root.path}/.bombflower-pending.json').existsSync(), isFalse);
  expect(Directory('${root.path}-saveas').existsSync(), isFalse);
}

String _exportFailure(ExportResult result) =>
    result.error ?? result.issues.map((issue) => issue.message).join('; ');
