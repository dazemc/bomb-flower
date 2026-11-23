/// Dirty-state reporting for open projects and backups.
library;

import 'identity.dart';

/// Two independent dirty badges and the change summary behind them.
///
/// [hasUnsavedChanges] compares current fingerprints with the last successful
/// export. [differsFromOriginal] compares them with the bytes captured at open.
/// Undo back to the saved state clears the first; reset to the sidecar original
/// clears the second.
final class const DirtyState(
  final bool hasUnsavedChanges,
  final bool differsFromOriginal,
  final int changedFieldCount,
  final int changedByteCount,
  final Set<SaveSlotId> dirtySlots, {
  final Set<FieldId> changedFields = const <FieldId>{},
}) {
  /// No changes of either kind.
  static const DirtyState clean = DirtyState(
    false,
    false,
    0,
    0,
    <SaveSlotId>{},
  );

  /// Whether no unsaved changes exist.
  bool get isClean => !hasUnsavedChanges;

  /// Whether the current bytes differ from the opened originals.
  bool get isModified => differsFromOriginal;

  @override
  bool operator ==(Object other) =>
      other is DirtyState &&
      other.hasUnsavedChanges == hasUnsavedChanges &&
      other.differsFromOriginal == differsFromOriginal &&
      other.changedFieldCount == changedFieldCount &&
      other.changedByteCount == changedByteCount &&
      _setsEqual(other.dirtySlots, dirtySlots) &&
      _setsEqual(other.changedFields, changedFields);

  @override
  int get hashCode => Object.hash(
    hasUnsavedChanges,
    differsFromOriginal,
    changedFieldCount,
    changedByteCount,
    Object.hashAll(dirtySlots),
    Object.hashAll(changedFields),
  );

  @override
  String toString() =>
      'DirtyState(unsaved: $hasUnsavedChanges, modified: $differsFromOriginal, '
      'fields: $changedFieldCount, bytes: $changedByteCount, '
      'slots: ${dirtySlots.map((slot) => slot.value).join(', ')})';
}

bool _setsEqual<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);
