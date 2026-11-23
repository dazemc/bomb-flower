/// Audit done-audit-05, criterion 5: validation and bounds.
///
/// Every case runs the production codec, resolver and engine. Cases that are
/// silently accepted are asserted as accepted and labelled as findings; they
/// are not turned into passes by a test-only guard.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/adapter/progress_layout_builder.dart';
import 'package:bomb_flower/data/adapter/progress_layout_resolver.dart';
import 'package:bomb_flower/data/codec/progress_codec.dart';
import 'package:bomb_flower/domain/core/core.dart' hide ByteRegion;
import 'package:bomb_flower/domain/save/progress_layout.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration/support/progress_chain.dart';
import '../support/byte_assert.dart';

/// Where scratch save roots live; always inside the repo's ignored `.tmp/`.
const String scratchRoot = '.tmp/audit/bounds';

void main() {
  late GameDataSchema schema;
  late Uint8List realProgress;

  setUpAll(() async {
    schema = await loadGameDataSchema();
    realProgress = File('.tmp/audit/real-save/slot_00/progress.sav')
        .readAsBytesSync();
  });

  group('criterion 5 — out-of-range values', () {
    test(
      'Int above its declared 32-bit range is refused, not clamped',
      () async {
        final repo = createProgressRepository(schema);
        final project = _projectOf(await repo.open('.tmp/audit/real-save'));
        final engine = createProgressEngine();

        final before = project.document(progressSlotId)!.snapshot.materialize();

        FieldWriteException? thrown;
        try {
          engine.apply(project, const SetScalar(lifeFieldId, 2147483648));
        } on FieldWriteException catch (error) {
          thrown = error;
        }
        expect(thrown, isNotNull, reason: '2147483648 fits no signed Int');
        expect(thrown!.code, FieldWriteCodes.outOfRange);
        expect(
          thrown.message,
          'Value 2147483648 is above the declared maximum 2147483647',
        );
        expect(
          thrown.toString(),
          contains('FieldWriteException[field.out_of_range]'),
        );
        // A refused write must not create a patch or bump a revision.
        expectByteIdentical(
          before,
          project.document(progressSlotId)!.snapshot.materialize(),
        );
        expect(project.document(progressSlotId)!.snapshot.revision, 0);
        chainLog('Int 2147483648 -> ${thrown.code}: ${thrown.message}');
      },
    );

    test('negative value is refused with the documented message', () async {
      final repo = createProgressRepository(schema);
      final project = _projectOf(await repo.open('.tmp/audit/real-save'));
      final engine = createProgressEngine();

      FieldWriteException? thrown;
      try {
        engine.apply(project, const SetScalar(lifeFieldId, -1));
      } on FieldWriteException catch (error) {
        thrown = error;
      }
      expect(thrown, isNotNull);
      expect(thrown!.code, FieldWriteCodes.outOfRange);
      expect(
        thrown.message,
        'Value -1 is negative; layouts declare unsigned bounds only',
      );
      chainLog('Int -1 -> ${thrown.code}: ${thrown.message}');
    });

    test('FINDING: Life > MaxLife is accepted silently (no cross-field rule)', () async {
      final repo = createProgressRepository(schema);
      final project = _projectOf(await repo.open('.tmp/audit/real-save'));
      final engine = createProgressEngine();

      final maxLife = fieldInt(project, maxLifeFieldId);
      final edited = engine.apply(project, const SetScalar(lifeFieldId, 99));
      expect(fieldInt(edited, lifeFieldId), 99);
      expect(fieldInt(edited, maxLifeFieldId), maxLife);
      expect(
        99,
        greaterThan(maxLife),
        reason: 'the sample MaxLife is $maxLife',
      );

      final issues = engine.validateResult(edited).issues;
      final rangeIssues = issues
          .where((issue) => issue.code == ValidationCodes.fieldOutOfRange)
          .toList();
      expect(
        rangeIssues,
        isEmpty,
        reason: 'no descriptor-level range issue exists for 99',
      );
      expect(
        engine
            .planExport(
              edited,
              destinationRoot: '.tmp/audit/bounds/never-written',
              mode: ExportMode.saveAs,
            )
            .isSafe,
        isTrue,
      );
      chainLog(
        'Life 99 > MaxLife $maxLife -> accepted; validation issues with '
        'field.out_of_range = ${rangeIssues.length} (cross-field rule ABSENT)',
      );
    });
  });

  group('criterion 5 — corrupt input', () {
    test('truncated file is rejected at decode and at open', () async {
      final truncated = Uint8List.sublistView(realProgress, 0, 20);
      final decoded = ProgressCodec.decode(truncated);
      expect(decoded, isA<ProgressDecodeTruncated>());
      final trunc = decoded as ProgressDecodeTruncated;
      expect(trunc.length, 20);
      expect(trunc.minimumLength, greaterThan(20));

      final root = _writeCase('truncated', truncated);
      final detection = await _resolver(schema).detect(root.path);
      expect(detection, isA<SaveCorrupt>());
      final open = await createProgressRepository(schema).open(root.path);
      expect(open, isA<ParseUnsupported>());
      final unsupported = open as ParseUnsupported;
      expect(
        unsupported.reason,
        'No supported layout detected in ${root.path}',
      );
      expect(_entries(root), <String>['caption.sav', 'progress.sav']);
      expect(_sidecarExists(root), isFalse);
      chainLog(
        'truncated 20 bytes -> ${decoded.runtimeType} '
        'minimumLength=${trunc.minimumLength}, detect=${detection.runtimeType}, '
        'open=${unsupported.reason}',
      );
    });

    test('wrong magic is rejected at decode and at open', () async {
      final wrong = Uint8List.fromList(realProgress);
      wrong[0] = 0;
      final decoded = ProgressCodec.decode(wrong);
      expect(decoded, isA<ProgressBadMagic>());
      final bad = decoded as ProgressBadMagic;
      expect(bad.magic, 0x01020300);
      expect(bad.message, 'expected the magic 04 03 02 01');

      final root = _writeCase('bad-magic', wrong);
      final detection = await _resolver(schema).detect(root.path);
      expect(detection, isA<SaveNotASave>());
      expect((detection as SaveNotASave).magic, 0x01020300);
      final open = await createProgressRepository(schema).open(root.path);
      expect(open, isA<ParseUnsupported>());
      chainLog(
        'magic 00 03 02 01 -> ${decoded.runtimeType} '
        '(message: ${bad.message}), detect=${detection.runtimeType}, '
        'open=${describeParseResult(open)}',
      );
    });

    test('wrong revision is rejected at decode and at open', () async {
      final wrong = Uint8List.fromList(realProgress);
      _writeU32(wrong, ProgressLayout.revisionOffset, 1);
      final decoded = ProgressCodec.decode(wrong);
      expect(decoded, isA<ProgressRevisionMismatch>());
      final mismatch = decoded as ProgressRevisionMismatch;
      expect(mismatch.revision, 1);
      expect(mismatch.expected, ProgressLayout.revision);
      expect(
        mismatch.message,
        'expected revision ${ProgressLayout.revision}; the file stores 1',
      );

      final root = _writeCase('bad-revision', wrong);
      final detection = await _resolver(schema).detect(root.path);
      expect(detection, isA<SaveUnsupportedRevision>());
      expect((detection as SaveUnsupportedRevision).detected, 1);
      final open = await createProgressRepository(schema).open(root.path);
      expect(open, isA<ParseUnsupported>());
      chainLog(
        'revision 1 -> ${decoded.runtimeType} (message: ${mismatch.message}), '
        'detect=${detection.runtimeType}, open=${describeParseResult(open)}',
      );
    });
  });
}

