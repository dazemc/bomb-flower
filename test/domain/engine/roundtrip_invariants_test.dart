/// Round-trip invariants (a) and (b), proven against real retail saves.
///
/// Fixtures are copies of two read-only retail `progress.sav` files (122,852
/// and 122,940 bytes) staged in `.tmp/rt/slot_00/` and `.tmp/rt/slot_01/`.
/// The open root is the parent `.tmp/rt`: both slots then land in one layout as
/// `slot_00` and `slot_01`, which is the shape `FileSlotSource` resolves
/// (`<root>/<slot>/progress.sav`). Opening a root that *is* a `slot_NN`
/// directory is a different resolver mode and is not this test's subject.
///
/// These two invariants used to be `skip` stubs whose bodies were empty, so
/// removing the skip alone would have produced a vacuous pass. They now assert
/// real bytes from the real files:
///
/// * (a) a zero-edit open re-serialises byte for byte.
/// * (b) `PlayerStatus.Life` 16 -> 20 changes exactly one byte, and the
///   reserved header gap `[0x0C, 0x28)` plus an opaque tail span stay
///   byte-identical.
///
/// The other four invariants are covered elsewhere:
/// * (c) undo byte identity: `test/domain/engine/save_engine_test.dart`
///   "undo and redo (invariant c)".
/// * (d) no clamping / atomic failure: `test/domain/engine/save_engine_test.dart`
///   "rejects every invalid command atomically (invariant d)" and
///   `test/domain/core/edit_command_test.dart`.
/// * (e) open never writes: `test/data/io/file_save_repository_test.dart`
///   "opens read-only and creates no sidecar or pending manifest".
/// * (f) reject never partially writes: `test/data/io/atomic_file_writer_test.dart`
///   and `test/data/io/file_save_repository_test.dart`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/domain/core/core.dart' hide ByteRegion;
import 'package:bomb_flower/domain/save/progress_layout.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration/support/progress_chain.dart';
import '../../support/byte_assert.dart';

/// Scratch root: holds the two real fixture slots and receives the artifacts.
const String fixtureRoot = '.tmp/rt';

/// The read-only retail save tree. Never written; only copied out of.
const String realSaveRoot =
    '/home/daze/.local/share/longshot/save/5a3c9e1f0b7d24680000000000000001';

/// The two real slots this proof round-trips, in layout order.
const List<String> fixtureSlots = <String>['slot_00', 'slot_01'];

