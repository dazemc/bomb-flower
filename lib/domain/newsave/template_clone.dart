/// Length-preserving clone of an existing save pair.
///
/// Both inputs are decoded, validated, and copied. Only the bytes named by an
/// override are changed; every other byte is returned exactly as it arrived.
/// The file length never changes, so a cloned pair stays in the layout the game
/// wrote.
library;

import 'dart:typed_data';

import '../../data/codec/progress_codec.dart';
import '../save/caption_layout.dart';
import '../save/models/caption_save.dart';
import '../save/models/progress_save.dart';
import '../save/progress_layout.dart';
import '../save/progress_record.dart';

/// Hash of `PlayerStatus.Life` in `progress.sav`.
///
/// The value is the one [ProgressLayout.verifiedFieldNames] lists.
const int lifeFieldHash = 0x31AB5580;

/// Hash of `PlayerStatus.MaxLife` in `progress.sav`.
///
/// The value is the one [ProgressLayout.verifiedFieldNames] lists.
const int maxLifeFieldHash = 0xFBE01DA1;

/// The bytes and edited spans produced by [cloneSaveTemplate].
final class TemplateCloneResult {
  /// Creates a result.
  const TemplateCloneResult({
    required this.progressBytes,
    required this.captionBytes,
    required this.changedSpans,
  });

  /// The cloned `progress.sav` bytes, the same length as the input.
  final Uint8List progressBytes;

  /// The cloned `caption.sav` bytes, the same length as the input.
  final Uint8List captionBytes;

  /// The half-open byte ranges that were written, coalesced and sorted.
  ///
  /// An empty list means the outputs are byte-identical to the inputs.
  final List<(int start, int end)> changedSpans;
}

/// Clones a save pair, applying only the requested overrides.
///
/// [progress] and [caption] are never mutated; both outputs are fresh copies.
/// A `null` override leaves its bytes untouched.
///
/// [sceneName] and [mapPath] are written into the 64-byte caption slots at
/// [CaptionLayout.sceneNameOffset] and [CaptionLayout.mapPathOffset]. Each must
/// be printable ASCII of at most 63 code units, leaving room for a NUL, and its
/// slot is NUL-terminated and zero-filled.
///
/// [life] is written into `PlayerStatus.Life`'s 4-byte value word and must
/// satisfy `0 < life <= MaxLife` for the decoded save.
///
/// Throws [ArgumentError] when the inputs are not a valid save pair or an
/// override cannot be stored.
TemplateCloneResult cloneSaveTemplate({
  required Uint8List progress,
  required Uint8List caption,
  String? sceneName,
  String? mapPath,
  int? life,
}) {
  final captionInvalid = caption.length < CaptionLayout.minimumFileLength ||
      !CaptionSave.hasMagic(caption);
  if (captionInvalid) {
    throw ArgumentError.value(
      caption.length,
      'caption',
      'is not a caption.sav: it must start with 04 03 02 01 and be at least '
          '${CaptionLayout.minimumFileLength} byte(s)',
    );
  }

  final decoded = ProgressCodec.decode(progress);
  if (decoded is! ProgressDecodeOk) {
    throw ArgumentError.value(
      decoded.runtimeType.toString(),
      'progress',
      'does not decode to a supported progress.sav',
    );
  }
  final save = decoded.save;

  if (sceneName != null) {
    _requireStorableName(sceneName, 'sceneName');
  }
  if (mapPath != null) {
    _requireStorableName(mapPath, 'mapPath');
  }

  final progressBytes = Uint8List.fromList(progress);
  final captionBytes = Uint8List.fromList(caption);
  final spans = <(int, int)>[];

  if (life != null) {
    final lifeRecord = _requireIntRecord(save, lifeFieldHash, 'life');
    final maxLifeRecord = _requireIntRecord(save, maxLifeFieldHash, 'life');
    final maxLife = maxLifeRecord.asInt();
    if (maxLife <= 0) {
      throw ArgumentError.value(
        maxLife,
        'progress',
        'PlayerStatus.MaxLife is $maxLife; it must be positive',
      );
    }
    if (life <= 0 || life > maxLife) {
      throw ArgumentError.value(
        life,
        'life',
        'must satisfy 0 < life <= MaxLife ($maxLife)',
      );
    }
    final offset = lifeRecord.valueOffset;
    _writeU32(progressBytes, offset, life);
    spans.add((offset, offset + 4));
  }

  if (sceneName != null) {
    final offset = CaptionLayout.sceneNameOffset;
    _writeNameSlot(captionBytes, offset, sceneName);
    spans.add((offset, offset + CaptionLayout.nameLength));
  }
  if (mapPath != null) {
    final offset = CaptionLayout.mapPathOffset;
    _writeNameSlot(captionBytes, offset, mapPath);
    spans.add((offset, offset + CaptionLayout.nameLength));
  }

  return TemplateCloneResult(
    progressBytes: progressBytes,
    captionBytes: captionBytes,
    changedSpans: _coalesce(spans),
  );
}

ProgressRecord _requireIntRecord(ProgressSave save, int hash, String field) {
  final name = ProgressLayout.verifiedFieldNames[hash] ?? 'field';
  final record = save.recordByHash(hash);
  if (record == null) {
    throw ArgumentError.value(
      ProgressLayout.keyHex(hash),
      field,
      'progress.sav has no $name ($field) record',
    );
  }
  if (record.type != SaveType.intValue) {
    throw ArgumentError.value(
      record.type.label,
      field,
      '$name must be an Int; it is stored as ${record.type.label}',
    );
  }
  return record;
}

void _requireStorableName(String value, String parameter) {
  const maximum = CaptionLayout.nameLength - 1;
  if (value.length > maximum) {
    throw ArgumentError.value(
      value,
      parameter,
      'is ${value.length} character(s); at most $maximum fit in a '
          '${CaptionLayout.nameLength}-byte slot with its NUL',
    );
  }
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit < 0x20 || unit > 0x7e) {
      throw ArgumentError.value(
        value,
        parameter,
        'character at index $i is outside printable ASCII (0x20..0x7e)',
      );
    }
  }
}

void _writeNameSlot(Uint8List bytes, int offset, String value) {
  final end = offset + CaptionLayout.nameLength;
  bytes.fillRange(offset, end, 0);
  bytes.setRange(offset, offset + value.length, value.codeUnits);
}

void _writeU32(Uint8List bytes, int offset, int value) {
  for (var i = 0; i < 4; i++) {
    bytes[offset + i] = (value >> (8 * i)) & 0xff;
  }
}

List<(int, int)> _coalesce(List<(int, int)> spans) {
  if (spans.isEmpty) {
    return const <(int, int)>[];
  }
  final sorted = <(int, int)>[...spans]
    ..sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final span in sorted) {
    if (merged.isNotEmpty && span.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, span.$2 > last.$2 ? span.$2 : last.$2));
    } else {
      merged.add(span);
    }
  }
  return List<(int, int)>.unmodifiable(merged);
}
