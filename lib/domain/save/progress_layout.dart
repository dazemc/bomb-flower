/// Byte layout of Ocarina of Time's `progress.sav`.
///
/// The layout below was checked against the three scrubbed samples in
/// `.local-fixtures` (`kokiri-start`, `castle-gate`, `market-entrance`,
/// 120,572 bytes each). Longshot copies `progress.sav` without parsing it, so
/// the bytes, not a source file, are the authority here. Every observation
/// that matters is recorded on the affected descriptor.
///
/// The record stream has **32** sentinels, not 19: type ids 1..32 each end a
/// typed section, and 13 of those sections are always empty in the samples.
/// The "19 typed sections" in the verified notes are the 19 *populated*
/// sections. The totals reconcile exactly:
/// 11,925 fields + 32 sentinels + 1 footer = 11,958 records,
/// `0x28 + 8 * 11,958 = 0x175D8`, and the sample file is 120,572 bytes.
library;

/// How a record's value word relates to its data.
enum SaveRecordKind {
  /// The 4-byte value word *is* the value (`Bool`, `Int`, `Float`, `Enum`,
  /// `UInt`).
  inlineScalar,

  /// The value word is an absolute tail offset to a fixed-size span
  /// (`Vector3`, `String32`, `String64`, `Int64`, `UInt64`, `BoolArray`).
  tailFixed,

  /// The value word points to `{u32 count, count * elementSize}` bytes
  /// (`IntArray`, `FloatArray`, `EnumArray`, `String64Array`, `UIntArray`,
  /// `Int64Array`, `UInt64Array`).
  tailCounted,

  /// The value word points to a span whose length is not derivable from a
  /// verified header (`Binary`, `BinaryArray`, `WString16Array`). The span is
  /// inferred from the next tail pointer (or EOF) and preserved as opaque
  /// bytes.
  tailOpaque,

  /// A reserved section that is empty in every sample. A field in one of
  /// these sections cannot be interpreted and is rejected by the codec.
  unknown,
}

/// One of the 32 typed sections of `progress.sav`, in the order the file stores
/// them.
///
/// `typeId` is the sentinel value that terminates the section. `label` is this
/// package's name, not a name from the game. `kind` says how a record's value
/// word is interpreted. [fixedLength] is set for [SaveRecordKind.tailFixed]
/// (except [boolValue], which is inline) and [elementSize] for
/// [SaveRecordKind.tailCounted].
enum SaveType {
  boolValue(1, 'Bool', SaveRecordKind.inlineScalar),
  boolArray(2, 'BoolArray', SaveRecordKind.tailFixed, fixedLength: 8),
  intValue(3, 'Int', SaveRecordKind.inlineScalar),
  intArray(4, 'IntArray', SaveRecordKind.tailCounted, elementSize: 4),
  floatValue(5, 'Float', SaveRecordKind.inlineScalar),
  floatArray(6, 'FloatArray', SaveRecordKind.tailCounted, elementSize: 4),
  enumValue(7, 'Enum', SaveRecordKind.inlineScalar),
  enumArray(8, 'EnumArray', SaveRecordKind.tailCounted, elementSize: 4),
  reserved9(9, 'Reserved9', SaveRecordKind.unknown),
  reserved10(10, 'Reserved10', SaveRecordKind.unknown),
  vector3(11, 'Vector3', SaveRecordKind.tailFixed, fixedLength: 12),
  reserved12(12, 'Reserved12', SaveRecordKind.unknown),
  reserved13(13, 'Reserved13', SaveRecordKind.unknown),
  reserved14(14, 'Reserved14', SaveRecordKind.unknown),
  string32(15, 'String32', SaveRecordKind.tailFixed, fixedLength: 32),
  reserved16(16, 'Reserved16', SaveRecordKind.unknown),
  string64(17, 'String64', SaveRecordKind.tailFixed, fixedLength: 64),
  string64Array(
    18,
    'String64Array',
    SaveRecordKind.tailCounted,
    elementSize: 64,
  ),
  binary(19, 'Binary', SaveRecordKind.tailOpaque),
  binaryArray(20, 'BinaryArray', SaveRecordKind.tailOpaque),
  uintValue(21, 'UInt', SaveRecordKind.inlineScalar),
  uintArray(22, 'UIntArray', SaveRecordKind.tailCounted, elementSize: 4),
  int64(23, 'Int64', SaveRecordKind.tailFixed, fixedLength: 8),
  reserved24(24, 'Reserved24', SaveRecordKind.unknown),
  uint64(25, 'UInt64', SaveRecordKind.tailFixed, fixedLength: 8),
  uint64Array(26, 'UInt64Array', SaveRecordKind.tailCounted, elementSize: 8),
  reserved27(27, 'Reserved27', SaveRecordKind.unknown),
  wstring16Array(28, 'WString16Array', SaveRecordKind.tailOpaque),
  reserved29(29, 'Reserved29', SaveRecordKind.unknown),
  reserved30(30, 'Reserved30', SaveRecordKind.unknown),
  reserved31(31, 'Reserved31', SaveRecordKind.unknown),
  reserved32(32, 'Reserved32', SaveRecordKind.unknown);

