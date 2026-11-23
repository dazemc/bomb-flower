import 'dart:convert';

import 'package:bomb_flower/domain/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const slot = SaveSlotId('slot_00');
  final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
  final health = const FieldId('player.health');

  EditRecord record(
    int sequence,
    EditKind kind,
    EditCommand? command, {
    String description = 'test',
    int byteCount = 2,
  }) => EditRecord(
    sequence,
    kind,
    at,
    slot,
    sequence - 1,
    sequence,
    command,
    description,
    byteCount,
  );

  group('EditLog', () {
    test('appends immutably and keeps the newest records', () {
      final empty = EditLog(<EditRecord>[], maxRecords: 2);
      final first = empty.append(record(1, EditKind.open, null));
      final second = first.append(
        record(2, EditKind.apply, SetScalar(health, 1)),
      );
      final third = second.append(record(3, EditKind.undo, null));

      expect(empty.records, isEmpty);
      expect(first.records.length, 1);
      expect(second.records.length, 2);
      expect(third.records.length, 2);
      expect(third.records.map((entry) => entry.sequence), <int>[2, 3]);
      expect(third.nextSequence, 4);
      expect(third.last!.kind, EditKind.undo);
    });

    test('rejects an invalid retention bound', () {
      expect(() => EditLog(<EditRecord>[], maxRecords: 0), throwsArgumentError);
    });

    test('records are unmodifiable', () {
      final log = EditLog(<EditRecord>[record(1, EditKind.open, null)]);
      expect(
        () => log.records.add(record(2, EditKind.save, null)),
        throwsUnsupportedError,
      );
    });
  });

  group('JSON round-trip', () {
    test('serialises and restores every command and kind', () {
      final commands = <EditCommand>[
        SetScalar(health, 42),
        SetBit(health, 3, true),
        SetEnum(health, 'adult'),
        SetBytes(health, target: const ByteSpan(10, 3), bytes: <int>[1, 2, 3]),
      ];
      final kinds = <EditKind>[
        EditKind.apply,
        EditKind.undo,
        EditKind.redo,
        EditKind.reset,
        EditKind.duplicate,
        EditKind.open,
        EditKind.save,
      ];
      var log = EditLog.empty();
      var sequence = 1;
      for (final kind in kinds) {
        log = log.append(record(sequence, kind, null, description: kind.name));
        sequence++;
      }
      for (final command in commands) {
        log = log.append(
          record(
            sequence,
            EditKind.apply,
            command,
            description: command.description,
          ),
        );
        sequence++;
      }

      final encoded = log.encode();
      final decoded = EditLog.decode(encoded);

      expect(decoded.records.length, log.records.length);
      expect(decoded.records, log.records);
      expect(decoded.records.last.command, commands.last);
      expect(decoded.nextSequence, log.nextSequence);

      final viaJson = EditLog.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
      );
      expect(viaJson.records, log.records);
    });

    test('round-trips an empty log', () {
      final log = EditLog.empty();
      final decoded = EditLog.decode(log.encode());
      expect(decoded.records, isEmpty);
    });

    test('rejects unknown versions and malformed commands', () {
      expect(
        () => EditLog.fromJson(<String, Object?>{
          'version': 2,
          'records': <Object?>[],
        }),
        throwsFormatException,
      );
      expect(
        () => EditLog.decode('{"version":1,"records":{}}'),
        throwsFormatException,
      );
      expect(
        () => EditRecord.fromJson(<String, Object?>{
          'sequence': 1,
          'kind': 'apply',
          'at': at.toIso8601String(),
          'slot': 'slot_00',
          'beforeRevision': 0,
          'afterRevision': 1,
          'command': <String, Object?>{'type': 'nope', 'field': 'x'},
        }),
        throwsFormatException,
      );
    });
  });

  group('EditRecord', () {
    test('compares by all fields', () {
      final a = record(1, EditKind.apply, SetScalar(health, 1));
      final b = record(1, EditKind.apply, SetScalar(health, 1));
      final c = record(2, EditKind.apply, SetScalar(health, 1));

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('defaults description and byte count when absent from JSON', () {
      final decoded = EditRecord.fromJson(<String, Object?>{
        'sequence': 1,
        'kind': 'open',
        'at': at.toIso8601String(),
        'slot': 'slot_00',
        'beforeRevision': 0,
        'afterRevision': 0,
      });

      expect(decoded.command, isNull);
      expect(decoded.description, isEmpty);
      expect(decoded.byteCount, 0);
    });
  });
}
