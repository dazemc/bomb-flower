/// Callback-backed [SaveTabSource] over the live save project.
///
/// The adapter has no dependency on the save-session cubit or the bloc layer:
/// the app supplies closures over the live project and the session's edit,
/// undo, redo, validation, and slot-age state. Nothing here reads or writes
/// files, and no notification is invented: the real re-render trigger is the
/// [Listenable] supplied at construction.
library;

import 'package:flutter/foundation.dart';

import '../../domain/core/dirty_state.dart';
import '../../domain/core/edit_command.dart';
import '../../domain/core/identity.dart';
import '../../domain/core/save_project.dart';
import '../../domain/core/validation.dart';
import '../../domain/fields/field_groups.dart';
import 'save_tab_index.dart';
import 'save_tab_source.dart';

/// A [SaveTabSource] built from closures over the session.
///
/// [project] must return the live project or `null`. It is called on every
/// access, never cached, so a rebuild after an edit sees the new bytes.
///
/// The derived view lists and the dirty summary are memoised against the
/// project and issue-list instances they were built from: a project is immutable
/// and a new instance per edit, so `identical` is a sound cache key and a tab
/// that rebuilds without an edit pays nothing.
final class SessionSaveTabSource implements SlotScopedSaveTabSource {
  /// Creates a source.
  ///
  /// [issues] supplies the session's validation issues, [activeSlot] the slot
  /// the user selected, [slotAges] the observed slot timestamps, [changes] the
  /// re-render trigger, and [canUndo]/[canRedo] the session history state. All
  /// are optional because they live in session state rather than the immutable
  /// [SaveProject]. The defaults report "nothing known" honestly.
  factory SessionSaveTabSource({
    required SaveProject? Function() project,
    required void Function(EditCommand command) edit,
    required void Function() undo,
    required void Function() redo,
    List<ValidationIssue> Function()? issues,
    SaveSlotId? Function()? activeSlot,
    List<SlotAge> Function()? slotAges,
    Listenable? changes,
    bool Function()? canUndo,
    bool Function()? canRedo,
  }) {
    return SessionSaveTabSource._(
      project,
      edit,
      undo,
      redo,
      issues,
      activeSlot,
      slotAges,
      changes ?? _NeverNotifies(),
      canUndo,
      canRedo,
    );
  }

  SessionSaveTabSource._(
    this._project,
    this._edit,
    this._undo,
    this._redo,
    this._issues,
    this._activeSlot,
    this._slotAges,
    this._changes,
    this._canUndo,
    this._canRedo,
  );

  static final RegExp _progressSlotPattern = RegExp(r'^slot_\d+$');

  final SaveProject? Function() _project;
  final void Function(EditCommand command) _edit;
  final void Function() _undo;
  final void Function() _redo;
  final List<ValidationIssue> Function()? _issues;
  final SaveSlotId? Function()? _activeSlot;
  final List<SlotAge> Function()? _slotAges;
  final Listenable _changes;
  final bool Function()? _canUndo;
  final bool Function()? _canRedo;

  @override
  bool get isOpen => _project() != null;

  @override
  String? get rootPath => _project()?.rootPath;

  @override
  SaveSlotId? get activeSlot {
    final project = _project();
    if (project == null) {
      return null;
    }
    final injected = _activeSlot?.call();
    if (injected != null && project.documents.containsKey(injected)) {
      return injected;
    }
    for (final slot in project.documents.keys) {
      if (_progressSlotPattern.hasMatch(slot.value)) {
        return slot;
      }
    }
    return project.documents.isEmpty ? null : project.documents.keys.first;
  }

  @override
  Listenable get changes => _changes;

  /// Cache key for the derived index; null until a project is first indexed.
  SaveProject? _indexProject;
  List<ValidationIssue>? _indexIssues;
  SaveSlotId? _indexActiveSlot;
  SaveTabIndex? _index;

  /// Cache key for [dirty]; null until a project's summary is first computed.
  SaveProject? _dirtyProject;
  DirtyState? _dirtyState;

  /// A fresh copy of the active slot's current bytes, or `null` when closed.
  @override
  Uint8List? get activeSlotBytes {
    final slot = activeSlot;
    return slot == null ? null : bytesFor(slot);
  }

  /// A fresh copy of [slot]'s bytes, or `null` when it is not open.
  ///
  /// [ByteRegion.materialize] allocates a new buffer on every call, so callers
  /// can never mutate an engine-owned region through the returned array.
  @override
  Uint8List? bytesFor(SaveSlotId slot) {
    return _project()?.document(slot)?.snapshot.content.materialize();
  }