  const SaveType(
    this.typeId,
    this.label,
    this.kind, {
    this.fixedLength,
    this.elementSize,
  });

  /// The sentinel value that terminates this section (1..32).
  final int typeId;

  /// This package's name for the section.
  final String label;

  /// How records in this section store their value.
  final SaveRecordKind kind;

  /// Tail span length for [SaveRecordKind.tailFixed], except [boolValue].
  ///
  /// [boolValue]'s value is inline, and [boolArray] is the odd fixed tail shape
  /// `{u32 bitCount, u32 bits}` (always 8 bytes in the samples).
  final int? fixedLength;

  /// Element size for [SaveRecordKind.tailCounted].
  final int? elementSize;

  /// Whether the value word is the value itself.
  bool get isInline => kind == SaveRecordKind.inlineScalar;

  /// Whether the value word is a tail offset.
  bool get isTail =>
      kind == SaveRecordKind.tailFixed ||
      kind == SaveRecordKind.tailCounted ||
      kind == SaveRecordKind.tailOpaque;

  /// Whether a field in this section can be interpreted at all.
  bool get isKnown => kind != SaveRecordKind.unknown;

  /// The type for a sentinel's [typeId], or `null` when it is outside 1..32.
  static SaveType? forTypeId(int typeId) {
    for (final type in values) {
      if (type.typeId == typeId) {
        return type;
      }
    }
    return null;
  }
}

/// One section of the record stream and the evidence for its shape.
final class ProgressSectionDescriptor {
  const ProgressSectionDescriptor({
    required this.type,
    required this.sampleCount,
    required this.provenance,
  });

  /// Which typed section this is.
  final SaveType type;

  /// Field count in `kokiri-start`; all three samples agree.
  final int sampleCount;

  /// Where the shape was observed and what the samples showed.
  final String provenance;

  /// The sentinel value that ends the section.
  int get typeId => type.typeId;

  /// This package's section name.
  String get name => type.label;

  /// How the section's records store their values.
  SaveRecordKind get kind => type.kind;

  @override
  String toString() =>
      'ProgressSectionDescriptor($typeId $name, $sampleCount fields)';
}

/// Constants and section descriptors for the verified `progress.sav` layout.
///
/// Sources, in the order used:
/// - The three scrubbed samples in `.local-fixtures` (they agree byte for
///   byte on the header, the record count, the sentinel order and the footer).
/// - The verified format notes supplied with this codec, which agree with the
///   samples on every offset except the section count: the notes say 19 typed
///   sections and 32 sentinels, which is consistent only when "19" means the
///   populated sections.
/// - `scripts/longshot_saves.py` caps a repository `progress.sav` at 512 KiB
///   and copies the file unchanged; it does not document the record format.
abstract final class ProgressLayout {
  /// Offset of the four format bytes.
  static const int magicOffset = 0x00;

  /// The format bytes, in file order.
  static const List<int> magicBytes = <int>[0x04, 0x03, 0x02, 0x01];

  /// [magicBytes] read as a little-endian 32-bit integer.
  static const int magicValue = 0x01020304;

  /// Offset of the schema revision.
  static const int revisionOffset = 0x04;

  /// The only revision this codec understands (0x002D80EB).
  static const int revision = 2982123;

  /// Offset of the absolute start of the tail.
  static const int dataOffsetFieldOffset = 0x08;

  /// First byte of the zero-filled gap between the header and the records.
  static const int reservedOffset = 0x0C;

