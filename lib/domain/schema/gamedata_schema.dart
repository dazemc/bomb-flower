/// Pure-Dart models for the hash-verified GameData save schema.
///
/// The asset `assets/schema/gamedata_110.json` is generated from
/// `GameDataList.Product.110.byml` by `tool/gen_schema.dart`. It contains names,
/// types, defaults, section ids, and enum labels only: no game bytes, strings
/// from binary files, or artwork.
///
/// This library does not import Flutter. A Flutter `rootBundle` adapter belongs
/// in the data/presentation layer and can be passed to [GameDataSchema.load].
library;

import 'dart:convert';

import 'murmur3.dart';

/// The schema revision written in the save container at byte offset 4.
///
/// `2982123 == 0x2d80eb`.
const int gamedataSchemaRevision = 2982123;

/// The GameData type of a field.
///
/// The wire names are exactly the `Data` keys in
/// `GameDataList.Product.110.byml`.
enum SaveType {
  /// A boolean stored as a 32-bit inline value.
  boolean('Bool'),

  /// A fixed-length boolean array stored as a count plus a bit mask.
  booleanArray('BoolArray'),

  /// A signed 32-bit integer stored inline.
  integer('Int'),

  /// A count followed by signed 32-bit integers.
  integerArray('IntArray'),

  /// An IEEE-754 binary32 value stored inline.
  float32('Float'),

  /// A count followed by binary32 values.
  float32Array('FloatArray'),

  /// A 32-bit Murmur3 hash of an enum member name, stored inline.
  enumeration('Enum'),

  /// A count followed by 32-bit enum member hashes.
  enumerationArray('EnumArray'),

  /// An offset to three binary32 values.
  vector3('Vector3'),

  /// An offset to a fixed 16-byte, NUL-padded string (declared only).
  string16('String16'),

  /// An offset to a fixed 32-byte, NUL-padded string.
  string32('String32'),

  /// An offset to a fixed 64-byte, NUL-padded string.
  string64('String64'),

  /// A count followed by fixed 64-byte strings.
  string64Array('String64Array'),

  /// An offset to a length-prefixed byte string.
  binary('Binary'),

  /// A count followed by 32-bit values (observed; semantics unverified).
  binaryArray('BinaryArray'),

  /// An unsigned 32-bit integer stored inline.
  unsignedInteger('UInt'),

  /// A count followed by unsigned 32-bit integers.
  unsignedIntegerArray('UIntArray'),

  /// An offset to a signed 64-bit integer.
  int64('Int64'),

  /// An offset to an unsigned 64-bit integer.
  uint64('UInt64'),

  /// A count followed by unsigned 64-bit integers.
  uint64Array('UInt64Array'),

  /// An offset to a fixed 32-byte UTF-16LE string (declared only).
  wstring16('WString16'),

  /// A count followed by fixed 32-byte UTF-16LE strings.
  wstring16Array('WString16Array'),

  /// A declared 64-bit key that is not serialized into `progress.sav`.
  bool64bitKey('Bool64bitKey');

  const SaveType(this.wireName);

  /// The type name used by the BYML schema.
  final String wireName;

  /// Whether this type is serialized as a count plus elements.
  bool get isArray =>
      this == booleanArray ||
      this == integerArray ||
      this == float32Array ||
      this == enumerationArray ||
      this == string64Array ||
      this == binaryArray ||
      this == unsignedIntegerArray ||
      this == uint64Array ||
      this == wstring16Array;

  /// Whether the record's value slot is an absolute file offset.
  bool get isOffset =>
      this == vector3 ||
      this == string32 ||
      this == string64 ||
      this == string64Array ||
      this == binary ||
      this == binaryArray ||
      this == int64 ||
      this == uint64 ||
      isArray;

  /// The type for [wireName], or `null` for an unknown name.
  static SaveType? fromWireName(String wireName) {
    for (final type in values) {
      if (type.wireName == wireName) {
        return type;
      }
    }
    return null;
  }
}

/// One typed section of the record table.
final class SectionDef {
  /// Creates a section definition.
  const SectionDef({
    required this.typeId,
    required this.type,
    required this.count,
    required this.sentinelValue,
    required this.recordStart,
    required this.recordEnd,
    required this.sentinelRecordIndex,
  });

  /// The sentinel value that ends this section (`1..32`).
  final int typeId;

  /// The field type stored in this section.
  final SaveType type;

  /// Number of field records.
  final int count;

  /// The sentinel's second word; equal to [typeId] in every sample.
  final int sentinelValue;

