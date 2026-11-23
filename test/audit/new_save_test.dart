/// Audit done-audit-05, criterion 3: build a new save through the real path.
///
/// `NewSaveBuilder` + `NewSaveWriter` are the production constructors used by
/// `tool/create_save.dart`; the result is then opened by the production
/// repository and compared byte-for-byte with the real played save copy.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/domain/core/core.dart' hide ByteRegion;
import 'package:bomb_flower/domain/newsave/new_save_builder.dart';
import 'package:bomb_flower/domain/newsave/new_save_spec.dart';
import 'package:bomb_flower/domain/save/progress_layout.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:bomb_flower/data/newsave/new_save_writer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration/support/progress_chain.dart';
import '../integration/support/real_save_loader.dart';
import '../support/temp_roots.dart';

void main() {
  final resolution = resolveRealSaves();
  final skipReason = switch (resolution) {
    RealSaveAbsent(:final reason) => reason,
    _ => null,
  };
  late GameDataSchema schema;
  late Directory fileRoot;
  late String newSaveRoot;
  late String realSaveFile;

  setUpAll(() async {
    schema = await loadGameDataSchema();
    fileRoot = createTempRoot('audit/new-save');
    newSaveRoot = '${fileRoot.path}/newsave';
    realSaveFile = '${fileRoot.path}/real-save/slot_00/progress.sav';
    if (resolution is RealSaveFound) {
      _stageRealSlot(resolution, '${fileRoot.path}/real-save', 'slot_00');
    }
  });

  tearDownAll(() => removeTempRoot(fileRoot));

  group('criterion 3 — new save', () {
    late NewSaveBuild build;
    late NewSaveWriteResult write;
    late Uint8List bytes;

    setUpAll(() async {
      final root = Directory(newSaveRoot);
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
      build = NewSaveBuilder.build(
        schema: schema,
        spec: NewSaveSpec.preset(NewSavePreset.schemaDefaults),
      );
      write = await NewSaveWriter().write(
        rootDirectory: newSaveRoot,
        build: build,
      );
      bytes = File('$newSaveRoot/slot_00/progress.sav').readAsBytesSync();
    });

    test('header, magic, revision, tail and size are the verified shape', () async {
      expect(build.progressBytes, hasLength(120572));
      expect(build.dataOffset, 0x175D8);
      expect(build.dataOffset, 95704);
      expect(build.fieldCount, 11925);
      expect(build.recordCount, 11958);
      expect(build.sentinelCount, 32);
      expect(write.progressLength, 120572);
      expect(write.captionLength, greaterThan(0));

      final data = ByteData.sublistView(bytes);
      expect(bytes.sublist(0, 4), orderedEquals(ProgressLayout.magicBytes));
      expect(data.getUint32(0x04, Endian.little), ProgressLayout.revision);
      expect(data.getUint32(0x08, Endian.little), 0x175D8);
      expect(
        bytes.sublist(0x0C, 0x28),
        everyElement(0),
        reason: 'the 28-byte reserved header gap must stay zero',
      );
      final footerOffset = ProgressLayout.recordStart + 11957 * 8;
      expect(data.getUint32(footerOffset, Endian.little), 0xA3DB7114);
      final footerValue = data.getUint32(footerOffset + 4, Endian.little);
      expect(footerValue, ProgressLayout.footerValue);
      expect(bytes.length - 0x175D8, 24868, reason: 'tail length');
      expect(
        bytes.sublist(bytes.length - 8),
        everyElement(0),
        reason: 'the 8-byte zero trailer must be present',
      );
      expect(progressRecordCount(bytes), 11958);
      chainLog(
        'new save size=${bytes.length} dataOffset=0x175D8 tail=24868 '
        'magic=${ProgressLayout.magicBytes} revision=${ProgressLayout.revision} '
        'footer=0x${footerValue.toRadixString(16)}',
      );
    });

    test('parses cleanly through the production repository', () async {
      final open = await createProgressRepository(schema).open(newSaveRoot);
      expect(open, isA<ParseUnverified>());
      final project = (open as ParseUnverified).project;
      expect(project.slotLayout(progressSlotId)!.fields, hasLength(11925));
      expect(fieldInt(project, lifeFieldId), 12);
      expect(fieldInt(project, maxLifeFieldId), 12);
      expect(fieldInt(project, const FieldId('progress.a77921d7')), 0);
      chainLog(
        'new-save open -> ${describeParseResult(open)} '
        'Life=12 MaxLife=12 CurrentRupee=0',
      );
    });

    test('byte comparison against the real played save', () async {
      if (resolution is RealSaveMisconfigured) {
        fail(resolution.reason);
      }
      final real = File(realSaveFile).readAsBytesSync();
      final common = bytes.length < real.length ? bytes.length : real.length;
      final differing = <int>[];
      var diffCount = 0;
      for (var i = 0; i < common; i++) {
        if (bytes[i] != real[i]) {
          diffCount++;
          if (differing.length < 12) {
            differing.add(i);
          }
        }
      }
      expect(common, 120572);
      expect(real.length, 122852);
      expect(diffCount, greaterThan(0));
      expect(diffCount, lessThan(common));

      final project = (await createProgressRepository(
        schema,
      ).open(newSaveRoot) as ParseUnverified).project;
      final resolved = <String>[
        for (final offset in differing)
          '0x${offset.toRadixString(16)}=${_fieldAt(project, offset)}',
      ];
      chainLog(
        'vs real save: differing bytes in the ${common}B common prefix = '
        '$diffCount; real tail is ${real.length - common}B longer',
      );
      chainLog('first differing offsets: ${resolved.join(' | ')}');

      final tailDiff = <int>[];
      for (var i = common; i < real.length; i++) {
        if (real[i] != 0) {
          tailDiff.add(i);
          if (tailDiff.length == 12) {
            break;
          }
        }
      }
      chainLog(
        'first non-zero real bytes past 0x${common.toRadixString(16)}: '
        '${tailDiff.map((o) => '0x${o.toRadixString(16)}').join(',')}',
      );
    }, skip: skipReason);

    test('defaults that are asserted WITHOUT in-game evidence', () async {
      // These are asserted as *implementation* facts (schema/sample values),
      // not as proof that the game accepts them:
      //  * every field value is the BYML schema default (no host evidence that
      //    a played save starts from it);
      //  * sceneName/mapPath come from the caption samples, not the schema;
      //  * the caption JPEG is a synthetic 1x1 image;
      //  * no profile/player name exists, so none is written.
      final project = (await createProgressRepository(
        schema,
      ).open(newSaveRoot) as ParseUnverified).project;
      expect(fieldInt(project, lifeFieldId), 12);
      expect(fieldInt(project, maxLifeFieldId), 12);
      final caption = File('$newSaveRoot/slot_00/caption.sav')
          .readAsBytesSync();
      chainLog(
        'caption bytes=${caption.length} (jpeg=synthetic 1x1); '
        'defaults asserted from schema, in-game acceptance NOT evidenced',
      );
    });
  });
}

/// Copies the resolved [slot] directory into this file's unique root.
///
/// The source is the read-only retail/Longshot save tree that
/// [resolveRealSaves] discovered; a missing slot fails rather than producing a
/// partial fixture.
void _stageRealSlot(RealSaveFound found, String root, String slot) {
  final source = _sourceSlot(found, slot);
  if (source == null) {
    fail(
      'the resolved slots '
      '${found.slots.map((directory) => directory.path).toList()} '
      'contain no $slot to stage under $root',
    );
  }
  copyDirectorySync(source, Directory('$root/$slot'));
}

/// The resolved slot directory whose own name is [slot].
Directory? _sourceSlot(RealSaveFound found, String slot) {
  for (final directory in found.slots) {
    final segments = directory.uri.pathSegments.where(
      (segment) => segment.isNotEmpty,
    );
    if (segments.isNotEmpty && segments.last == slot) {
      return directory;
    }
  }
  return null;
}

String _fieldAt(SaveProject project, int offset) {
  for (final field in project.layout.allFields) {
    if (field.span.offset <= offset && offset < field.span.end) {
      return '${field.label} ${field.id.value}';
    }
  }
  return '<no declared field>';
}