  /// Length of the zero-filled gap (`0x0C..0x27`).
  static const int reservedLength = 0x1C;

  /// Offset of the first 8-byte record.
  static const int recordStart = 0x28;

  /// Size of one record: `{u32 key, u32 value}`.
  static const int recordSize = 8;

  /// Size of a record's value word.
  static const int valueWordSize = 4;

  /// One sentinel per type id, 1..32.
  static const int sentinelCount = 32;

  /// The shortest record stream: 32 sentinels and the footer.
  static const int minimumRecordCount = sentinelCount + 1;

  /// The shortest readable file: header plus [minimumRecordCount] records.
  static const int minimumFileLength =
      recordStart + minimumRecordCount * recordSize;

  /// Key of the last record before [dataOffsetFieldOffset]'s target.
  static const int footerKey = 0xA3DB7114;

  /// Value of the footer in all three samples. Opaque; never rewritten.
  static const int footerValue = 0x1D6F4;

  /// Tail start in all three samples.
  static const int sampleDataOffset = 0x175D8;

  /// Record count in all three samples.
  static const int sampleRecordCount = 11958;

  /// Field count in all three samples (records minus sentinels and footer).
  static const int sampleFieldCount = 11925;

  /// File length in all three samples.
  static const int sampleFileLength = 120572;

  /// Longshot's repository cap for `progress.sav` (512 KiB).
  ///
  /// This codec does not enforce it; it is recorded so callers can apply the
  /// same repository rule without re-deriving the number.
  static const int repositoryFileLengthCap = 512 << 10;

