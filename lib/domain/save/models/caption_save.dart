import 'dart:typed_data';

import '../caption_layout.dart';

/// The save date and time stored in `caption.sav`'s six header entries.
///
/// Values are the raw 32-bit little-endian words the game stores; the model
/// does not guess a calendar rule beyond exposing the parts the keys name
/// (`year`, `month`, `day`, `hour`, `minute`, `second`).
final class CaptionSavedAt {
  const CaptionSavedAt({
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.second,
  });

  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final int second;

  /// The value of [field].
  int valueOf(CaptionDateField field) => switch (field) {
    CaptionDateField.year => year,
    CaptionDateField.month => month,
    CaptionDateField.day => day,
    CaptionDateField.hour => hour,
    CaptionDateField.minute => minute,
    CaptionDateField.second => second,
  };

  /// A copy with one date part replaced.
  CaptionSavedAt withValue(CaptionDateField field, int value) =>
      switch (field) {
        CaptionDateField.year => CaptionSavedAt(
          year: value,
          month: month,
          day: day,
          hour: hour,
          minute: minute,
          second: second,
        ),
        CaptionDateField.month => CaptionSavedAt(
          year: year,
          month: value,
          day: day,
          hour: hour,
          minute: minute,
          second: second,
        ),
        CaptionDateField.day => CaptionSavedAt(
          year: year,
          month: month,
          day: value,
          hour: hour,
          minute: minute,
          second: second,
        ),
        CaptionDateField.hour => CaptionSavedAt(
          year: year,
          month: month,
          day: day,
          hour: value,
          minute: minute,
          second: second,
        ),
        CaptionDateField.minute => CaptionSavedAt(
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: value,
          second: second,
        ),
        CaptionDateField.second => CaptionSavedAt(
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: minute,
          second: value,
        ),
      };

  @override
  bool operator ==(Object other) =>
      other is CaptionSavedAt &&
      other.year == year &&
      other.month == month &&
      other.day == day &&
      other.hour == hour &&
      other.minute == minute &&
      other.second == second;

  @override
  int get hashCode => Object.hash(year, month, day, hour, minute, second);

  @override
  String toString() =>
      'CaptionSavedAt($year-${_two(month)}-${_two(day)} '
      '${_two(hour)}:${_two(minute)}:${_two(second)})';

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// An immutable, typed view of one `caption.sav`.
///
/// The model keeps a private copy of the exact bytes it was decoded from. The
/// codec starts every encode from that copy and patches only the spans the
/// caller edited, so a decode followed by an encode with no edits is
/// byte-identical even when the original contains stale bytes after a name's
/// NUL terminator (the market sample does).
final class CaptionSave {
  CaptionSave({
    required Uint8List originalBytes,
    required this.sceneName,
    required this.mapPath,
    required Uint8List jpegBytes,
    required this.savedAt,
  }) : _originalBytes = Uint8List.fromList(originalBytes),
       _jpegBytes = Uint8List.fromList(jpegBytes) {
    if (_originalBytes.length < CaptionLayout.minimumFileLength) {
      throw ArgumentError.value(
        _originalBytes.length,
        'originalBytes',
        'shorter than the minimum caption.sav length '
            '(${CaptionLayout.minimumFileLength})',
      );
    }
    if (!hasMagic(_originalBytes)) {
      throw ArgumentError.value(
        originalBytes,
        'originalBytes',
        'does not start with 04 03 02 01',
      );
    }
    final sceneProblem = nameProblem(sceneName);
    if (sceneProblem != null) {
      throw ArgumentError.value(sceneName, 'sceneName', sceneProblem);
    }
    final mapProblem = nameProblem(mapPath);
    if (mapProblem != null) {
      throw ArgumentError.value(mapPath, 'mapPath', mapProblem);
    }
    if (!hasJpegMarkers(_jpegBytes)) {
      throw ArgumentError.value(
        jpegBytes,
        'jpegBytes',
        'is not a JPEG: expected FF D8 at the start and FF D9 at the end',
      );
    }
  }

