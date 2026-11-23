import 'dart:math' as math;

/// A ranked search result from [SearchIndex].
class SearchHit<T> {
  const SearchHit({
    required this.item,
    required this.index,
    required this.score,
  });

  final T item;

  /// Position in the original item list; ties preserve insertion order.
  final int index;

  final int score;

  @override
  String toString() => 'SearchHit($index, score: $score)';
}

/// Pure-Dart, diacritic- and case-insensitive search ranking.
///
/// A match is scored in one of four bands — exact whole string, prefix, word
/// start, substring — then given a small bonus for a shorter label so that
/// "Kokiri" outranks "Kokiri Village Archive" within the prefix band. Ties keep
/// the original list order. No Flutter types are used, so the ranking can be
/// unit-tested on its own.
class SearchIndex<T> {
  SearchIndex({
    required Iterable<T> items,
    required String Function(T item) label,
    String Function(T item)? search,
  }) : _items = List<T>.unmodifiable(items) {
    for (var index = 0; index < _items.length; index++) {
      final item = _items[index];
      final foldedLabel = foldSearchText(label(item));
      final foldedSearch = foldSearchText((search ?? label)(item));
      _labels.add(foldedLabel);
      _haystacks.add(foldedSearch);
      _wordStarts.add(_collectWordStarts(foldedSearch));
    }
  }

  static const int exactScore = 1000;
  static const int prefixScore = 800;
  static const int wordStartScore = 600;
  static const int substringScore = 400;

  static const int _lengthBonusCeiling = 40;

  final List<T> _items;
  final List<String> _labels = <String>[];
  final List<String> _haystacks = <String>[];
  final List<Set<int>> _wordStarts = <Set<int>>[];

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;

  List<T> get items => _items;

  /// Ranked matches for [query]. An empty query returns every item in original
  /// order with score 0.
  List<SearchHit<T>> rank(String query) {
    final folded = foldSearchText(query);
    final hits = <SearchHit<T>>[];
    for (var index = 0; index < _items.length; index++) {
      if (folded.isEmpty) {
        hits.add(SearchHit<T>(item: _items[index], index: index, score: 0));
        continue;
      }
      final score = _scoreAt(index, folded);
      if (score != null) {
        hits.add(SearchHit<T>(item: _items[index], index: index, score: score));
      }
    }
    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });
    return List<SearchHit<T>>.unmodifiable(hits);
  }

  /// Convenience wrapper returning only the matching items.
  List<T> search(String query) {
    return List<T>.unmodifiable(rank(query).map((hit) => hit.item));
  }

  /// The score for the item at [index], or null when it does not match.
  int? scoreAt(int index, String query) {
    if (index < 0 || index >= _items.length) return null;
    final folded = foldSearchText(query);
    if (folded.isEmpty) return 0;
    return _scoreAt(index, folded);
  }

  int? _scoreAt(int index, String foldedQuery) {
    final haystack = _haystacks[index];
    if (haystack.isEmpty) return null;

    final int base;
    if (haystack == foldedQuery) {
      base = exactScore;
    } else if (haystack.startsWith(foldedQuery)) {
      base = prefixScore;
    } else if (_matchesWordStart(index, foldedQuery)) {
      base = wordStartScore;
    } else if (haystack.contains(foldedQuery)) {
      base = substringScore;
    } else {
      return null;
    }

    final bonus = math.max(0, _lengthBonusCeiling - _labels[index].length);
    return base + bonus;
  }

  bool _matchesWordStart(int index, String foldedQuery) {
    final haystack = _haystacks[index];
    final starts = _wordStarts[index];
    var from = 0;
    while (from <= haystack.length - foldedQuery.length) {
      final at = haystack.indexOf(foldedQuery, from);
      if (at < 0) return false;
      if (starts.contains(at)) return true;
      from = at + 1;
    }
    return false;
  }

  static Set<int> _collectWordStarts(String haystack) {
    final starts = <int>{0};
    for (var i = 1; i < haystack.length; i++) {
      if (!_isWordChar(haystack.codeUnitAt(i - 1))) starts.add(i);
    }
    return starts;
  }

  static bool _isWordChar(int codeUnit) {
    return (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
        (codeUnit >= 0x30 && codeUnit <= 0x39);
  }
}

/// Folds case, combining marks, and common Latin diacritics to ASCII.
///
/// This is deliberately a table, not a locale database: the app ships no
/// locale data and the catalogue names are Latin script. It is pure Dart so the
/// search index can be tested without a widget binding.
String foldSearchText(String input) {
  final lower = input.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    // Combining marks left behind by decomposed input (e + U+0301).
    if (rune >= 0x0300 && rune <= 0x036F) continue;
    final character = String.fromCharCode(rune);
    buffer.write(_diacriticFold[character] ?? character);
  }
  return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

const Map<String, String> _diacriticFold = <String, String>{
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'æ': 'ae',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'ď': 'd',
  'đ': 'd',
  'ð': 'd',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ė': 'e',
  'ę': 'e',
  'ě': 'e',
  'ğ': 'g',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'į': 'i',
  'ł': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ő': 'o',
  'œ': 'oe',
  'ř': 'r',
  'ś': 's',
  'š': 's',
  'ş': 's',
  'ß': 'ss',
  'ť': 't',
  'þ': 'th',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ű': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ź': 'z',
  'ż': 'z',
  'ž': 'z',
};