  /// The 32 sections in file order.
  static const List<ProgressSectionDescriptor> sections =
      <ProgressSectionDescriptor>[
        ProgressSectionDescriptor(
          type: SaveType.boolValue,
          sampleCount: 10212,
          provenance:
              'All three samples: 10,212 records, every value 0 or 1 inline. '
              'Type 1.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.boolArray,
          sampleCount: 6,
          provenance:
              'All three samples: 6 records, each a pointer to 8 bytes '
              '{u32 bitCount, u32 bits}; bitCount is 5, 6, 7 or 10. Type 2.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.intValue,
          sampleCount: 1144,
          provenance:
              'All three samples: 1,144 records, inline signed 32-bit. '
              'Type 3.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.intArray,
          sampleCount: 155,
          provenance:
              'All three samples: 155 records, pointer to '
              '{u32 count, count * 4}. Type 4.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.floatValue,
          sampleCount: 76,
          provenance:
              'All three samples: 76 records, inline IEEE-754 binary32. '
              'Type 5.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.floatArray,
          sampleCount: 3,
          provenance:
              'All three samples: 3 records, pointer to '
              '{u32 count, count * 4}. Type 6.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.enumValue,
          sampleCount: 101,
          provenance:
              'All three samples: 101 records, inline 32-bit hash. Type 7.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.enumArray,
          sampleCount: 14,
          provenance:
              'All three samples: 14 records, pointer to '
              '{u32 count, count * 4}. Type 8.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.reserved9,
          sampleCount: 0,
          provenance:
              'All three samples: the bare sentinel {0, 9}; no field observed. '
              'Layout unverified, so a field here is rejected.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.reserved10,
          sampleCount: 0,
          provenance:
              'All three samples: the bare sentinel {0, 10}; no field '
              'observed. Layout unverified, so a field here is rejected.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.vector3,
          sampleCount: 16,
          provenance:
              'All three samples: 16 records, pointer to 12 bytes '
              '(3 x little-endian binary32). Type 11.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.reserved12,
          sampleCount: 0,
          provenance:
              'All three samples: the bare sentinel {0, 12}; no field '
              'observed. Layout unverified, so a field here is rejected.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.reserved13,
          sampleCount: 0,
          provenance:
              'All three samples: the bare sentinel {0, 13}; no field '
              'observed. Layout unverified, so a field here is rejected.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.reserved14,
          sampleCount: 0,
          provenance:
              'All three samples: the bare sentinel {0, 14}; no field '
              'observed. Layout unverified, so a field here is rejected.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.string32,
          sampleCount: 1,
          provenance:
              'All three samples: 1 record, pointer to a 32-byte '
              'NUL-terminated buffer. Type 15.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.reserved16,
          sampleCount: 0,
          provenance:
              'All three samples: the bare sentinel {0, 16}; no field '
              'observed. The notes mention a String16 shape but no sample '
              'confirms one, so the section stays unknown.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.string64,
          sampleCount: 30,
          provenance:
              'All three samples: 30 records, pointer to a 64-byte '
              'NUL-terminated buffer. Type 17.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.string64Array,
          sampleCount: 3,
          provenance:
              'All three samples: 3 records, pointer to '
              '{u32 count, count * 64-byte NUL-terminated strings}. Type 18.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.binary,
          sampleCount: 3,
          provenance:
              'All three samples: 3 records, opaque. Spans are 404, 4 and 4 '
              'bytes; the first word of the 404-byte span is 400, but no '
              'source verifies a length header. Type 19.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.binaryArray,
          sampleCount: 2,
          provenance:
              'All three samples: 2 records, opaque 44-byte spans. The first '
              'word is 10, but the element shape is unverified. Type 20.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.uintValue,
          sampleCount: 87,
          provenance:
              'All three samples: 87 records, inline unsigned 32-bit. '
              'Type 21.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.uintArray,
          sampleCount: 33,
          provenance:
              'All three samples: 33 records, pointer to '
              '{u32 count, count * 4}. Type 22.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.int64,
          sampleCount: 28,
          provenance:
              'All three samples: 28 records, pointer to 8 bytes '
              '(little-endian signed 64-bit). Type 23.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.reserved24,
          sampleCount: 0,
          provenance:
              'All three samples: the bare sentinel {0, 24}; no field '
              'observed. Layout unverified, so a field here is rejected.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.uint64,
          sampleCount: 5,
          provenance:
              'All three samples: 5 records, pointer to 8 bytes '
              '(little-endian unsigned 64-bit). Type 25.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.uint64Array,
          sampleCount: 4,
          provenance:
              'All three samples: 4 records, pointer to '
              '{u32 count, count * 8}. Type 26.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.reserved27,
          sampleCount: 0,
          provenance:
              'All three samples: the bare sentinel {0, 27}; no field '
              'observed. Layout unverified, so a field here is rejected.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.wstring16Array,
          sampleCount: 2,
          provenance:
              'All three samples: 2 records, opaque. Spans are 324 and 332 '
              'bytes; the first word is 10. The notes say the shape is '
              'unverified, so it is preserved as an opaque range. Type 28.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.reserved29,
          sampleCount: 0,
          provenance:
              'All three samples: the bare sentinel {0, 29}; no field '
              'observed. Layout unverified, so a field here is rejected.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.reserved30,
          sampleCount: 0,
          provenance:
              'All three samples: the bare sentinel {0, 30}; no field '
              'observed. Layout unverified, so a field here is rejected.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.reserved31,
          sampleCount: 0,
          provenance:
              'All three samples: the bare sentinel {0, 31}; no field '
              'observed. Layout unverified, so a field here is rejected.',
        ),
        ProgressSectionDescriptor(
          type: SaveType.reserved32,
          sampleCount: 0,
          provenance:
              'All three samples: the bare sentinel {0, 32}; no field '
              'observed. Layout unverified, so a field here is rejected.',
        ),
      ];

  /// The only field names verified for this file.
  ///
  /// This is deliberately a short, explicit table, not a hash-to-name
  /// dictionary. [ProgressSaveNameHook.nameFor] returns `null` for every other
  /// key unless a name map is injected by the caller.
  static const Map<int, String> verifiedFieldNames = <int, String>{
    0x1D6189DA: 'Sequence_CurrentBanc',
    0xCEA220D3: 'Sequence_IsChildhood',
    0xA4AEE8CD: 'Player_Rot_For_Map',
    0x31AB5580: 'PlayerStatus.Life',
    0xFBE01DA1: 'PlayerStatus.MaxLife',
    0xA77921D7: 'PlayerStatus.CurrentRupee',
    0x960AD56A: 'Player_Pos_For_Map',
  };

  /// The descriptor for [type].
  static ProgressSectionDescriptor sectionFor(SaveType type) =>
      sections[type.index];

  /// A key as `0x` plus eight lower-case hex digits.
  static String keyHex(int key) => '0x${key.toRadixString(16).padLeft(8, '0')}';
}
