import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Visual classification for one byte in the hex editor.
enum ByteMarkKind {
  /// The byte was edited in this session.
  modified,

  /// The byte fails a domain validation rule.
  invalid,

  /// The byte's meaning is not known yet.
  unknown,

  /// The byte was checked against a verified source.
  verified,
}

/// Resolves a human-readable meaning for one bit.
///
/// [byteOffset] is the offset into the buffer (not the displayed address) and
/// [bitIndex] is `0` for the least-significant bit through `7` for the
/// most-significant bit. Returning `null` means "no label".
typedef BitLabelProvider = String? Function(int byteOffset, int bitIndex);

/// An inclusive-start, exclusive-end range of writable byte offsets.
@immutable
final class HexEditableRange {
  /// Creates a writable range spanning `[start, end)`.
  const HexEditableRange({required this.start, required this.end})
    : assert(start >= 0, 'start must be non-negative'),
      assert(end >= start, 'end must not precede start');

  /// First writable offset, inclusive.
  final int start;

  /// First offset after the range, exclusive.
  final int end;

  /// Whether [offset] falls inside this range.
  bool contains(int offset) => offset >= start && offset < end;

  @override
  String toString() => 'HexEditableRange($start, $end)';
}

/// Selection and edit state for [HexEditor].
///
/// The controller owns the buffer, the caret/selection, and byte marks. It has
/// no bloc or app-theme dependency so the editor can be reused in isolation.
///
/// All mutations of byte values go through [writeByte] (or [toggleBit], which
/// delegates to it). That method is the single bounds and editability gate:
/// it throws instead of clamping, so a caller can never silently corrupt an
/// address outside the buffer or outside [editableRange].
class HexEditorController extends ChangeNotifier {
  /// Wraps [bytes] and optionally restricts writes to [editableRange].
  ///
  /// [baseOffset] is added to every displayed address, for region views of a
  /// larger file. It does not change the buffer indices used by [writeByte].
  ///
  /// Throws [ArgumentError] when [baseOffset] is negative, when [editableRange]
  /// has a negative start, or when [editableRange] extends past [bytes].
  HexEditorController({
    required Uint8List bytes,
    this.baseOffset = 0,
    this.editableRange,
    this.readOnly = false,
  }) : _bytes = bytes {
    if (baseOffset < 0) {
      throw ArgumentError.value(baseOffset, 'baseOffset', 'Must be >= 0');
    }
    final range = editableRange;
    if (range != null) {
      if (range.start < 0) {
        throw ArgumentError.value(
          range.start,
          'editableRange.start',
          'Must be >= 0',
        );
      }
      if (range.end > bytes.length) {
        throw ArgumentError.value(
          range.end,
          'editableRange.end',
          'Must not exceed the buffer length (${bytes.length})',
        );
      }
      if (range.end < range.start) {
        throw ArgumentError.value(
          range.end,
          'editableRange.end',
          'Must not precede editableRange.start (${range.start})',
        );
      }
    }
  }

  final Uint8List _bytes;
  final Map<int, ByteMarkKind> _marks = <int, ByteMarkKind>{};
  final Set<int> _modifiedOffsets = <int>{};

  /// Offset added to displayed addresses (for region views).
  final int baseOffset;

  /// Writable span, or `null` when every byte is writable.
  final HexEditableRange? editableRange;

  /// When true, [writeByte] refuses all writes.
  final bool readOnly;

  int? _anchor;
  int? _extent;
  int _revision = 0;

  /// The buffer being edited. Index `0` is buffer offset `0`.
  Uint8List get bytes => _bytes;

  /// Buffer length in bytes.
  int get length => _bytes.length;

  /// Whether the buffer has no bytes.
  bool get isEmpty => _bytes.isEmpty;

  /// Incremented after every successful write.
  ///
  /// Hosts can compare this to avoid rescanning a large buffer when only the
  /// selection changed.
  int get revision => _revision;

  /// Fixed end of the selection, or `null` when nothing is selected.
  int? get selectionAnchor => _anchor;

  /// Moving end of the selection, or `null` when nothing is selected.
  int? get selectionExtent => _extent;

  /// The byte that receives typed hex digits.
  int? get activeOffset => _extent ?? _anchor;

  /// First selected offset, inclusive, or `null`.
  int? get selectionStart {
    final anchor = _anchor;
    final extent = _extent;
    if (anchor == null || extent == null) return null;
    return anchor < extent ? anchor : extent;
  }

  /// Offset just after the last selected byte, or `null`.
  int? get selectionEnd {
    final anchor = _anchor;
    final extent = _extent;
    if (anchor == null || extent == null) return null;
    return anchor > extent ? anchor + 1 : extent + 1;
  }

  /// Number of selected bytes, or `0` when nothing is selected.
  int get selectionLength {
    final start = selectionStart;
    final end = selectionEnd;
    if (start == null || end == null) return 0;
    return end - start;
  }

  /// A copy of the current byte marks.
  Map<int, ByteMarkKind> get marks => UnmodifiableMapView(_marks);

  /// A copy of the offsets edited through [writeByte].
  Set<int> get modifiedOffsets => UnmodifiableSetView(_modifiedOffsets);

  /// Whether byte [offset] can be written right now.
  bool isEditable(int offset) {
    if (readOnly) return false;
    if (offset < 0 || offset >= _bytes.length) return false;
    final range = editableRange;
    return range == null || range.contains(offset);
  }

