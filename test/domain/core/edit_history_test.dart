import 'package:bomb_flower/domain/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const slot = SaveSlotId('slot_00');
  final field = const FieldId('player.health');
  var clock = DateTime.utc(2026, 1, 1, 12);

  DateTime now() => clock;

  SaveSnapshot snapshot(int revision, int byte) =>
      SaveSnapshot(slot, revision, ByteRegion.fromBytes(<int>[byte]));

  SetScalar scalar(int value) => SetScalar(field, value);

  late EditHistory history;

  setUp(() {
    clock = DateTime.utc(2026, 1, 1, 12);
    history = EditHistory(clock: now);
  });

  void advance(int milliseconds) {
    clock = clock.add(Duration(milliseconds: milliseconds));
  }

  group('recording and coalescing', () {
    test('records one entry and exposes the changelist', () {
      final before = snapshot(0, 0);
      final after = snapshot(1, 1);
      history.record(scalar(1), before, after);

      expect(history.canUndo, isTrue);
      expect(history.changelist.length, 1);
      expect(history.changelist.single.before, before);
      expect(history.changelist.single.after, after);
      expect(history.changelist.single.commands, <EditCommand>[scalar(1)]);
      expect(history.changelistSummary, contains('SetScalar'));
    });

    test('coalesces same-field rapid edits inside the window', () {
      final before = snapshot(0, 0);
      final first = snapshot(1, 1);
      final second = snapshot(2, 2);

      history.record(scalar(1), before, first);
      advance(100);
      history.record(scalar(2), first, second);

      expect(history.changelist.length, 1);
      expect(history.changelist.single.before, before);
      expect(history.changelist.single.after, second);
      expect(history.changelist.single.commands, <EditCommand>[
        scalar(1),
        scalar(2),
      ]);
    });

    test('does not coalesce outside the window', () {
      history.record(scalar(1), snapshot(0, 0), snapshot(1, 1));
      advance(401);
      history.record(scalar(2), snapshot(1, 1), snapshot(2, 2));

      expect(history.changelist.length, 2);
    });

    test('does not coalesce across fields or command types', () {
      history.record(scalar(1), snapshot(0, 0), snapshot(1, 1));
      advance(10);
      history.record(
        const SetScalar(FieldId('other'), 1),
        snapshot(1, 1),
        snapshot(2, 2),
      );
      expect(history.changelist.length, 2);

      history = EditHistory(clock: now);
      history.record(scalar(1), snapshot(0, 0), snapshot(1, 1));
      advance(10);
      history.record(SetBit(field, 0, true), snapshot(1, 1), snapshot(2, 2));
      expect(history.changelist.length, 2);
    });

    test('SetBytes coalesces only for the same target span', () {
      SetBytes command(int offset) =>
          SetBytes(field, target: ByteSpan(offset, 1), bytes: <int>[1]);

      history.record(command(0), snapshot(0, 0), snapshot(1, 1));
      advance(10);
      history.record(command(0), snapshot(1, 1), snapshot(2, 2));
      expect(history.changelist.length, 1);

      advance(10);
      history.record(command(1), snapshot(2, 2), snapshot(3, 3));
      expect(history.changelist.length, 2);
    });

    test('seal starts a new group', () {
      history.record(scalar(1), snapshot(0, 0), snapshot(1, 1));
      advance(10);
      history.seal();
      history.record(scalar(2), snapshot(1, 1), snapshot(2, 2));
      advance(10);
      history.record(scalar(3), snapshot(2, 2), snapshot(3, 3));

      expect(history.changelist.length, 2);
      expect(history.changelist.last.commands.length, 2);
    });

    test('coalesce:false starts a new entry', () {
      history.record(scalar(1), snapshot(0, 0), snapshot(1, 1));
      advance(10);
      history.record(
        scalar(2),
        snapshot(1, 1),
        snapshot(2, 2),
        coalesce: false,
      );

      expect(history.changelist.length, 2);
    });
  });

  group('undo and redo', () {
    test('undo moves an entry to redo and redo moves it back', () {
      final before = snapshot(0, 0);
      final after = snapshot(1, 1);
      history.record(scalar(1), before, after);

      final undone = history.undo();
      expect(undone, isNotNull);
      expect(undone!.before, before);
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isTrue);

      final redone = history.redo();
      expect(redone, isNotNull);
      expect(redone!.after, after);
      expect(history.canUndo, isTrue);
      expect(history.canRedo, isFalse);
    });

    test('undo and redo on empty stacks return null', () {
      expect(history.undo(), isNull);
      expect(history.redo(), isNull);
    });

    test('a new edit clears redo', () {
      history.record(scalar(1), snapshot(0, 0), snapshot(1, 1));
      expect(history.undo(), isNotNull);
      expect(history.canRedo, isTrue);

      advance(1000);
      history.record(scalar(2), snapshot(1, 1), snapshot(2, 2));
      expect(history.canRedo, isFalse);
    });

    test('clear empties both stacks without touching bytes', () {
      history.record(scalar(1), snapshot(0, 0), snapshot(1, 1));
      history.undo();
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isTrue);

      history.clear();
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
    });
  });

  group('bounded depth', () {
    test('default depth is 100 and evicts the oldest', () {
      for (var i = 0; i < 101; i++) {
        history.record(
          SetScalar(FieldId('field.$i'), i),
          snapshot(i, i),
          snapshot(i + 1, i + 1),
        );
      }

      expect(history.changelist.length, 100);
      expect(history.changelist.first.before.revision, 1);
      expect(history.changelist.last.after.revision, 101);
    });

    test('custom maxDepth is honoured', () {
      history = EditHistory(maxDepth: 2, clock: now);
      for (var i = 0; i < 3; i++) {
        history.record(
          SetScalar(FieldId('field.$i'), i),
          snapshot(i, i),
          snapshot(i + 1, i + 1),
        );
      }

      expect(history.changelist.length, 2);
      expect(history.changelist.first.before.revision, 1);
    });
  });

  group('transactions', () {
    test('commits all records as one entry', () {
      final before = snapshot(0, 0);
      final first = snapshot(1, 1);
      final second = snapshot(2, 2);

      history.beginTransaction('Group');
      expect(history.inTransaction, isTrue);
      history.record(scalar(1), before, first);
      history.record(scalar(2), first, second);
      expect(history.canUndo, isFalse);
      expect(history.transactionBefore, before);

      history.commitTransaction();
      expect(history.inTransaction, isFalse);
      expect(history.changelist.length, 1);
      expect(history.changelist.single.label, 'Group');
      expect(history.changelist.single.commands.length, 2);
      expect(history.changelist.single.before, before);
      expect(history.changelist.single.after, second);
    });

    test('rollback returns the pre-group snapshot and pushes nothing', () {
      final before = snapshot(0, 0);
      history.beginTransaction('Group');
      history.record(scalar(1), before, snapshot(1, 1));

      expect(history.rollbackTransaction(), before);
      expect(history.canUndo, isFalse);
      expect(history.inTransaction, isFalse);
      expect(history.transactionBefore, isNull);
    });

    test('rollback of an empty group returns null', () {
      history.beginTransaction('Empty');
      expect(history.rollbackTransaction(), isNull);
    });

    test('nested transactions throw', () {
      history.beginTransaction('One');
      expect(() => history.beginTransaction('Two'), throwsStateError);
      history.rollbackTransaction();
    });

    test('commit or rollback without a transaction throws', () {
      expect(history.commitTransaction, throwsStateError);
      expect(history.rollbackTransaction, throwsStateError);
    });

    test('undo, redo, and clear during a transaction throw', () {
      history.beginTransaction('Group');
      expect(history.undo, throwsStateError);
      expect(history.redo, throwsStateError);
      expect(history.clear, throwsStateError);
      history.rollbackTransaction();
    });

    test('transaction edits do not coalesce with later edits', () {
      history.beginTransaction('Group');
      history.record(scalar(1), snapshot(0, 0), snapshot(1, 1));
      history.commitTransaction();
      advance(10);
      history.record(scalar(2), snapshot(1, 1), snapshot(2, 2));

      expect(history.changelist.length, 2);
    });
  });

  group('synthetic entries', () {
    test('recordSynthetic stores no commands', () {
      final before = snapshot(0, 0);
      final after = snapshot(1, 1);
      history.recordSynthetic('Reset slot_00 to original', before, after);

      expect(history.changelist.single.commands, isEmpty);
      expect(history.changelist.single.label, contains('Reset'));
      expect(history.changelist.single.before, before);
      expect(history.changelist.single.after, after);
    });

    test('recordSynthetic is refused during a transaction', () {
      history.beginTransaction('Group');
      expect(
        () => history.recordSynthetic('Reset', snapshot(0, 0), snapshot(1, 1)),
        throwsStateError,
      );
      history.rollbackTransaction();
    });
  });
}
