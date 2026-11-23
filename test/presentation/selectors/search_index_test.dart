import 'package:bomb_flower/presentation/widgets/selectors/searchable_select.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final items = <String>[
    'Kokiri Sword',
    'Kokiri Shield',
    'Great Kokiri',
    'Master Sword',
    'Kókiri Tunic',
    'Somethingkokiri',
  ];

  SearchIndex<String> index({List<String>? values}) {
    final source = values ?? items;
    return SearchIndex<String>(items: source, label: (item) => item);
  }

  group('SearchIndex ranking', () {
    test('matches case-insensitively', () {
      expect(index().search('KOK'), contains('Kokiri Sword'));
    });

    test('folds diacritics in both the query and the label', () {
      expect(index().search('kok'), contains('Kókiri Tunic'));
      expect(index().search('KÓK'), contains('Kokiri Sword'));
      expect(foldSearchText('Kókiri'), 'kokiri');
    });

    test('removes combining marks from decomposed input', () {
      expect(foldSearchText('Ko\u0301kiri'), 'kokiri');
    });

    test('orders prefix before word-start before substring', () {
      final ranked = index().rank('kok');
      final labels = ranked.map((hit) => hit.item).toList();
      final prefix = labels.indexOf('Kokiri Sword');
      final wordStart = labels.indexOf('Great Kokiri');
      final substring = labels.indexOf('Somethingkokiri');

      expect(prefix, isNonNegative);
      expect(wordStart, greaterThan(prefix));
      expect(substring, greaterThan(wordStart));
    });

    test('prefers the shorter prefix within the same band', () {
      final ranked = SearchIndex<String>(
        items: <String>['Kokiri Village', 'Kokiri'],
        label: (item) => item,
      ).rank('kok');
      expect(ranked.first.item, 'Kokiri');
    });

    test('empty query returns every item in original order', () {
      final ranked = index().rank('');
      expect(ranked.map((hit) => hit.item).toList(), items);
      expect(ranked.every((hit) => hit.score == 0), isTrue);
    });

    test('no match returns an empty ranking', () {
      expect(index().search('ganon'), isEmpty);
    });

    test('search extractor can add keywords not in the label', () {
      final searchable = SearchIndex<String>(
        items: <String>['Sword', 'Shield'],
        label: (item) => item,
        search: (item) => item == 'Sword' ? 'Sword master kokiri' : item,
      );
      expect(searchable.search('kokiri'), <String>['Sword']);
    });

    test('ties preserve insertion order', () {
      final ranked = SearchIndex<String>(
        items: <String>['Aaa', 'Bbb'],
        label: (item) => item,
      ).rank('');
      expect(ranked.map((hit) => hit.item).toList(), <String>['Aaa', 'Bbb']);
    });

    test('scoreAt returns null for out-of-range indices', () {
      expect(index().scoreAt(-1, 'kok'), isNull);
      expect(index().scoreAt(99, 'kok'), isNull);
      expect(index().scoreAt(0, 'kok'), isNotNull);
    });
  });
}
