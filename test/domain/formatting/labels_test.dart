import 'package:bomb_flower/domain/formatting/labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('titleFromFieldName', () {
    test('derives the leaf title from a dotted name', () {
      expect(titleFromFieldName('PlayerStatus.CurrentRupee'), 'Current Rupee');
      expect(titleFromFieldName('PlayerStatus.MaxLife'), 'Max Life');
      expect(titleFromFieldName('caption.sceneName'), 'Scene Name');
    });

    test('splits camel case without a dot', () {
      expect(titleFromFieldName('MaxLife'), 'Max Life');
      expect(titleFromFieldName('isAdult'), 'Is Adult');
      expect(titleFromFieldName('ocarinaSlotA'), 'Ocarina Slot A');
      expect(titleFromFieldName('Weapon_Sword_Kokiri'), 'Weapon Sword Kokiri');
    });

    test('uses the override map for awkward acronyms', () {
      expect(titleFromFieldName('caption.jpegLength'), 'JPEG Length');
      expect(fieldTitleOverrides['caption.jpegLength'], 'JPEG Length');
    });

    test('accepts a caller-supplied override map', () {
      expect(
        titleFromFieldName(
          'PlayerStatus.HP',
          overrides: const <String, String>{'PlayerStatus.HP': 'Health'},
        ),
        'Health',
      );
      expect(
        titleFromFieldName(
          'caption.jpegLength',
          overrides: const <String, String>{},
        ),
        'Jpeg Length',
      );
    });

    test('handles empty input', () {
      expect(titleFromFieldName(''), '');
      expect(titleFromFieldName('   '), '');
    });
  });

  group('groupFromFieldName', () {
    test('returns the prefix before the first dot', () {
      expect(groupFromFieldName('PlayerStatus.CurrentRupee'), 'PlayerStatus');
      expect(groupFromFieldName('caption.jpegLength'), 'caption');
    });

    test('returns an empty group when there is no prefix', () {
      expect(groupFromFieldName('Life'), '');
      expect(groupFromFieldName(''), '');
      expect(groupFromFieldName('.Life'), '');
    });
  });

  group('searchTokens', () {
    test('lowercases and splits dotted names', () {
      expect(searchTokens('PlayerStatus.CurrentRupee'), <String>[
        'player',
        'status',
        'current',
        'rupee',
      ]);
    });

    test('splits camel case and separators', () {
      expect(searchTokens('MaxLife'), <String>['max', 'life']);
      expect(searchTokens('Weapon_Sword-Kokiri'), <String>[
        'weapon',
        'sword',
        'kokiri',
      ]);
    });

    test('removes duplicates and preserves first-seen order', () {
      expect(searchTokens('Life life LIFE'), <String>['life']);
      expect(searchTokens('Rupee Life rupee'), <String>['rupee', 'life']);
    });

    test('returns no tokens for empty or punctuation-only input', () {
      expect(searchTokens(''), isEmpty);
      expect(searchTokens('  ...  '), isEmpty);
    });
  });
}
