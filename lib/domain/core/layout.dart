/// Format, layout, and migration metadata.
///
/// Layouts are data supplied by research. This library contains no offsets,
/// version numbers, or checksum constants.
library;

import 'byte_region.dart';
import 'field_metadata.dart';
import 'identity.dart';

/// One slot's layout metadata and field descriptors.
final class const SaveSlotLayout(
  final SaveSlotId id,
  final String relativePath,
  final List<FieldDescriptor> fields, {
  final int? expectedLength,
  final List<IntegritySpec> integrity = const <IntegritySpec>[],
}) {
  /// The descriptor for [fieldId], if declared for this slot.
  FieldDescriptor? field(FieldId fieldId) {
    for (final descriptor in fields) {
      if (descriptor.id == fieldId) {
        return descriptor;
      }
    }
    return null;
  }
}

/// A pure transformation from one layout version to the next.
abstract interface class LayoutMigration {
  /// Source version.
  int get fromVersion;

  /// Target version.
  int get toVersion;

  /// Returns migrated bytes; never writes in place.
  ByteRegion migrate(ByteRegion source);
}

/// One format version's slots and integrity metadata.
final class const LayoutDescriptor(
  final String id,
  final int version,
  final List<SaveSlotLayout> slots, {
  final int minimumVersion = 1,
  final List<LayoutMigration> migrations = const <LayoutMigration>[],
}) {
  /// The layout for [slotId], if present.
  SaveSlotLayout? slot(SaveSlotId slotId) {
    for (final slot in slots) {
      if (slot.id == slotId) {
        return slot;
      }
    }
    return null;
  }

  /// The field descriptor with [fieldId] across all slots, if present.
  FieldDescriptor? descriptor(FieldId fieldId) {
    for (final slot in slots) {
      final descriptor = slot.field(fieldId);
      if (descriptor != null) {
        return descriptor;
      }
    }
    return null;
  }

  /// Every declared field in slot order.
  List<FieldDescriptor> get allFields => <FieldDescriptor>[
    for (final slot in slots) ...slot.fields,
  ];

  /// The migration from [from] to [from] + 1, if declared.
  LayoutMigration? migrationFrom(int from) {
    for (final migration in migrations) {
      if (migration.fromVersion == from) {
        return migration;
      }
    }
    return null;
  }
}

/// A save format family: a display name and its ordered layout versions.
final class const SaveFormat(
  final String id,
  final String displayName,
  final List<LayoutDescriptor> layouts,
) {
  /// Returns an exact version match; no ranges or nearest-version guessing.
  LayoutDescriptor? layoutFor(int version) {
    for (final layout in layouts) {
      if (layout.version == version) {
        return layout;
      }
    }
    return null;
  }

  /// The highest known layout version, or `null` when no layouts exist.
  int? get newestVersion {
    int? newest;
    for (final layout in layouts) {
      if (newest == null || layout.version > newest) {
        newest = layout.version;
      }
    }
    return newest;
  }
}