  /// First raw record index, or `-1` when the section is empty.
  final int recordStart;

  /// Last raw record index, or `-1` when the section is empty.
  final int recordEnd;

  /// Raw record index of the `{0, typeId}` sentinel.
  final int sentinelRecordIndex;

  /// Whether the section has no fields.
  bool get isEmpty => count == 0;

  @override
  String toString() => 'SectionDef($typeId, ${type.wireName}, $count)';
}

/// One member of an enum table.
final class EnumMember {
  /// Creates an enum member.
  const EnumMember({required this.name, required this.hash});

  /// The member's source name.
  final String name;

  /// Murmur3_x86_32 of [name], as stored on disk.
  final int hash;

  @override
  String toString() => 'EnumMember($name, ${hashHex(hash)})';
}

/// A named enum table with hash and name lookups.
final class EnumTable {
  /// Creates a table and its lookup maps.
  EnumTable({required this.key, required List<EnumMember> members})
    : members = List<EnumMember>.unmodifiable(members),
      byHash = Map<int, EnumMember>.unmodifiable(<int, EnumMember>{
        for (final member in members) member.hash: member,
      }),
      byName = Map<String, EnumMember>.unmodifiable(<String, EnumMember>{
        for (final member in members) member.name: member,
      });

  /// The stable key used by [SaveFieldDef.enumTable].
  ///
  /// This is the first verified field name that uses the table, or
  /// `enum_<hash>` when no field name is known. The BYML does not store enum
  /// type names, so these keys are identifiers, not claims about a type name.
  final String key;

  /// Members in source order.
  final List<EnumMember> members;

  /// Lookup by member hash.
  final Map<int, EnumMember> byHash;

  /// Lookup by member name.
  final Map<String, EnumMember> byName;

  /// Resolves a stored enum value to its member, or `null` if unknown.
  EnumMember? member(int hash) => byHash[hash];

  /// Resolves a member name to its stored hash, or `null` if unknown.
  EnumMember? memberNamed(String name) => byName[name];

  @override
  String toString() => 'EnumTable($key, ${members.length} members)';
}

/// One field definition from the GameData schema.
final class SaveFieldDef {
  /// Creates a field definition.
  const SaveFieldDef({
    required this.id,
    required this.name,
    required this.hash,
    required this.type,
    required this.section,
    required this.defaultValue,
    required this.arrayLen,
    required this.enumTable,
    required this.defaultLabel,
    required this.saveFileIndex,
    required this.presentOnDisk,
    required this.verified,
    required this.recordIndex,
    required this.nameSource,
    this.notes,
  });

  /// Stable index in the JSON list (sorted by [hash]).
  final int id;

  /// The verified full field name, or `null` when no name preimage was found.
  final String? name;

  /// The BYML key: Murmur3_x86_32 of [name] for 32-bit fields, or the
  /// declared 64-bit key for [SaveType.bool64bitKey].
  final int hash;

  /// The field's type.
  final SaveType type;

  /// The section id (`1..32`), or `null` for a type with no disk section.
  final int? section;

  /// The schema default. Vector3 values are maps with `x`, `y`, `z`.
  final Object? defaultValue;

  /// Declared element count for array types, otherwise `null`.
  final int? arrayLen;

  /// The enum table for Enum/EnumArray fields, otherwise `null`.
  final EnumTable? enumTable;

  /// The enum member label for [defaultValue], when it is an enum hash.
  final String? defaultLabel;

  /// `0` for progress.sav, `1` option.sav, `2` caption.sav, `3` account.sav,
  /// or `-1` for a runtime-only declaration.
  final int saveFileIndex;

  /// Whether this field is serialized into the referenced save file.
  final bool presentOnDisk;

  /// Whether the hash was checked against a record stream (on-disk fields) or
  /// against the BYML entry and, when named, against the name's Murmur3.
  final bool verified;

  /// Raw record index in the 8-byte table, or `null` when not on disk.
  ///
  /// The record starts at `40 + 8 * recordIndex`; its value word is at
  /// `40 + 8 * recordIndex + 4`.
  final int? recordIndex;

  /// Where [name] came from: `host-code`, `game-string`, `struct-default`,
  /// or `prefix-search`. `null` when [name] is `null`.
  final String? nameSource;

  /// Optional extraction note (for example, a runtime-only declaration).
  final String? notes;

  /// Whether a verified name is available.
  bool get hasName => name != null;

  /// A display label that never invents a name.
  String get displayName => name ?? 'hash ${hashHex(hash)}';

