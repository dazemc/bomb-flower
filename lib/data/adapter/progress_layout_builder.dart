/// Slot layouts for decoded `progress.sav` and `caption.sav` files.
library;

import 'dart:typed_data';

import 'package:bomb_flower/domain/core/field_metadata.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/core/layout.dart';
import 'package:bomb_flower/domain/save/caption_layout.dart';
import 'package:bomb_flower/domain/save/models/caption_save.dart';
import 'package:bomb_flower/domain/save/models/progress_save.dart';
import 'package:bomb_flower/domain/save/progress_layout.dart' as save_layout;
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';

import 'progress_field_id.dart';

/// Builds [SaveSlotLayout]s from decoded saves and the GameData schema.
///
/// The schema is the only source of names; a record the schema does not name
/// keeps its hash in the label and [FieldConfidence.unverified] confidence.
/// Layouts are descriptions, never guesses: an unnamed field is read-only and
/// every citation says which evidence produced it.
final class ProgressLayoutBuilder {
  /// Creates a builder over [schema].
  const ProgressLayoutBuilder(this.schema);

  /// The schema used to name `progress.sav` fields.
  final GameDataSchema schema;

  /// Describes every field record of [save] in file order.
  ///
  /// [slot] defaults to `slot_00`; the slot's path is `<slot>/progress.sav`.
  SaveSlotLayout buildProgressSlotLayout(
    ProgressSave save, {
    SaveSlotId? slot,
  }) {
    final resolvedSlot = slot ?? SaveSlotId.progress(0);
    // One O(n) index; never schema.byHashOnDisk inside the record loop.
    final defs = <int, SaveFieldDef>{
      for (final def in schema.fields) def.hash: def,
    };
    final fields = <FieldDescriptor>[];
    for (final record in save.records) {
      if (record.isSentinel) {
        continue;
      }
      final def = defs[record.key];
      final evidence = _progressEvidence(def);
      final span = record.dataOffset == null
          ? ByteSpan(record.valueOffset, 4)
          : ByteSpan(record.dataOffset!, record.dataLength);
      final bounds = _boundsFor(record.type);
      fields.add(
        FieldDescriptor(
          progressFieldId(record),
          resolvedSlot,
          def?.name ?? 'Unnamed 0x${_hex8(record.key)}',
          _kindFor(record.type),
          span,
          evidence.confidence,
          evidence.source,
          // Both files are little-endian; without this the encoder would
          // byte-swap every written scalar.
          endianness: Endian.little,
          min: bounds.min,
          max: bounds.max,
          choices: record.type == save_layout.SaveType.enumValue
              ? _choicesFor(def)
              : const <String, int>{},
          readOnly: !_isEditable(record.type, span.length, evidence.confidence),
        ),
      );
    }
    return SaveSlotLayout(
      resolvedSlot,
      '${resolvedSlot.value}/progress.sav',
      List<FieldDescriptor>.unmodifiable(fields),
      expectedLength: save.length,
    );
  }

  /// Describes the six layout fields and the six date entries of [caption].
  ///
  /// [progressSlot] defaults to `slot_00`. The caption slot **id** is
  /// `<progressSlot>.caption` (for example `slot_00.caption`), which is
  /// deliberately not a progress slot id, while its **relative path** is
  /// `<progressSlot>/caption.sav` (for example `slot_00/caption.sav`): the
  /// caption file lives beside `progress.sav` inside the slot folder.
  SaveSlotLayout buildCaptionSlotLayout(
    CaptionSave caption, {
    SaveSlotId? progressSlot,
  }) {
    final progress = progressSlot ?? SaveSlotId.progress(0);
    final slot = SaveSlotId('${progress.value}.caption');
    final fields = <FieldDescriptor>[];
    for (final field in CaptionLayout.fields) {
      final length = switch (field.size) {
        final size? => size,
        null when field.type == CaptionFieldType.jpeg => caption.jpegLength,
        null => null,
      };
      if (length == null) {
        continue;
      }
      final evidence = _captionFieldEvidence(field);
      fields.add(
        FieldDescriptor(
          FieldId('caption.${field.name}'),
          slot,
          field.name,
          _captionKind(field.type),
          ByteSpan(field.offset, length),
          evidence.confidence,
          evidence.source,
          endianness: Endian.little,
          readOnly: evidence.readOnly,
        ),
      );
    }
    for (final date in CaptionLayout.dateFields) {
      fields.add(
        FieldDescriptor(
          FieldId('caption.savedAt.${date.field.name}'),
          slot,
          'savedAt.${date.field.name}',
          FieldKind.integer,
          ByteSpan(date.sampleOffset + 4, 4),
          FieldConfidence.verified,
          'caption:docs/SAVE-FORMAT.md',
          endianness: Endian.little,
          // [date.sampleOffset] is a sample observation, not an invariant:
          // the codec finds each entry by its key, so a fixed value span
          // cannot be rewritten safely.
          readOnly: true,
        ),
      );
    }
    return SaveSlotLayout(
      slot,
      '${progress.value}/caption.sav',
      List<FieldDescriptor>.unmodifiable(fields),
      expectedLength: caption.originalBytes.length,
    );
  }

