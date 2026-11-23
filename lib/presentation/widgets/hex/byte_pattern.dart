import 'dart:typed_data';

/// A parsed byte-sequence search query.
///
/// Hex queries accept ASCII whitespace, commas, and an optional single `0x`
/// prefix, for example `DE AD BE EF`, `deadbeef`, or `0xDEADBEEF`. ASCII
/// queries use the query characters verbatim.
final class BytePattern {
  const BytePattern._(this.bytes);

  /// The bytes to find.
  final Uint8List bytes;

  /// Number of bytes in the pattern.
  int get length => bytes.length;

  /// Parses [query], returning `null` for a malformed query.
  ///
  /// Hex mode requires an even, non-zero number of hex digits. ASCII mode
  /// requires at least one character and rejects code units above `0xFF`.
  static BytePattern? tryParse(String query, {bool ascii = false}) {
    if (ascii) {
      if (query.isEmpty) return null;
      final units = query.codeUnits;
      if (units.any((unit) => unit > 0xFF)) return null;
      return BytePattern._(Uint8List.fromList(units));
    }

    var cleaned = query.replaceAll(RegExp(r'[\s,]+'), '');
    if (cleaned.startsWith('0x') || cleaned.startsWith('0X')) {
      cleaned = cleaned.substring(2);
    }
    if (cleaned.isEmpty || cleaned.length.isOdd) return null;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleaned)) return null;

    final bytes = Uint8List(cleaned.length ~/ 2);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = int.parse(
        cleaned.substring(index * 2, index * 2 + 2),
        radix: 16,
      );
    }
    return BytePattern._(bytes);
  }

  /// Finds non-overlapping matches of this pattern in [data].
  List<int> findAll(Uint8List data) {
    final matches = <int>[];
    if (bytes.isEmpty || data.length < bytes.length) return matches;

    final lastStart = data.length - bytes.length;
    for (var start = 0; start <= lastStart; start++) {
      var matched = true;
      for (var index = 0; index < bytes.length; index++) {
        if (data[start + index] != bytes[index]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        matches.add(start);
        start += bytes.length - 1;
      }
    }
    return matches;
  }
}