  /// The four format bytes at offset 0, read as a little-endian integer.
  ///
  /// The same four bytes are the format's magic and its version stamp
  /// (`04.03.02.01`); no source documents a separate version field.
  int get magic => CaptionLayout.magicValue;

  /// The scene name at offset 684, e.g. `KokiriForest`.
  final String sceneName;

  /// The scene/map path at offset 748, e.g.
  /// `KokiriForest/KokiriForest_Child`.
  ///
  /// The sources call this field `map`, but the bytes are a path, not a
  /// numeric map id. The first segment repeats [sceneName]; [mapName] is the
  /// part after the last `/`.
  final String mapPath;

  /// The date and time in the six header entries.
  final CaptionSavedAt savedAt;

  final Uint8List _originalBytes;
  final Uint8List _jpegBytes;

  /// A defensive copy of the exact bytes this save was decoded from.
  Uint8List get originalBytes => Uint8List.fromList(_originalBytes);

  /// A defensive copy of the JPEG at [CaptionLayout.jpegOffset].
  Uint8List get jpegBytes => Uint8List.fromList(_jpegBytes);

  /// The JPEG's length in bytes, as stored at offset 1392.
  int get jpegLength => _jpegBytes.length;

  /// The part of [mapPath] after the last `/`, or the whole path when it has
  /// no `/`.
  String get mapName {
    final slash = mapPath.lastIndexOf('/');
    return slash < 0 ? mapPath : mapPath.substring(slash + 1);
  }

  /// A copy with selected fields replaced. The original bytes are retained.
  CaptionSave copyWith({
    String? sceneName,
    String? mapPath,
    Uint8List? jpegBytes,
    CaptionSavedAt? savedAt,
  }) => CaptionSave(
    originalBytes: _originalBytes,
    sceneName: sceneName ?? this.sceneName,
    mapPath: mapPath ?? this.mapPath,
    jpegBytes: jpegBytes ?? _jpegBytes,
    savedAt: savedAt ?? this.savedAt,
  );

  /// Whether [bytes] starts with the `04 03 02 01` magic.
  static bool hasMagic(List<int> bytes) {
    if (bytes.length < CaptionLayout.magicBytes.length) {
      return false;
    }
    for (var i = 0; i < CaptionLayout.magicBytes.length; i++) {
      if (bytes[i] != CaptionLayout.magicBytes[i]) {
        return false;
      }
    }
    return true;
  }

  /// Whether [bytes] has a JPEG start marker and a JPEG end marker.
  static bool hasJpegMarkers(List<int> bytes) {
    if (bytes.length < CaptionLayout.minimumJpegLength) {
      return false;
    }
    return bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[bytes.length - 2] == 0xff &&
        bytes[bytes.length - 1] == 0xd9;
  }

  /// Why [value] cannot be stored in a 64-byte name span, or `null` when it can.
  ///
  /// The stored strings are single-byte printable ASCII in every source and
  /// sample. There is no evidence for UTF-8 or UTF-16 here, so those are
  /// rejected rather than guessed at. A value of exactly 64 bytes fills the
  /// span and has no NUL terminator, matching `control.c`'s 64-byte loop.
  static String? nameProblem(String value) {
    if (value.length > CaptionLayout.nameLength) {
      return 'longer than ${CaptionLayout.nameLength} characters';
    }
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit < 0x20 || unit > 0x7e) {
        return 'character at index $i is outside printable ASCII '
            '(0x20..0x7e)';
      }
    }
    return null;
  }

  /// Whether [value] can be stored in a name span.
  static bool isValidName(String value) => nameProblem(value) == null;

  @override
  String toString() =>
      'CaptionSave(scene: $sceneName, map: $mapPath, '
      'jpeg: $jpegLength bytes, savedAt: $savedAt)';
}
