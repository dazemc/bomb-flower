import 'dart:convert';
import 'dart:io';

import 'package:bomb_flower/data/io/io.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bombflower_atomic_');
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  String path(String name) => '${temp.path}/$name';

  List<FileSystemEntity> tempDebris() => temp
      .listSync(recursive: true)
      .where((entry) => entry.path.contains('bombflower-tmp'))
      .toList();

  group('AtomicFileWriter.write', () {
    test('writes a new file and reports its fingerprint', () async {
      final writer = AtomicFileWriter();
      final target = path('new.sav');

      final result = await writer.write(target, <int>[1, 2, 3]);

      expect(File(target).readAsBytesSync(), <int>[1, 2, 3]);
      expect(result.path, target);
      expect(result.byteCount, 3);
      expect(result.fingerprint, Fnv1a.hash32(<int>[1, 2, 3]));
      expect(result.backupPath, isNull);
      expect(tempDebris(), isEmpty);
    });

    test('keeps one .bak of the previous version', () async {
      final writer = AtomicFileWriter();
      final target = path('save.sav');
      await writer.write(target, <int>[1, 2]);

      final result = await writer.write(target, <int>[3, 4]);

      expect(File(target).readAsBytesSync(), <int>[3, 4]);
      expect(File('$target.bak').readAsBytesSync(), <int>[1, 2]);
      expect(result.backupPath, '$target.bak');

      await writer.write(target, <int>[5, 6]);
      expect(File('$target.bak').readAsBytesSync(), <int>[3, 4]);
      expect(tempDebris(), isEmpty);
    });

    test(
      'does not create .bak when previous-version retention is off',
      () async {
        final writer = AtomicFileWriter();
        final target = path('save.sav');
        await writer.write(target, <int>[1]);

        await writer.write(target, <int>[2], keepPreviousVersion: false);

        expect(File(target).readAsBytesSync(), <int>[2]);
        expect(File('$target.bak').existsSync(), isFalse);
      },
    );

    test(
      'restores the previous target on verify failure with .bak retention off',
      () async {
        final target = path('save.sav');
        await AtomicFileWriter().write(target, <int>[1, 2]);
        final writer = AtomicFileWriter(
          hooks: AtomicWriteHooks(
            onBeforeFinalVerify: (path) {
              File(path).writeAsBytesSync(<int>[9]);
            },
          ),
        );

        await expectLater(
          writer.write(target, <int>[3, 4], keepPreviousVersion: false),
          throwsA(isA<AtomicWriteException>()),
        );

        expect(File(target).readAsBytesSync(), <int>[1, 2]);
        expect(File('$target.bak').existsSync(), isFalse);
        expect(tempDebris(), isEmpty);
      },
    );

    test('a failing pre-rename hook leaves the target untouched', () async {
      final target = path('save.sav');
      await AtomicFileWriter().write(target, <int>[1, 2]);
      final writer = AtomicFileWriter(
        hooks: AtomicWriteHooks(
          onBeforeRename: (_) => throw StateError('injected crash'),
        ),
      );

      await expectLater(
        writer.write(target, <int>[3, 4]),
        throwsA(
          isA<AtomicWriteException>().having(
            (error) => error.code,
            'code',
            ValidationCodes.writeVerifyFailed,
          ),
        ),
      );

      expect(File(target).readAsBytesSync(), <int>[1, 2]);
      expect(tempDebris(), isEmpty);
    });

    test('a final verification failure restores the previous target', () async {
      final target = path('save.sav');
      await AtomicFileWriter().write(target, <int>[1, 2]);
      final writer = AtomicFileWriter(
        hooks: AtomicWriteHooks(
          onBeforeFinalVerify: (path) {
            File(path).writeAsBytesSync(<int>[9, 9, 9]);
          },
        ),
      );

      await expectLater(
        writer.write(target, <int>[3, 4]),
        throwsA(
          isA<AtomicWriteException>().having(
            (error) => error.code,
            'code',
            ValidationCodes.writeVerifyFailed,
          ),
        ),
      );

      expect(File(target).readAsBytesSync(), <int>[1, 2]);
      expect(File('$target.bak').readAsBytesSync(), <int>[1, 2]);
      expect(tempDebris(), isEmpty);
    });

    test('refuses to write through a symlink', () async {
      final real = File(path('real.sav'))..writeAsBytesSync(<int>[1, 2]);
      final link = path('link.sav');
      Link(link).createSync(real.path);
      final writer = AtomicFileWriter();

      await expectLater(
        writer.write(link, <int>[3]),
        throwsA(
          isA<AtomicWriteException>().having(
            (error) => error.code,
            'code',
            ValidationCodes.pathConflict,
          ),
        ),
      );

      expect(real.readAsBytesSync(), <int>[1, 2]);
      expect(FileSystemEntity.isLinkSync(link), isTrue);
      expect(tempDebris(), isEmpty);
    });

    test('returns an empty list for an empty batch', () async {
      expect(await AtomicFileWriter().writeAll(<String, List<int>>{}), isEmpty);
    });
  });

  group('AtomicFileWriter.writeAll', () {
    test('stages and writes every file, retaining .bak files', () async {
      final first = path('a.sav');
      final second = path('nested/b.sav');
      await AtomicFileWriter().write(first, <int>[1]);
      final writer = AtomicFileWriter();

      final results = await writer.writeAll(<String, List<int>>{
        first: <int>[2],
        second: <int>[3],
      });

      expect(results.length, 2);
      expect(File(first).readAsBytesSync(), <int>[2]);
      expect(File('$first.bak').readAsBytesSync(), <int>[1]);
      expect(File(second).readAsBytesSync(), <int>[3]);
      expect(File('$second.bak').existsSync(), isFalse);
      expect(tempDebris(), isEmpty);
    });

    test('a staging failure touches no target and clears debris', () async {
      final first = path('a.sav');
      final second = path('b.sav');
      await AtomicFileWriter().write(first, <int>[1]);
      var calls = 0;
      final writer = AtomicFileWriter(
        hooks: AtomicWriteHooks(
          onAfterTempWritten: (_) {
            calls++;
            if (calls == 2) {
              throw StateError('injected staging failure');
            }
          },
        ),
      );

      await expectLater(
        writer.writeAll(<String, List<int>>{
          first: <int>[2],
          second: <int>[3],
        }),
        throwsA(isA<AtomicWriteException>()),
      );

      expect(File(first).readAsBytesSync(), <int>[1]);
      expect(File(second).existsSync(), isFalse);
      expect(File('$first.bak').existsSync(), isFalse);
      expect(tempDebris(), isEmpty);
    });

    test('a final verification failure rolls every target back', () async {
      final first = path('a.sav');
      final second = path('b.sav');
      await AtomicFileWriter().write(first, <int>[1]);
      await AtomicFileWriter().write(second, <int>[2]);
      var verifications = 0;
      final writer = AtomicFileWriter(
        hooks: AtomicWriteHooks(
          onBeforeFinalVerify: (_) {
            verifications++;
            if (verifications == 2) {
              throw StateError('injected verification crash');
            }
          },
        ),
      );

      await expectLater(
        writer.writeAll(<String, List<int>>{
          first: <int>[3],
          second: <int>[4],
        }),
        throwsA(isA<AtomicWriteException>()),
      );

      expect(File(first).readAsBytesSync(), <int>[1]);
      expect(File(second).readAsBytesSync(), <int>[2]);
      expect(tempDebris(), isEmpty);
    });

    test('removes a committed manifest after success', () async {
      final target = path('a.sav');
      final manifest = path(pendingManifestName);

      await AtomicFileWriter().writeAll(<String, List<int>>{
        target: <int>[1, 2],
      }, manifestPath: manifest);

      expect(File(target).readAsBytesSync(), <int>[1, 2]);
      expect(File(manifest).existsSync(), isFalse);
      expect(tempDebris(), isEmpty);
    });

    test('recovers a pending manifest by finishing verified renames', () async {
      final target = path('a.sav');
      final tempPath = path('a.sav.bombflower-tmp-test');
      final manifest = path(pendingManifestName);
      File(target).writeAsBytesSync(<int>[1]);
      File(tempPath).writeAsBytesSync(<int>[2, 3]);
      final bytes = <int>[2, 3];
      File(manifest).writeAsStringSync(
        jsonEncode(
          AtomicWriteManifest(AtomicWriteManifest.pending, <AtomicWriteEntry>[
            AtomicWriteEntry(
              target,
              tempPath,
              '$target.bak',
              bytes.length,
              Fnv1a.hash32(bytes),
            ),
          ]).toJson(),
        ),
      );

      final report = await AtomicFileWriter().recover(manifest);

      expect(report.recovered, isTrue);
      expect(File(target).readAsBytesSync(), <int>[2, 3]);
      expect(File(tempPath).existsSync(), isFalse);
      expect(File(manifest).existsSync(), isFalse);
    });

    test('cleans a committed manifest whose targets verify', () async {
      final target = path('a.sav');
      final manifest = path(pendingManifestName);
      File(target).writeAsBytesSync(<int>[2, 3]);
      File(manifest).writeAsStringSync(
        jsonEncode(
          AtomicWriteManifest(AtomicWriteManifest.committed, <AtomicWriteEntry>[
            AtomicWriteEntry(
              target,
              path('missing-temp'),
              null,
              2,
              Fnv1a.hash32(<int>[2, 3]),
            ),
          ]).toJson(),
        ),
      );

      final report = await AtomicFileWriter().recover(manifest);

      expect(report.recovered, isTrue);
      expect(File(target).readAsBytesSync(), <int>[2, 3]);
      expect(File(manifest).existsSync(), isFalse);
    });

    test('reports an absent manifest without creating one', () async {
      final manifest = path(pendingManifestName);
      final report = await AtomicFileWriter().recover(manifest);

      expect(report.recovered, isFalse);
      expect(report.messages, isEmpty);
      expect(File(manifest).existsSync(), isFalse);
    });
  });
}