  @override
  String toString() => 'SaveFieldDef($displayName, ${type.wireName})';
}

/// A revision mismatch between the loaded schema and a save file header.
final class SchemaRevisionMismatch implements Exception {
  /// Creates a mismatch error.
  const SchemaRevisionMismatch({required this.expected, required this.actual});

  /// The revision declared by the schema.
  final int expected;

  /// The revision read from the save header.
  final int actual;

  @override
  String toString() =>
      'SchemaRevisionMismatch: schema is ${hashHex(expected)}, '
      'file header is ${hashHex(actual)}';
}

/// The complete GameData save schema.
final class GameDataSchema {
  GameDataSchema._({
    required this.schemaRevision,
    required this.schemaRevisionHex,
    required this.game,
    required this.provenance,
    required this.counts,
    required this.sections,
    required this.emptySectionIds,
    required this.fields,
    required this.absentFields,
    required this.declaredNotSaved,
    required this.enums,
    required this.unresolved,
  }) : _byHash = <int, SaveFieldDef>{
         for (final field in fields) field.hash: field,
         for (final field in declaredNotSaved)
           if (!_containsHash(fields, field.hash)) field.hash: field,
       },
       _byName = <String, SaveFieldDef>{
         for (final field in fields)
           if (field.name != null) field.name!: field,
         for (final field in declaredNotSaved)
           if (field.name != null && !_containsName(fields, field.name!))
             field.name!: field,
       },
       _sections = <int, SectionDef>{
         for (final section in sections) section.typeId: section,
       };

  /// Parses and validates [json].
  ///
  /// When [fileRevision] is supplied, it must equal [schemaRevision]; this is
  /// the version gate an editor should call with the header's revision.
  factory GameDataSchema.fromJsonString(String json, {int? fileRevision}) {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('GameData schema must be a JSON object');
    }

    final schemaRevision = _int(decoded['schemaRevision'], 'schemaRevision');
    if (schemaRevision != gamedataSchemaRevision) {
      throw FormatException(
        'Unsupported schema revision ${hashHex(schemaRevision)}; '
        'expected ${hashHex(gamedataSchemaRevision)}',
      );
    }
    final schemaRevisionHex = _string(
      decoded['schemaRevisionHex'],
      'schemaRevisionHex',
    );
    if (schemaRevisionHex != revisionHex(schemaRevision)) {
      throw FormatException(
        'schemaRevisionHex $schemaRevisionHex does not match '
        '${revisionHex(schemaRevision)}',
      );
    }
    if (fileRevision != null && fileRevision != schemaRevision) {
      throw SchemaRevisionMismatch(
        expected: schemaRevision,
        actual: fileRevision,
      );
    }

    final enumsJson = _map(decoded['enums'], 'enums');
    final enums = <String, EnumTable>{};
    for (final entry in enumsJson.entries) {
      final membersJson = _list(entry.value, 'enums.${entry.key}');
      final members = <EnumMember>[];
      for (var i = 0; i < membersJson.length; i++) {
        final member = _map(membersJson[i], 'enums.${entry.key}[$i]');
        final name = _string(member['name'], 'enums.${entry.key}[$i].name');
        final hash = _int(member['hash'], 'enums.${entry.key}[$i].hash');
        if (hash < 0 || hash > 0xffffffff) {
          throw FormatException(
            'Enum member ${entry.key}.$name hash is not 32-bit: $hash',
          );
        }
        if (murmur3X86_32(name) != hash) {
          throw FormatException(
            'Enum member ${entry.key}.$name hash does not match its name',
          );
        }
        members.add(EnumMember(name: name, hash: hash));
      }
      if (members.isEmpty) {
        throw FormatException('Enum table ${entry.key} has no members');
      }
      enums[entry.key] = EnumTable(key: entry.key, members: members);
    }

    final fieldsJson = _list(decoded['fields'], 'fields');
    final fields = <SaveFieldDef>[];
    for (var i = 0; i < fieldsJson.length; i++) {
      fields.add(_field(fieldsJson[i], enums, 'fields[$i]', present: true));
    }
    final absentJson = _list(decoded['absentFields'], 'absentFields');
    final absent = <SaveFieldDef>[];
    for (var i = 0; i < absentJson.length; i++) {
      absent.add(
        _field(absentJson[i], enums, 'absentFields[$i]', present: false),
      );
    }
    final declaredJson = _list(decoded['declaredNotSaved'], 'declaredNotSaved');
    final declared = <SaveFieldDef>[];
    for (var i = 0; i < declaredJson.length; i++) {
      declared.add(
        _field(declaredJson[i], enums, 'declaredNotSaved[$i]', present: false),
      );
    }