ProgressLayoutResolver _resolver(GameDataSchema schema) =>
    ProgressLayoutResolver(ProgressLayoutBuilder(schema));

Directory _writeCase(String name, Uint8List progress) {
  final root = Directory('$scratchRoot/$name');
  if (root.existsSync()) {
    root.deleteSync(recursive: true);
  }
  final slot = Directory('${root.path}/slot_00')..createSync(recursive: true);
  File('${slot.path}/progress.sav').writeAsBytesSync(progress);
  File('${slot.path}/caption.sav').writeAsBytesSync(
    File('.tmp/audit/real-save/slot_00/caption.sav').readAsBytesSync(),
  );
  return root;
}

List<String> _entries(Directory root) {
  final names = <String>[
    for (final entry in Directory('${root.path}/slot_00').listSync())
      entry.uri.pathSegments.where((segment) => segment.isNotEmpty).last,
  ]..sort();
  return names;
}

bool _sidecarExists(Directory root) =>
    Directory('${root.path}.bombflower-original').existsSync();

void _writeU32(Uint8List bytes, int offset, int value) {
  for (var index = 0; index < 4; index++) {
    bytes[offset + index] = (value >> (index * 8)) & 0xff;
  }
}

SaveProject _projectOf(ParseResult result) => switch (result) {
  ParseOk(:final project) => project,
  ParseUnverified(:final project) => project,
  _ => fail('open failed: ${describeParseResult(result)}'),
};
