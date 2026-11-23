/// Audit done-audit-05, criteria 1, 2, 4, 6, 7: the REAL played save.
///
/// Input is a read-only copy at `.tmp/audit/real-save/slot_00/progress.sav`
/// (sha256 03f4f46a6ba8c71a242cece8982382ccaa8dc5f79775876b45b16ae4c9f9d0ba,
/// 122,852 bytes). The production resolver/codec/engine do every byte read;
/// nothing here substitutes a fixture.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/domain/core/core.dart' hide ByteRegion;
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration/support/progress_chain.dart';
import '../support/byte_assert.dart';

/// Root of the read-only copied save.
const String realSaveRoot = '.tmp/audit/real-save';

/// `PlayerStatus.CurrentRupee` — Int, host-cited, tab `resources.rupees`.
const FieldId rupeeFieldId = FieldId('progress.a77921d7');

/// `PlayerStatus.IsDefenseUP` — Bool, struct-cited, tab `equipment.state`.
const FieldId defenseFieldId = FieldId('progress.56bbe07c');

/// `DungeonInfo.FireTemple.IsGetCompass` — Bool, string-cited, tab `dungeons`.
const FieldId fireCompassFieldId = FieldId('progress.0aa068b6');

/// `IsGet.Item_Melody_SunSong` — Bool, string-cited, tab `progression`.
const FieldId sunSongFieldId = FieldId('progress.165dd1ad');

/// The five verified fields this audit edits, across four tabs.
const Map<FieldId, String> auditedFields = <FieldId, String>{
  lifeFieldId: 'PlayerStatus.Life (resources.health)',
  rupeeFieldId: 'PlayerStatus.CurrentRupee (resources.rupees)',
  defenseFieldId: 'PlayerStatus.IsDefenseUP (equipment.state)',
  fireCompassFieldId: 'DungeonInfo.FireTemple.IsGetCompass (dungeons)',
  sunSongFieldId: 'IsGet.Item_Melody_SunSong (progression)',
};

/// Integer read-back of [id], failing when the field is absent/non-numeric.
int readInt(SaveProject project, FieldId id) {
  final field = project.document(progressSlotId)?.field(id);
  expect(field, isNotNull, reason: '${id.value} is not in the opened layout');
  final value = field!.value;
  expect(value, isA<IntValue>(), reason: '${id.value} decoded to $value');
  return (value as IntValue).value;
}

/// Boolean read-back of [id], failing when the field is absent/non-boolean.
bool readBool(SaveProject project, FieldId id) {
  final field = project.document(progressSlotId)?.field(id);
  expect(field, isNotNull, reason: '${id.value} is not in the opened layout');
  final value = field!.value;
  expect(value, isA<BoolValue>(), reason: '${id.value} decoded to $value');
  return (value as BoolValue).value;
}

/// Label of the first declared descriptor whose span contains [offset].
String fieldAt(SaveProject project, int offset) {
  for (final field in project.layout.allFields) {
    if (field.span.offset <= offset && offset < field.span.end) {
      return '${field.label} ${field.id.value} @ ${field.span}';
    }
  }
  return '<no declared field spans this offset>';
}