    final sectionsJson = _list(decoded['sections'], 'sections');
    final sections = <SectionDef>[];
    for (var i = 0; i < sectionsJson.length; i++) {
      final section = _map(sectionsJson[i], 'sections[$i]');
      final typeId = _int(section['typeId'], 'sections[$i].typeId');
      final type = _saveType(section['typeName'], 'sections[$i].typeName');
      final count = _int(section['count'], 'sections[$i].count');
      final sentinel = _int(
        section['sentinelValue'],
        'sections[$i].sentinelValue',
      );
      final start = _int(section['recordStart'], 'sections[$i].recordStart');
      final end = _int(section['recordEnd'], 'sections[$i].recordEnd');
      final sentinelIndex = _int(
        section['sentinelRecordIndex'],
        'sections[$i].sentinelRecordIndex',
      );
      sections.add(
        SectionDef(
          typeId: typeId,
          type: type,
          count: count,
          sentinelValue: sentinel,
          recordStart: start,
          recordEnd: end,
          sentinelRecordIndex: sentinelIndex,
        ),
      );
    }

    final emptyIds = _list(
      decoded['emptySectionIds'],
      'emptySectionIds',
    ).map((value) => _int(value, 'emptySectionIds[]')).toList(growable: false);

    final schema = GameDataSchema._(
      schemaRevision: schemaRevision,
      schemaRevisionHex: schemaRevisionHex,
      game: _string(decoded['game'], 'game'),
      provenance: Map<String, Object?>.unmodifiable(
        _map(decoded['provenance'], 'provenance'),
      ),
      counts: Map<String, int>.unmodifiable(
        _map(
          decoded['counts'],
          'counts',
        ).map((key, value) => MapEntry(key, _int(value, 'counts.$key'))),
      ),
      sections: List<SectionDef>.unmodifiable(sections),
      emptySectionIds: List<int>.unmodifiable(emptyIds),
      fields: List<SaveFieldDef>.unmodifiable(fields),
      absentFields: List<SaveFieldDef>.unmodifiable(absent),
      declaredNotSaved: List<SaveFieldDef>.unmodifiable(declared),
      enums: Map<String, EnumTable>.unmodifiable(enums),
      unresolved: List<Map<String, Object?>>.unmodifiable(
        _list(decoded['unresolved'], 'unresolved').map(
          (value) =>
              Map<String, Object?>.unmodifiable(_map(value, 'unresolved[]')),
        ),
      ),
    );
    schema._validate();
    return schema;
  }

  /// Loads and validates the schema from an injected reader.
  ///
  /// In Flutter, pass `() => rootBundle.loadString('assets/schema/...')` from
  /// the data/presentation layer. In tests, pass a file or string reader.
  static Future<GameDataSchema> load(
    Future<String> Function() readJson, {
    int? fileRevision,
  }) async {
    return GameDataSchema.fromJsonString(
      await readJson(),
      fileRevision: fileRevision,
    );
  }

  /// The schema revision (`2982123`).
  final int schemaRevision;

  /// The revision as lower-case hex (`0x2d80eb`).
  final String schemaRevisionHex;

  /// Human-readable game/build string.
  final String game;

  /// Provenance metadata copied from the asset.
  final Map<String, Object?> provenance;

  /// Counts copied from the asset, validated against the lists.
  final Map<String, int> counts;

  /// The 20 non-empty typed sections, in type-id order.
  final List<SectionDef> sections;

  /// The 12 sentinel-only section ids (`9, 10, 12, ...`).
  final List<int> emptySectionIds;

  /// The 11,925 fields serialized into `progress.sav`.
  final List<SaveFieldDef> fields;

  /// The 11,657 `Bool64bitKey` declarations that are not on disk.
  final List<SaveFieldDef> absentFields;

  /// `SaveFileIndex == -1` scalar/array/enum/string declarations.
  ///
  /// These are runtime-only fields; they are exposed so [byHash] can resolve
  /// names the host reads (for example `Sequence_IsLoadingBanc`).
  final List<SaveFieldDef> declaredNotSaved;

  /// Enum tables keyed by [EnumTable.key].
  final Map<String, EnumTable> enums;

  /// Extraction gaps and grouped unresolved-name counts.
  final List<Map<String, Object?>> unresolved;

  final Map<int, SaveFieldDef> _byHash;
  final Map<String, SaveFieldDef> _byName;
  final Map<int, SectionDef> _sections;

  /// Resolves a 32-bit field hash, including runtime-only declarations.
  ///
  /// For an on-disk-only lookup use [byHashOnDisk].
  SaveFieldDef? byHash(int hash) => _byHash[hash];

  /// Resolves a name, including runtime-only declarations.
  ///
  /// For an on-disk-only lookup use [byNameOnDisk].
  SaveFieldDef? byName(String name) => _byName[name];

  /// Resolves an on-disk field by hash.
  SaveFieldDef? byHashOnDisk(int hash) {
    for (final field in fields) {
      if (field.hash == hash) {
        return field;
      }
    }
    return null;
  }

  /// Resolves an on-disk field by verified name.
  SaveFieldDef? byNameOnDisk(String name) {
    for (final field in fields) {
      if (field.name == name) {
        return field;
      }
    }
    return null;
  }

  /// Returns the section for [typeId], or `null` when it is empty/unknown.
  SectionDef? section(int typeId) => _sections[typeId];

  /// Returns the enum table called [key], or `null`.
  EnumTable? enumTable(String key) => enums[key];

  /// Whether [headerRevision] matches this schema's revision.
  bool revisionMatches(int headerRevision) => headerRevision == schemaRevision;

  /// Throws [SchemaRevisionMismatch] unless [headerRevision] matches.
  void validateRevision(int headerRevision) {
    if (!revisionMatches(headerRevision)) {
      throw SchemaRevisionMismatch(
        expected: schemaRevision,
        actual: headerRevision,
      );
    }
  }

  /// On-disk fields that have a verified name.
  Iterable<SaveFieldDef> get namedFields =>
      fields.where((field) => field.hasName);

  /// On-disk fields that are present but have no recovered name.
  Iterable<SaveFieldDef> get unnamedFields =>
      fields.where((field) => !field.hasName);

  void _validate() {
    if (fields.length != counts['onDiskFields']) {
      throw FormatException(
        'Field count ${fields.length} does not match counts.onDiskFields',
      );
    }
    if (absentFields.length != counts['absentBool64bitKey']) {
      throw FormatException(
        'Absent count ${absentFields.length} does not match '
        'counts.absentBool64bitKey',
      );
    }
    if (declaredNotSaved.length != counts['declaredNotSaved']) {
      throw FormatException(
        'Declared count ${declaredNotSaved.length} does not match '
        'counts.declaredNotSaved',
      );
    }
    if (sections.length != counts['sections']) {
      throw FormatException('Section count does not match counts.sections');
    }

    final hashes = <int>{};
    final names = <String>{};
    for (final field in fields) {
      if (field.type == SaveType.bool64bitKey) {
        throw const FormatException('Bool64bitKey must not be on disk');
      }
      if (!hashes.add(field.hash)) {
        throw FormatException(
          'Duplicate on-disk field hash ${hashHex(field.hash)}',
        );
      }
      final name = field.name;
      if (name != null) {
        if (murmur3X86_32(name) != field.hash) {
          throw FormatException(
            'Field $name hash does not match ${hashHex(field.hash)}',
          );
        }
        if (!names.add(name)) {
          throw FormatException('Duplicate field name $name');
        }
      }
      if (!field.verified) {
        throw FormatException(
          'On-disk field ${field.displayName} is unverified',
        );
      }
      final section = _sections[field.section];
      if (section == null || section.type != field.type) {
        throw FormatException(
          'Field ${field.displayName} has no matching section',
        );
      }
    }

    var sectionTotal = 0;
    for (final section in sections) {
      sectionTotal += section.count;
      if (section.count !=
          fields.where((f) => f.section == section.typeId).length) {
        throw FormatException(
          'Section ${section.typeId} count does not match its fields',
        );
      }
    }
    if (sectionTotal != fields.length) {
      throw FormatException(
        'Section counts sum to $sectionTotal, expected ${fields.length}',
      );
    }

    final absentHashes = <int>{};
    for (final field in absentFields) {
      if (field.type != SaveType.bool64bitKey) {
        throw const FormatException(
          'absentFields must contain only Bool64bitKey entries',
        );
      }
      if (field.presentOnDisk) {
        throw const FormatException(
          'A Bool64bitKey must not be present on disk',
        );
      }
      if (!absentHashes.add(field.hash)) {
        throw FormatException('Duplicate Bool64bitKey hash ${field.hash}');
      }
    }

    for (final field in declaredNotSaved) {
      if (field.saveFileIndex != -1 || field.presentOnDisk) {
        throw const FormatException(
          'declaredNotSaved entries must have SaveFileIndex -1',
        );
      }
    }
  }

  static bool _containsHash(List<SaveFieldDef> fields, int hash) =>
      fields.any((field) => field.hash == hash);

  static bool _containsName(List<SaveFieldDef> fields, String name) =>
      fields.any((field) => field.name == name);
}

