import 'dart:typed_data';

import 'package:bomb_flower/domain/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  group('identities', () {
    test('progress slots pad to two digits', () {
      expect(SaveSlotId.progress(0).value, 'slot_00');
      expect(SaveSlotId.progress(9).value, 'slot_09');
      expect(SaveSlotId.progress(42).value, 'slot_42');
      expect(() => SaveSlotId.progress(-1), throwsRangeError);
    });

    test('extension types compare by value', () {
      expect(const SaveSlotId('a'), const SaveSlotId('a'));
      expect(const FieldId('x'), const FieldId('x'));
      expect(const FieldId('x') == const FieldId('y'), isFalse);
    });
  });

  group('ByteSpan', () {
    test('end is half-open', () {
      const span = ByteSpan(10, 3);
      expect(span.end, 13);
      expect(span.isValid, isTrue);
      expect(const ByteSpan(-1, 0).isValid, isFalse);
      expect(const ByteSpan(0, -1).isValid, isFalse);
    });

    test('contains is inclusive of both boundaries', () {
      const outer = ByteSpan(10, 10);
      expect(outer.contains(const ByteSpan(10, 10)), isTrue);
      expect(outer.contains(const ByteSpan(10, 1)), isTrue);
      expect(outer.contains(const ByteSpan(19, 1)), isTrue);
      expect(outer.contains(const ByteSpan(20, 0)), isTrue);
      expect(outer.contains(const ByteSpan(9, 1)), isFalse);
      expect(outer.contains(const ByteSpan(19, 2)), isFalse);
    });

    test('overlaps is strict and empty spans never overlap', () {
      const span = ByteSpan(10, 10);
      expect(span.overlaps(const ByteSpan(9, 2)), isTrue);
      expect(span.overlaps(const ByteSpan(19, 2)), isTrue);
      expect(span.overlaps(const ByteSpan(20, 1)), isFalse);
      expect(span.overlaps(const ByteSpan(10, 0)), isFalse);
      expect(span.overlaps(const ByteSpan(5, 5)), isFalse);
    });

    test('value equality and hash', () {
      expect(const ByteSpan(1, 2), const ByteSpan(1, 2));
      expect(const ByteSpan(1, 2).hashCode, const ByteSpan(1, 2).hashCode);
      expect(const ByteSpan(1, 2) == const ByteSpan(1, 3), isFalse);
    });
  });

  group('FieldDescriptor', () {
    test('is editable only when verified and writable', () {
      expect(healthField().isEditable, isTrue);
      expect(healthField(readOnly: true).isEditable, isFalse);
      expect(
        healthField(confidence: FieldConfidence.inferred).isEditable,
        isFalse,
      );
      expect(
        healthField(confidence: FieldConfidence.unverified).isEditable,
        isFalse,
      );
    });

    test('layout validity requires a positive span and a citation', () {
      expect(healthField().isLayoutValid, isTrue);
      expect(
        const FieldDescriptor(
          FieldId('x'),
          SaveSlotId('s'),
          'X',
          FieldKind.integer,
          ByteSpan(0, 0),
          FieldConfidence.verified,
          'source',
        ).isLayoutValid,
        isFalse,
      );
      expect(
        const FieldDescriptor(
          FieldId('x'),
          SaveSlotId('s'),
          'X',
          FieldKind.integer,
          ByteSpan(0, 1),
          FieldConfidence.verified,
          '',
        ).isLayoutValid,
        isFalse,
      );
    });

    test('value equality includes choices and bounds', () {
      expect(healthField(), healthField());
      expect(healthField().hashCode, healthField().hashCode);
      expect(healthField(endianness: Endian.little) == healthField(), isFalse);
    });
  });

  group('layouts and formats', () {
    test('SaveFormat only performs exact version matches', () {
      final format = testFormat();
      expect(format.layoutFor(7), isNotNull);
      expect(format.layoutFor(6), isNull);
      expect(format.layoutFor(8), isNull);
      expect(format.newestVersion, 7);
    });

    test('layout lookups find slots and fields', () {
      final layout = testLayout();
      expect(layout.slot(progressSlot), isNotNull);
      expect(layout.slot(const SaveSlotId('missing')), isNull);
      expect(layout.descriptor(healthId), isNotNull);
      expect(layout.descriptor(const FieldId('missing')), isNull);
      expect(layout.allFields.length, greaterThanOrEqualTo(7));
      expect(layout.migrationFrom(7), isNull);
    });

    test('slot field lookup is scoped to its slot', () {
      final slot = progressLayout();
      expect(slot.field(healthId), isNotNull);
      expect(slot.field(accountNameId), isNull);
    });

    test('IntegritySpec treats only verified as confirmed', () {
      final spec = testIntegrity();
      expect(spec.isConfirmed, isFalse);
      expect(
        testIntegrity(confidence: FieldConfidence.verified).isConfirmed,
        isTrue,
      );
      expect(spec.coversChange(const ByteSpan(10, 2)), isTrue);
      expect(spec.coversChange(const ByteSpan(250, 2)), isFalse);
    });
  });

  group('FieldValue', () {
    test('variants compare by value', () {
      expect(const IntValue(1), const IntValue(1));
      expect(const IntValue(1) == const IntValue(2), isFalse);
      expect(
        const EnumValue(key: 'a', rawValue: 1),
        const EnumValue(key: 'a', rawValue: 1),
      );
      expect(const BoolValue(true), const BoolValue(true));
      expect(const BitfieldValue(3), const BitfieldValue(3));
      expect(const StringValue('x'), const StringValue('x'));
      expect(
        const PositionValue(x: 1, y: 2, z: 3),
        const PositionValue(x: 1, y: 2, z: 3),
      );
      expect(VectorValue(<double>[1, 2]), VectorValue(<double>[1, 2]));
      expect(
        ListValue(const <FieldValue>[IntValue(1)]),
        ListValue(const <FieldValue>[IntValue(1)]),
      );
    });

    test('list variants are unmodifiable copies', () {
      final source = <double>[1, 2];
      final vector = VectorValue(source);
      source.add(3);
      expect(vector.components, <double>[1, 2]);
      expect(() => vector.components.add(4), throwsUnsupportedError);

      final items = <FieldValue>[const IntValue(1)];
      final list = ListValue(items);
      items.add(const IntValue(2));
      expect(list.items, <FieldValue>[const IntValue(1)]);
      expect(() => list.items.add(const IntValue(3)), throwsUnsupportedError);
    });
  });

  group('SaveDocument', () {
    test('finds fields by id', () {
      final region = ByteRegion.fromBytes(Uint8List(256));
      final snapshot = SaveSnapshot(progressSlot, 0, region);
      final document = SaveDocument(
        progressSlot,
        progressLayout(),
        snapshot,
        const <SaveField<FieldValue>>[],
      );

      expect(document.field(healthId), isNull);
      expect(document.snapshot, snapshot);
      expect(document.slot, progressSlot);
    });
  });

  group('parse and export types', () {
    test('ParseResult variants carry their payloads', () {
      final region = ByteRegion.fromBytes(<int>[1]);
      final project = SaveProject(
        'p',
        '/save',
        '/save.bombflower-original',
        testLayout(),
        7,
        <SaveSlotId, SaveSnapshot>{
          progressSlot: SaveSnapshot(progressSlot, 0, region),
        },
        const <SaveSlotId, SaveDocument>{},
        <SaveSlotId, int>{progressSlot: 1},
        EditHistory(),
        EditLog.empty(),
      );

      expect(ParseOk(project).project, project);
      expect(
        ParseUnverified(project, const <FieldId>[unknownId]).unverifiedFields,
        <FieldId>[unknownId],
      );
      expect(
        const ParseUnsupported('newer', detectedVersion: 9).detectedVersion,
        9,
      );
      expect(
        const ParseCorrupt('bad', at: ByteSpan(1, 2)).at,
        const ByteSpan(1, 2),
      );
    });

    test('ExportPlan safety is blocking-issue emptiness', () {
      final project = SaveProject(
        'p',
        '/save',
        '/save.bombflower-original',
        testLayout(),
        7,
        const <SaveSlotId, SaveSnapshot>{},
        const <SaveSlotId, SaveDocument>{},
        const <SaveSlotId, int>{},
        EditHistory(),
        EditLog.empty(),
      );
      final plan = ExportPlan(
        project,
        ExportMode.saveInPlace,
        '/save',
        <SaveSlotId, SaveSnapshot>{},
        <ValidationIssue>[],
        BackupPolicy.standard,
        false,
      );

      expect(plan.isSafe, isTrue);
      expect(plan.slots, isEmpty);
    });
  });
}
