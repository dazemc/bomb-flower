/// Field-name, group and search-token derivation for the save editor.
///
/// Field names in the save layout are identifiers such as
/// `PlayerStatus.CurrentRupee` and `caption.jpegLength`. The functions here turn
/// them into stable labels and search tokens without touching Flutter or the
/// filesystem.
library;

/// Human labels for field names whose automatic title is wrong or awkward.
///
/// The automatic rule splits camel case and underscores and capitalises each
/// word. It cannot know acronyms (`JPEG`) or names the format spells as one
/// word, so those are listed here. Keys are full field names, including the
/// group prefix, so a leaf name can be overridden only in the group where that
/// is correct.
const Map<String, String> fieldTitleOverrides = <String, String>{
  'PlayerStatus.CurrentRupee': 'Current Rupee',
  'PlayerStatus.MaxLife': 'Max Life',
  'PlayerStatus.Life': 'Life',
  'caption.sceneName': 'Scene Name',
  'caption.mapPath': 'Map Path',
  'caption.jpegLength': 'JPEG Length',
};

/// Derives a title from a dotted field name.
///
/// The leaf after the last dot is split on dots, underscores, hyphens and
/// whitespace, then on camel-case boundaries, and each word gets a leading
/// capital: `"PlayerStatus.CurrentRupee"` → `"Current Rupee"`,
/// `"MaxLife"` → `"Max Life"`, `"isAdult"` → `"Is Adult"`.
///
/// [overrides] is consulted first with the full trimmed name. It defaults to
/// [fieldTitleOverrides], which maps `"caption.jpegLength"` to `"JPEG Length"`
/// rather than the automatic `"Jpeg Length"`. Pass an empty map to see the
/// automatic title.
String titleFromFieldName(
  String fieldName, {
  Map<String, String> overrides = fieldTitleOverrides,
}) {
  final trimmed = fieldName.trim();
  final override = overrides[trimmed];
  if (override != null) {
    return override;
  }
  if (trimmed.isEmpty) {
    return '';
  }
  final leaf = trimmed.split('.').last;
  return _tokenize(leaf).map(_capitalize).join(' ');
}

/// Returns the group before the first dot, or `''` when there is no group.
///
/// `"PlayerStatus.CurrentRupee"` → `"PlayerStatus"`,
/// `"caption.jpegLength"` → `"caption"`, `"Life"` → `""`. A leading dot has an
/// empty group, which is also returned as `''`.
String groupFromFieldName(String fieldName) {
  final separator = fieldName.indexOf('.');
  if (separator <= 0) {
    return '';
  }
  return fieldName.substring(0, separator);
}

/// Splits [value] into lower-case search tokens, preserving first-seen order
/// and removing duplicates.
///
/// `"PlayerStatus.CurrentRupee"` → `["player", "status", "current", "rupee"]`,
/// `"MaxLife"` → `["max", "life"]`, `"Life life"` → `["life"]`, and an empty or
/// punctuation-only string → `[]`. The input is split on dots, underscores,
/// hyphens and whitespace, plus camel-case boundaries.
List<String> searchTokens(String value) {
  final seen = <String>{};
  final tokens = <String>[];
  for (final token in _tokenize(value)) {
    final lower = token.toLowerCase();
    if (lower.isEmpty || !seen.add(lower)) {
      continue;
    }
    tokens.add(lower);
  }
  return List<String>.unmodifiable(tokens);
}

final RegExp _separators = RegExp(r'[_.\-\s]+');
final RegExp _lowerToUpper = RegExp(r'([a-z0-9])([A-Z])');
final RegExp _acronymToWord = RegExp(r'([A-Z]+)([A-Z][a-z])');

List<String> _tokenize(String value) {
  final spaced = value
      .replaceAll(_separators, ' ')
      .replaceAllMapped(_lowerToUpper, (match) => '${match[1]} ${match[2]}')
      .replaceAllMapped(_acronymToWord, (match) => '${match[1]} ${match[2]}');
  return spaced
      .split(' ')
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
}

String _capitalize(String token) {
  if (token.isEmpty) {
    return token;
  }
  final first = token.substring(0, 1);
  final upper = first.toUpperCase();
  if (upper == first) {
    return token;
  }
  return '$upper${token.substring(1)}';
}