  static ({FieldConfidence confidence, String source}) _progressEvidence(
    SaveFieldDef? def,
  ) {
    final resolved = def;
    if (resolved == null || resolved.name == null) {
      return (confidence: FieldConfidence.unverified, source: 'unverified');
    }
    final source = resolved.nameSource?.toLowerCase() ?? '';
    if (source.startsWith('struct')) {
      return (confidence: FieldConfidence.verified, source: 'schema:struct');
    }
    if (source.startsWith('host')) {
      return (
        confidence: FieldConfidence.verified,
        source: 'host:oot_state_tap.c',
      );
    }
    if (source.startsWith('game') || source.startsWith('string')) {
      return (confidence: FieldConfidence.verified, source: 'schema:string');
    }
    if (source.startsWith('prefix')) {
      return (confidence: FieldConfidence.inferred, source: 'schema:prefix');
    }
    return (confidence: FieldConfidence.unverified, source: 'unverified');
  }

  static FieldKind _kindFor(save_layout.SaveType type) => switch (type) {
    save_layout.SaveType.boolValue => FieldKind.boolean,
    save_layout.SaveType.intValue => FieldKind.integer,
    save_layout.SaveType.uintValue ||
    save_layout.SaveType.floatValue => FieldKind.integer,
    save_layout.SaveType.enumValue => FieldKind.enumeration,
    save_layout.SaveType.string32 ||
    save_layout.SaveType.string64 => FieldKind.string,
    save_layout.SaveType.vector3 => FieldKind.vector,
    save_layout.SaveType.int64 ||
    save_layout.SaveType.uint64 => FieldKind.integer,
    _ => FieldKind.list,
  };

  static ({num? min, num? max}) _boundsFor(save_layout.SaveType type) =>
      switch (type) {
        save_layout.SaveType.intValue => (min: -2147483648, max: 2147483647),
        save_layout.SaveType.uintValue ||
        save_layout.SaveType.floatValue => (min: 0, max: 4294967295),
        save_layout.SaveType.int64 => (min: -9223372036854775808, max: null),
        save_layout.SaveType.uint64 => (min: 0, max: null),
        _ => (min: null, max: null),
      };

  static Map<String, int> _choicesFor(SaveFieldDef? def) {
    final table = def?.enumTable;
    if (table == null) {
      return const <String, int>{};
    }
    return <String, int>{
      for (final member in table.members) member.name: member.hash,
    };
  }

  /// Whether a field can be rewritten without moving or resizing its bytes.
  ///
  /// Fixed-width scalars qualify; arrays, opaque spans and strings whose span
  /// is not exactly the layout's slot length do not.
  static bool _isEditable(
    save_layout.SaveType type,
    int length,
    FieldConfidence confidence,
  ) {
    if (confidence != FieldConfidence.verified) {
      return false;
    }
    return switch (type) {
      save_layout.SaveType.boolValue ||
      save_layout.SaveType.intValue ||
      save_layout.SaveType.uintValue ||
      save_layout.SaveType.floatValue ||
      save_layout.SaveType.enumValue => length == 4,
      save_layout.SaveType.string32 => length == 32,
      save_layout.SaveType.string64 => length == 64,
      save_layout.SaveType.vector3 => length == 12,
      save_layout.SaveType.int64 || save_layout.SaveType.uint64 => length == 8,
      _ => false,
    };
  }

  static FieldKind _captionKind(CaptionFieldType type) => switch (type) {
    CaptionFieldType.ascii => FieldKind.string,
    CaptionFieldType.jpeg => FieldKind.list,
    CaptionFieldType.magic || CaptionFieldType.unsignedInt => FieldKind.integer,
  };

  /// Evidence for one `CaptionLayout.fields` entry.
  ///
  /// Scene and map names are host-cited and length-preserving 64-byte ASCII
  /// slots, so they are editable. The JPEG length is host-cited but stays
  /// read-only: it must equal the JPEG blob length, and a lone edit would
  /// corrupt the file. Everything else keeps its own provenance and is
  /// conservative.
  static ({FieldConfidence confidence, String source, bool readOnly})
  _captionFieldEvidence(CaptionFieldDescriptor field) => switch (field.name) {
    'sceneName' || 'mapPath' => (
      confidence: FieldConfidence.verified,
      source: 'caption:control.c:1885',
      readOnly: false,
    ),
    'jpegLength' => (
      confidence: FieldConfidence.verified,
      source: 'caption:control.c:1894',
      readOnly: true,
    ),
    _ => (
      confidence: _captionConfidence(field.provenance),
      source: 'caption:${field.provenance}',
      readOnly: true,
    ),
  };

  static FieldConfidence _captionConfidence(String provenance) =>
      provenance.toLowerCase().contains('verified')
      ? FieldConfidence.verified
      : FieldConfidence.inferred;

  static String _hex8(int value) => value.toRadixString(16).padLeft(8, '0');
}
