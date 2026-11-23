import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// A half-open byte range `[start, end)` that a test allows to change.
class ByteRegion {
  const ByteRegion(this.start, this.end, this.label)
    : assert(start >= 0, 'start must be non-negative'),
      assert(end >= start, 'end must not be before start');

  /// First byte included in the region.
  final int start;

  /// First byte after the region (exclusive).
  final int end;

  /// Human-readable name shown in failure output.
  final String label;

  /// Number of bytes covered by the region.
  int get length => end - start;

  /// Whether [offset] falls inside `[start, end)`.
  bool contains(int offset) => offset >= start && offset < end;

  @override
  String toString() => '$label [0x${_hex(start)}, 0x${_hex(end)})';
}

/// A coalesced run of changed bytes.
class ByteRun {
  const ByteRun(this.start, this.length)
    : assert(start >= 0, 'start must be non-negative'),
      assert(length > 0, 'length must be positive');

  /// First changed byte.
  final int start;

  /// Number of changed bytes in the run.
  final int length;

  /// First byte after the run (exclusive).
  int get end => start + length;

  @override
  String toString() =>
      '0x${_hex(start)}..0x${_hex(end)} '
      '($length byte${length == 1 ? '' : 's'}, end exclusive)';
}

/// Coalesced differences between two byte buffers.
class ByteRegionDiff {
  ByteRegionDiff(Iterable<ByteRun> runs)
    : runs = List<ByteRun>.unmodifiable(runs);

  /// Changed runs in ascending offset order. Adjacent changes are merged.
  final List<ByteRun> runs;

  /// Whether the buffers differ at all.
  bool get hasChanges => runs.isNotEmpty;

  /// Compares [before] and [after] up to the shorter length.
  ///
  /// When the lengths differ, the extra tail is reported as a run starting at
  /// the shorter length, so an append or truncation is visible in the result.
  static ByteRegionDiff diff(Uint8List before, Uint8List after) {
    final runs = <ByteRun>[];
    final common = math.min(before.length, after.length);
    int? runStart;

    for (var i = 0; i < common; i++) {
      if (before[i] != after[i]) {
        runStart ??= i;
      } else if (runStart != null) {
        _appendRun(runs, runStart, i - runStart);
        runStart = null;
      }
    }
    if (runStart != null) {
      _appendRun(runs, runStart, common - runStart);
    }

    if (after.length > common) {
      _appendRun(runs, common, after.length - common);
    } else if (before.length > common) {
      _appendRun(runs, common, before.length - common);
    }

    return ByteRegionDiff(runs);
  }
}

/// Asserts that [a] and [b] are byte-identical.
///
/// On failure, reports the first differing offset and a hex window with
/// [radius] (default 16) bytes either side for both buffers.
void expectByteIdentical(Uint8List a, Uint8List b, {String? reason}) {
  final prefix = reason == null || reason.isEmpty ? '' : '$reason\n';
  final common = math.min(a.length, b.length);

  for (var i = 0; i < common; i++) {
    if (a[i] != b[i]) {
      fail(
        '${prefix}Byte buffers differ at offset ${_offset(i)}: '
        'first has 0x${_byteHex(a[i])}, second has 0x${_byteHex(b[i])}.\n'
        'first (${a.length} bytes) around offset:\n'
        '${hexWindow(a, i)}\n'
        'second (${b.length} bytes) around offset:\n'
        '${hexWindow(b, i)}',
      );
    }
  }

  if (a.length != b.length) {
    fail(
      '${prefix}Byte buffers are identical up to the shorter length but '
      'differ in length: first is ${a.length} bytes, second is ${b.length} '
      'bytes; first length difference at offset ${_offset(common)}.',
    );
  }
}

/// Asserts that only bytes inside [allowed] differ between [before] and
/// [after].
///
/// The buffers must have the same length. On failure, every coalesced run of
/// changed bytes outside the allowed regions is reported with its offset
/// range, plus a hex window around the first unexpected byte.
void expectOnlyRegionsChanged(
  Uint8List before,
  Uint8List after,
  List<ByteRegion> allowed, {
  String? reason,
}) {
  final prefix = reason == null || reason.isEmpty ? '' : '$reason\n';

  if (before.length != after.length) {
    fail(
      '${prefix}Byte buffer lengths differ: before is ${before.length} '
      'bytes, after is ${after.length} bytes; region checks require '
      'equal-length buffers.',
    );
  }

  final diff = ByteRegionDiff.diff(before, after);
  if (!diff.hasChanges) {
    return;
  }

  final unexpected = <ByteRun>[];
  for (final run in diff.runs) {
    int? runStart;
    for (var i = run.start; i < run.end; i++) {
      final isAllowed = allowed.any((region) => region.contains(i));
      if (!isAllowed) {
        runStart ??= i;
      } else if (runStart != null) {
        _appendRun(unexpected, runStart, i - runStart);
        runStart = null;
      }
    }
    if (runStart != null) {
      _appendRun(unexpected, runStart, run.end - runStart);
    }
  }

  if (unexpected.isEmpty) {
    return;
  }

  final labels = allowed.isEmpty
      ? '<none>'
      : allowed.map((region) => region.label).join(', ');
  final firstOffset = unexpected.first.start;
  fail(
    '${prefix}Found ${unexpected.length} unexpected changed region'
    '${unexpected.length == 1 ? '' : 's'} outside allowed regions '
    '[$labels]:\n'
    '${unexpected.map((run) => '  $run').join('\n')}\n'
    'First unexpected offset: ${_offset(firstOffset)}\n'
    'before around offset:\n'
    '${hexWindow(before, firstOffset)}\n'
    'after around offset:\n'
    '${hexWindow(after, firstOffset)}',
  );
}

/// Formats [bytes] as an address/hex/ASCII window around [offset].
///
/// [offset] is clamped to the buffer, and [radius] bytes on either side are
/// included. Rows hold up to 16 bytes and addresses are absolute.
String hexWindow(Uint8List bytes, int offset, {int radius = 16}) {
  assert(radius >= 0, 'radius must be non-negative');
  if (bytes.isEmpty) {
    return '(empty buffer)';
  }

  final center = offset.clamp(0, bytes.length - 1);
  final start = math.max(0, center - radius);
  final end = math.min(bytes.length, center + radius + 1);
  final lines = <String>[];

  for (var lineStart = start; lineStart < end; lineStart += 16) {
    final lineEnd = math.min(lineStart + 16, end);
    final hex = StringBuffer();
    final ascii = StringBuffer();

    for (var i = lineStart; i < lineEnd; i++) {
      if (i > lineStart) {
        hex.write(' ');
      }
      if (i - lineStart == 8) {
        hex.write(' ');
      }
      hex.write(_byteHex(bytes[i]));
      final byte = bytes[i];
      ascii.write(
        byte >= 0x20 && byte <= 0x7e ? String.fromCharCode(byte) : '.',
      );
    }

    lines.add('${_hex(lineStart)}  $hex  |$ascii|');
  }

  return lines.join('\n');
}

void _appendRun(List<ByteRun> runs, int start, int length) {
  if (length <= 0) {
    return;
  }
  if (runs.isNotEmpty && runs.last.end == start) {
    final last = runs.removeLast();
    runs.add(ByteRun(last.start, last.length + length));
  } else {
    runs.add(ByteRun(start, length));
  }
}

String _hex(int value) => value.toRadixString(16).padLeft(8, '0');

String _offset(int value) => '0x${_hex(value)} ($value)';

String _byteHex(int value) => value.toRadixString(16).padLeft(2, '0');
