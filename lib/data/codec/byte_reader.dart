import 'dart:typed_data';

/// A bounds-checked reader for the integer primitives used by save codecs.
///
/// Every read states its byte order explicitly. A read outside the buffer
/// throws [ByteReaderRangeError] instead of returning a truncated or shifted
/// value, so a codec can turn malformed input into a typed failure rather than
/// indexing past the end.
final class ByteReader {
  const ByteReader(this.bytes, {this.label = 'buffer'});

  /// The buffer being read. It is not copied.
  final Uint8List bytes;

  /// A name used in range-error messages, such as a file name.
  final String label;

  /// The number of bytes available.
  int get length => bytes.length;

  /// Throws [ByteReaderRangeError] unless `[offset, offset + size)` is inside
  /// the buffer and `size` is not negative.
  void checkBounds(int offset, int size) {
    if (size < 0 || offset < 0 || offset > length - size) {
      throw ByteReaderRangeError(
        label: label,
        offset: offset,
        size: size,
        available: length,
      );
    }
  }

  /// Reads one unsigned byte at [offset].
  int u8(int offset) {
    checkBounds(offset, 1);
    return bytes[offset];
  }

  /// Reads a little-endian unsigned 16-bit integer at [offset].
  int u16le(int offset) {
    checkBounds(offset, 2);
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  /// Reads a big-endian unsigned 16-bit integer at [offset].
  int u16be(int offset) {
    checkBounds(offset, 2);
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  /// Reads a little-endian unsigned 32-bit integer at [offset].
  int u32le(int offset) {
    checkBounds(offset, 4);
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  /// Reads a big-endian unsigned 32-bit integer at [offset].
  int u32be(int offset) {
    checkBounds(offset, 4);
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  /// Returns a copy of `size` bytes starting at [offset].
  Uint8List copyRange(int offset, int size) {
    checkBounds(offset, size);
    return Uint8List.fromList(bytes.sublist(offset, offset + size));
  }
}

/// The buffer was shorter than a requested read.
final class ByteReaderRangeError extends Error {
  ByteReaderRangeError({
    required this.label,
    required this.offset,
    required this.size,
    required this.available,
  });

  /// The buffer's name.
  final String label;

  /// The requested start offset.
  final int offset;

  /// The requested byte count.
  final int size;

  /// The buffer's actual length.
  final int available;

  @override
  String toString() =>
      '$label: cannot read $size byte(s) at $offset; '
      'the buffer is $available byte(s) long';
}