void main() {
  late GameDataSchema schema;

  setUpAll(() async {
    schema = await loadGameDataSchema();
    for (final slot in fixtureSlots) {
      _ensureFixture(slot);
      expect(
        File(_fixturePath(slot)).existsSync(),
        isTrue,
        reason: 'missing real fixture ${_fixturePath(slot)}',
      );
      expect(File(_fixturePath(slot)).lengthSync(), greaterThan(0));
    }
  });

  group('(a) zero-edit round-trip is byte-identical', () {
    test('should re-serialize both real slots byte for byte', () async {
      final repo = createProgressRepository(schema);
      final open = await repo.open(fixtureRoot);
      chainLog('(a) open $fixtureRoot -> ${describeParseResult(open)}');

      expect(
        open,
        isNot(isA<ParseCorrupt>()),
        reason: 'the real save must never parse as corrupt',
      );
      expect(open, anyOf(isA<ParseOk>(), isA<ParseUnverified>()));

      final project = _projectOf(open);
      expect(
        project.layout.slots.map((slot) => slot.id.value).toList(),
        <String>['slot_00', 'slot_01'],
      );

      for (final slot in fixtureSlots) {
        final slotId = _slotIdOf(slot);
        final layout = project.slotLayout(slotId);
        expect(layout, isNotNull, reason: '$slot must be in the opened layout');
        expect(layout!.relativePath, '$slot/progress.sav');

        final document = project.document(slotId);
        expect(document, isNotNull, reason: '$slot has no open document');

        final onDisk = _readFixture(slot);
        final reserialized = document!.snapshot.materialize();

        expect(reserialized, hasLength(onDisk.length));
        expect(reserialized.length, File(_fixturePath(slot)).lengthSync());
        expectByteIdentical(
          onDisk,
          reserialized,
          reason: '(a) zero-edit round-trip of $slot must preserve every byte',
        );

        // The layout is derived from the file's own record stream: 11,925
        // fields plus 32 sentinels plus the footer.
        expect(layout.expectedLength, onDisk.length);
        expect(layout.fields, hasLength(progressRecordCount(onDisk) - 33));

        final artifact = _writeArtifact(slot, 'progress.sav', reserialized);
        expectByteIdentical(onDisk, artifact);
        chainLog(
          '(a) $slot bytes=${artifact.length} '
          'fields=${layout.fields.length} '
          'records=${progressRecordCount(onDisk)} identical=true '
          'out=${_outPath(slot, 'progress.sav')}',
        );
      }
    });
  });

  group('(b) a field edit changes only its declared span plus integrity bytes', () {
    test('should change exactly one Life byte and nothing else', () async {
      final repo = createProgressRepository(schema);
      final engine = createProgressEngine();
      final project = _projectOf(await repo.open(fixtureRoot));

      // `SetScalar(lifeFieldId, ...)` resolves through
      // `LayoutDescriptor.descriptor`, which returns the first declared match:
      // the `PlayerStatus.Life` of slot_00.
      final targetSlot = progressSlotId;
      final targetName = targetSlot.value;
      final original = project.document(targetSlot)!.snapshot.materialize();
      final lifeOffset = lifeValueOffset(schema);

      final descriptor = project.layout.descriptor(lifeFieldId);
      expect(descriptor, isNotNull);
      expect(descriptor!.slot, targetSlot);
      expect(descriptor.span.offset, lifeOffset);
      expect(descriptor.span.length, ProgressLayout.valueWordSize);
      expect(fieldInt(project, lifeFieldId), isNot(20));

      final editedProject = engine.apply(
        project,
        const SetScalar(lifeFieldId, 20),
      );
      expect(fieldInt(editedProject, lifeFieldId), 20);
      final edited = editedProject.document(targetSlot)!.snapshot.materialize();

      final diff = ByteRegionDiff.diff(original, edited);
      chainLog('(b) diff runs=${diff.runs}');
      expect(
        diff.runs,
        hasLength(1),
        reason:
            'a scalar edit may only touch its own value word, saw '
            '${diff.runs}',
      );
      expect(diff.runs.single.start, lifeOffset);
      expect(diff.runs.single.length, 1);
      expect(editedProject.dirty.changedByteCount, 1);

      // No integrity scheme exists, so nothing may change because of one.
      // docs/SAVE-FORMAT.md §7: "No checksum was found."
      expect(
        editedProject.layout.slot(targetSlot)!.integrity,
        isEmpty,
        reason:
            'SAVE-FORMAT.md §7 found no checksum, so an edit may not '
            'change integrity bytes',
      );

      // The reserved header gap must be unclaimed and preserved.
      // docs/SAVE-FORMAT.md §2: "0x0c | 28 | all zero | Reserved";
      // §9.2: "bytes 0x0c-0x27 are zero in every sample and must stay zero".
      const gap = ByteSpan(
        ProgressLayout.reservedOffset,
        ProgressLayout.reservedLength,
      );
      expect(gap.offset, 0x0C);
      expect(gap.end, 0x28);
      expect(gap.length, 28);

      final claimants = <String>[
        for (final field in project.layout.allFields)
          if (field.span.overlaps(gap))
            '${field.label} ${field.id.value} ${field.span}',
      ];
      expect(
        claimants,
        isEmpty,
        reason:
            'the reserved header gap $gap must be unmapped, but these '
            'descriptors claim it: $claimants',
      );
      expect(
        edited.sublist(gap.offset, gap.end),
        orderedEquals(original.sublist(gap.offset, gap.end)),
        reason: 'the reserved header gap must be preserved verbatim',
      );
      chainLog(
        'original 0x0C..0x28:\n${hexWindow(original, 0x0C, radius: 28)}',
      );
      chainLog('edited   0x0C..0x28:\n${hexWindow(edited, 0x0C, radius: 28)}');

      // One opaque, unverified tail span must survive too: SAVE-FORMAT.md §9.8
      // "Preserve unknown fields and unknown tail bytes".
      final tailStart = _readU32(
        original,
        ProgressLayout.dataOffsetFieldOffset,
      );
      final opaque = project.layout.allFields.firstWhere(
        (field) =>
            field.span.offset >= tailStart &&
            field.span.length >= 16 &&
            field.confidence != FieldConfidence.verified,
        orElse: () => fail(
          'the layout declares no opaque tail span at or after '
          '0x${tailStart.toRadixString(16)} to assert preservation of',
        ),
      );
      expect(opaque.span.overlaps(ByteSpan(lifeOffset, 1)), isFalse);
      expect(
        edited.sublist(opaque.span.offset, opaque.span.end),
        orderedEquals(original.sublist(opaque.span.offset, opaque.span.end)),
        reason:
            'opaque span ${opaque.span} of ${opaque.id.value} must be '
            'preserved',
      );
      chainLog(
        'opaque ${opaque.label} ${opaque.id.value} kind=${opaque.kind.name} '
        'confidence=${opaque.confidence.name} span=${opaque.span} '
        'length=${opaque.span.length} identical=true',
      );

      // Editing slot_00 must not touch the other open slot.
      final otherSlot = SaveSlotId.progress(1);
      expectByteIdentical(
        project.document(otherSlot)!.snapshot.materialize(),
        editedProject.document(otherSlot)!.snapshot.materialize(),
        reason: 'a slot_00 edit must leave slot_01 byte-identical',
      );

      chainLog(
        'original Life @0x${lifeOffset.toRadixString(16)}:\n'
        '${hexWindow(original, lifeOffset, radius: 8)}',
      );
      chainLog(
        'edited   Life @0x${lifeOffset.toRadixString(16)}:\n'
        '${hexWindow(edited, lifeOffset, radius: 8)}',
      );

      final artifact = _writeArtifact(
        targetName,
        'edited-progress.sav',
        edited,
      );
      expectByteIdentical(edited, artifact);
      expect(
        ByteRegionDiff.diff(original, artifact).runs,
        hasLength(1),
        reason: 'the written artifact must differ in exactly one byte',
      );
      chainLog(
        '(b) edited artifact bytes=${artifact.length} '
        'out=${_outPath(targetName, 'edited-progress.sav')}',
      );
    });
  });
}

