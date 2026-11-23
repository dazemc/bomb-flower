import 'dart:typed_data';

import 'package:bomb_flower/domain/save/caption_layout.dart';
import 'package:bomb_flower/domain/save/models/caption_save.dart';

/// A small, known JPEG-shaped payload used by the synthetic tests.
///
/// It has a `FF D8` start marker and a `FF D9` end marker, which is all the
/// codec checks; the bytes are made up here, not copied from the game or from
/// any artwork.
const List<int> syntheticJpegBytes = <int>[
  0xff, 0xd8, // SOI
  0xff, 0xe0, 0x00, 0x10, // APP0, length 16
  0x4a, 0x46, 0x49, 0x46, 0x00, // "JFIF\0"
  0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
  0xff, 0xda, 0x00, 0x08, // SOS, length 8
  0x01, 0x01, 0x00, 0x00, 0x3f, 0x00, // one component
  0x00, 0x11, 0x22, 0x33, // made-up entropy-coded bytes
  0xff, 0xd9, // EOI
];

/// Builds a synthetic `caption.sav` in memory.
///
/// The defaults are a valid layout: the verified magic, the 1392 marker, the
/// six date entries at the offsets observed in the three repository samples,
/// two printable names, and [syntheticJpegBytes]. Individual arguments can
/// spoil one field without spoiling the others.
///
/// [sceneTrailer] and [mapTrailer] are written after the name's NUL. They model
/// the stale bytes the market sample keeps after a shorter name. [jpegLength]
/// overrides the word at offset 1392 without changing the payload, which makes
/// a length that does not fit the buffer. [dateOffsets] can move or omit date
/// entries; a missing field is left without a key.
Uint8List buildSyntheticCaption({
  String sceneName = 'TestScene',
  String mapPath = 'TestScene/Room_1',
  List<int>? sceneTrailer,
  List<int>? mapTrailer,
  List<int> jpeg = syntheticJpegBytes,
  int? jpegLength,
  int layoutCheck = CaptionLayout.layoutCheckValue,
  List<int> magic = CaptionLayout.magicBytes,
  CaptionSavedAt? savedAt,
  Map<CaptionDateField, int>? dateOffsets,
}) {
  if (magic.length > 4) {
    throw ArgumentError.value(magic, 'magic', 'longer than 4 bytes');
  }

  final header = Uint8List(CaptionLayout.jpegOffset);
  header.setRange(0, magic.length, magic);
  _writeU32Le(header, CaptionLayout.layoutCheckOffset, layoutCheck);

  final date =
      savedAt ??
      const CaptionSavedAt(
        year: 2026,
        month: 1,
        day: 1,
        hour: 0,
        minute: 0,
        second: 0,
      );
  final offsets =
      dateOffsets ??
      <CaptionDateField, int>{
        for (final descriptor in CaptionLayout.dateFields)
          descriptor.field: descriptor.sampleOffset,
      };
  for (final descriptor in CaptionLayout.dateFields) {
    final offset = offsets[descriptor.field];
    if (offset == null) {
      continue;
    }
    _writeU32Le(header, offset, descriptor.key);
    _writeU32Le(header, offset + 4, date.valueOf(descriptor.field));
  }

  _writeName(header, CaptionLayout.sceneNameOffset, sceneName, sceneTrailer);
  _writeName(header, CaptionLayout.mapPathOffset, mapPath, mapTrailer);
  _writeU32Le(
    header,
    CaptionLayout.jpegLengthOffset,
    jpegLength ?? jpeg.length,
  );

  final out = Uint8List(CaptionLayout.jpegOffset + jpeg.length);
  out.setRange(0, CaptionLayout.jpegOffset, header);
  out.setRange(CaptionLayout.jpegOffset, out.length, jpeg);
  return out;
}

void _writeName(
  Uint8List header,
  int offset,
  String value,
  List<int>? trailer,
) {
  if (!CaptionSave.isValidName(value)) {
    throw ArgumentError.value(
      value,
      'name',
      CaptionSave.nameProblem(value) ?? 'not storable',
    );
  }
  final bytes = value.codeUnits;
  header.setRange(offset, offset + bytes.length, bytes);
  if (bytes.length == CaptionLayout.nameLength) {
    if (trailer != null && trailer.isNotEmpty) {
      throw ArgumentError.value(
        trailer,
        'trailer',
        'a 64-byte name fills the span; there is no room for a trailer',
      );
    }
    return;
  }
  header[offset + bytes.length] = 0;
  if (trailer == null || trailer.isEmpty) {
    return;
  }
  final start = offset + bytes.length + 1;
  if (start + trailer.length > offset + CaptionLayout.nameLength) {
    throw ArgumentError.value(
      trailer,
      'trailer',
      'does not fit after the name and its NUL',
    );
  }
  header.setRange(start, start + trailer.length, trailer);
}

void _writeU32Le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
  bytes[offset + 3] = (value >> 24) & 0xff;
}
