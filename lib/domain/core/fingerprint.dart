/// Non-cryptographic content fingerprints.
///
/// FNV-1a 32 is used as a cheap dirty-check hint and as a stable diagnostic id.
/// It is not a checksum of a game save, is not collision resistant, and must
/// never be used to accept or reject a file.
library;

/// Fowler–Noll–Vo 1a, 32-bit variant.
abstract final class Fnv1a {
  /// The 32-bit FNV offset basis.
  static const int offsetBasis32 = 0x811c9dc5;

  /// The 32-bit FNV prime.
  static const int prime32 = 0x01000193;

  /// Hashes `bytes[start:end]` (half-open) into an unsigned 32-bit value.
  ///
  /// Byte values are masked to eight bits so a caller passing a plain
  /// `List<int>` cannot make the result depend on out-of-range values.
  static int hash32(List<int> bytes, {int start = 0, int? end}) {
    final stop = end ?? bytes.length;
    if (start < 0 || stop < start || stop > bytes.length) {
      throw RangeError(
        'Range [$start, $stop) is outside ${bytes.length} bytes',
      );
    }
    var hash = offsetBasis32;
    for (var i = start; i < stop; i++) {
      hash = ((hash ^ (bytes[i] & 0xff)) * prime32) & 0xffffffff;
    }
    return hash;
  }

  /// The hash as eight lower-case hexadecimal digits.
  static String hex32(int hash) =>
      (hash & 0xffffffff).toRadixString(16).padLeft(8, '0');
}
