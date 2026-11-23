import 'package:flutter/foundation.dart';

import '../../domain/core/edit_command.dart';
import '../../domain/core/field_metadata.dart';
import '../../domain/core/field_value.dart';
import '../../domain/core/save_project.dart';
import '../../domain/core/validation.dart';
import '../../domain/fields/field_groups.dart';

/// A single field as the save tab should render it.
final class TabFieldView {
  const TabFieldView({
    required this.descriptor,
    required this.value,
    required this.isDirty,
    this.issueMessage,
  });

  /// Schema description of the field (name, hash, source).
  final FieldDescriptor descriptor;

  /// Decoded value, or null when the view is opaque (no decoded form).
  final FieldValue? value;

  /// True when the field differs from what was last saved.
  final bool isDirty;

  /// Human-readable inline validation text, if the current value is invalid.
  final String? issueMessage;
}

/// The age of one save slot on disk.
final class SlotAge {
  const SlotAge({
    required this.slot,
    required this.progressPath,
    this.modifiedAt,
  });

  /// Slot this age belongs to.
  final SaveSlotId slot;

  /// Filesystem path of the slot's progress document.
  final String progressPath;

  /// Last modification time, when the filesystem could supply one.
  final DateTime? modifiedAt;

  /// True when a modification time is available.
  bool get hasTimestamp => modifiedAt != null;
}

/// Read/write port the save tab renders against.
abstract interface class SaveTabSource {
  /// True when a project is open and the tab can show content.
  bool get isOpen;

  /// Root directory of the open project, or null when none is open.
  String? get rootPath;

  /// Slot the tab is editing, if any.
  SaveSlotId? get activeSlot;

  /// Re-render trigger; hosts rebuild the tab when this notifies.
  Listenable get changes;

  /// Field views belonging to [group], possibly empty.
  List<TabFieldView> viewsFor(EditorTabGroup group);

  /// Every field view the source can render.
  Iterable<TabFieldView> get allViews;

  /// True when any field differs from the last saved state.
  bool get isDirty;

  /// Number of fields that differ from the last saved state.
  int get changedFieldCount;

  /// Most recently modified slot, if timestamps are known.
  SaveSlotId? get newestSlot;

  /// Known ages of the project's slots.
  List<SlotAge> get slotAges;

  /// True when an undo step is available.
  bool get canUndo;

  /// True when a redo step is available.
  bool get canRedo;

  /// Applies [command] to the open project.
  void edit(EditCommand command);

  /// Undoes the most recent edit.
  void undo();

  /// Redoes the most recently undone edit.
  void redo();
}