SaveFieldDef _field(
  Object? value,
  Map<String, EnumTable> enums,
  String context, {
  required bool present,
}) {
  final map = _map(value, context);
  final type = _saveType(map['type'], '$context.type');
  final enumKey = map['enumValues'] == null
      ? null
      : _string(map['enumValues'], '$context.enumValues');
  final table = enumKey == null ? null : enums[enumKey];
  if (enumKey != null && table == null) {
    throw FormatException('$context references unknown enum table $enumKey');
  }
  final sectionValue = map['section'];
  final section = sectionValue == null
      ? null
      : _int(sectionValue, '$context.section');
  final arrayLenValue = map['arrayLen'];
  final arrayLen = arrayLenValue == null
      ? null
      : _int(arrayLenValue, '$context.arrayLen');
  final recordValue = map['recordIndex'];
  final recordIndex = recordValue == null
      ? null
      : _int(recordValue, '$context.recordIndex');
  final nameValue = map['name'];
  final name = nameValue == null ? null : _string(nameValue, '$context.name');
  final sourceValue = map['nameSource'];
  final nameSource = sourceValue == null
      ? null
      : _string(sourceValue, '$context.nameSource');
  final defaultLabelValue = map['defaultLabel'];
  final defaultLabel = defaultLabelValue == null
      ? null
      : _string(defaultLabelValue, '$context.defaultLabel');
  final notesValue = map['notes'];
  final notes = notesValue == null
      ? null
      : _string(notesValue, '$context.notes');
  final defaultValue = _freeze(map['default'], '$context.default');
  final hashValue = map.containsKey('hash') ? map['hash'] : map['hash64'];
  final hash = _int(hashValue, '$context.hash');

  if (name != null) {
    if (type != SaveType.bool64bitKey && murmur3X86_32(name) != hash) {
      throw FormatException('$context name $name does not match its hash');
    }
  }
  if (type == SaveType.enumeration || type == SaveType.enumerationArray) {
    if (table == null) {
      throw FormatException('$context is an enum but has no enum table');
    }
  } else if (table != null) {
    throw FormatException('$context is not an enum but has an enum table');
  }
  if (present && !_bool(map['presentOnDisk'], '$context.presentOnDisk')) {
    throw FormatException('$context must be present on disk');
  }

  return SaveFieldDef(
    id: _int(map['id'], '$context.id'),
    name: name,
    hash: hash,
    type: type,
    section: section,
    defaultValue: defaultValue,
    arrayLen: arrayLen,
    enumTable: table,
    defaultLabel: defaultLabel,
    saveFileIndex: _int(map['saveFileIndex'], '$context.saveFileIndex'),
    presentOnDisk: _bool(map['presentOnDisk'], '$context.presentOnDisk'),
    verified: _bool(map['verified'], '$context.verified'),
    recordIndex: recordIndex,
    nameSource: nameSource,
    notes: notes,
  );
}

SaveType _saveType(Object? value, String context) {
  final name = _string(value, context);
  final type = SaveType.fromWireName(name);
  if (type == null) {
    throw FormatException('$context has unknown type $name');
  }
  return type;
}

Map<String, Object?> _map(Object? value, String context) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, entry) => MapEntry(key.toString(), entry as Object?),
    );
  }
  throw FormatException('$context must be an object');
}

List<Object?> _list(Object? value, String context) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  throw FormatException('$context must be a list');
}

int _int(Object? value, String context) {
  if (value is int) {
    return value;
  }
  if (value is num && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('$context must be an integer');
}

String _string(Object? value, String context) {
  if (value is String) {
    return value;
  }
  throw FormatException('$context must be a string');
}

bool _bool(Object? value, String context) {
  if (value is bool) {
    return value;
  }
  throw FormatException('$context must be a boolean');
}

Object? _freeze(Object? value, String context) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.map((entry) => _freeze(entry, context)),
    );
  }
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(
      value.map(
        (key, entry) =>
            MapEntry(key.toString(), _freeze(entry, '$context.$key')),
      ),
    );
  }
  throw FormatException('$context has an unsupported JSON value');
}
