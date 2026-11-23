/// Callback-backed [SaveTabSource] over the live save project.
///
/// The adapter has no dependency on the save-session cubit or the bloc layer:
/// the app supplies closures over the live project and the session's edit,
/// undo, redo, validation, and slot-age state. Nothing here reads or writes
/// files, and no notification is invented: the real re-render trigger is the
/// [Listenable] supplied at construction.
library;

import 'package:flutter/foundation.dart';

import '../../domain/core/edit_command.dart';
import '../../domain/core/field_metadata.dart';
import '../../domain/core/field_value.dart';
import '../../domain/core/identity.dart';
import '../../domain/core/save_project.dart';
import '../../domain/core/validation.dart';
import '../../domain/fields/field_groups.dart';
import 'save_tab_source.dart';

/// The catalogue's verified `overview.headline` names, in display order.
const List<String> _overviewHeadlineNames = <String>[
  'PlayerStatus.Life',
  'PlayerStatus.MaxLife',
  'PlayerStatus.MP',
  'PlayerStatus.MPMax',
  'PlayerStatus.CurrentRupee',
  'Sequence_CurrentBanc',
  'Sequence_IsChildhood',
];

/// The catalogue's verified `playerWorld.orientation` and
/// `playerWorld.location` names, in display order.
const List<String> _playerWorldHeadlineNames = <String>[
  'Player_Pos_For_Map',
  'Player_Rot_For_Map',
  'DungeonRoom',
  'Sequence_CurrentBanc',
  'Sequence_IsChildhood',
];

/// A [SaveTabSource] built from closures over the session.
///
/// [project] must return the live project or `null`. It is called on every
/// access, never cached, so a rebuild after an edit sees the new bytes.
final class SessionSaveTabSource implements SaveTabSource {
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
  /// Only `overview` and `playerWorld` have a documented mapping: the exact
  /// verified schema names the catalogue puts in `overview.headline`,
  /// `playerWorld.orientation`, and `playerWorld.location`, matched against
  /// [FieldDescriptor.label]. Every other group returns an empty list: their
  /// membership needs the generated catalogue and hash resolution, which this
  /// adapter must not guess. S3 supplies the real grouping.
  @override
  List<TabFieldView> viewsFor(EditorTabGroup group) {
    final names = switch (group) {
      EditorTabGroup.overview => _overviewHeadlineNames,
      EditorTabGroup.playerWorld => _playerWorldHeadlineNames,
      _ => null,
    };
    if (names == null) {
      return const <TabFieldView>[];
    }
    final project = _project();
    if (project == null) {
      return const <TabFieldView>[];
    }
    final slot = activeSlot;
    if (slot == null) {
      return const <TabFieldView>[];
    }
    final document = project.documents[slot];
    if (document == null) {
      return const <TabFieldView>[];
    }
    final issues = _issues?.call() ?? const <ValidationIssue>[];
    final wanted = names.toSet();
    return <TabFieldView>[
      for (final field in document.fields)
        if (wanted.contains(field.descriptor.label)) _viewOf(field, issues),
    ];
  }

  /// Every field of every open document, active slot first.
  @override
  Iterable<TabFieldView> get allViews {
    final project = _project();
    if (project == null) {
      return const <TabFieldView>[];
    }
    final issues = _issues?.call() ?? const <ValidationIssue>[];
    final ordered = <SaveSlotId>[];
    final seen = <SaveSlotId>{};
    final slot = activeSlot;
    if (slot != null && project.documents.containsKey(slot)) {
      ordered.add(slot);
      seen.add(slot);
    }
    for (final candidate in project.documents.keys) {
      if (seen.add(candidate)) {
        ordered.add(candidate);
      }
    }
    return <TabFieldView>[
      for (final candidate in ordered) ...<TabFieldView>[
        for (final field in project.documents[candidate]!.fields)
          _viewOf(field, issues),
      ],
    ];
  }

  @override
  bool get isDirty => _project()?.dirty.hasUnsavedChanges ?? false;

  @override
  int get changedFieldCount => _project()?.dirty.changedFieldCount ?? 0;

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

  TabFieldView _viewOf(
    SaveField<FieldValue> field,
    List<ValidationIssue> issues,
  ) {
    return TabFieldView(
      descriptor: field.descriptor,
      value: field.value,
      isDirty: field.isDirty,
      issueMessage: _messageFor(field.descriptor, issues),
    );
  }

  String? _messageFor(
    FieldDescriptor descriptor,
    List<ValidationIssue> issues,
  ) {
    for (final issue in issues) {
      if (issue.field == descriptor.id && issue.slot == descriptor.slot) {
        return issue.message;
      }
    }
    return null;
  }
}

/// A [ChangeNotifier] that is deliberately never notified.
///
/// The session cubit stream is the real trigger; the default exists only so a
/// source can be constructed before that stream is wired.
final class _NeverNotifies extends ChangeNotifier {}
