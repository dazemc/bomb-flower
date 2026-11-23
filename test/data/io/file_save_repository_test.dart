import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/io/io.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/core/fixtures.dart';

void writeSaveTree(String root, {Uint8List? progress}) {
  Directory('$root/slot_00').createSync(recursive: true);
  File('$root/account.sav').writeAsBytesSync(accountBytes());
  File('$root/option.sav').writeAsBytesSync(optionBytes());
  File('$root/slot_00/progress.sav')
      .writeAsBytesSync(progress ?? progressBytes());
}

Map<String, String> treeState(String root) {
  final directory = Directory(root);
  final result = <String, String>{};
  final entities = directory.listSync(recursive: true)
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final entity in entities) {
    final relative = entity.path.substring(root.length + 1);
    if (entity is Directory) {
      result['$relative/'] =
          'dir:${entity.statSync().modified.microsecondsSinceEpoch}';
    } else if (entity is File) {
      result[relative] =
          '${entity.lengthSync()}:'
          '${entity.lastModifiedSync().microsecondsSinceEpoch}:'
          '${Fnv1a.hash32(entity.readAsBytesSync())}';
    }
  }
  return result;
}

SaveProject projectFrom(ParseResult result) {
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

void main() {
  late Directory temp;
  late String root;
  late LayoutDescriptor layout;
  late SaveEngine engine;
  late FileSaveRepository repository;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bombflower_repo_');
    root = '${temp.path}/save';
    layout = testLayout(includeUnverified: false);
    engine = SaveEngine(testFormat(includeUnverified: false));
    repository = FileSaveRepository(
      engine: engine,
      resolveLayout: (_) async => LayoutSelection(layout, 7),
    );
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  group('open', () {
    test(
      'opens read-only and creates no sidecar or pending manifest',
      () async {
        writeSaveTree(root);
        final before = treeState(root);

        final result = await repository.open(root);

        expect(result, isA<ParseOk>());
        expect(treeState(root), before);
        expect(Directory('$root.bombflower-original').existsSync(), isFalse);
        expect(File('$root/$pendingManifestName').existsSync(), isFalse);
      },
    );

    test('truncated input is rejected and leaves the tree untouched', () async {
      writeSaveTree(root, progress: Uint8List(255));
      final before = treeState(root);

      final result = await repository.open(root);

      expect(result, isA<ParseCorrupt>());
      expect(treeState(root), before);
      expect(Directory('$root.bombflower-original').existsSync(), isFalse);
    });

    test('missing input is rejected without writing', () async {
      writeSaveTree(root);
      File('$root/option.sav').deleteSync();
      final before = treeState(root);

      final result = await repository.open(root);

      expect(result, isA<ParseCorrupt>());
      expect(treeState(root), before);
    });

    test('an absent layout is unsupported', () async {
      writeSaveTree(root);
      repository = FileSaveRepository(
        engine: engine,
        resolveLayout: (_) async => null,
      );

      expect(await repository.open(root), isA<ParseUnsupported>());
    });

    test('a path-traversing layout is rejected as corrupt', () async {
      writeSaveTree(root);
      final unsafe = LayoutDescriptor('unsafe', 7, <SaveSlotLayout>[
        SaveSlotLayout(
          progressSlot,
          '../escape.sav',
          progressLayout(includeUnverified: false).fields,
          expectedLength: 256,
        ),
      ]);
      repository = FileSaveRepository(
        engine: SaveEngine(
          SaveFormat('unsafe', 'Unsafe', <LayoutDescriptor>[unsafe]),
        ),
        resolveLayout: (_) async => LayoutSelection(unsafe, 7),
      );

      expect(await repository.open(root), isA<ParseCorrupt>());
      expect(File('${temp.path}/escape.sav').existsSync(), isFalse);
    });
  });

  group('export in place', () {
    test('writes atomically, retains .bak, and creates the sidecar', () async {
      writeSaveTree(root);
      final opened = projectFrom(await repository.open(root));
      final edited = engine.apply(opened, const SetScalar(healthId, 42));
      final plan = engine.planExport(
        edited,
        destinationRoot: root,
        mode: ExportMode.saveInPlace,
      );

      final result = await repository.writeExport(plan);

      expect(result.succeeded, isTrue);
      expect(File('$root/slot_00/progress.sav').readAsBytesSync()[11], 42);
      expect(
        File('$root/slot_00/progress.sav.bak').readAsBytesSync(),
        progressBytes(),
      );
      expect(File('$root/account.sav.bak').existsSync(), isTrue);
      expect(File('$root/$pendingManifestName').existsSync(), isFalse);
      expect(File('$root.bombflower-original/READY').existsSync(), isTrue);
      expect(result.project!.dirty.hasUnsavedChanges, isFalse);
    });

    test('refuses to write when the sidecar is incomplete', () async {
      writeSaveTree(root);
      final opened = projectFrom(await repository.open(root));
      final edited = engine.apply(opened, const SetScalar(healthId, 42));
      Directory('$root.bombflower-original').createSync(recursive: true);
      final before = treeState(root);
      final plan = engine.planExport(
        edited,
        destinationRoot: root,
        mode: ExportMode.saveInPlace,
      );

      final result = await repository.writeExport(plan);

      expect(result.succeeded, isFalse);
      expect(
        result.issues.any(
          (issue) => issue.code == ValidationCodes.backupConflict,
        ),
        isTrue,
      );
      expect(treeState(root), before);
    });
  });

  group('reset and duplicate', () {
    test('reset restores the sidecar original to disk', () async {
      writeSaveTree(root);
      final opened = projectFrom(await repository.open(root));
      final edited = engine.apply(opened, const SetScalar(healthId, 42));
      await repository.writeExport(
        engine.planExport(
          edited,
          destinationRoot: root,
          mode: ExportMode.saveInPlace,
        ),
      );
      expect(File('$root/slot_00/progress.sav').readAsBytesSync()[11], 42);

      final reset = await repository.reset(edited, progressSlot);

      expect(
        File('$root/slot_00/progress.sav').readAsBytesSync(),
        progressBytes(),
      );
      expect(
        reset.documents[progressSlot]!.snapshot.materialize(),
        progressBytes(),
      );
      expect(reset.history.canUndo, isTrue);
    });

    test('duplicate writes original bytes and its own sidecar', () async {
      writeSaveTree(root);
      final opened = projectFrom(await repository.open(root));
      final edited = engine.apply(opened, const SetScalar(healthId, 42));
      final destination = '${temp.path}/duplicate';

      final result = await repository.duplicate(
        edited,
        progressSlot,
        destinationRoot: destination,
      );

      expect(result.succeeded, isTrue);
      expect(
        File('$destination/slot_00/progress.sav').readAsBytesSync(),
        progressBytes(),
      );
      expect(
        File('$destination.bombflower-original/READY').existsSync(),
        isTrue,
      );
    });
  });
}
