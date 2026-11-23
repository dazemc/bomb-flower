import 'dart:typed_data';

/// Builds synthetic save buffers in memory, with no committed binary fixtures.
///
/// The progress skeleton is [progressSaveSize] zero bytes. The caption
/// skeleton is [captionSaveSize] zero bytes with the verified magic
/// `04 03 02 01` at offset 0. Callers then set the fields they care about.
///
/// The builder is mutable and fluent; [build] returns an independent copy.
class SaveFixtureBuilder {
  SaveFixtureBuilder._(this._bytes);

  /// Creates an all-zero progress.sav skeleton.
  factory SaveFixtureBuilder.progress() =>
      SaveFixtureBuilder._(Uint8List(progressSaveSize));

  /// Creates a caption.sav skeleton with the verified magic bytes.
  factory SaveFixtureBuilder.caption() {
    final bytes = Uint8List(captionSaveSize);
    bytes.setRange(0, captionMagic.length, captionMagic);
    return SaveFixtureBuilder._(bytes);
  }

  /// Size of the sample progress.sav files.
  static const int progressSaveSize = 120572;

  /// Size of the sample caption.sav files.
  static const int captionSaveSize = 4741;

  /// Verified caption.sav magic at offset 0.
  static const List<int> captionMagic = <int>[0x04, 0x03, 0x02, 0x01];

  /// Offset of the little-endian JPEG length in caption.sav.
  static const int captionJpegLengthOffset = 1392;

  /// Offset where the JPEG payload starts in caption.sav.
  static const int captionJpegOffset = 1396;

  /// Largest payload that fits in the caption skeleton.
  static const int maxJpegLength = captionSaveSize - captionJpegOffset;

  final Uint8List _bytes;

  /// Current buffer length in bytes.
  int get length => _bytes.length;

  /// Writes one byte at [offset].
  SaveFixtureBuilder withU8(int offset, int value) {
    _checkUnsigned(value, 0xff, 'value');
    _requireSpace(offset, 1);
    _bytes[offset] = value;
    return this;
  }

  /// Writes a big-endian 16-bit value at [offset].
  SaveFixtureBuilder withU16(int offset, int value) {
    _checkUnsigned(value, 0xffff, 'value');
    _requireSpace(offset, 2);
    ByteData.sublistView(_bytes).setUint16(offset, value, Endian.big);
    return this;
  }

  /// Writes a big-endian 32-bit value at [offset].
  SaveFixtureBuilder withU32(int offset, int value) {
    _checkUnsigned(value, 0xffffffff, 'value');
    _requireSpace(offset, 4);
    ByteData.sublistView(_bytes).setUint32(offset, value, Endian.big);
    return this;
  }

  /// Writes [bytes] starting at [offset].
  ///
  /// Throws [RangeError] when the write would fall outside the fixture.
  SaveFixtureBuilder withBytesAt(int offset, List<int> bytes) {
    _requireSpace(offset, bytes.length);
    for (final byte in bytes) {
      _checkUnsigned(byte, 0xff, 'byte');
    }
    _bytes.setRange(offset, offset + bytes.length, bytes);
    return this;
  }

  /// Sets the little-endian JPEG length field in caption.sav.
  ///
  /// This does not write a payload; use [withJpegPayload] to set both.
  SaveFixtureBuilder withJpegLength(int length) {
    _requireCaption('withJpegLength');
    _checkUnsigned(length, maxJpegLength, 'length');
    _setU32LittleEndian(captionJpegLengthOffset, length);
    return this;
  }

  /// Writes a JPEG payload at [captionJpegOffset] and updates its length.
  ///
  /// The rest of the caption buffer is zeroed so repeated builds stay
  /// deterministic.
  SaveFixtureBuilder withJpegPayload(List<int> payload) {
    _requireCaption('withJpegPayload');
    if (payload.length > maxJpegLength) {
      throw RangeError.range(
        payload.length,
        0,
        maxJpegLength,
        'payload.length',
        'JPEG payload does not fit in the caption fixture',
      );
    }
    for (final byte in payload) {
      _checkUnsigned(byte, 0xff, 'byte');
    }

    _setU32LittleEndian(captionJpegLengthOffset, payload.length);
    _bytes.setRange(
      captionJpegOffset,
      captionJpegOffset + payload.length,
      payload,
    );
    _bytes.fillRange(captionJpegOffset + payload.length, _bytes.length, 0);
    return this;
  }

  /// Returns an independent copy of the current buffer.
  ///
  /// Mutating the returned buffer does not affect this builder or later
  /// builds.
  Uint8List build() => Uint8List.fromList(_bytes);

  void _requireCaption(String method) {
    if (_bytes.length != captionSaveSize) {
      throw StateError('$method is only valid on a caption fixture');
    }
  }

  void _requireSpace(int offset, int count) {
    if (offset < 0 || offset + count > _bytes.length) {
      throw RangeError(
        'offset $offset with $count byte(s) does not fit in a '
        '${_bytes.length}-byte fixture',
      );
    }
  }

  void _setU32LittleEndian(int offset, int value) {
    _requireSpace(offset, 4);
    ByteData.sublistView(_bytes).setUint32(offset, value, Endian.little);
  }

  void _checkUnsigned(int value, int max, String name) {
    if (value < 0 || value > max) {
      throw RangeError.range(value, 0, max, name);
    }
  }
}