  /// Field views for [group].
  ///
  /// Only `overview` and `playerWorld` have a documented mapping; every other
  /// group returns an empty list. See [SaveTabIndex.viewsFor].
  @override
  List<TabFieldView> viewsFor(EditorTabGroup group) {
    return _indexForProject()?.viewsFor(group) ?? const <TabFieldView>[];
  }

  /// Views for [slot], built once per project snapshot.
  @override
  List<TabFieldView> viewsForSlot(SaveSlotId slot) {
    return _indexForProject()?.viewsForSlot(slot) ?? const <TabFieldView>[];
  }

  /// Views for the active slot, or empty when nothing is active.
  @override
  List<TabFieldView> get activeSlotViews {
    return _indexForProject()?.activeSlotViews ?? const <TabFieldView>[];
  }

  /// Every field of every open document, active slot first.
  @override
  Iterable<TabFieldView> get allViews {
    return _indexForProject()?.allViews ?? const <TabFieldView>[];
  }

  /// The index for the current project, rebuilt only when the project, the
  /// issue list, or the resolved active slot changes identity.
  SaveTabIndex? _indexForProject() {
    final project = _project();
    if (project == null) {
      _index = null;
      _indexProject = null;
      _indexIssues = null;
      _indexActiveSlot = null;
      return null;
    }
    final issues = _issues?.call() ?? const <ValidationIssue>[];
    final slot = activeSlot;
    if (_index != null &&
        identical(project, _indexProject) &&
        identical(issues, _indexIssues) &&
        slot == _indexActiveSlot) {
      return _index;
    }
    final index = SaveTabIndex(
      project: project,
      issues: issues,
      orderedSlots: _orderedSlots(project, slot),
      activeSlot: slot,
    );
    _index = index;
    _indexProject = project;
    _indexIssues = issues;
    _indexActiveSlot = slot;
    return index;
  }

  /// The project's slots with [active] first, then the rest in document order.
  static List<SaveSlotId> _orderedSlots(
    SaveProject project,
    SaveSlotId? active,
  ) {
    final ordered = <SaveSlotId>[];
    final seen = <SaveSlotId>{};
    if (active != null && project.documents.containsKey(active)) {
      ordered.add(active);
      seen.add(active);
    }
    for (final candidate in project.documents.keys) {
      if (seen.add(candidate)) {
        ordered.add(candidate);
      }
    }
    return ordered;
  }

  /// The project's dirty summary, computed once per project instance.
  DirtyState? _dirtyForProject() {
    final project = _project();
    if (project == null) {
      _dirtyState = null;
      _dirtyProject = null;
      return null;
    }
    if (identical(project, _dirtyProject)) {
      return _dirtyState;
    }
    final dirty = project.dirty;
    _dirtyProject = project;
    _dirtyState = dirty;
    return dirty;
  }

  @override
  bool get isDirty => _dirtyForProject()?.hasUnsavedChanges ?? false;

  @override
  int get changedFieldCount => _dirtyForProject()?.changedFieldCount ?? 0;

  @override
  SaveSlotId? get newestSlot {
    SaveSlotId? newest;
    DateTime? newestAt;
    for (final age in slotAges) {
      final modifiedAt = age.modifiedAt;
      if (modifiedAt == null) {
        continue;
      }
      if (newestAt == null || modifiedAt.isAfter(newestAt)) {
        newest = age.slot;
        newestAt = modifiedAt;
      }
    }
    return newest;
  }

  @override
  List<SlotAge> get slotAges {
    final callback = _slotAges;
    if (callback == null) {
      return const <SlotAge>[];
    }
    final ages = callback();
    return ages.isEmpty ? const <SlotAge>[] : List<SlotAge>.unmodifiable(ages);
  }

  /// Whether the session reports an undo step.
  ///
  /// [SaveProject] does not expose enough session state for this adapter to
  /// answer on its own, so the default is the honest `false` until the app
  /// supplies [canUndo].
  @override
  bool get canUndo => _canUndo?.call() ?? false;

  /// Whether the session reports a redo step; see [canUndo].
  @override
  bool get canRedo => _canRedo?.call() ?? false;

  @override
  void edit(EditCommand command) => _edit(command);

  @override
  void undo() => _undo();

  @override
  void redo() => _redo();
}

/// A [ChangeNotifier] that is deliberately never notified.
///
/// The session cubit stream is the real trigger; the default exists only so a
/// source can be constructed before that stream is wired.
final class _NeverNotifies extends ChangeNotifier {}
