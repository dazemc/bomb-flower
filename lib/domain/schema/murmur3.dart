/// MurmurHash3_x86_32, the hash the game uses for GameData field names.
///
/// Implemented here with `dart:convert` only so both the schema loader and the
/// standalone generator can use the exact same code. Names are UTF-8 encoded;
/// all GameData names are ASCII, but the implementation does not rely on that.
library;

import 'dart:convert';

/// The 32-bit MurmurHash3 x86 hash of [input] with [seed] (default `0`).
///
/// The algorithm follows Austin Appleby's reference `MurmurHash3_x86_32`,
/// including the little-endian 4-byte blocks, the tail handling, and the
/// final avalanche. The result is always in `0x00000000..0xffffffff`.
int murmur3X86_32(String input, [int seed = 0]) {
  final data = utf8.encode(input);
  var hash = seed & 0xffffffff;
  const c1 = 0xcc9e2d51;
  const c2 = 0x1b873593;

  var index = 0;
  while (index + 4 <= data.length) {
    var k =
        data[index] |
        (data[index + 1] << 8) |
        (data[index + 2] << 16) |
        (data[index + 3] << 24);
    k = (k * c1) & 0xffffffff;
    k = ((k << 15) | (k >> 17)) & 0xffffffff;
    k = (k * c2) & 0xffffffff;

    hash ^= k;
    hash = ((hash << 13) | (hash >> 19)) & 0xffffffff;
    hash = (hash * 5 + 0xe6546b64) & 0xffffffff;
    index += 4;
  }

  final remaining = data.length - index;
  var tail = 0;
  if (remaining >= 3) {
    tail ^= data[index + 2] << 16;
  }
  if (remaining >= 2) {
    tail ^= data[index + 1] << 8;
  }
  if (remaining >= 1) {
    tail ^= data[index];
  }
  if (remaining > 0) {
    tail = (tail * c1) & 0xffffffff;
    tail = ((tail << 15) | (tail >> 17)) & 0xffffffff;
    tail = (tail * c2) & 0xffffffff;
    hash ^= tail;
  }

  hash ^= data.length;
  hash ^= hash >> 16;
  hash = (hash * 0x85ebca6b) & 0xffffffff;
  hash ^= hash >> 13;
  hash = (hash * 0xc2b2ae35) & 0xffffffff;
  hash ^= hash >> 16;
  return hash & 0xffffffff;
}

/// Formats a 32-bit hash as lower-case `0x` plus eight hex digits.
String hashHex(int hash) =>
    '0x${(hash & 0xffffffff).toRadixString(16).padLeft(8, '0')}';

/// Formats a schema revision as lower-case `0x` without leading zeroes.
String revisionHex(int revision) => '0x${revision.toRadixString(16)}';
