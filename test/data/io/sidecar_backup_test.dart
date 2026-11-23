import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/io/io.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/engine/ports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/core/fixtures.dart';

Map<SaveSlotId, ByteRegion> originalRegions({Uint8List? progress}) =>
    <SaveSlotId, ByteRegion>{
      SaveSlotId.account: ByteRegion.fromBytes(accountBytes()),
      SaveSlotId.options: ByteRegion.fromBytes(optionBytes()),
      progressSlot: ByteRegion.fromBytes(progress ?? progressBytes()),
    };

void main() {
  late Directory temp;
  late String saveRoot;
  late LayoutDescriptor layout;
  late SidecarBackup backup;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bombflower_sidecar_');
    saveRoot = '${temp.path}/save';
    layout = testLayout(includeUnverified: false);
    backup = SidecarBackup(
      saveRoot: saveRoot,
      layout: layout,
      projectId: 'project-1',
      formatId: 'test-format',
      clock: () => DateTime.utc(2026, 1, 1),
    );
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  group('read-only inspection', () {
    test('never creates the sidecar on inspect, read, or verify', () async {
      expect(backup.inspect(), SidecarStatus.absent);
      expect(await backup.read(progressSlot), isNull);
      expect(await backup.verify(originalRegions()), isFalse);
      expect(Directory(backup.rootPath).existsSync(), isFalse);
    });

    test('reports incomplete when READY is missing', () {
      Directory(backup.rootPath).createSync(recursive: true);
      expect(backup.inspect(), SidecarStatus.incomplete);
    });

    test('reports incomplete when the manifest is unreadable', () {
      Directory(backup.rootPath).createSync(recursive: true);
      File(backup.readyPath).writeAsStringSync('ready');
      File(backup.manifestPath).writeAsStringSync('{not json');
      expect(backup.inspect(), SidecarStatus.incomplete);
    });
  });

  group('ensure', () {
    test('creates READY, a manifest, and mirrored files', () async {
      await backup.ensure(originalRegions(), BackupPolicy.standard);

      expect(backup.inspect(), SidecarStatus.ready);
      expect(File(backup.readyPath).readAsStringSync(), isNotEmpty);
      final manifest = SidecarManifest.fromJson(
        jsonDecode(File(backup.manifestPath).readAsStringSync())
            as Map<String, Object?>,
      );
      expect(manifest.projectId, 'project-1');
      expect(manifest.formatId, 'test-format');
      expect(manifest.layoutVersion, 7);
      expect(manifest.createdAt, '2026-01-01T00:00:00.000Z');
      expect(await backup.verify(originalRegions()), isTrue);

      final restored = await backup.read(progressSlot);
      expect(restored, progressBytes());
      expect(await backup.restore(progressSlot), progressBytes());
      expect(
        File(
          resolveUnderRoot(
            backup.filesPath,
            layout.slot(progressSlot)!.relativePath,
          ),
        ).existsSync(),
        isTrue,
      );
    });

    test('reuses a READY sidecar that still matches', () async {
      final originals = originalRegions();
      await backup.ensure(originals, BackupPolicy.standard);
      final manifestBefore = File(backup.manifestPath).readAsStringSync();

      await backup.ensure(originals, BackupPolicy.standard);

      expect(File(backup.manifestPath).readAsStringSync(), manifestBefore);
      expect(await backup.verify(originals), isTrue);
    });

    test('never silently overwrites an incomplete sidecar', () async {
      Directory(backup.rootPath).createSync(recursive: true);
      final marker = File('${backup.rootPath}/marker.txt')
        ..writeAsStringSync('do not lose me');

      await expectLater(
        backup.ensure(originalRegions(), BackupPolicy.standard),
        throwsA(
          isA<OriginalBackupException>().having(
            (error) => error.code,
            'code',
            ValidationCodes.backupConflict,
          ),
        ),
      );

      expect(marker.readAsStringSync(), 'do not lose me');
      expect(File(backup.readyPath).existsSync(), isFalse);
    });

    test(
      'never silently overwrites a READY sidecar with different bytes',
      () async {
        final originals = originalRegions();
        await backup.ensure(originals, BackupPolicy.standard);
        final changed = progressBytes(health: 42);
        final changedOriginals = originalRegions(progress: changed);

        await expectLater(
          backup.ensure(changedOriginals, BackupPolicy.standard),
          throwsA(
            isA<OriginalBackupException>().having(
              (error) => error.code,
              'code',
              ValidationCodes.backupConflict,
            ),
          ),
        );

        expect(await backup.read(progressSlot), progressBytes());
        expect(await backup.verify(originals), isTrue);
        expect(await backup.verify(changedOriginals), isFalse);
      },
    );

    test('verify detects a modified sidecar file', () async {
      final originals = originalRegions();
      await backup.ensure(originals, BackupPolicy.standard);
      final file = File(
        resolveUnderRoot(
          backup.filesPath,
          layout.slot(progressSlot)!.relativePath,
        ),
      );
      Process.runSync('chmod', <String>['0644', file.path]);
      file.writeAsBytesSync(Uint8List(256));

      expect(await backup.verify(originals), isFalse);
    });

    test('restore refuses a slot with no sidecar before creation', () async {
      expect(
        () => backup.restore(progressSlot),
        throwsA(isA<OriginalBackupException>()),
      );
      expect(Directory(backup.rootPath).existsSync(), isFalse);
    });

    test('a corrupt manifest is not trusted', () async {
      await backup.ensure(originalRegions(), BackupPolicy.standard);
      File(backup.manifestPath).writeAsStringSync('{not json');

      expect(backup.inspect(), SidecarStatus.incomplete);
      expect(await backup.verify(originalRegions()), isFalse);
      expect(
        () => backup.ensure(originalRegions(), BackupPolicy.standard),
        throwsA(isA<OriginalBackupException>()),
      );
    });
  });
}
