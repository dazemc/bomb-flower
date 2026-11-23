import 'package:material_ui/material_ui.dart';

import '../../domain/core/core.dart';
import '../theme/bomb_flower_colors.dart';
import '../theme/bomb_flower_spacing.dart';
import '../theme/bomb_flower_typography.dart';
import '../widgets/data/provenance_badge.dart';
import '../widgets/data/stone_table.dart';
import 'save_dialog_frame.dart';

/// Shows one slot's open-time original beside its current decoded values.
///
/// Only one slot is compared per dialog because changed byte spans are computed
/// per slot. When [slotLabel] names a slot with changes that slot wins; otherwise
/// the first changed slot is used, so the dialog opens on something to act on.
final class CompareSaveDialog extends StatefulWidget {
  /// Creates the comparison dialog.
  const CompareSaveDialog({super.key, required this.project, this.slotLabel});

  /// The open project to compare against its retained originals.
  final SaveProject project;

  /// Preferred slot, for example `slot_00`; null means no preference.
  final String? slotLabel;

  /// Shows the dialog; Close and Escape both just dismiss it.
  static Future<void> show(
    BuildContext context, {
    required SaveProject project,
    String? slotLabel,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: BombFlowerColors.scrim,
      builder: (dialogContext) =>
          CompareSaveDialog(project: project, slotLabel: slotLabel),
    );
  }

  @override
  State<CompareSaveDialog> createState() => _CompareSaveDialogState();
}

class _CompareSaveDialogState extends State<CompareSaveDialog> {
  /// The compiled change summary, computed once because it reads file bytes.
  late final DirtyState _dirty;

  /// The slot this dialog compares, or null when the project has no documents.
  late final SaveSlotId? _slot;

  /// Coalesced current-vs-original byte runs for [_slot].
  late final List<ByteSpan> _spans;

  /// Changed fields for [_slot], sorted by ascending span offset.
  late final List<_CompareRow> _rows;

