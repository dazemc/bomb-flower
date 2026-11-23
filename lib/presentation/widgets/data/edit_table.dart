import 'package:flutter/services.dart'
    show
        KeyDownEvent,
        KeyRepeatEvent,
        LogicalKeyboardKey,
        TextEditingValue,
        TextInputFormatter;
import 'package:material_ui/material_ui.dart';

import '../../../domain/core/field_metadata.dart';
import '../../../domain/core/field_value.dart';
import '../../../domain/fields/field_groups.dart';
import '../../tabs_support/field_editor.dart';
import '../../tabs_support/save_tab_source.dart';
import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../common/rune_chip.dart';
import '../controls/brass_toggle.dart';
import '../controls/numeric_field.dart';
import '../selectors/searchable_select.dart';
import 'provenance_badge.dart';

/// How one row's value is edited.
enum EditCellKind { integer, boolean, enumeration, string }

/// Immutable, already-resolved description of one table row.
///
/// Every display string in a row is resolved by the caller or by
/// [buildEditTableRows]; the table itself never reads bytes, never consults a
/// save source, and never decides whether a field may be edited.
final class EditTableRow {
  const EditTableRow({
    required this.id,
    required this.label,
    required this.typeLabel,
    required this.valueLabel,
    required this.level,
    required this.source,
    required this.isModified,
    this.kind,
    this.readOnlyReason,
    this.min,
    this.max,
    this.choices = const <String>[],
    this.textCap,
    this.issueMessage,
    this.intValue,
    this.boolValue,
    this.enumKey,
    this.textValue,
  });

  /// Stable id, unique per table (for example a `FieldId.value`).
  final String id;

  /// Verified field name, shown and searched.
  final String label;

  /// Schema wire type text, for example `Bool`, `Int`, or `Enum`.
  final String typeLabel;

  /// Current decoded value as display text. Never empty.
  final String valueLabel;

  /// Evidence level for the label and the value.
  final ProvenanceLevel level;

  /// Citation shown in the badge tooltip.
  final String source;

  /// True when the value differs from what was last saved.
  final bool isModified;

  /// Editor for this row, or `null` when no editor exists at all.
  final EditCellKind? kind;

  /// Non-null when the row is read-only; rendered as visible text.
  final String? readOnlyReason;

  /// Inclusive lower bound from the schema; `null` means unknown.
  final num? min;

  /// Inclusive upper bound from the schema; `null` means unknown.
  final num? max;

  /// Enumeration keys, in schema order.
  final List<String> choices;

  /// Maximum characters for a fixed-byte string cell.
  final int? textCap;

  /// Engine validation text, shown inline.
  final String? issueMessage;

  /// Stored integer for an integer row, exactly as `IntValue.value`.
  final int? intValue;

  /// Stored boolean for a boolean row, exactly as `BoolValue.value`.
  final bool? boolValue;

  /// Stored enumeration key for an enumeration row, exactly as
  /// `EnumValue.key`; may be empty when the raw value has no key.
  final String? enumKey;

  /// Stored text for a string row, exactly as `StringValue.value`.
  final String? textValue;

  /// True when an editor is available and the row is not read-only.
  bool get isEditable => readOnlyReason == null && kind != null;
}

/// Fallback display text for a value that has no printable form.
const String editTableEmptyValue = '—';

/// Reason shown for a field whose span cannot be edited without resizing.
const String editTableFixedWidthReason =
    'Fixed-width rule: this span cannot be rewritten without resizing';

/// Reason shown for vector, position, bitfield, and list cells.
const String editTableOpaqueKindReason =
    'Vector and list cells have no length-preserving cell editor';

/// Reason shown when the save does not store a catalogue field.
const String editTableNotStoredReason = 'Not stored in this save';

