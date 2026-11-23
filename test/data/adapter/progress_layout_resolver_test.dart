import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/adapter/progress_layout_builder.dart';
import 'package:bomb_flower/data/adapter/progress_layout_resolver.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/engine/ports.dart';
import 'package:bomb_flower/domain/save/progress_layout.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late ProgressLayoutResolver resolver;

  setUp(() {
    root = Directory.systemTemp.createTempSync('bomb_flower_resolver_');
    resolver = ProgressLayoutResolver(ProgressLayoutBuilder(_emptySchema()));
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'an empty directory is not a save and detection does not throw',
    () async {
      final detection = await resolver.detect(root.path);

      expect(detection, isA<SaveNotASave>());
      final notASave = detection as SaveNotASave;
      expect(notASave.path, root.path);
      expect(notASave.reason, contains('no slot_NN/progress.sav'));
      expect(notASave.magic, 0);
    },
  );

  test('a wrong magic is reported as not a save, with that magic', () async {
    final file = _writeSlot(root, 0, _minimalProgress(magic: 0xDEADBEEF));
    final before = file.readAsBytesSync();
    final entriesBefore = _entries(root);

    final detection = await resolver.detect(root.path);

    expect(detection, isA<SaveNotASave>());
    final notASave = detection as SaveNotASave;
    expect(notASave.magic, 0xDEADBEEF);
    expect(notASave.reason, isNotNull);
    expect(file.readAsBytesSync(), before);
    expect(_entries(root), entriesBefore);
  });

  test('an unsupported revision reports the revision it detected', () async {
    final file = _writeSlot(root, 0, _minimalProgress(revision: 1));
    final before = file.readAsBytesSync();

    final detection = await resolver.detect(root.path);

    expect(detection, isA<SaveUnsupportedRevision>());
    final unsupported = detection as SaveUnsupportedRevision;
    expect(unsupported.detected, 1);
    expect(unsupported.path, endsWith('progress.sav'));
    expect(file.readAsBytesSync(), before);
  });

  test('a truncated buffer reports the failure the codec reports', () async {
    final bytes = _minimalProgress().sublist(0, 20);
    final file = _writeSlot(root, 0, bytes);
    final before = file.readAsBytesSync();

    final detection = await resolver.detect(root.path);

    // The full header is present but the data offset (304) points past EOF,
    // so ProgressCodec reports truncation, which the resolver maps to corrupt.
    expect(detection, isA<SaveCorrupt>());
    expect((detection as SaveCorrupt).reason, isNotEmpty);
    expect(file.readAsBytesSync(), before);
  });

  test('a decodable slot is detected with the verified revision', () async {
    final bytes = _minimalProgress(includeField: true);
    _writeSlot(root, 0, bytes);

    final detection = await resolver.detect(root.path);

    expect(detection, isA<SaveDetected>());
    final selection = (detection as SaveDetected).selection;
    expect(selection.detectedVersion, 2982123);
    expect(selection.layout.id, 'oot-remake-progress');
    expect(selection.layout.version, 2982123);
    expect(selection.layout.slots, hasLength(1), reason: 'no caption.sav');
    final progress = selection.layout.slots.single;
    expect(progress.id, SaveSlotId.progress(0));
    expect(progress.relativePath, 'slot_00/progress.sav');
    expect(
      progress.fields,
      hasLength(1),
      reason: 'exactly one non-sentinel record was written',
    );
    expect(progress.expectedLength, bytes.length);

    final resolved = await resolver.call(root.path);
    expect(resolved, isA<LayoutResolved>());
    expect(
      (resolved as LayoutResolved).selection.detectedVersion,
      2982123,
    );
  });

  test('call reports a typed rejection for every non-save case', () async {
    final empty = Directory('${root.path}/empty')..createSync();
    final wrongMagic = Directory('${root.path}/wrong')..createSync();
    _writeSlot(wrongMagic, 0, _minimalProgress(magic: 0xDEADBEEF));
    final revision = Directory('${root.path}/revision')..createSync();
    _writeSlot(revision, 0, _minimalProgress(revision: 1));
    final truncated = Directory('${root.path}/truncated')..createSync();
    _writeSlot(truncated, 0, _minimalProgress().sublist(0, 20));

    final emptyResult = await resolver.call(empty.path);
    expect(
      (emptyResult as LayoutRejected).kind,
      LayoutRejectionKind.notASave,
    );
    expect(emptyResult.reason, contains('no slot_NN/progress.sav'));

    final wrongMagicResult =
        await resolver.call(wrongMagic.path) as LayoutRejected;
    expect(wrongMagicResult.kind, LayoutRejectionKind.notASave);
    expect(wrongMagicResult.reason, contains('0xdeadbeef'));

    final revisionResult =
        await resolver.call(revision.path) as LayoutRejected;
    expect(revisionResult.kind, LayoutRejectionKind.unsupportedRevision);
    expect(revisionResult.detectedVersion, 1);
    expect(revisionResult.reason, contains('2982123'));

    final truncatedResult =
        await resolver.call(truncated.path) as LayoutRejected;
    expect(truncatedResult.kind, LayoutRejectionKind.corrupt);
    expect(truncatedResult.reason, isNotEmpty);
  });
}