/// Root plus slot name of the real fixture, e.g. `.tmp/rt/slot_00/progress.sav`.
String _fixturePath(String slot) => '$fixtureRoot/$slot/progress.sav';

/// Artifact path under `.tmp/rt/out/<slot>/`.
String _outPath(String slot, String name) => '$fixtureRoot/out/$slot/$name';

/// `slot_00` -> `SaveSlotId.progress(0)`.
SaveSlotId _slotIdOf(String slot) =>
    SaveSlotId.progress(int.parse(slot.substring('slot_'.length)));

/// Copies a fixture out of the read-only retail tree when the copy is absent.
///
/// The source is opened for reading only. A machine without the retail save
/// fails with the two paths named rather than skipping the assertion.
void _ensureFixture(String slot) {
  final target = File(_fixturePath(slot));
  if (target.existsSync()) {
    return;
  }
  final source = File('$realSaveRoot/$slot/progress.sav');
  if (!source.existsSync()) {
    fail(
      'no fixture at ${target.path} and no read-only source at '
      '${source.path}; copy a real progress.sav into ${target.parent.path}',
    );
  }
  target.parent.createSync(recursive: true);
  source.copySync(target.path);
}

/// The fixture bytes, as a private copy so no caller can mutate the file view.
Uint8List _readFixture(String slot) =>
    Uint8List.fromList(File(_fixturePath(slot)).readAsBytesSync());

/// Writes [bytes] to the artifact path and returns what reached disk.
Uint8List _writeArtifact(String slot, String name, Uint8List bytes) {
  final file = File(_outPath(slot, name))
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  return Uint8List.fromList(file.readAsBytesSync());
}

/// The project of an accepted open, or a failure naming the rejection.
SaveProject _projectOf(ParseResult result) => switch (result) {
  ParseOk(:final project) => project,
  ParseUnverified(:final project) => project,
  _ => fail('open failed: ${describeParseResult(result)}'),
};

/// Little-endian u32 at [offset].
int _readU32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);