  /// Highlighted table row; only read when [_rows] is non-empty.
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    final dirty = project.dirty;
    final spansBySlot = <SaveSlotId, List<ByteSpan>>{
      for (final slot in project.documents.keys)
        slot: project.changedSpans(slot),
    };
    final slot = _resolveSlot(project, spansBySlot, widget.slotLabel);
    _dirty = dirty;
    _slot = slot;
    _spans = slot == null ? const <ByteSpan>[] : spansBySlot[slot]!;
    _rows = slot == null
        ? const <_CompareRow>[]
        : _changedRows(project, dirty, slot);
  }

  /// Picks the slot to compare, preferring [slotLabel] when it has changes.
  SaveSlotId? _resolveSlot(
    SaveProject project,
    Map<SaveSlotId, List<ByteSpan>> spansBySlot,
    String? slotLabel,
  ) {
    final slots = project.documents.keys;

    bool hasChanges(SaveSlotId slot) =>
        (spansBySlot[slot] ?? const <ByteSpan>[]).isNotEmpty;

    if (slotLabel != null) {
      for (final slot in slots) {
        if (slot.value == slotLabel && hasChanges(slot)) {
          return slot;
        }
      }
    }
    for (final slot in slots) {
      if (hasChanges(slot)) {
        return slot;
      }
    }
    if (slotLabel != null) {
      for (final slot in slots) {
        if (slot.value == slotLabel) {
          return slot;
        }
      }
    }
    return slots.isEmpty ? null : slots.first;
  }

  /// [slot]'s changed fields, ordered by their declared span offset.
  List<_CompareRow> _changedRows(
    SaveProject project,
    DirtyState dirty,
    SaveSlotId slot,
  ) {
    final document = project.document(slot);
    if (document == null) {
      return const <_CompareRow>[];
    }
    final rows = <_CompareRow>[
      for (final field in document.fields)
        if (dirty.changedFields.contains(field.descriptor.id) || field.isDirty)
          _CompareRow(field, _levelOf(field.descriptor.confidence)),
    ];
    rows.sort(
      (a, b) => a.field.descriptor.span.offset.compareTo(
        b.field.descriptor.span.offset,
      ),
    );
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final slot = _slot;
    final nothingToShow =
        !_dirty.differsFromOriginal || (_rows.isEmpty && _spans.isEmpty);
    return SaveDialogFrame(
      title: 'Compare original and edited save',
      icon: Icons.compare_arrows,
      maxWidth: 1000,
      subtitle: slot?.value,
      footer: _footer(),
      child: nothingToShow || slot == null ? _emptyBody() : _body(slot),
    );
  }

  /// The honest empty state: no change is claimed and no table is shown.
  Widget _emptyBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BombFlowerSpacing.huge),
      child: Text(
        'No changes yet — this save matches the original.',
        key: const Key('compare-empty'),
        textAlign: TextAlign.center,
        style: BombFlowerTypography.body.copyWith(
          color: BombFlowerColors.inkSecondary,
        ),
      ),
    );
  }

  /// Summary header, changed-field table, detail strip, and byte spans.
  Widget _body(SaveSlotId slot) {
    final project = widget.project;
    final original = project.originals[slot];
    final current = project.document(slot)?.snapshot;
    final byteCount = _spans.fold<int>(0, (total, span) => total + span.length);
    final fieldCount = _rows.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          spacing: BombFlowerSpacing.lg,
          runSpacing: BombFlowerSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              slot.value,
              key: const Key('compare-slot-label'),
              style: BombFlowerTypography.label.copyWith(
                color: BombFlowerColors.ink,
              ),
            ),
            Text(
              '$fieldCount field${fieldCount == 1 ? '' : 's'} changed',
              key: const Key('compare-header-fields'),
              style: BombFlowerTypography.caption.copyWith(
                color: BombFlowerColors.inkSecondary,
              ),
            ),
            Text(
              '$byteCount byte${byteCount == 1 ? '' : 's'} changed',
              key: const Key('compare-header-bytes'),
              style: BombFlowerTypography.caption.copyWith(
                color: BombFlowerColors.inkSecondary,
              ),
            ),
            if (original != null && current != null) ...<Widget>[
              Text(
                'Original ${_hex32(original.fingerprint)}',
                key: const Key('compare-original-fingerprint'),
                style: _monoCaption,
              ),
              Text(
                'Current ${_hex32(current.fingerprint)}',
                key: const Key('compare-current-fingerprint'),
                style: _monoCaption,
              ),
            ],
          ],
        ),
        const SizedBox(height: BombFlowerSpacing.xl),
        StoneTable<_CompareRow>(
          key: const Key('compare-field-table'),
          columns: _columns,
          rows: _rows,
          selectedIndex: _rows.isEmpty ? null : _selected,
          onRowTap: (_, index) => setState(() => _selected = index),
          emptyMessage: 'No decoded fields changed',
        ),
        if (_rows.isNotEmpty) ...<Widget>[
          const SizedBox(height: BombFlowerSpacing.md),
          _detailStrip(),
        ],
        if (_spans.isNotEmpty) ...<Widget>[
          const SizedBox(height: BombFlowerSpacing.xl),
          Text(
            'Changed byte spans',
            style: BombFlowerTypography.label.copyWith(
              color: BombFlowerColors.ink,
            ),
          ),
          const SizedBox(height: BombFlowerSpacing.xs),
          Wrap(
            key: const Key('compare-byte-spans'),
            spacing: BombFlowerSpacing.md,
            runSpacing: BombFlowerSpacing.xs,
            children: <Widget>[
              for (var i = 0; i < _spans.length; i++)
                Text(
                  _spanLabel(_spans[i]),
                  key: Key('compare-span-$i'),
                  style: _monoCaption,
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// The selected field's real provenance chip and byte span.
  Widget _detailStrip() {
    final row = _rows[_selected];
    final field = row.field;
    return Wrap(
      spacing: BombFlowerSpacing.md,
      runSpacing: BombFlowerSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        ProvenanceBadge(
          key: const Key('compare-provenance'),
          level: row.level,
          source: field.descriptor.source,
        ),
        Text(
          _spanLabel(field.descriptor.span),
          key: const Key('compare-field-span'),
          style: _monoCaption,
        ),
      ],
    );
  }

  /// The preservation note plus the single Close action.
  Widget _footer() {
    final note = widget.project.preserveUnknown
        ? 'Unchanged bytes are preserved exactly. The open-time original '
              'stays in memory for this session and is mirrored to the save\'s '
              'original backup when the save is exported.'
        : 'This project was opened without byte preservation, so untouched '
              'bytes are not guaranteed to survive an export.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          note,
          key: const Key('compare-footer-note'),
          style: BombFlowerTypography.caption.copyWith(
            color: BombFlowerColors.inkMuted,
          ),
        ),
        const SizedBox(height: BombFlowerSpacing.md),
        SaveDialogActions(
          children: <Widget>[
            SaveDialogCancelButton(
              key: const Key('compare-close'),
              label: 'Close',
            ),
          ],
        ),
      ],
    );
  }

  static TextStyle get _monoCaption => BombFlowerTypography.mono.copyWith(
    fontSize: 11,
    height: 16 / 11,
    color: BombFlowerColors.inkSecondary,
  );
}

