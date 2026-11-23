import 'dart:io';

import 'package:bomb_flower/data/newsave/new_save_writer.dart';
import 'package:bomb_flower/domain/core/fingerprint.dart';
import 'package:bomb_flower/domain/newsave/new_save_builder.dart';
import 'package:bomb_flower/domain/newsave/new_save_spec.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late GameDataSchema schema;
  late NewSaveBuild build;
  late Directory temp;

  setUpAll(() async {
    schema = GameDataSchema.fromJsonString(
      await File('assets/schema/gamedata_110.json').readAsString(),
    );
    build = NewSaveBuilder.build(
      schema: schema,
      spec: NewSaveSpec.preset(NewSavePreset.schemaDefaults),
    );
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bomb_flower_newsave_');
  });

  tearDown(() {
    if (!temp.existsSync()) {
      return;
    }
    final prefix =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'bomb_flower_newsave_';
    if (!temp.path.startsWith(prefix)) {
      fail('refusing to delete non-temp path ${temp.path}');
    }
    temp.deleteSync(recursive: true);
  });

  String join(String directory, String name) =>
      '$directory${Platform.pathSeparator}$name';

  String slotPath(String name) =>
      join(join(temp.path, NewSaveWriter.slotDirectoryName), name);

  group('NewSaveWriter.write', () {
    test('writes both files into an existing empty directory', () async {
      final result = await NewSaveWriter().write(
        rootDirectory: temp.path,
        build: build,
      );

      expect(result.rootDirectory, temp.path);
      expect(
        result.progressPath,
        join(
          join(temp.path, NewSaveWriter.slotDirectoryName),
          NewSaveWriter.progressFileName,
        ),
      );
      expect(
        result.captionPath,
        join(
          join(temp.path, NewSaveWriter.slotDirectoryName),
          NewSaveWriter.captionFileName,
        ),
      );

      final progress = File(result.progressPath);
      final caption = File(result.captionPath);
      expect(progress.existsSync(), isTrue);
      expect(caption.existsSync(), isTrue);

      expect(progress.lengthSync(), result.progressLength);
      expect(caption.lengthSync(), result.captionLength);
      expect(result.progressLength, build.progressBytes.length);
      expect(result.captionLength, build.captionBytes.length);

      expect(progress.readAsBytesSync(), orderedEquals(build.progressBytes));
      expect(caption.readAsBytesSync(), orderedEquals(build.captionBytes));
    });

    test('creates the root and slot_00 when the root does not exist', () async {
      final root = join(temp.path, 'new-root');
      expect(Directory(root).existsSync(), isFalse);

      final result = await NewSaveWriter().write(
        rootDirectory: root,
        build: build,
      );

      expect(Directory(root).existsSync(), isTrue);
      expect(
        Directory(join(root, NewSaveWriter.slotDirectoryName)).existsSync(),
        isTrue,
      );
      expect(File(result.progressPath).existsSync(), isTrue);
      expect(File(result.captionPath).existsSync(), isTrue);
      expect(
        File(result.progressPath).readAsBytesSync(),
        orderedEquals(build.progressBytes),
      );
      expect(
        File(result.captionPath).readAsBytesSync(),
        orderedEquals(build.captionBytes),
      );
    });

    test('refuses a non-empty directory without touching it', () async {
      final keep = File(join(temp.path, 'keep.txt'));
      keep.writeAsStringSync('keep me');

      await expectLater(
        NewSaveWriter().write(rootDirectory: temp.path, build: build),
        throwsA(
          isA<NewSaveWriteException>().having(
            (error) => error.code,
            'code',
            NewSaveWriteException.destinationNotEmpty,
          ),
        ),
      );

      expect(keep.readAsStringSync(), 'keep me');
      expect(
        Directory(join(temp.path, NewSaveWriter.slotDirectoryName))
            .existsSync(),
        isFalse,
      );
    });

    test('refuses a directory that already contains slot_00', () async {
      final slot = Directory(join(temp.path, NewSaveWriter.slotDirectoryName));
      slot.createSync();

      await expectLater(
        NewSaveWriter().write(rootDirectory: temp.path, build: build),
        throwsA(
          isA<NewSaveWriteException>().having(
            (error) => error.code,
            'code',
            NewSaveWriteException.destinationNotEmpty,
          ),
        ),
      );

      expect(slot.existsSync(), isTrue);
      expect(slot.listSync(), isEmpty);
      expect(
        File(slotPath(NewSaveWriter.progressFileName)).existsSync(),
        isFalse,
      );
      expect(
        File(slotPath(NewSaveWriter.captionFileName)).existsSync(),
        isFalse,
      );
    });

    test(
      'allowOverwrite keeps the first progress.sav as a .bak file',
      () async {
        final writer = NewSaveWriter();
        final first = await writer.write(
          rootDirectory: temp.path,
          build: build,
        );
        final firstProgressBytes = File(first.progressPath).readAsBytesSync();
        expect(firstProgressBytes, orderedEquals(build.progressBytes));

        final secondBuild = NewSaveBuilder.build(
          schema: schema,
          spec: NewSaveSpec.preset(
            NewSavePreset.schemaDefaults,
            startPosition: const SavePosition(x: 1.25, y: -2.5, z: 3.75),
          ),
        );
        expect(
          secondBuild.progressBytes,
          isNot(orderedEquals(build.progressBytes)),
        );

        final second = await writer.write(
          rootDirectory: temp.path,
          build: secondBuild,
          allowOverwrite: true,
        );

        expect(
          File(second.progressPath).readAsBytesSync(),
          orderedEquals(secondBuild.progressBytes),
        );
        final backup = File('${second.progressPath}.bak');
        expect(backup.existsSync(), isTrue);
        expect(backup.readAsBytesSync(), orderedEquals(firstProgressBytes));
        expect(
          File(second.captionPath).readAsBytesSync(),
          orderedEquals(secondBuild.captionBytes),
        );

        await expectLater(
          writer.write(rootDirectory: temp.path, build: build),
          throwsA(
            isA<NewSaveWriteException>().having(
              (error) => error.code,
              'code',
              NewSaveWriteException.destinationNotEmpty,
            ),
          ),
        );
        expect(
          File(second.progressPath).readAsBytesSync(),
          orderedEquals(secondBuild.progressBytes),
        );
      },
    );

    test('reports FNV-1a 32 fingerprints of the in-memory bytes', () async {
      final result = await NewSaveWriter().write(
        rootDirectory: temp.path,
        build: build,
      );

      expect(result.progressFingerprint, Fnv1a.hash32(build.progressBytes));
      expect(result.captionFingerprint, Fnv1a.hash32(build.captionBytes));
      expect(
        result.progressFingerprint,
        Fnv1a.hash32(File(result.progressPath).readAsBytesSync()),
      );
      expect(
        result.captionFingerprint,
        Fnv1a.hash32(File(result.captionPath).readAsBytesSync()),
      );
    });
  });
}