/// Builds rows for one tab: every catalogue field becomes a row, resolved
/// against the save's views by label.
///
/// Missing and unverified fields stay visible and read-only with a stated
/// reason; a catalogue field is never dropped. Duplicate catalogue names collapse
/// to one row (the first wins). A found descriptor supplies the id, the bounds,
/// the choices, the citation, and the kind; the catalogue supplies the wire type
/// and the name order.
List<EditTableRow> buildEditTableRows({
  required Iterable<FieldRef> catalogueFields,
  required Iterable<TabFieldView> views,
}) {
  final viewsByLabel = <String, TabFieldView>{};
  for (final view in views) {
    viewsByLabel.putIfAbsent(view.descriptor.label, () => view);
  }

  final seenNames = <String>{};
  final rows = <EditTableRow>[];
  for (final field in catalogueFields) {
    if (!seenNames.add(field.name)) {
      continue;
    }
    final view = viewsByLabel[field.name];
    rows.add(
      view == null ? _missingRow(field) : _resolvedRow(field, view),
    );
  }
  return rows;
}

EditTableRow _missingRow(FieldRef field) {
  return EditTableRow(
    id: 'catalogue:${field.hashHex}',
    label: field.name,
    typeLabel: field.type,
    valueLabel: editTableEmptyValue,
    level: _levelForProvenance(field.provenance),
    source: 'Catalogue field ${field.name} is not present in this save '
        '(hash ${field.hashHex})',
    isModified: false,
    readOnlyReason: editTableNotStoredReason,
  );
}

EditTableRow _resolvedRow(FieldRef field, TabFieldView view) {
  final descriptor = view.descriptor;
  final value = view.value;
  final formatted = formatFieldValue(value);
  final valueLabel = formatted.isEmpty ? editTableEmptyValue : formatted;

  // Typed seeds come only from the decoded value; a display label is never
  // parsed back into a value.
  final intValue = switch (value) {
    IntValue(:final value) => value,
    _ => null,
  };
  final boolValue = switch (value) {
    BoolValue(:final value) => value,
    _ => null,
  };
  final enumKey = switch (value) {
    EnumValue(:final key) => key,
    _ => null,
  };
  final textValue = switch (value) {
    StringValue(:final value) => value,
    _ => null,
  };

  EditCellKind? kind;
  String? reason;
  if (descriptor.confidence == FieldConfidence.inferred) {
    reason =
        'Field name is prefix-derived (inferred), so the meaning is not '
        'verified';
  } else if (descriptor.confidence == FieldConfidence.unverified) {
    reason = 'Field has no verified name';
  } else if (descriptor.readOnly) {
    reason = editTableFixedWidthReason;
  } else if (value == null) {
    reason = 'No decoded value';
  } else {
    final candidate = _kindFor(descriptor.kind);
    if (candidate == null) {
      reason = editTableOpaqueKindReason;
    } else if (!_hasTypedValue(candidate, intValue, boolValue, enumKey,
        textValue)) {
      reason = 'No decoded value';
    } else {
      kind = candidate;
    }
  }

  final editable = kind != null;
  return EditTableRow(
    id: descriptor.id.value,
    label: field.name,
    typeLabel: field.type,
    valueLabel: valueLabel,
    level: _levelFor(field.provenance, descriptor.confidence),
    source: descriptor.source,
    isModified: view.isDirty,
    kind: kind,
    readOnlyReason: reason,
    min: editable ? descriptor.min : null,
    max: editable ? descriptor.max : null,
    choices: kind == EditCellKind.enumeration
        ? List<String>.unmodifiable(descriptor.choices.keys)
        : const <String>[],
    textCap: kind == EditCellKind.string ? descriptor.span.length - 1 : null,
    issueMessage: view.issueMessage,
    intValue: kind == EditCellKind.integer ? intValue : null,
    boolValue: kind == EditCellKind.boolean ? boolValue : null,
    enumKey: kind == EditCellKind.enumeration ? enumKey : null,
    textValue: kind == EditCellKind.string ? textValue : null,
  );
}

