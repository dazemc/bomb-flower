/// Copy-on-write byte storage for save slots.
library;

import 'dart:typed_data';

import 'field_metadata.dart';
import 'fingerprint.dart';

/// A replacement of [span] with an owned byte copy.
///
/// The constructor copies [bytes] so callers cannot mutate history by keeping
/// a reference to their list.
final class BytePatch {
  /// Creates a patch whose byte count must equal `span.length`.
  BytePatch(this.span, List<int> bytes) : bytes = Uint8List.fromList(bytes) {
    if (!span.isValid) {
      throw RangeError('Patch span must be non-negative: $span');
    }
    if (bytes.length != span.length) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'must equal span.length (${span.length})',
      );
    }
  }

  /// The replaced range.
  final ByteSpan span;

  /// The owned replacement bytes.
  final Uint8List bytes;

  @override
  String toString() => 'BytePatch($span, ${bytes.length} bytes)';
}

/// Immutable-by-exposure bytes stored as one base buffer plus persistent
/// patches.
///
/// Ingest copies a file exactly once. Every edit appends one [BytePatch] and
/// shares the base buffer and the previous patch list, so memory and CPU scale
/// with changed bytes rather than file size. [materialize] is the only
/// operation that allocates a full copy, and it returns a fresh buffer the
/// caller owns.
///
/// When the patch list grows past [maxPatches] or its payload past
/// [maxPatchBytes], the next edit materializes once and starts a new base.
/// That is byte-preserving compaction, not a per-edit full copy.
final class ByteRegion {
  /// Copies [bytes] into an immutable base region.
  ByteRegion.fromBytes(List<int> bytes)
    : _base = Uint8List.fromList(bytes),
      _patches = const <BytePatch>[],
      length = bytes.length;

  ByteRegion._(this._base, this._patches, this.length, this._cachedFingerprint);

  /// Maximum number of patches retained before compaction.
  static const int maxPatches = 64;

  /// Maximum patch payload retained before compaction.
  static const int maxPatchBytes = 16 * 1024;

  final Uint8List _base;
  final List<BytePatch> _patches;

  /// Number of bytes in the region.
  final int length;

  int? _cachedFingerprint;

  /// Test/diagnostic seam: the immutable base buffer shared by derived regions.
  ///
  /// The returned buffer is internal state. Callers must never mutate it; doing
  /// so corrupts this region and every region that shares it.
  Uint8List get debugBase => _base;

  /// Whether no patch has been applied.
  bool get isPristine => _patches.isEmpty;

  /// Number of patches currently layered over the base.
  int get patchCount => _patches.length;

  /// Total payload bytes held by patches.
  int get patchByteCount =>
      _patches.fold(0, (total, patch) => total + patch.span.length);

  /// Non-cryptographic content hint; computed once and cached.
  int get fingerprint => _cachedFingerprint ??= Fnv1a.hash32(materialize());

  /// A fresh buffer containing base bytes with every patch applied.
  Uint8List materialize() {
    final out = Uint8List.fromList(_base);
    for (final patch in _patches) {
      out.setRange(patch.span.offset, patch.span.end, patch.bytes);
    }
    return out;
  }

  /// Returns a new region with [span] replaced by a copy of [bytes].
  ///
  /// Throws [RangeError] when [span] is invalid or outside this region and
  /// [ArgumentError] when the byte count does not match the span. The original
  /// region and its base buffer are never modified.
  ByteRegion replace(ByteSpan span, List<int> bytes) {
    _checkSpan(span);
    if (bytes.length != span.length) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'must equal span.length (${span.length})',
      );
    }

    final patch = BytePatch(span, bytes);
    final nextPatches = <BytePatch>[..._patches, patch];
    final nextPayload = patchByteCount + patch.span.length;
    if (nextPatches.length > maxPatches || nextPayload > maxPatchBytes) {
      final compacted = materialize();
      compacted.setRange(span.offset, span.end, patch.bytes);
      return ByteRegion._(
        compacted,
        const <BytePatch>[],
        length,
        _cachedFingerprint,
      );
    }
    return ByteRegion._(_base, nextPatches, length, null);
  }

  /// Copies `span.length` current bytes into a new buffer.
  Uint8List slice(ByteSpan span) {
    _checkSpan(span);
    final out = Uint8List(span.length);
    for (var i = 0; i < span.length; i++) {
      out[i] = _byteAt(span.offset + i);
    }
    return out;
  }

  /// Reads one unsigned byte at [index].
  int readByte(int index) {
    _checkRange(index, 1);
    return _byteAt(index);
  }

  /// Reads a big-endian unsigned 16-bit integer at [index].
  int readU16BE(int index) {
    _checkRange(index, 2);
    return (_byteAt(index) << 8) | _byteAt(index + 1);
  }

  /// Reads a little-endian unsigned 16-bit integer at [index].
  int readU16LE(int index) {
    _checkRange(index, 2);
    return _byteAt(index) | (_byteAt(index + 1) << 8);
  }

  /// Reads a big-endian unsigned 32-bit integer at [index].
  int readU32BE(int index) {
    _checkRange(index, 4);
    return (_byteAt(index) << 24) |
        (_byteAt(index + 1) << 16) |
        (_byteAt(index + 2) << 8) |
        _byteAt(index + 3);
  }

  /// Reads a little-endian unsigned 32-bit integer at [index].
  int readU32LE(int index) {
    _checkRange(index, 4);
    return _byteAt(index) |
        (_byteAt(index + 1) << 8) |
        (_byteAt(index + 2) << 16) |
        (_byteAt(index + 3) << 24);
  }

  /// Whether the materialized bytes equal [other]'s materialized bytes.
  ///
  /// Materializes both regions; this is for tests and collision safety checks,
  /// not for UI state comparison.
  bool sameBytesAs(ByteRegion other) {
    if (length != other.length) {
      return false;
    }
    if (identical(this, other)) {
      return true;
    }
    final a = materialize();
    final b = other.materialize();
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  int _byteAt(int index) {
    for (var i = _patches.length - 1; i >= 0; i--) {
      final patch = _patches[i];
      if (index >= patch.span.offset && index < patch.span.end) {
        return patch.bytes[index - patch.span.offset];
      }
    }
    return _base[index];
  }

  void _checkRange(int index, int size) {
    if (index < 0 || index > length - size) {
      throw RangeError.range(index, 0, length - size, 'index');
    }
  }

  void _checkSpan(ByteSpan span) {
    if (!span.isValid) {
      throw RangeError('Invalid span: $span');
    }
    if (span.end > length) {
      throw RangeError.range(span.end, 0, length, 'span.end');
    }
  }

  @override
  String toString() =>
      'ByteRegion(length: $length, patches: $patchCount, '
      'fingerprint: ${Fnv1a.hex32(fingerprint)})';
}
