import 'package:bomb_flower/domain/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  const slot = SaveSlotId('slot_00');

  group('DirtyState', () {
    test('clean has no badges', () {
      expect(DirtyState.clean.isClean, isTrue);
      expect(DirtyState.clean.isModified, isFalse);
      expect(DirtyState.clean.changedFieldCount, 0);
      expect(DirtyState.clean.changedByteCount, 0);
      expect(DirtyState.clean.dirtySlots, isEmpty);
      expect(DirtyState.clean.changedFields, isEmpty);
    });

    test('compares all fields and sets by value', () {
      const a = DirtyState(
        true,
        false,
        1,
        2,
        <SaveSlotId>{progressSlot},
        changedFields: <FieldId>{healthId},
      );
      const b = DirtyState(
        true,
        false,
        1,
        2,
        <SaveSlotId>{progressSlot},
        changedFields: <FieldId>{healthId},
      );
      const c = DirtyState(
        true,
        false,
        1,
        2,
        <SaveSlotId>{progressSlot},
        changedFields: <FieldId>{flagsId},
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a.toString(), contains('slot_00'));
    });
  });

  group('ValidationIssue', () {
    test('only errors are blocking', () {
      const info = ValidationIssue(
        Severity.info,
        ValidationCodes.fieldUnverified,
        'info',
        slot,
      );
      const warning = ValidationIssue(
        Severity.warning,
        ValidationCodes.integrityUnconfirmed,
        'warning',
        slot,
      );
      const error = ValidationIssue(
        Severity.error,
        ValidationCodes.fileSizeMismatch,
        'error',
        slot,
      );

      expect(info.isBlocking, isFalse);
      expect(warning.isBlocking, isFalse);
      expect(error.isBlocking, isTrue);
    });

    test('value equality includes optional context', () {
      const a = ValidationIssue(
        Severity.error,
        'code',
        'message',
        progressSlot,
        field: healthId,
        remedy: 'fix',
      );
      const b = ValidationIssue(
        Severity.error,
        'code',
        'message',
        progressSlot,
        field: healthId,
        remedy: 'fix',
      );
      const c = ValidationIssue(
        Severity.error,
        'code',
        'message',
        progressSlot,
        field: healthId,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a.toString(), contains('slot_00'));
    });
  });

  group('ValidationResult', () {
    test('aggregates blocking and non-blocking issues', () {
      final result = ValidationResult(<ValidationIssue>[
        const ValidationIssue(
          Severity.warning,
          ValidationCodes.fieldUnverified,
          'warning',
          progressSlot,
          field: unknownId,
        ),
        const ValidationIssue(
          Severity.error,
          ValidationCodes.fileSizeMismatch,
          'error',
          progressSlot,
        ),
        const ValidationIssue(
          Severity.info,
          ValidationCodes.fieldUnverified,
          'info',
          SaveSlotId.account,
        ),
      ]);

      expect(result.hasBlockingErrors, isTrue);
      expect(result.canExport, isFalse);
      expect(result.blockingIssues.length, 1);
      expect(result.nonBlockingIssues.length, 2);
      expect(result.forSlot(progressSlot).length, 2);
      expect(result.forSlot(accountLayout.id).length, 1);
      expect(result.forSlot(const SaveSlotId('missing')), isEmpty);
    });

    test('warnings alone do not block export', () {
      final result = ValidationResult(<ValidationIssue>[
        const ValidationIssue(
          Severity.warning,
          ValidationCodes.fieldUnverified,
          'warning',
          progressSlot,
        ),
      ]);

      expect(result.hasBlockingErrors, isFalse);
      expect(result.canExport, isTrue);
    });

    test('empty result is clean', () {
      expect(const ValidationResult.empty().hasBlockingErrors, isFalse);
      expect(const ValidationResult.empty().isEmpty, isTrue);
      expect(const ValidationResult.empty().canExport, isTrue);
    });

    test('copies its input', () {
      final issues = <ValidationIssue>[
        const ValidationIssue(Severity.info, 'code', 'message', progressSlot),
      ];
      final result = ValidationResult(issues);
      issues.clear();

      expect(result.issues.length, 1);
      expect(result.issues, isNotEmpty);
    });
  });
}