  /// Whether [offset] is inside the current selection.
  bool isSelected(int offset) {
    final start = selectionStart;
    final end = selectionEnd;
    return start != null && end != null && offset >= start && offset < end;
  }

  /// The selected bytes formatted as space-separated uppercase hex.
  String get selectionHex {
    final start = selectionStart;
    final end = selectionEnd;
    if (start == null || end == null) return '';
    final parts = <String>[];
    for (var offset = start; offset < end; offset++) {
      parts.add(_hex2(_bytes[offset]));
    }
    return parts.join(' ');
  }

  /// Reads one byte, throwing [RangeError] outside the buffer.
  int valueAt(int offset) {
    _checkOffset(offset);
    return _bytes[offset];
  }

  /// Selects one byte.
  ///
  /// With [extend], the existing anchor is kept and [offset] becomes the
  /// moving end. Without it, the selection collapses onto [offset].
  void selectByte(int offset, {bool extend = false}) {
    _checkOffset(offset);
    final int? nextAnchor;
    if (extend) {
      nextAnchor = _anchor ?? offset;
    } else {
      nextAnchor = offset;
    }
    if (_anchor == nextAnchor && _extent == offset) return;
    _anchor = nextAnchor;
    _extent = offset;
    notifyListeners();
  }

  /// Selects the inclusive range from [anchor] through [extent].
  void selectRange(int anchor, int extent) {
    _checkOffset(anchor);
    _checkOffset(extent);
    if (_anchor == anchor && _extent == extent) return;
    _anchor = anchor;
    _extent = extent;
    notifyListeners();
  }

  /// Moves the caret by [delta], clamped to the buffer for keyboard use.
  ///
  /// Navigation deliberately clamps at the ends of the buffer. Writes never
  /// clamp: they go through [writeByte] and throw.
  void moveSelection(int delta, {bool extend = false}) {
    if (_bytes.isEmpty) return;
    final current = _extent ?? 0;
    final target = (current + delta).clamp(0, _bytes.length - 1);
    final int? nextAnchor;
    if (extend) {
      nextAnchor = _anchor ?? current;
    } else {
      nextAnchor = target;
    }
    if (_anchor == nextAnchor && _extent == target) return;
    _anchor = nextAnchor;
    _extent = target;
    notifyListeners();
  }

  /// Clears the selection (the buffer is untouched).
  void clearSelection() {
    if (_anchor == null && _extent == null) return;
    _anchor = null;
    _extent = null;
    notifyListeners();
  }

  /// Writes [value] to [offset].
  ///
  /// This is the only byte-value mutation path. It throws:
  /// - [RangeError] when [offset] is outside `[0, length)`;
  /// - [RangeError] when [value] is outside `[0, 255]`;
  /// - [RangeError] when [editableRange] is set and does not contain [offset];
  /// - [StateError] when the controller is [readOnly].
  ///
  /// Nothing is clamped. On success the byte is marked
  /// [ByteMarkKind.modified] and added to [modifiedOffsets].
  void writeByte(int offset, int value) {
    _checkOffset(offset);
    if (value < 0 || value > 0xFF) {
      throw RangeError.range(value, 0, 0xFF, 'value');
    }
    final range = editableRange;
    if (range != null && !range.contains(offset)) {
      throw RangeError.range(
        offset,
        range.start,
        range.end - 1,
        'offset',
        'Byte is outside the editable range ${range.start}..${range.end - 1}.',
      );
    }
    if (readOnly) {
      throw StateError('Cannot write bytes while the editor is read-only.');
    }
    _bytes[offset] = value;
    _revision++;
    _marks[offset] = ByteMarkKind.modified;
    _modifiedOffsets.add(offset);
    notifyListeners();
  }

  /// Flips one bit of one byte.
  ///
  /// [bitIndex] is `0` (LSB) through `7` (MSB). Bounds and editability are
  /// enforced by [writeByte], so a read-only or out-of-range toggle throws.
  void toggleBit(int offset, int bitIndex) {
    _checkOffset(offset);
    if (bitIndex < 0 || bitIndex > 7) {
      throw RangeError.range(bitIndex, 0, 7, 'bitIndex');
    }
    writeByte(offset, _bytes[offset] ^ (1 << bitIndex));
  }

  /// Adds or replaces the mark for [offset].
  void setMark(int offset, ByteMarkKind kind) {
    _checkOffset(offset);
    _marks[offset] = kind;
    notifyListeners();
  }

  /// Removes the mark for [offset], if any.
  void clearMark(int offset) {
    if (_marks.remove(offset) != null) notifyListeners();
  }

  /// Replaces all marks, validating every key first.
  void setMarks(Map<int, ByteMarkKind> marks) {
    for (final offset in marks.keys) {
      _checkOffset(offset);
    }
    _marks
      ..clear()
      ..addAll(marks);
    notifyListeners();
  }

  /// Forgets which offsets have been edited (marks are kept).
  void clearModified() {
    if (_modifiedOffsets.isEmpty) return;
    _modifiedOffsets.clear();
    notifyListeners();
  }

  void _checkOffset(int offset) {
    if (offset < 0 || offset >= _bytes.length) {
      throw RangeError.range(
        offset,
        0,
        _bytes.length - 1,
        'offset',
        _bytes.isEmpty ? 'The buffer is empty.' : null,
      );
    }
  }

  static String _hex2(int value) =>
      value.toRadixString(16).padLeft(2, '0').toUpperCase();
}
