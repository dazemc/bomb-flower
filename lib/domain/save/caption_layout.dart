/// Byte layout of Ocarina of Time's `caption.sav`.
///
/// The layout below is the one Longshot reads and writes. Every offset was
/// checked against the three scrubbed samples in Longshot's `assets/saves`
/// (`kokiri-start`, `castle-gate`, `market-entrance`, 4,741 bytes each) before
/// this file was written. The bytes win over a source when they disagree; the
/// discrepancies are recorded on the affected descriptor.
library;

/// How the bytes of a field are interpreted.
enum CaptionFieldType {
  /// Four bytes that identify the format: `04 03 02 01`.
  magic,

  /// A 32-bit unsigned integer.
  unsignedInt,

  /// Printable ASCII, NUL-terminated inside a fixed 64-byte span.
  ascii,

  /// A JPEG stream, from its `FF D8` start marker to its `FF D9` end marker.
  jpeg,
}

/// The byte order of an integer field.
enum CaptionEndianness {
  /// Least-significant byte first.
  little,

  /// Most-significant byte first.
  big,

  /// Not an integer field.
  notApplicable,
}

/// One field of the `caption.sav` layout, with the evidence for it.
final class CaptionFieldDescriptor {
  const CaptionFieldDescriptor({
    required this.name,
    required this.offset,
    required this.size,
    required this.type,
    required this.endianness,
    required this.provenance,
  });

  /// The field's name in this package.
  final String name;

  /// Byte offset from the start of the file.
  final int offset;

  /// Fixed size in bytes, or `null` when the size is stored elsewhere.
  final int? size;

  /// How to interpret the bytes.
  final CaptionFieldType type;

  /// Byte order, when [type] is [CaptionFieldType.unsignedInt].
  final CaptionEndianness endianness;

  /// Where the field is documented and what the samples showed.
  final String provenance;

  @override
  String toString() => 'CaptionFieldDescriptor($name @ $offset)';
}

/// One of the six date entries in the header.
///
/// The entries are key/value pairs: a 32-bit little-endian hash key followed by
/// a 32-bit little-endian value. They are found by key, not by a fixed offset,
/// because no source guarantees where the game put them.
enum CaptionDateField { year, month, day, hour, minute, second }

/// A date key and the offset it occupied in the three repository samples.
final class CaptionDateKeyDescriptor {
  const CaptionDateKeyDescriptor({
    required this.field,
    required this.key,
    required this.sampleOffset,
    required this.provenance,
  });

  /// Which date part this entry holds.
  final CaptionDateField field;

  /// The 32-bit little-endian hash key of the entry.
  final int key;

  /// The key's offset in all three `assets/saves` samples (an observation, not
  /// an invariant: the codec locates entries by [key]).
  final int sampleOffset;

  /// Where the key and its meaning are documented.
  final String provenance;

  /// The key as `0x` plus eight lower-case hex digits.
  String get keyHex => '0x${key.toRadixString(16).padLeft(8, '0')}';

  @override
  String toString() => 'CaptionDateKeyDescriptor(${field.name} $keyHex)';
}

/// Constants and field descriptors for the verified `caption.sav` layout.
///
/// Sources, in the order used:
/// - `host/control.c` (`caption_json`, lines 1869-1901) reads the magic, the
///   two names, the JPEG length and the JPEG.
/// - `scripts/longshot_saves.py` lines 565-588 defines `CAPTION_*` and the six
///   date keys, and requires the JPEG to end the file.
/// - `website/src/lib/save-scrub.ts` lines 11-19 mirrors the Python constants.
/// - `docs/dev/reference/saves.md` lines 92-94 states the layout in prose.
abstract final class CaptionLayout {
  /// Offset of the four format bytes.
  static const int magicOffset = 0;

  /// The format bytes, in file order.
  static const List<int> magicBytes = <int>[0x04, 0x03, 0x02, 0x01];

  /// [magicBytes] read as a little-endian 32-bit integer.
  static const int magicValue = 0x01020304;

  /// Length of the scene and map-path spans.
  static const int nameLength = 64;

  /// Offset of the scene name (the field `control.c` calls `scene`).
  static const int sceneNameOffset = 684;

  /// Offset of the scene/map path (the field `control.c` calls `map`).
  static const int mapPathOffset = 748;

  /// Offset of the marker that holds [layoutCheckValue].
  static const int layoutCheckOffset = 540;

  /// The value at [layoutCheckOffset]: the offset of [jpegLengthOffset].
  static const int layoutCheckValue = 1392;

  /// Length of the fixed header before the JPEG length field.
  static const int headerLength = 1392;

  /// Offset of the JPEG's length, a 32-bit little-endian integer.
  static const int jpegLengthOffset = 1392;

  /// Offset of the JPEG's first byte.
  static const int jpegOffset = 1396;

  /// The shortest buffer that can hold the layout and a `FF D8 FF D9` JPEG.
  ///
  /// `control.c` reads 1,400 header bytes and refuses less; the Python and
  /// TypeScript readers require `jpegOffset + 4`.
  static const int minimumFileLength = 1400;

  /// The shortest possible JPEG: start marker plus end marker.
  static const int minimumJpegLength = 4;