/// Whether [value] carries the typed field [kind] needs to seed its editor.
bool _hasTypedValue(
  EditCellKind kind,
  int? intValue,
  bool? boolValue,
  String? enumKey,
  String? textValue,
) {
  return switch (kind) {
    EditCellKind.integer => intValue != null,
    EditCellKind.boolean => boolValue != null,
    EditCellKind.enumeration => enumKey != null,
    EditCellKind.string => textValue != null,
  };
}

EditCellKind? _kindFor(FieldKind kind) {
  return switch (kind) {
    FieldKind.integer => EditCellKind.integer,
    FieldKind.boolean => EditCellKind.boolean,
    FieldKind.enumeration => EditCellKind.enumeration,
    FieldKind.string => EditCellKind.string,
    FieldKind.bitfield ||
    FieldKind.list ||
    FieldKind.vector ||
    FieldKind.position => null,
  };
}

ProvenanceLevel _levelFor(
  FieldProvenance provenance,
  FieldConfidence confidence,
) {
  if (confidence == FieldConfidence.unverified) {
    return ProvenanceLevel.unknown;
  }
  if (confidence == FieldConfidence.inferred ||
      provenance == FieldProvenance.inferred) {
    return ProvenanceLevel.inferred;
  }
  return provenance == FieldProvenance.observed
      ? ProvenanceLevel.observed
      : ProvenanceLevel.verified;
}

ProvenanceLevel _levelForProvenance(FieldProvenance provenance) {
  return switch (provenance) {
    FieldProvenance.verified => ProvenanceLevel.verified,
    FieldProvenance.observed => ProvenanceLevel.observed,
    FieldProvenance.inferred => ProvenanceLevel.inferred,
  };
}

/// One searchable, virtualised, editable table over already-resolved rows.
///
/// The widget is presentation only: it renders [rows], reports commit intent
/// through the four typed callbacks, and owns no save model. It is one keyboard
/// stop: Up/Down move a row cursor, Home/End jump, and Enter focuses the cursor
/// row's cell editor. Rows live in a [ListView.builder] with a fixed
/// [itemExtent], so only visible rows are built.
///
/// The table owns a bounded height so it can sit inside a tab's unbounded
/// vertical scroll frame without a "Vertical viewport was given unbounded
/// height" error.
class EditTable extends StatefulWidget {
  const EditTable({
    super.key,
    required this.rows,
    required this.onInteger,
    required this.onBoolean,
    required this.onEnumeration,
    required this.onText,
    this.height = 520,
    this.searchHint = 'Search fields by name',
    this.emptyMessage = 'No fields to display',
    this.errorMessage,
  });

  /// Rows to render, already resolved in display order.
  final List<EditTableRow> rows;

  /// Receives a committed integer edit.
  final void Function(String id, int value) onInteger;

  /// Receives a committed boolean edit.
  final void Function(String id, bool value) onBoolean;

  /// Receives a committed enumeration edit.
  final void Function(String id, String key) onEnumeration;

  /// Receives a committed string edit.
  final void Function(String id, String text) onText;

  /// Bounded height of the row viewport.
  final double height;

  /// Hint for the name search box.
  final String searchHint;

  /// Shown when no row survives the search and filters.
  final String emptyMessage;

  /// Non-null renders an explicit error state instead of rows.
  final String? errorMessage;

  /// Fixed row extent, used as the list's `itemExtent`.
  ///
  /// This is the control height, not [BombFlowerSpacing.tableRowHeight]: a row
  /// must hold a 36 px editor plus that editor's inline error text, so 64 px
  /// replaces the 36 px text-row token.
  static const double rowExtent = 64;

  static Key rowKey(String id) => ValueKey<String>('edit-table-row-$id');

  static const Key searchFieldKey = ValueKey<String>('edit-table-search');

  static const Key editableOnlyKey = ValueKey<String>(
    'edit-table-editable-only',
  );

