/// Shared wiring for the open → edit → undo → redo → save-as → reopen chain.
///
/// The engine and repository are the production types unchanged:
/// [createProgressRepository] returns the repository that
/// `ProgressSaveRepositoryFactory.create` builds, so the chain exercises the
/// production resolver, caption slot path (`slot_00/caption.sav`) and
/// `FileSaveRepository` without any test-only adaptation.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/adapter/progress_field_value_codec.dart';
import 'package:bomb_flower/data/adapter/progress_repository.dart';
import 'package:bomb_flower/data/codec/progress_codec.dart';
import 'package:bomb_flower/data/io/file_save_repository.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/engine/save_engine.dart';
import 'package:bomb_flower/domain/save/models/progress_save.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';

/// `PlayerStatus.Life`, a 4-byte little-endian integer.
const FieldId lifeFieldId = FieldId('progress.31ab5580');

/// `PlayerStatus.MaxLife`, a 4-byte little-endian integer.
const FieldId maxLifeFieldId = FieldId('progress.fbe01da1');

/// `Sequence_CurrentBanc`, a 32-byte string field.
const FieldId sequenceFieldId = FieldId('progress.1d6189da');

/// The only slot the chain opens.
final SaveSlotId progressSlotId = SaveSlotId.progress(0);

/// Loads the on-disk schema from the repository root.
///
/// `flutter test` runs with the repository root as the working directory.
Future<GameDataSchema> loadGameDataSchema() async =>
    GameDataSchema.fromJsonString(
      await File('assets/schema/gamedata_110.json').readAsString(),
    );

/// The production engine wiring used by [createProgressRepository].
SaveEngine createProgressEngine() => SaveEngine(
  const SaveFormat(
    'oot-remake',
    'Ocarina of Time (Switch 2 remake)',
    <LayoutDescriptor>[],
  ),
  valueCodec: const ProgressFieldValueCodec(),
);

/// The production repository wiring, exactly as
/// `ProgressSaveRepositoryFactory.create` builds it.
///
/// [ProgressSaveRepositoryFactory.create] declares `SaveRepository` but always
/// returns a [FileSaveRepository]; the cast keeps this helper's existing
/// signature for its callers.
FileSaveRepository createProgressRepository(GameDataSchema schema) =>
    ProgressSaveRepositoryFactory(schema: schema).create('')
        as FileSaveRepository;

/// Value offset of the Life field: `0x28 + 8 * recordIndex + 4`.
int lifeValueOffset(GameDataSchema schema) {
  final def = schema.byNameOnDisk('PlayerStatus.Life');
  final index = def?.recordIndex;
  if (index == null) {
    throw StateError('schema has no on-disk PlayerStatus.Life record');
  }
  return 0x28 + 8 * index + 4;
}

/// Decoded integer value of [fieldId] in [project].
int fieldInt(SaveProject project, FieldId fieldId) {
  final value = project.document(progressSlotId)?.field(fieldId)?.value;
  if (value is! IntValue) {
    throw StateError('$fieldId is not an integer field: $value');
  }
  return value.value;
}

/// The four little-endian bytes of the u32 at [offset], as `0c 00 00 00`.
String hexU32(Uint8List bytes, int offset) => <String>[
  for (var i = 0; i < 4; i++)
    bytes[offset + i].toRadixString(16).padLeft(2, '0'),
].join(' ');

/// Decodes [bytes] and returns the total record count.
int progressRecordCount(Uint8List bytes) => _decode(bytes).recordCount;

/// The 32 `{0, typeId}` sentinels of a `progress.sav`, as `key:value` pairs.
List<({int key, int value})> progressSentinels(Uint8List bytes) =>
    <({int key, int value})>[
      for (final sentinel in _decode(bytes).sentinels)
        (key: sentinel.key, value: sentinel.rawValue),
    ];

/// The footer `{key, value}` pair of a `progress.sav`.
({int key, int value}) progressFooter(Uint8List bytes) {
  final footer = _decode(bytes).footer;
  return (key: footer.key, value: footer.rawValue);
}

ProgressSave _decode(Uint8List bytes) {
  final result = ProgressCodec.decode(bytes);
  if (result is ProgressDecodeOk) {
    return result.save;
  }
  throw StateError('could not decode progress.sav: $result');
}

/// Sorted entry names in [directory], or an empty list when absent.
List<String> directoryEntries(Directory directory) {
  if (!directory.existsSync()) {
    return const <String>[];
  }
  final names = <String>[
    for (final entry in directory.listSync(followLinks: false))
      entry.uri.pathSegments.where((segment) => segment.isNotEmpty).last,
  ];
  names.sort();
  return names;
}

/// Writes one [`[chain] ...`] line so a run can be quoted from the report.
void chainLog(String message) => stdout.writeln('[chain] $message');

/// Short description of a parse outcome.
String describeParseResult(ParseResult result) => switch (result) {
  ParseOk() => 'ParseOk',
  ParseUnverified(:final unverifiedFields) =>
    'ParseUnverified(${unverifiedFields.length} unverified fields)',
  ParseUnsupported(:final reason) => 'ParseUnsupported($reason)',
  ParseCorrupt(:final reason) => 'ParseCorrupt($reason)',
};