/// One changed field paired with the provenance level its descriptor claims.
final class _CompareRow {
  const _CompareRow(this.field, this.level);

  final SaveField<FieldValue> field;
  final ProvenanceLevel level;
}

/// Column order: identity, original, current, evidence.
final List<StoneTableColumn<_CompareRow>> _columns =
    <StoneTableColumn<_CompareRow>>[
      StoneTableColumn<_CompareRow>(
        label: 'Field',
        flex: 3,
        cell: (row) => row.field.descriptor.label,
      ),
      StoneTableColumn<_CompareRow>(
        label: 'Original',
        flex: 2,
        cell: (row) => _formatValue(row.field.originalValue),
      ),
      StoneTableColumn<_CompareRow>(
        label: 'Current',
        flex: 2,
        cell: (row) => _formatValue(row.field.value),
      ),
      StoneTableColumn<_CompareRow>(
        label: 'Provenance',
        flex: 1,
        cell: (row) => row.level.label,
      ),
    ];

/// Renders a decoded value without inventing meaning it does not carry.
String _formatValue(FieldValue value) {
  return switch (value) {
    IntValue(:final value) => '$value',
    BoolValue(:final value) => value ? 'true' : 'false',
    BitfieldValue(:final bits) => '0x${bits.toRadixString(16)}',
    EnumValue(:final key, :final rawValue) =>
      key.isNotEmpty
          ? key
          : rawValue == null
          ? '—'
          : '0x${rawValue.toRadixString(16)}',
    StringValue(:final value) => value.isEmpty ? '(empty)' : value,
    PositionValue(:final x, :final y, :final z) => '$x, $y, $z',
    VectorValue(:final components) =>
      components.isEmpty ? '—' : components.join(', '),
    ListValue(:final items) => '${items.length} items',
  };
}

/// Maps research confidence onto the badge vocabulary.
ProvenanceLevel _levelOf(FieldConfidence confidence) {
  return switch (confidence) {
    FieldConfidence.verified => ProvenanceLevel.verified,
    FieldConfidence.inferred => ProvenanceLevel.inferred,
    FieldConfidence.unverified => ProvenanceLevel.unknown,
  };
}

/// The eight-digit FNV-1a display form used elsewhere in the shell.
String _hex32(int value) => '0x${value.toRadixString(16).padLeft(8, '0')}';

/// `0x<offset> +<length>` for one byte span.
String _spanLabel(ByteSpan span) =>
    '0x${span.offset.toRadixString(16)} +${span.length}';