  /// The verified fields, in file order.
  static const List<CaptionFieldDescriptor> fields = <CaptionFieldDescriptor>[
    CaptionFieldDescriptor(
      name: 'magic',
      offset: magicOffset,
      size: 4,
      type: CaptionFieldType.magic,
      endianness: CaptionEndianness.notApplicable,
      provenance:
          'host/control.c:1882 memcmp("\\x04\\x03\\x02\\x01", 4); '
          'scripts/longshot_saves.py:571 CAPTION_MAGIC; '
          'website/src/lib/save-scrub.ts:13; docs/dev/reference/saves.md:92. '
          'All three assets/saves samples start 04 03 02 01.',
    ),
    CaptionFieldDescriptor(
      name: 'layoutCheck',
      offset: layoutCheckOffset,
      size: 4,
      type: CaptionFieldType.unsignedInt,
      endianness: CaptionEndianness.little,
      provenance:
          'scripts/longshot_saves.py:573-574 CAPTION_CHECK=540, value 1392; '
          'website/src/lib/save-scrub.ts:55; docs/dev/reference/saves.md:93. '
          'All three samples hold 70 05 00 00 (1392) at 540.',
    ),
    CaptionFieldDescriptor(
      name: 'sceneName',
      offset: sceneNameOffset,
      size: nameLength,
      type: CaptionFieldType.ascii,
      endianness: CaptionEndianness.notApplicable,
      provenance:
          'host/control.c:1885 (which=0); scripts/longshot_saves.py:572 '
          'CAPTION_SCENE=684; website/src/lib/save-scrub.ts:14. '
          'Samples: "KokiriForest", "HyruleField", "Market" (NUL-terminated; '
          'the market sample has stale "ield" bytes after the NUL).',
    ),
    CaptionFieldDescriptor(
      name: 'mapPath',
      offset: mapPathOffset,
      size: nameLength,
      type: CaptionFieldType.ascii,
      endianness: CaptionEndianness.notApplicable,
      provenance:
          'host/control.c:1885 (which=1) calls it map; '
          'scripts/longshot_saves.py:572 CAPTION_MAP=748. The bytes are not a '
          'numeric map id but a scene/map path: samples "KokiriForest/'
          'KokiriForest_Child", "HyruleField/HyruleField_Child", '
          '"Market/Market_Child". The market sample has stale "eld_Child" and '
          '"d" bytes after the first NUL.',
    ),
    CaptionFieldDescriptor(
      name: 'jpegLength',
      offset: jpegLengthOffset,
      size: 4,
      type: CaptionFieldType.unsignedInt,
      endianness: CaptionEndianness.little,
      provenance:
          'host/control.c:1894; scripts/longshot_saves.py:574 '
          'CAPTION_JPEG_LEN=1392; website/src/lib/save-scrub.ts:57. '
          'All three samples hold 11 0d 00 00 (3345) at 1392, and '
          '1396 + 3345 = 4741, the file length.',
    ),
    CaptionFieldDescriptor(
      name: 'jpeg',
      offset: jpegOffset,
      size: null,
      type: CaptionFieldType.jpeg,
      endianness: CaptionEndianness.notApplicable,
      provenance:
          'host/control.c:1899-1901; scripts/longshot_saves.py:575,612-618 '
          'CAPTION_JPEG=1396 and requires the JPEG to reach end of file; '
          'website/src/lib/save-scrub.ts:57-63. All three samples start '
          'ff d8 ff e0 00 10 4a 46 49 46 at 1396 and end ff d9 at 4739-4740.',
    ),
  ];

  /// The six date keys, in the order the samples store them.
  static const List<CaptionDateKeyDescriptor> dateFields =
      <CaptionDateKeyDescriptor>[
        CaptionDateKeyDescriptor(
          field: CaptionDateField.month,
          key: 0xdfd840d3,
          sampleOffset: 280,
          provenance:
              'scripts/longshot_saves.py:586-588; all three samples have the '
              'key at 280 and the value 1 at 284.',
        ),
        CaptionDateKeyDescriptor(
          field: CaptionDateField.second,
          key: 0x5ee50bed,
          sampleOffset: 288,
          provenance:
              'scripts/longshot_saves.py:586-588; all three samples have the '
              'key at 288 and the value 0 at 292.',
        ),
        CaptionDateKeyDescriptor(
          field: CaptionDateField.minute,
          key: 0x27853bf7,
          sampleOffset: 304,
          provenance:
              'scripts/longshot_saves.py:586-588; all three samples have the '
              'key at 304 and the value 0 at 308.',
        ),
        CaptionDateKeyDescriptor(
          field: CaptionDateField.day,
          key: 0xbd46f485,
          sampleOffset: 312,
          provenance:
              'scripts/longshot_saves.py:586-588; all three samples have the '
              'key at 312 and the value 1 at 316.',
        ),
        CaptionDateKeyDescriptor(
          field: CaptionDateField.hour,
          key: 0x23f3d75e,
          sampleOffset: 328,
          provenance:
              'scripts/longshot_saves.py:586-588; all three samples have the '
              'key at 328 and the value 0 at 332.',
        ),
        CaptionDateKeyDescriptor(
          field: CaptionDateField.year,
          key: 0x9811a3f7,
          sampleOffset: 360,
          provenance:
              'scripts/longshot_saves.py:586-588; all three samples have the '
              'key at 360 and the value 2026 at 364.',
        ),
      ];
}
