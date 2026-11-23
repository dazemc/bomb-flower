import 'package:bomb_flower/data/system/directory_picker.dart';
import 'package:bomb_flower/data/system/open_diagnostics.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

SaveFolderInfo folder({
  required String path,
  bool exists = true,
  bool isDirectory = true,
  bool progressSavePresent = false,
  List<String> slots = const <String>[],
}) => SaveFolderInfo(
  path: path,
  exists: exists,
  isDirectory: isDirectory,
  progressSavePresent: progressSavePresent,
  slotDirectories: slots,
);

void main() {
  group('slot folder diagnosis', () {
    test('a slot_NN folder holding progress.sav names its parent', () {
      final info = folder(
        path: '/saves/kokiri-start/slot_00',
        progressSavePresent: true,
      );

      expect(isSlotFolderRoot(info), isTrue);
      expect(
        slotFolderMisselection(info),
        'That is a slot folder. Choose the folder that contains it '
        '(/saves/kokiri-start).',
      );
    });

    test('a real save root is not diagnosed as a slot folder', () {
      final info = folder(
        path: '/saves/kokiri-start',
        slots: <String>['slot_00', 'slot_01'],
      );

      expect(isSlotFolderRoot(info), isFalse);
      expect(slotFolderMisselection(info), isNull);
    });

    test('a slot-named folder without progress.sav is not a slot root', () {
      final info = folder(path: '/saves/kokiri-start/slot_00');

      expect(isSlotFolderRoot(info), isFalse);
      expect(slotFolderMisselection(info), isNull);
    });

    test('progress.sav in a folder that is not slot_NN is not a slot root', () {
      final info = folder(
        path: '/saves/kokiri-start',
        progressSavePresent: true,
      );

      expect(isSlotFolderRoot(info), isFalse);
      expect(slotFolderMisselection(info), isNull);
    });

    test('a missing folder is never diagnosed', () {
      final info = folder(
        path: '/saves/kokiri-start/slot_00',
        exists: false,
        isDirectory: false,
        progressSavePresent: true,
      );

      expect(slotFolderMisselection(info), isNull);
    });
  });

  group('open log line', () {
    test('a verified open logs the bare outcome', () {
      expect(
        formatOpenLogLine(path: '/saves/a', outcome: OpenOutcome.ok),
        'open /saves/a -> ParseOk',
      );
    });

    test('an unverified open logs the bare outcome even with a reason', () {
      expect(
        formatOpenLogLine(
          path: '/saves/a',
          outcome: OpenOutcome.unverified,
          reason: 'ignored',
        ),
        'open /saves/a -> ParseUnverified',
      );
    });

    test('an unsupported open logs its reason', () {
      expect(
        formatOpenLogLine(
          path: '/saves/a',
          outcome: OpenOutcome.unsupported,
          reason: 'detected layout version 9',
        ),
        'open /saves/a -> ParseUnsupported: detected layout version 9',
      );
    });

    test('a corrupt open logs its reason and never any field values', () {
      const reason = 'record 41 ends past the file end';
      const fieldValue = '0xDEADBEEF';

      final line = formatOpenLogLine(
        path: '/saves/a',
        outcome: OpenOutcome.corrupt,
        reason: reason,
      );

      expect(line, 'open /saves/a -> ParseCorrupt: $reason');
      expect(line, isNot(contains(fieldValue)));
    });

    test('a parse result maps onto its outcome and reason', () {
      final ok = openOutcomeOf(ParseOk(_project()));
      expect(ok.outcome, OpenOutcome.ok);
      expect(ok.reason, isNull);

      final unverified = openOutcomeOf(
        ParseUnverified(_project(), const <FieldId>[]),
      );
      expect(unverified.outcome, OpenOutcome.unverified);

      final unsupported = openOutcomeOf(
        const ParseUnsupported('version 12 is newer'),
      );
      expect(unsupported.outcome, OpenOutcome.unsupported);
      expect(unsupported.reason, 'version 12 is newer');

      final corrupt = openOutcomeOf(const ParseCorrupt('bad magic'));
      expect(corrupt.outcome, OpenOutcome.corrupt);
      expect(corrupt.reason, 'bad magic');
    });
  });
}

const LayoutDescriptor _layout = LayoutDescriptor(
  'diagnostics-layout',
  1,
  <SaveSlotLayout>[],
);

SaveProject _project() => SaveProject(
  'diagnostics-project',
  '/saves/a',
  '/saves/a.bombflower',
  _layout,
  1,
  const <SaveSlotId, SaveSnapshot>{},
  const <SaveSlotId, SaveDocument>{},
  const <SaveSlotId, int>{},
  EditHistory(),
  EditLog.empty(),
);
