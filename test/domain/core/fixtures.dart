/// Synthetic layouts and bytes shared by engine/IO tests.
///
/// These are test-only values, not game offsets. They let the format-agnostic
/// core be exercised before a real layout lands.
library;

import 'dart:typed_data';

import 'package:bomb_flower/domain/core/core.dart';

/// Progress slot used by the tests.
const SaveSlotId progressSlot = SaveSlotId('slot_00');

/// Field ids used by the tests.
const FieldId healthId = FieldId('player.health');
const FieldId flagsId = FieldId('player.flags');
const FieldId modeId = FieldId('player.mode');
const FieldId nameId = FieldId('player.name');
const FieldId unknownId = FieldId('player.unknown');
const FieldId accountNameId = FieldId('account.name');
const FieldId volumeId = FieldId('option.volume');

/// A two-byte big-endian integer with inclusive bounds 0..100.
FieldDescriptor healthField({
  FieldConfidence confidence = FieldConfidence.verified,
  bool readOnly = false,
  Endian endianness = Endian.big,
}) => FieldDescriptor(
  healthId,
  progressSlot,
  'Health',
  FieldKind.integer,
  const ByteSpan(10, 2),
  confidence,
  'test/domain/core/fixtures.dart',
  endianness: endianness,
  min: 0,
  max: 100,
  readOnly: readOnly,
);

/// A one-byte bitfield.
const FieldDescriptor flagsField = FieldDescriptor(
  flagsId,
  progressSlot,
  'Flags',
  FieldKind.bitfield,
  ByteSpan(20, 1),
  FieldConfidence.verified,
  'test/domain/core/fixtures.dart',
);

/// A one-byte enumeration.
const FieldDescriptor modeField = FieldDescriptor(
  modeId,
  progressSlot,
  'Mode',
  FieldKind.enumeration,
  ByteSpan(30, 1),
  FieldConfidence.verified,
  'test/domain/core/fixtures.dart',
  choices: <String, int>{'child': 1, 'adult': 2},
  min: 1,
  max: 2,
);

/// An eight-byte text field edited through `SetBytes`.
const FieldDescriptor nameField = FieldDescriptor(
  nameId,
  progressSlot,
  'Name',
  FieldKind.string,
  ByteSpan(40, 8),
  FieldConfidence.verified,
  'test/domain/core/fixtures.dart',
);

/// An inferred field that must stay read-only.
const FieldDescriptor unknownField = FieldDescriptor(
  unknownId,
  progressSlot,
  'Unknown',
  FieldKind.integer,
  ByteSpan(50, 2),
  FieldConfidence.inferred,
  'test/domain/core/fixtures.dart',
);

/// A verified field with an empty citation, used to test validation.
const FieldDescriptor uncitedField = FieldDescriptor(
  FieldId('player.uncited'),
  progressSlot,
  'Uncited',
  FieldKind.integer,
  ByteSpan(60, 1),
  FieldConfidence.verified,
  '',
);

/// The progress-slot layout.
SaveSlotLayout progressLayout({
  List<IntegritySpec> integrity = const <IntegritySpec>[],
  bool includeUnverified = true,
  bool includeUncited = false,
  int? expectedLength = 256,
}) => SaveSlotLayout(
  progressSlot,
  'slot_00/progress.sav',
  <FieldDescriptor>[
    healthField(),
    flagsField,
    modeField,
    nameField,
    if (includeUnverified) unknownField,
    if (includeUncited) uncitedField,
  ],
  expectedLength: expectedLength,
  integrity: integrity,
);

/// The account-slot layout.
const SaveSlotLayout accountLayout = SaveSlotLayout(
  SaveSlotId.account,
  'account.sav',
  <FieldDescriptor>[
    FieldDescriptor(
      accountNameId,
      SaveSlotId.account,
      'Account name',
      FieldKind.string,
      ByteSpan(0, 4),
      FieldConfidence.verified,
      'test/domain/core/fixtures.dart',
    ),
  ],
  expectedLength: 64,
);

/// The options-slot layout.
const SaveSlotLayout optionLayout = SaveSlotLayout(
  SaveSlotId.options,
  'option.sav',
  <FieldDescriptor>[
    FieldDescriptor(
      volumeId,
      SaveSlotId.options,
      'Volume',
      FieldKind.integer,
      ByteSpan(0, 1),
      FieldConfidence.verified,
      'test/domain/core/fixtures.dart',
      min: 0,
      max: 10,
    ),
  ],
  expectedLength: 32,
);

/// A complete layout version 7 (minimum 5).
LayoutDescriptor testLayout({
  List<IntegritySpec> integrity = const <IntegritySpec>[],
  bool includeUnverified = true,
  bool includeUncited = false,
  int? expectedLength = 256,
}) => LayoutDescriptor('test-layout', 7, <SaveSlotLayout>[
  accountLayout,
  optionLayout,
  progressLayout(
    integrity: integrity,
    includeUnverified: includeUnverified,
    includeUncited: includeUncited,
    expectedLength: expectedLength,
  ),
], minimumVersion: 5);

/// The format wrapping [testLayout].
SaveFormat testFormat({
  List<IntegritySpec> integrity = const <IntegritySpec>[],
  bool includeUnverified = true,
  bool includeUncited = false,
}) => SaveFormat('test-format', 'Test Format', <LayoutDescriptor>[
  testLayout(
    integrity: integrity,
    includeUnverified: includeUnverified,
    includeUncited: includeUncited,
  ),
]);

/// An unconfirmed integrity scheme covering the progress header.
IntegritySpec testIntegrity({
  FieldConfidence confidence = FieldConfidence.unverified,
}) => IntegritySpec('test-scheme', const ByteSpan(250, 2), const <ByteSpan>[
  ByteSpan(0, 250),
], confidence);

/// Deterministic progress bytes.
Uint8List progressBytes({
  int health = 100,
  int flags = 0,
  int mode = 1,
  String name = 'TestSave',
}) {
  final bytes = Uint8List(256);
  bytes[10] = (health >> 8) & 0xff;
  bytes[11] = health & 0xff;
  bytes[20] = flags & 0xff;
  bytes[30] = mode & 0xff;
  for (var i = 0; i < name.length && i < 8; i++) {
    bytes[40 + i] = name.codeUnitAt(i) & 0xff;
  }
  bytes[250] = 0x12;
  bytes[251] = 0x34;
  return bytes;
}

/// Deterministic account bytes.
Uint8List accountBytes() {
  final bytes = Uint8List(64);
  bytes.setRange(0, 4, <int>[0x41, 0x42, 0x43, 0x00]);
  return bytes;
}

/// Deterministic option bytes.
Uint8List optionBytes({int volume = 5}) {
  final bytes = Uint8List(32);
  bytes[0] = volume;
  return bytes;
}

/// Bytes for every slot in [layout].
Map<SaveSlotId, ByteRegion> testFiles({
  LayoutDescriptor? layout,
  Uint8List? progress,
}) {
  final target = layout ?? testLayout();
  final files = <SaveSlotId, ByteRegion>{
    SaveSlotId.account: ByteRegion.fromBytes(accountBytes()),
    SaveSlotId.options: ByteRegion.fromBytes(optionBytes()),
    progressSlot: ByteRegion.fromBytes(progress ?? progressBytes()),
  };
  return <SaveSlotId, ByteRegion>{
    for (final slot in target.slots)
      if (files[slot.id] != null) slot.id: files[slot.id]!,
  };
}