  static const Key changedOnlyKey = ValueKey<String>(
    'edit-table-changed-only',
  );

  static const Key countKey = ValueKey<String>('edit-table-count');

  static const Key listKey = ValueKey<String>('edit-table-list');

  static const Key errorKey = ValueKey<String>('edit-table-error');

  @override
  State<EditTable> createState() => _EditTableState();
}

class _EditTableState extends State<EditTable> {
  static const double _typeWidth = 84;
  static const double _sourceWidth = 150;
  static const double _gap = BombFlowerSpacing.md;

  final TextEditingController _search = TextEditingController();
  final FocusNode _tableFocus = FocusNode(debugLabel: 'EditTable');
  final ScrollController _scroll = ScrollController();
  final Map<String, FocusScopeNode> _cellScopes = <String, FocusScopeNode>{};

  bool _editableOnly = false;
  bool _changedOnly = false;
  bool _hasFocus = false;
  int _cursor = 0;
  String? _hoveredId;

  @override
  void initState() {
    super.initState();
    _tableFocus.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(EditTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _cursor = _cursorFor(_visibleRows.length);
  }

  @override
  void dispose() {
    _tableFocus.removeListener(_handleFocusChange);
    _tableFocus.dispose();
    _search.dispose();
    _scroll.dispose();
    for (final scope in _cellScopes.values) {
      scope.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    if (_hasFocus != _tableFocus.hasFocus) {
      setState(() => _hasFocus = _tableFocus.hasFocus);
    }
  }

  List<EditTableRow> get _visibleRows {
    final needle = _search.text.trim().toLowerCase();
    return <EditTableRow>[
      for (final row in widget.rows)
        if ((!_editableOnly || row.isEditable) &&
            (!_changedOnly || row.isModified) &&
            (needle.isEmpty ||
                row.label.toLowerCase().contains(needle) ||
                row.typeLabel.toLowerCase().contains(needle)))
          row,
    ];
  }

  int get _editableCount => widget.rows.where((row) => row.isEditable).length;

  int _cursorFor(int length) =>
      length == 0 ? 0 : _cursor.clamp(0, length - 1).toInt();

  void _resetFilters() {
    setState(() {
      _cursor = 0;
    });
    _scrollToTop();
  }

  void _setEditableOnly(bool value) {
    setState(() {
      _editableOnly = value;
      _cursor = 0;
    });
    _scrollToTop();
  }

  void _setChangedOnly(bool value) {
    setState(() {
      _changedOnly = value;
      _cursor = 0;
    });
    _scrollToTop();
  }

  void _scrollToTop() {
    if (_scroll.hasClients && _scroll.offset != 0) {
      _scroll.jumpTo(0);
    }
  }

  void _selectRow(int index, List<EditTableRow> rows) {
    if (index < 0 || index >= rows.length) return;
    _tableFocus.requestFocus();
    if (_cursor != index) {
      setState(() => _cursor = index);
    }
  }

  FocusScopeNode _cellScope(String id) {
    return _cellScopes.putIfAbsent(
      id,
      () => FocusScopeNode(
        debugLabel: 'EditTable.cell.$id',
        skipTraversal: true,
        traversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
      ),
    );
  }

  /// Focuses the first focusable control inside the cursor row's cell.
  void _focusCursorEditor(List<EditTableRow> rows) {
    if (rows.isEmpty) return;
    final row = rows[_cursorFor(rows.length)];
    if (!row.isEditable) return;
    final scope = _cellScope(row.id);
    final target = ReadingOrderTraversalPolicy().findFirstFocus(scope);
    target?.requestFocus();
  }

  void _revealCursor(int index) {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    final top = index * EditTable.rowExtent;
    final bottom = top + EditTable.rowExtent;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;
    double? target;
    if (top < viewTop) {
      target = top;
    } else if (bottom > viewBottom) {
      target = bottom - position.viewportDimension;
    }
    if (target == null) return;
    final clamped = target.clamp(0.0, position.maxScrollExtent).toDouble();
    if (clamped != position.pixels) {
      _scroll.jumpTo(clamped);
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rows = _visibleRows;
    if (rows.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final cursor = _cursorFor(rows.length);

    if (key == LogicalKeyboardKey.arrowDown) {
      _moveCursor(cursor + 1, rows.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveCursor(cursor - 1, rows.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _moveCursor(0, rows.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _moveCursor(rows.length - 1, rows.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _focusCursorEditor(rows);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveCursor(int index, int length) {
    final next = index.clamp(0, length - 1).toInt();
    if (next != _cursor) {
      setState(() => _cursor = next);
    }
    _revealCursor(next);
  }

  void _setHovered(String? id) {
    if (_hoveredId == id) return;
    setState(() => _hoveredId = id);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final rows = _visibleRows;
    final cursorIndex = _cursorFor(rows.length);
    final error = widget.errorMessage;

    return Focus(
      focusNode: _tableFocus,
      onKeyEvent: _handleKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildToolbar(palette),
          const SizedBox(height: BombFlowerSpacing.xs),
          Text(
            'Showing ${rows.length} of ${widget.rows.length} fields · '
            '$_editableCount editable',
            key: EditTable.countKey,
            style: BombFlowerTypography.caption.copyWith(
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: BombFlowerSpacing.sm),
          if (error != null)
            _ErrorBanner(message: error, palette: palette)
          else ...<Widget>[
            _buildHeader(palette),
            Divider(height: 1, color: palette.border),
            if (rows.isEmpty)
              SizedBox(
                height: widget.height,
                child: _EmptyBody(
                  message: widget.emptyMessage,
                  palette: palette,
                ),
              )
            else
              SizedBox(
                height: widget.height,
                child: ListView.builder(
                  key: EditTable.listKey,
                  controller: _scroll,
                  itemExtent: EditTable.rowExtent,
                  itemCount: rows.length,
                  padding: EdgeInsets.zero,
                  itemBuilder: (BuildContext context, int index) {
                    return _buildRow(
                      rows[index],
                      index,
                      cursorIndex,
                      palette,
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbar(BombFlowerTheme palette) {
    return Wrap(
      spacing: BombFlowerSpacing.lg,
      runSpacing: BombFlowerSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 320,
          child: TextField(
            key: EditTable.searchFieldKey,
            controller: _search,
            maxLines: 1,
            style: BombFlowerTypography.body.copyWith(
              color: palette.textPrimary,
            ),
            textInputAction: TextInputAction.search,
            onChanged: (_) => _resetFilters(),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.searchHint,
              hintStyle: BombFlowerTypography.body.copyWith(
                color: palette.textMuted,
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 17,
                color: palette.textMuted,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
          ),
        ),
        BrassToggle(
          key: EditTable.editableOnlyKey,
          value: _editableOnly,
          label: 'Editable only',
          onChanged: _setEditableOnly,
        ),
        BrassToggle(
          key: EditTable.changedOnlyKey,
          value: _changedOnly,
          label: 'Changed only',
          onChanged: _setChangedOnly,
        ),
      ],
    );
  }

  Widget _buildHeader(BombFlowerTheme palette) {
    final style = BombFlowerTypography.tableHeader.copyWith(
      color: palette.textMuted,
    );
    return Container(
      height: BombFlowerSpacing.tableHeaderHeight,
      color: palette.surfaceSunken,
      padding: const EdgeInsets.symmetric(
        horizontal: BombFlowerSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text('Field', style: style)),
          const SizedBox(width: _gap),
          SizedBox(width: _typeWidth, child: Text('Type', style: style)),
          const SizedBox(width: _gap),
          Expanded(child: Text('Value', style: style)),
          const SizedBox(width: _gap),
          SizedBox(width: _sourceWidth, child: Text('Source', style: style)),
        ],
      ),
    );
  }

  Widget _buildRow(
    EditTableRow row,
    int index,
    int cursorIndex,
    BombFlowerTheme palette,
  ) {
    final cursor = _hasFocus && index == cursorIndex;
    final hovered = _hoveredId == row.id;

    return MouseRegion(
      onEnter: (_) => _setHovered(row.id),
      onExit: (_) {
        if (_hoveredId == row.id) _setHovered(null);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectRow(index, _visibleRows),
        child: Container(
          key: EditTable.rowKey(row.id),
          height: EditTable.rowExtent,
          padding: const EdgeInsets.symmetric(
            horizontal: BombFlowerSpacing.md,
            vertical: BombFlowerSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: cursor
                ? palette.selection
                : hovered
                ? BombFlowerColors.hoverPaper
                : Colors.transparent,
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: _fieldCell(row, palette),
              ),
              const SizedBox(width: _gap),
              SizedBox(
                width: _typeWidth,
                child: Text(
                  row.typeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BombFlowerTypography.table.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                flex: 3,
                child: _valueCell(row, palette),
              ),
              const SizedBox(width: _gap),
              SizedBox(
                width: _sourceWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: ProvenanceBadge(
                      level: row.level,
                      source: row.source,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldCell(EditTableRow row, BombFlowerTheme palette) {
    final reason = row.readOnlyReason;
    final issue = row.issueMessage;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                row.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BombFlowerTypography.table.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (row.isModified) ...<Widget>[
              const SizedBox(width: BombFlowerSpacing.xs),
              const RuneChip(
                variant: RuneChipVariant.modified,
                label: 'Modified',
                compact: true,
              ),
            ],
          ],
        ),
        if (issue != null)
          Text(
            issue,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BombFlowerTypography.caption.copyWith(
              color: palette.danger,
            ),
          ),
        if (reason != null)
          Text(
            reason,
            maxLines: issue == null ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: BombFlowerTypography.caption.copyWith(
              color: palette.textMuted,
            ),
          ),
      ],
    );
  }

  Widget _valueCell(EditTableRow row, BombFlowerTheme palette) {
    if (!row.isEditable) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          row.valueLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: BombFlowerTypography.table.copyWith(
            color: palette.textMuted,
          ),
        ),
      );
    }

    final cellKey = ValueKey<String>('edit-table-cell-${row.id}');
    final kind = row.kind!;
    final Widget editor;

    if (kind == EditCellKind.integer) {
      editor = NumericField(
        key: cellKey,
        // Seeded from the decoded value, never from the display label.
        value: row.intValue!,
        min: row.min,
        max: row.max,
        allowNegative: (row.min ?? 0) < 0,
        validator: _wholeNumberValidator,
        onChanged: (num next) {
          if (!next.isFinite) return;
          final whole = next is int
              ? next
              : next == next.roundToDouble()
              ? next.round()
              : null;
          if (whole == null) return;
          if (row.min != null && whole < row.min!) return;
          if (row.max != null && whole > row.max!) return;
          widget.onInteger(row.id, whole);
        },
      );
    } else if (kind == EditCellKind.boolean) {
      editor = Align(
        alignment: Alignment.centerLeft,
        child: BrassToggle(
          key: cellKey,
          value: row.boolValue!,
          onChanged: (bool next) => widget.onBoolean(row.id, next),
        ),
      );
    } else if (kind == EditCellKind.enumeration) {
      final key = row.enumKey;
      final known = key != null && row.choices.contains(key);
      final select = SearchableSelect<String>(
        key: cellKey,
        items: row.choices,
        itemLabel: (String choice) => choice,
        // An empty or unknown key is never replaced by a fabricated choice.
        value: known ? key : null,
        onChanged: (String choice) => widget.onEnumeration(row.id, choice),
      );
      editor = known
          ? select
          : Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                select,
                Text(
                  row.valueLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BombFlowerTypography.caption.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ],
            );
    } else {
      editor = _TextCell(
        key: cellKey,
        initialText: row.textValue!,
        cap: row.textCap,
        onCommit: (String text) => widget.onText(row.id, text),
      );
    }

    // A per-cell scope lets Enter focus this row's editor without owning the
    // control's internal focus node. It is skipped by Tab traversal, so the
    // table's own node remains the table stop.
    return FocusScope(node: _cellScope(row.id), child: editor);
  }

  static String? _wholeNumberValidator(num? value) {
    if (value == null) {
      return 'Enter a whole number.';
    }
    if (value is! int && value != value.roundToDouble()) {
      return 'Enter a whole number.';
    }
    return null;
  }

}

class _TextCell extends StatefulWidget {
  const _TextCell({
    super.key,
    required this.initialText,
    required this.cap,
    required this.onCommit,
  });

  final String initialText;
  final int? cap;
  final ValueChanged<String> onCommit;

  @override
  State<_TextCell> createState() => _TextCellState();
}

class _TextCellState extends State<_TextCell> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late String _lastCommitted;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lastCommitted = widget.initialText;
    _controller = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode(debugLabel: 'EditTable.string');
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(_TextCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialText != widget.initialText) {
      _lastCommitted = widget.initialText;
      if (!_focusNode.hasFocus) {
        _controller.value = TextEditingValue(
          text: widget.initialText,
          selection: TextSelection.collapsed(
            offset: widget.initialText.length,
          ),
        );
        _error = null;
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus && mounted) {
      _commit();
    }
  }

  void _commit() {
    final text = _controller.text;
    final cap = widget.cap;
    final String? error;
    if (cap != null && text.length > cap) {
      error = 'Text must be at most $cap characters.';
    } else if (text.codeUnits.any((int unit) => unit < 0x20 || unit > 0x7e)) {
      error = 'Use printable ASCII characters only.';
    } else {
      error = null;
    }

    if (error != null) {
      if (error != _error) {
        setState(() => _error = error);
      }
      return;
    }

    if (_error != null) {
      setState(() => _error = null);
    }
    if (text == _lastCommitted) return;
    _lastCommitted = text;
    widget.onCommit(text);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          inputFormatters: <TextInputFormatter>[
            _PrintableAsciiFormatter(widget.cap),
          ],
          style: BombFlowerTypography.mono.copyWith(
            color: palette.textPrimary,
          ),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _focusNode.unfocus(),
          decoration: const InputDecoration(isDense: true),
        ),
        if (_error != null)
          Text(
            _error!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BombFlowerTypography.caption.copyWith(
              color: palette.danger,
            ),
          ),
      ],
    );
  }
}

class _PrintableAsciiFormatter extends TextInputFormatter {
  _PrintableAsciiFormatter(this.cap);

  final int? cap;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cap = this.cap;
    if (cap != null && newValue.text.length > cap) {
      return oldValue;
    }
    final printable = newValue.text.codeUnits.every(
      (int unit) => unit >= 0x20 && unit <= 0x7e,
    );
    return printable ? newValue : oldValue;
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.message, required this.palette});

  final String message;
  final BombFlowerTheme palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(BombFlowerSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.inbox_outlined, size: 24, color: palette.textMuted),
            const SizedBox(height: BombFlowerSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: BombFlowerTypography.body.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.palette});

  final String message;
  final BombFlowerTheme palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: EditTable.errorKey,
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(BombFlowerSpacing.lg),
      decoration: BoxDecoration(
        color: BombFlowerColors.dangerSurface,
        borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
        border: Border.all(color: palette.danger),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: palette.danger),
          const SizedBox(width: BombFlowerSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: BombFlowerTypography.body.copyWith(
                color: BombFlowerColors.dangerInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