/// A schema with no fields, enough to construct a [ProgressLayoutBuilder].
GameDataSchema _emptySchema() => GameDataSchema.fromJsonString('''
{
  "schemaRevision": 2982123,
  "schemaRevisionHex": "0x2d80eb",
  "game": "synthetic-test",
  "provenance": {},
  "counts": {
    "onDiskFields": 0,
    "absentBool64bitKey": 0,
    "declaredNotSaved": 0,
    "sections": 0
  },
  "sections": [],
  "emptySectionIds": [],
  "fields": [],
  "absentFields": [],
  "declaredNotSaved": [],
  "enums": {},
  "unresolved": []
}
''');

/// Writes `<root>/slot_NN/progress.sav` and returns the file.
File _writeSlot(Directory root, int index, Uint8List bytes) {
  final slot = Directory(
    '${root.path}/slot_${index.toString().padLeft(2, '0')}',
  )..createSync(recursive: true);
  return File('${slot.path}/progress.sav')..writeAsBytesSync(bytes);
}

/// A minimal valid `progress.sav`: header, optional field, 32 sentinels, footer.
Uint8List _minimalProgress({
  int magic = ProgressLayout.magicValue,
  int revision = ProgressLayout.revision,
  bool includeField = false,
}) {
  final fieldCount = includeField ? 1 : 0;
  final recordCount = ProgressLayout.sentinelCount + fieldCount + 1;
  final length =
      ProgressLayout.recordStart + recordCount * ProgressLayout.recordSize;
  final bytes = Uint8List(length);
  _writeU32(bytes, ProgressLayout.magicOffset, magic);
  _writeU32(bytes, ProgressLayout.revisionOffset, revision);
  _writeU32(bytes, ProgressLayout.dataOffsetFieldOffset, length);
  var recordIndex = 0;
  if (includeField) {
    // One Bool field (inline value 1) in the first section.
    final offset =
        ProgressLayout.recordStart + recordIndex * ProgressLayout.recordSize;
    _writeU32(bytes, offset, 0xCEA220D3);
    _writeU32(bytes, offset + 4, 1);
    recordIndex++;
  }
  for (var i = 0; i < ProgressLayout.sentinelCount; i++) {
    final offset =
        ProgressLayout.recordStart + recordIndex * ProgressLayout.recordSize;
    _writeU32(bytes, offset, 0);
    _writeU32(bytes, offset + 4, i + 1);
    recordIndex++;
  }
  final footerOffset =
      ProgressLayout.recordStart + recordIndex * ProgressLayout.recordSize;
  _writeU32(bytes, footerOffset, ProgressLayout.footerKey);
  _writeU32(bytes, footerOffset + 4, ProgressLayout.footerValue);
  return bytes;
}

void _writeU32(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
  bytes[offset + 3] = (value >> 24) & 0xff;
}

List<String> _entries(Directory directory) =>
    directory.listSync().map((entity) => entity.path).toList()..sort();
