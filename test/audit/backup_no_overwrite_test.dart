/// Audit done-audit-05, criterion 8: backups and no silent overwrite.
///
/// Drives `FileSaveRepository.writeExport` → `SidecarBackup` →
/// `AtomicFileWriter` (`.bak` + temp + rename + verify). Every byte compared
/// here ends up on disk under `.tmp/audit/`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/io/sidecar_backup.dart';
import 'package:bomb_flower/data/newsave/new_save_writer.dart';
import 'package:bomb_flower/domain/core/core.dart' hide ByteRegion;
import 'package:bomb_flower/domain/newsave/new_save_builder.dart';
import 'package:bomb_flower/domain/newsave/new_save_spec.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration/support/progress_chain.dart';
import '../support/byte_assert.dart';

const String inPlaceRoot = '.tmp/audit/backup-inplace';
const String saveAsSourceRoot = '.tmp/audit/backup-saveas-source';
const String saveAsDestination = '.tmp/audit/backup-saveas-destination';

void main() {
  late GameDataSchema schema;

  setUpAll(() async {
    schema = await loadGameDataSchema();
  });

  Future<void> buildNewSave(String root) async {
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
  }

  group('criterion 8 — in-place export', () {
    test('writes .bak + sidecar before replacing; original bytes survive',
        () async {
      await buildNewSave(inPlaceRoot);
      final repo = createProgressRepository(schema);
      final project = _projectOf(await repo.open(inPlaceRoot));
      final original = project
          .document(progressSlotId)!
          .snapshot
          .materialize();
      final progressFile = File('$inPlaceRoot/slot_00/progress.sav');
      final captionFile = File('$inPlaceRoot/slot_00/caption.sav');
      final originalCaption = captionFile.readAsBytesSync();
      expect(progressFile.readAsBytesSync(), orderedEquals(original));

      final edited = createProgressEngine().apply(
        project,
        const SetScalar(lifeFieldId, 20),
      );
      final editedBytes = edited
          .document(progressSlotId)!
          .snapshot
          .materialize();
      expect(editedBytes, isNot(orderedEquals(original)));

      final plan = createProgressEngine().planExport(
        edited,
        destinationRoot: inPlaceRoot,
        mode: ExportMode.saveInPlace,
      );
      expect(plan.isSafe, isTrue, reason: _issues(plan));
      final result = await repo.writeExport(plan);
      expect(result.succeeded, isTrue, reason: _issues(plan));

      // The target now holds the edit; the previous version survives in .bak.
      expect(progressFile.readAsBytesSync(), orderedEquals(editedBytes));
      final bak = File('${progressFile.path}.bak');
      expect(bak.existsSync(), isTrue, reason: 'a .bak must be written');
      expect(bak.readAsBytesSync(), orderedEquals(original));
      final captionBak = File('${captionFile.path}.bak');
      expect(captionBak.existsSync(), isTrue);
      expect(captionBak.readAsBytesSync(), orderedEquals(originalCaption));

      // The sidecar holds the open-time original, not the edited payload.
      final sidecar = SidecarBackup(
        saveRoot: inPlaceRoot,
        layout: project.layout,
      );
      expect(sidecar.inspect(), SidecarStatus.ready);
      final stored = await sidecar.read(progressSlotId);
      expect(stored, isNotNull);
      expectByteIdentical(original, stored!);
      expect(hexU32(stored, lifeValueOffset(schema)), '0c 00 00 00');
      expect(hexU32(progressFile.readAsBytesSync(), lifeValueOffset(schema)),
          '14 00 00 00');

      final listing = _listing(progressFile.parent.path);
      chainLog('in-place listing after export: ${listing.join(' ')}');
      expect(listing, containsAll(<String>['progress.sav', 'progress.sav.bak']));
      expect(Directory('$inPlaceRoot.bombflower-original').existsSync(), isTrue);
      expect(
        File('$inPlaceRoot/.bombflower-pending.json').existsSync(),
        isFalse,
        reason: 'the batch manifest must be removed after success',
      );
      chainLog(
        'in-place: target=${progressFile.lengthSync()}B (Life 20) '
        '.bak=${bak.lengthSync()}B (Life 12) sidecar=${SidecarStatus.ready}',
      );
    });
  });

  group('criterion 8 — save-as to a new path', () {
    test('source bytes/mtime survive; destination gets its own sidecar',
        () async {
      await buildNewSave(saveAsSourceRoot);
      final destination = Directory(saveAsDestination);
      if (destination.existsSync()) {
        destination.deleteSync(recursive: true);
      }
      final sidecar = Directory('$saveAsDestination.bombflower-original');
      if (sidecar.existsSync()) {
        sidecar.deleteSync(recursive: true);
      }

      final repo = createProgressRepository(schema);
      final project = _projectOf(await repo.open(saveAsSourceRoot));
      final sourceProgress = File('$saveAsSourceRoot/slot_00/progress.sav');
      final sourceCaption = File('$saveAsSourceRoot/slot_00/caption.sav');
      final sourceOriginal = sourceProgress.readAsBytesSync();
      final sourceCaptionOriginal = sourceCaption.readAsBytesSync();
      final progressStat = sourceProgress.statSync();
      final captionStat = sourceCaption.statSync();
      final sourceListing = _listing(saveAsSourceRoot);

      final edited = createProgressEngine().apply(
        project,
        const SetScalar(lifeFieldId, 20),
      );
      final plan = createProgressEngine().planExport(
        edited,
        destinationRoot: saveAsDestination,
        mode: ExportMode.saveAs,
      );
      expect(plan.isSafe, isTrue, reason: _issues(plan));
      final result = await repo.writeExport(plan);
      expect(result.succeeded, isTrue, reason: _issues(plan));

      expect(sourceProgress.readAsBytesSync(), orderedEquals(sourceOriginal));
      expect(sourceCaption.readAsBytesSync(), orderedEquals(sourceCaptionOriginal));
      expect(sourceProgress.statSync().modified, progressStat.modified);
      expect(sourceCaption.statSync().modified, captionStat.modified);
      expect(_listing(saveAsSourceRoot), sourceListing);
      expect(
        Directory('$saveAsSourceRoot.bombflower-original').existsSync(),
        isFalse,
      );

      final exported = File('$saveAsDestination/slot_00/progress.sav');
      expect(exported.existsSync(), isTrue);
      final exportedBytes = Uint8List.fromList(exported.readAsBytesSync());
      expect(hexU32(exportedBytes, lifeValueOffset(schema)), '14 00 00 00');
      final destinationSidecar = SidecarBackup(
        saveRoot: saveAsDestination,
        layout: project.layout,
      );
      expect(destinationSidecar.inspect(), SidecarStatus.ready);
      final destinationStored = await destinationSidecar.read(progressSlotId);
      expect(destinationStored, isNotNull);
      expectByteIdentical(exportedBytes, destinationStored!);
      chainLog(
        'save-as: destination listing=${_listing(saveAsDestination).join(' ')}; '
        'source untouched (bytes+mtime+listing identical)',
      );
    });
  });
}

List<String> _listing(String root) {
  final names = <String>[
    for (final entry in Directory(root).listSync(followLinks: false))
      entry.uri.pathSegments.where((segment) => segment.isNotEmpty).last,
  ]..sort();
  return names;
}

String _issues(ExportPlan plan) => plan.blockingIssues
    .map((issue) => '${issue.code}: ${issue.message}')
    .join('; ');

SaveProject _projectOf(ParseResult result) => switch (result) {
  ParseOk(:final project) => project,
  ParseUnverified(:final project) => project,
  _ => fail('open failed: ${describeParseResult(result)}'),
};
