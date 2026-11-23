/// An indexed, memoised derivation of [TabFieldView]s from one open project.
///
/// Before this existed, every tab called `allViews`, which walked all ~11,925
/// fields of all six progress documents and linearly scanned the whole
/// validation issue list (≈50,000 unverified issues) for every field: about
/// 17 seconds of work per tab open. The index turns the issue lookup into one
/// O(issues) pass and materialises one slot's views on demand, so a tab build
/// costs O(fields of the active slot).
///
/// The index is immutable and is valid only for the project and issue list it
/// was built from. [SessionSaveTabSource] keys the cache on `identical(project)`
/// and `identical(issues)`; a project is immutable and a new instance per edit,
/// so that key is sound.
library;

import '../../domain/core/field_metadata.dart';
import '../../domain/core/field_value.dart';
import '../../domain/core/identity.dart';
import '../../domain/core/save_project.dart';
import '../../domain/core/validation.dart';
import '../../domain/fields/field_groups.dart';
import 'save_tab_source.dart';

/// The verified `overview.headline` names, in display order.
const List<String> _overviewHeadlineNames = <String>[
  'PlayerStatus.Life',
  'PlayerStatus.MaxLife',
  'PlayerStatus.MP',
  'PlayerStatus.MPMax',
  'PlayerStatus.CurrentRupee',
  'Sequence_CurrentBanc',
  'Sequence_IsChildhood',
];

/// The verified `playerWorld.orientation` and `playerWorld.location` names.
const List<String> _playerWorldHeadlineNames = <String>[
  'Player_Pos_For_Map',
  'Player_Rot_For_Map',
  'DungeonRoom',
  'Sequence_CurrentBanc',
  'Sequence_IsChildhood',
];

/// Slot-scoped, lazily materialised field views for one project snapshot.
final class SaveTabIndex {
  /// Builds an index for [project].
  ///
  /// [orderedSlots] is the source's display order (active slot first); the
  /// overview and player/world groups read the first slot in that order, and
  /// [allViews] concatenates every slot in it. [activeSlot] is kept separately
  /// because a slot with no document still counts as "the active slot" for
  /// cache identity.
  SaveTabIndex({
    required this._project,
    required List<ValidationIssue> issues,
    required List<SaveSlotId> orderedSlots,
    required this.activeSlot,
  }) : _orderedSlots = List<SaveSlotId>.unmodifiable(orderedSlots),
       _issueMessages = _indexIssues(issues);

  final SaveProject _project;
  final List<SaveSlotId> _orderedSlots;

  /// The slot the tabs should scope to, if any.
  final SaveSlotId? activeSlot;

  /// First message per slot and field; the issue list's order is preserved, so
  /// the first issue for a field still wins, exactly as before.
  ///
  /// Nested rather than a `'slot\0field'` single map: both keys are extension
  /// types over [String], so a lookup allocates nothing, while building a
  /// combined key per field allocated ~12,000 strings per slot.
  final Map<SaveSlotId, Map<FieldId, String>> _issueMessages;

  final Map<SaveSlotId, List<TabFieldView>> _slotViews =
      <SaveSlotId, List<TabFieldView>>{};
  final Map<EditorTabGroup, List<TabFieldView>> _groupViews =
      <EditorTabGroup, List<TabFieldView>>{};
  List<TabFieldView>? _all;

  /// Every field of every open document, active slot first.
  List<TabFieldView> get allViews => _all ??= List<TabFieldView>.unmodifiable(
    <TabFieldView>[for (final slot in _orderedSlots) ...viewsForSlot(slot)],
  );

  /// Views for [slot], built once and reused.
  List<TabFieldView> viewsForSlot(SaveSlotId slot) {
    final cached = _slotViews[slot];
    if (cached != null) {
      return cached;
    }
    final document = _project.documents[slot];
    if (document == null) {
      return _slotViews[slot] = const <TabFieldView>[];
    }
    final views = List<TabFieldView>.unmodifiable(<TabFieldView>[
      for (final field in document.fields) _viewOf(field),
    ]);
    return _slotViews[slot] = views;
  }

  /// Views for the active slot, or empty when nothing is active.
  List<TabFieldView> get activeSlotViews {
    final slot = activeSlot;
    return slot == null ? const <TabFieldView>[] : viewsForSlot(slot);
  }

  /// Views belonging to [group].
  ///
  /// Only `overview` and `playerWorld` have a documented mapping: the exact
  /// verified schema names the catalogue puts in `overview.headline`,
  /// `playerWorld.orientation`, and `playerWorld.location`, matched against
  /// [FieldDescriptor.label]. Every other group is empty: their membership
  /// needs the generated catalogue and hash resolution, which the adapter must
  /// not guess.
  List<TabFieldView> viewsFor(EditorTabGroup group) {
    final cached = _groupViews[group];
    if (cached != null) {
      return cached;
    }
    final names = switch (group) {
      EditorTabGroup.overview => _overviewHeadlineNames,
      EditorTabGroup.playerWorld => _playerWorldHeadlineNames,
      _ => null,
    };
    if (names == null) {
      return _groupViews[group] = const <TabFieldView>[];
    }
    final wanted = names.toSet();
    final views = <TabFieldView>[
      for (final view in activeSlotViews)
        if (wanted.contains(view.descriptor.label)) view,
    ];
    return _groupViews[group] = List<TabFieldView>.unmodifiable(views);
  }

  TabFieldView _viewOf(SaveField<FieldValue> field) {
    final descriptor = field.descriptor;
    return TabFieldView(
      descriptor: descriptor,
      value: field.value,
      isDirty: field.isDirty,
      issueMessage: _issueMessages[descriptor.slot]?[descriptor.id],
    );
  }

  static Map<SaveSlotId, Map<FieldId, String>> _indexIssues(
    List<ValidationIssue> issues,
  ) {
    final bySlot = <SaveSlotId, Map<FieldId, String>>{};
    for (final issue in issues) {
      final field = issue.field;
      if (field == null) {
        continue;
      }
      bySlot
          .putIfAbsent(issue.slot, () => <FieldId, String>{})
          .putIfAbsent(field, () => issue.message);
    }
    return bySlot;
  }
}