void main() {
  late GameDataSchema schema;

  setUpAll(() async {
    schema = await loadGameDataSchema();
    expect(
      File('$realSaveRoot/slot_00/progress.sav').existsSync(),
      isTrue,
      reason: 'audit copy is missing; copy the real save first',
    );
  });

  group('criterion 1 — real save round trip', () {
    test('parse -> materialize reproduces the file byte for byte', () async {
      final repo = createProgressRepository(schema);
      final open = await repo.open(realSaveRoot);
      chainLog('real open -> ${describeParseResult(open)}');
      expect(open, isA<ParseUnverified>());
      final project = (open as ParseUnverified).project;

      final document = project.document(progressSlotId);
      expect(document, isNotNull);
      final parsed = document!.snapshot.materialize();
      final onDisk = Uint8List.fromList(
        File('$realSaveRoot/slot_00/progress.sav').readAsBytesSync(),
      );

      expect(parsed, hasLength(onDisk.length));
      expect(parsed.length, 122852);
      expectByteIdentical(onDisk, parsed, reason: 'open must be lossless');

      // The layout is derived from the file's own record stream.
      final layout = project.slotLayout(progressSlotId)!;
      expect(layout.relativePath, 'slot_00/progress.sav');
      expect(layout.fields, hasLength(11925));
      expect(progressRecordCount(onDisk), 11958);

      // Emit the re-serialized bytes so the report can quote sha256sum.
      File('.tmp/audit/reserialized-progress.sav')
        ..createSync(recursive: true)
        ..writeAsBytesSync(parsed);
      chainLog(
        'roundtrip bytes=${parsed.length} fields=${layout.fields.length} '
        'records=${progressRecordCount(onDisk)} identical=true',
      );
    });
  });

  group('criterion 2 — unknown bytes preserved', () {
    test('editing Life changes only its byte; header gap and opaque tail '
        'bytes survive', () async {
      final engine = createProgressEngine();
      final repo = createProgressRepository(schema);
      final project = _projectOf(await repo.open(realSaveRoot));
      final original = project.document(progressSlotId)!.snapshot.materialize();
      final lifeOffset = lifeValueOffset(schema);

      final edited = engine.apply(project, const SetScalar(lifeFieldId, 20));
      final editedBytes = edited
          .document(progressSlotId)!
          .snapshot
          .materialize();

      // The whole-file diff is exactly the one byte that carries 16 -> 20.
      final diff = ByteRegionDiff.diff(original, editedBytes);
      expect(diff.runs, hasLength(1));
      expect(diff.runs.single.start, lifeOffset);
      expect(diff.runs.single.length, 1);

      // The reserved header gap 0x0C..0x27 is mapped to no field at all.
      const gap = ByteSpan(0x0C, 0x1C);
      expect(
        editedBytes.sublist(gap.offset, gap.end),
        orderedEquals(original.sublist(gap.offset, gap.end)),
        reason: 'the reserved header gap must be preserved',
      );
      chainLog(
        'original 0x0C..0x28:\n${hexWindow(original, 0x0C, radius: 28)}',
      );
      chainLog(
        'edited   0x0C..0x28:\n${hexWindow(editedBytes, 0x0C, radius: 28)}',
      );

      // An opaque Binary span in the tail, read-only and unnamed: preserved.
      final opaque = project.layout.allFields.firstWhere(
        (field) =>
            field.span.offset >= 0x175D8 &&
            field.span.length > 16 &&
            field.kind == FieldKind.list,
      );
      expect(
        editedBytes.sublist(opaque.span.offset, opaque.span.end),
        orderedEquals(original.sublist(opaque.span.offset, opaque.span.end)),
        reason: 'opaque span ${opaque.span} must be preserved',
      );
      chainLog(
        'opaque ${opaque.id.value} ${opaque.span} '
        'len=${opaque.span.length} identical=true',
      );

      // Structural metadata is untouched too.
      expect(
        progressSentinels(editedBytes),
        orderedEquals(progressSentinels(original)),
      );
      expect(progressFooter(editedBytes), progressFooter(original));
      chainLog(
        'sentinels=${progressSentinels(editedBytes).length} '
        'footer=${progressFooter(editedBytes)} unchanged',
      );
    });
  });

  group('criterion 4 — five verified fields edit correctly', () {
    test(
      'set, re-read, assert equality for five fields across four tabs',
      () async {
        final engine = createProgressEngine();
        final repo = createProgressRepository(schema);
        var project = _projectOf(await repo.open(realSaveRoot));

        const intTargets = <FieldId, int>{
          lifeFieldId: 20,
          rupeeFieldId: 500,
        };
        const boolTargets = <FieldId, int>{
          defenseFieldId: 1,
          fireCompassFieldId: 1,
          sunSongFieldId: 1,
        };

        for (final entry in intTargets.entries) {
          final before = readInt(project, entry.key);
          project = engine.apply(project, SetScalar(entry.key, entry.value));
          final after = readInt(project, entry.key);
          expect(
            after,
            entry.value,
            reason: '${entry.key.value} did not stick',
          );
          final descriptor = project.layout.descriptor(entry.key)!;
          expect(descriptor.confidence.name, 'verified');
          expect(descriptor.isEditable, isTrue);
          chainLog(
            'EDIT ${auditedFields[entry.key]} id=${entry.key.value} '
            'hash=0x${entry.key.value.substring(8)} span=${descriptor.span} '
            'before=$before after=$after',
          );
        }

        for (final entry in boolTargets.entries) {
          final before = readBool(project, entry.key);
          expect(
            before,
            isFalse,
            reason: '${entry.key.value} must start false for the edit to '
                'change a byte',
          );
          project = engine.apply(project, SetScalar(entry.key, entry.value));
          final after = readBool(project, entry.key);
          expect(
            after,
            isTrue,
            reason: '${entry.key.value} did not stick as BoolValue(true)',
          );
          expect(
            project.document(progressSlotId)?.field(entry.key)?.value,
            isA<BoolValue>(),
            reason: '${entry.key.value} must stay a BoolValue',
          );
          final descriptor = project.layout.descriptor(entry.key)!;
          expect(descriptor.confidence.name, 'verified');
          expect(descriptor.isEditable, isTrue);
          chainLog(
            'EDIT ${auditedFields[entry.key]} id=${entry.key.value} '
            'hash=0x${entry.key.value.substring(8)} span=${descriptor.span} '
            'before=$before after=$after',
          );
        }

        final targets = <FieldId>[...intTargets.keys, ...boolTargets.keys];
        expect(project.dirty.changedFieldCount, targets.length);
        expect(project.dirty.changedFields.length, targets.length);
      },
    );
  });

  group('criterion 6 — undo/redo and dirty tracking', () {
    test(
      'edit -> dirty -> undo restores bytes -> redo restores value',
      () async {
        final engine = createProgressEngine();
        final repo = createProgressRepository(schema);
        final opened = _projectOf(await repo.open(realSaveRoot));
        final original = opened
            .document(progressSlotId)!
            .snapshot
            .materialize();

        expect(opened.dirty.hasUnsavedChanges, isFalse);
        expect(opened.dirty.differsFromOriginal, isFalse);
        expect(opened.history.canUndo, isFalse);
        expect(opened.history.canRedo, isFalse);

        final edited = engine.apply(opened, const SetScalar(lifeFieldId, 20));
        expect(edited.dirty.hasUnsavedChanges, isTrue);
        expect(edited.dirty.differsFromOriginal, isTrue);
        expect(edited.dirty.changedFieldCount, 1);
        expect(edited.dirty.changedByteCount, 1);
        expect(edited.history.canUndo, isTrue);
        expect(edited.history.canRedo, isFalse);
        expect(readInt(edited, lifeFieldId), 20);
        chainLog(
          'edit Life -> 20 unsaved=${edited.dirty.hasUnsavedChanges} '
          'canUndo=${edited.history.canUndo}',
        );

        final undone = engine.undo(edited);
        expect(readInt(undone, lifeFieldId), 16);
        expect(undone.dirty.hasUnsavedChanges, isFalse);
        expect(undone.dirty.differsFromOriginal, isFalse);
        expect(undone.dirty.changedFieldCount, 0);
        expect(undone.history.canUndo, isFalse);
        expect(undone.history.canRedo, isTrue);
        expectByteIdentical(
          original,
          undone.document(progressSlotId)!.snapshot.materialize(),
          reason: 'undo must restore the opened bytes exactly',
        );
        chainLog(
          'undo Life -> 16 unsaved=false canRedo=${undone.history.canRedo}',
        );

        final redone = engine.redo(undone);
        expect(readInt(redone, lifeFieldId), 20);
        expect(redone.dirty.hasUnsavedChanges, isTrue);
        expect(redone.history.canUndo, isTrue);
        expect(redone.history.canRedo, isFalse);
        chainLog('redo Life -> 20 unsaved=${redone.dirty.hasUnsavedChanges}');
      },
    );
  });

  group('criterion 7 — original-vs-edited diff, headless', () {
    test('SaveProject.changedSpans is the compare dialog data path', () async {
      final engine = createProgressEngine();
      final repo = createProgressRepository(schema);
      final opened = _projectOf(await repo.open(realSaveRoot));
      final original = opened.document(progressSlotId)!.snapshot.materialize();

      final edited = engine.apply(opened, const SetScalar(lifeFieldId, 20));
      final spans = edited.changedSpans(progressSlotId);
      expect(spans, hasLength(1));
      expect(spans.single.offset, lifeValueOffset(schema));
      expect(spans.single.length, 1);
      chainLog(
        'changedSpans=${spans.map((s) => '${s.offset}+${s.length}').join(',')}',
      );
      for (final span in spans) {
        chainLog(
          'changed run ${span.offset}+${span.length} resolves to '
          '${fieldAt(edited, span.offset)}',
        );
      }

      // The original side of the comparison is the open-time snapshot, and it
      // is byte-identical to the file: the dialog reads project.originals.
      final retained = edited.originals[progressSlotId]!;
      expectByteIdentical(original, retained.materialize());
      expect(edited.dirty.differsFromOriginal, isTrue);

      final spansByField = <String>[];
      for (final field in auditedFields.keys) {
        final descriptor = edited.layout.descriptor(field)!;
        final touched = spans.any(
          (span) =>
              span.offset < descriptor.span.end &&
              descriptor.span.offset < span.offset + span.length,
        );
        spansByField.add('${field.value}:$touched');
      }
      chainLog('spans touch fields: ${spansByField.join(' ')}');
    });
  });
}

SaveProject _projectOf(ParseResult result) => switch (result) {
  ParseOk(:final project) => project,
  ParseUnverified(:final project) => project,
  _ => fail('open failed: ${describeParseResult(result)}'),
};
