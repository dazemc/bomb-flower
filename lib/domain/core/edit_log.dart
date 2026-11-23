/// Append-only audit log for save-session actions.
library;

import 'dart:convert';

import 'edit_command.dart';
import 'field_metadata.dart';
import 'identity.dart';

/// What an audit record describes.
enum EditKind {
  /// A field edit was applied.
  apply,

  /// The prior state was restored by undo.
  undo,

  /// An undone state was re-applied.
  redo,

  /// A slot was reset to its original bytes.
  reset,

  /// A slot or project was duplicated.
  duplicate,

  /// A save folder was opened.
  open,

  /// The project was exported.
  save,
}

/// One immutable audit record.
///
/// Records are never removed by undo; only the bounded retention policy drops
/// the oldest entries. [byteCount] is the number of changed bytes attributable
/// to the action, or the bytes opened/written for [EditKind.open] and
/// [EditKind.save].
final class const EditRecord(
  final int sequence,
  final EditKind kind,
  final DateTime at,
  final SaveSlotId slot,
  final int beforeRevision,
  final int afterRevision, [
  final EditCommand? command,
  final String description = '',
  final int byteCount = 0,
]) {
  /// Serialises this record to JSON-compatible values.
  Map<String, Object?> toJson() => <String, Object?>{
    'sequence': sequence,
    'kind': kind.name,
    'at': at.toIso8601String(),
    'slot': slot.value,
    'beforeRevision': beforeRevision,
    'afterRevision': afterRevision,
    if (command != null) 'command': _commandToJson(command!),
    'description': description,
    'byteCount': byteCount,
  };

  /// Parses a record produced by [toJson].
  static EditRecord fromJson(Map<String, Object?> json) {
    final sequence = _readInt(json, 'sequence');
    final kindName = _readString(json, 'kind');
    final kind = EditKind.values.where((value) => value.name == kindName);
    if (kind.isEmpty) {
      throw FormatException('Unknown edit kind "$kindName"');
    }
    final atText = _readString(json, 'at');
    final at = DateTime.tryParse(atText);
    if (at == null) {
      throw FormatException('Invalid timestamp "$atText"');
    }
    return EditRecord(
      sequence,
      kind.first,
      at,
      SaveSlotId(_readString(json, 'slot')),
      _readInt(json, 'beforeRevision'),
      _readInt(json, 'afterRevision'),
      _commandFromJson(json['command']),
      json['description'] is String ? json['description']! as String : '',
      json['byteCount'] is int ? json['byteCount']! as int : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EditRecord &&
      other.sequence == sequence &&
      other.kind == kind &&
      other.at == at &&
      other.slot == slot &&
      other.beforeRevision == beforeRevision &&
      other.afterRevision == afterRevision &&
      other.command == command &&
      other.description == description &&
      other.byteCount == byteCount;

  @override
  int get hashCode => Object.hash(
    sequence,
    kind,
    at,
    slot,
    beforeRevision,
    afterRevision,
    command,
    description,
    byteCount,
  );

  @override
  String toString() =>
      'EditRecord($sequence, ${kind.name}, ${slot.value}, "$description")';
}

/// A bounded, append-only list of audit records.
///
/// Instances are immutable; [append] returns a new log. The newest
/// [maxRecords] entries are retained.
final class EditLog {
  /// Creates a log, trimming the oldest records if [records] is oversized.
  EditLog(Iterable<EditRecord> records, {this.maxRecords = 1000})
    : records = List<EditRecord>.unmodifiable(
        records.length <= maxRecords
            ? records
            : records.skip(records.length - maxRecords),
      ) {
    if (maxRecords < 1) {
      throw ArgumentError.value(maxRecords, 'maxRecords', 'must be positive');
    }
  }

  /// An empty log with the default retention limit.
  EditLog.empty() : this(const <EditRecord>[]);

  /// Retained records, oldest first.
  final List<EditRecord> records;

  /// Maximum retained record count.
  final int maxRecords;

  /// Whether no records exist.
  bool get isEmpty => records.isEmpty;

  /// Number of retained records.
  int get length => records.length;

  /// The next sequence number for an append.
  int get nextSequence => records.isEmpty ? 1 : records.last.sequence + 1;

  /// The newest retained record, if any.
  EditRecord? get last => records.isEmpty ? null : records.last;

  /// Returns a new log with [record] appended, evicting the oldest if needed.
  EditLog append(EditRecord record) =>
      EditLog(<EditRecord>[...records, record], maxRecords: maxRecords);

  /// Serialises the whole log.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'maxRecords': maxRecords,
    'records': records.map((record) => record.toJson()).toList(),
  };

  /// Parses a log produced by [toJson].
  static EditLog fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version != 1) {
      throw FormatException('Unsupported edit-log version "$version"');
    }
    final rawRecords = json['records'];
    if (rawRecords is! List<Object?>) {
      throw const FormatException('Edit log must contain a records list');
    }
    final records = <EditRecord>[];
    for (final raw in rawRecords) {
      if (raw is! Map<String, Object?>) {
        throw FormatException('Record is not a JSON object: $raw');
      }
      records.add(EditRecord.fromJson(raw));
    }
    final maxRecords = json['maxRecords'];
    return EditLog(
      records,
      maxRecords: maxRecords is int && maxRecords > 0 ? maxRecords : 1000,
    );
  }

  /// Encodes the log as a JSON string.
  String encode() => jsonEncode(toJson());

  /// Decodes a log from [encode] output.
  static EditLog decode(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, Object?>) {
      throw const FormatException('Edit log JSON must be an object');
    }
    return fromJson(value);
  }

  @override
  String toString() => 'EditLog(${records.length} records)';
}

Map<String, Object?> _commandToJson(EditCommand command) => switch (command) {
  SetScalar(:final field, :final value) => <String, Object?>{
    'type': 'setScalar',
    'field': field.value,
    'value': value,
  },
  SetBit(:final field, :final bit, :final value) => <String, Object?>{
    'type': 'setBit',
    'field': field.value,
    'bit': bit,
    'value': value,
  },
  SetEnum(:final field, :final key) => <String, Object?>{
    'type': 'setEnum',
    'field': field.value,
    'key': key,
  },
  SetBytes(:final field, :final target, :final bytes) => <String, Object?>{
    'type': 'setBytes',
    'field': field.value,
    'target': <String, Object?>{
      'offset': target.offset,
      'length': target.length,
    },
    'bytes': bytes.toList(),
  },
};

EditCommand? _commandFromJson(Object? raw) {
  if (raw == null) {
    return null;
  }
  if (raw is! Map<String, Object?>) {
    throw FormatException('Command is not a JSON object: $raw');
  }
  final field = FieldId(_readString(raw, 'field'));
  return switch (raw) {
    {'type': 'setScalar', 'value': final int value} => SetScalar(field, value),
    {'type': 'setBit', 'bit': final int bit, 'value': final bool value} =>
      SetBit(field, bit, value),
    {'type': 'setEnum', 'key': final String key} => SetEnum(field, key),
    {
      'type': 'setBytes',
      'target': {'offset': final int offset, 'length': final int length},
      'bytes': final List<Object?> bytes,
    } =>
      SetBytes(
        field,
        target: ByteSpan(offset, length),
        bytes: <int>[
          for (final byte in bytes)
            if (byte is int)
              byte
            else
              throw FormatException('SetBytes byte is not an int: $byte'),
        ],
      ),
    {'type': final Object? type} => throw FormatException(
      'Unknown edit command "$type"',
    ),
    _ => throw const FormatException('Edit command is missing a type'),
  };
}

int _readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('"$key" must be an integer, got $value');
}

String _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  throw FormatException('"$key" must be a string, got $value');
}
