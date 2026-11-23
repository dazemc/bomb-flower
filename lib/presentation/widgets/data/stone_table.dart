import 'package:flutter/services.dart'
    show KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../common/procedural_painters.dart';

/// One typed column in a [StoneTable].
///
/// [cell] returns display text; the table makes no assumptions about the row
/// type. Fixed [width] columns keep identity/flag fields stable while flexible
/// columns share the remaining space.
class StoneTableColumn<T> {
  const StoneTableColumn({
    required this.label,
    required this.cell,
    this.width,
    this.flex = 1,
    this.sortable = false,
    this.textAlign = TextAlign.left,
  }) : assert(width == null || width > 0, 'width must be positive'),
       assert(flex > 0, 'flex must be positive');

  final String label;
  final String Function(T row) cell;
  final double? width;
  final int flex;
  final bool sortable;
  final TextAlign textAlign;
}

/// A parchment table with stone dividers and a brass sort indicator.
///
/// The table reports sort intent through [onSort] and never reorders [rows]
/// itself. It is keyboard reachable as one row-navigation stop: Up/Down move the
/// row highlight, Home/End jump to the ends, and Enter/Space invoke [onRowTap].
/// Sortable headers are separate Tab stops with their own focus ring. Under
/// 900 px available width the content keeps a 900 px minimum and scrolls
/// horizontally rather than crushing cells.
class StoneTable<T> extends StatefulWidget {
  const StoneTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.selectedIndex,
    this.emptyMessage = 'No rows to display',
    this.onSort,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.autofocus = false,
  });

  final List<StoneTableColumn<T>> columns;
  final List<T> rows;
  final void Function(T row, int index)? onRowTap;
  final int? selectedIndex;
  final String emptyMessage;
  final void Function(int columnIndex, bool ascending)? onSort;
  final int? sortColumnIndex;
  final bool sortAscending;
  final bool autofocus;

  static const double minimumContentWidth = 900;

  static Key rowKey(int index) => ValueKey<String>('stone-table-row-$index');
  static Key headerKey(int index) =>
      ValueKey<String>('stone-table-header-$index');
  static const Key horizontalScrollKey = ValueKey<String>(
    'stone-table-horizontal-scroll',
  );

  @override
  State<StoneTable<T>> createState() => _StoneTableState<T>();
}

class _StoneTableState<T> extends State<StoneTable<T>> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'StoneTable');
  int _focusedRow = 0;
  bool _hasFocus = false;
  int? _sortColumn;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _sortColumn = widget.sortColumnIndex;
    _sortAscending = widget.sortAscending;
    _focusedRow = widget.selectedIndex ?? 0;
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(StoneTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sortColumnIndex != oldWidget.sortColumnIndex) {
      _sortColumn = widget.sortColumnIndex;
    }
    if (widget.sortAscending != oldWidget.sortAscending) {
      _sortAscending = widget.sortAscending;
    }
    if (widget.rows.isEmpty) {
      _focusedRow = 0;
    } else if (_focusedRow >= widget.rows.length) {
      _focusedRow = widget.rows.length - 1;
    }
    if (widget.selectedIndex != null &&
        widget.selectedIndex != oldWidget.selectedIndex &&
        !_hasFocus &&
        widget.rows.isNotEmpty) {
      _focusedRow = widget.selectedIndex!
          .clamp(0, widget.rows.length - 1)
          .toInt();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_hasFocus != _focusNode.hasFocus) {
      setState(() => _hasFocus = _focusNode.hasFocus);
    }
  }

  void _sort(int columnIndex) {
    if (widget.onSort == null) return;
    final column = widget.columns[columnIndex];
    if (!column.sortable) return;
    final ascending = _sortColumn == columnIndex ? !_sortAscending : true;
    setState(() {
      _sortColumn = columnIndex;
      _sortAscending = ascending;
    });
    widget.onSort!(columnIndex, ascending);
  }

  void _selectRow(int index) {
    if (index < 0 || index >= widget.rows.length) return;
    _focusNode.requestFocus();
    setState(() => _focusedRow = index);
    widget.onRowTap?.call(widget.rows[index], index);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (widget.rows.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      final next = (_focusedRow + 1).clamp(0, widget.rows.length - 1).toInt();
      if (next != _focusedRow) setState(() => _focusedRow = next);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      final next = (_focusedRow - 1).clamp(0, widget.rows.length - 1).toInt();
      if (next != _focusedRow) setState(() => _focusedRow = next);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      if (_focusedRow != 0) setState(() => _focusedRow = 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      final last = widget.rows.length - 1;
      if (_focusedRow != last) setState(() => _focusedRow = last);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      _selectRow(_focusedRow);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : StoneTable.minimumContentWidth;
        final wide = width >= StoneTable.minimumContentWidth;
        final contentWidth = wide ? width : StoneTable.minimumContentWidth;

        final table = SizedBox(
          width: contentWidth,
          child: _buildTable(palette),
        );
        final body = wide
            ? table
            : SingleChildScrollView(
                key: StoneTable.horizontalScrollKey,
                scrollDirection: Axis.horizontal,
                child: table,
              );

        return Semantics(
          container: true,
          label: 'Table, ${widget.rows.length} rows',
          child: Focus(
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            onKeyEvent: _handleKey,
            child: body,
          ),
        );
      },
    );
  }

  Widget _buildTable(BombFlowerTheme palette) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeader(palette),
        Divider(height: 1, color: palette.border),
        if (widget.rows.isEmpty)
          _EmptyBody(message: widget.emptyMessage, palette: palette)
        else
          for (var index = 0; index < widget.rows.length; index++)
            _buildRow(index, palette),
      ],
    );
  }

  Widget _buildHeader(BombFlowerTheme palette) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: BombFlowerSpacing.tableHeaderHeight,
      ),
      color: palette.surfaceSunken,
      padding: const EdgeInsets.symmetric(
        horizontal: BombFlowerSpacing.md,
        vertical: BombFlowerSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const SizedBox(width: 20),
          for (var index = 0; index < widget.columns.length; index++)
            _buildHeaderCell(index, palette),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(int index, BombFlowerTheme palette) {
    final column = widget.columns[index];
    final canSort = column.sortable && widget.onSort != null;
    final ascending = _sortColumn == index ? _sortAscending : null;
    final sortLabel = ascending == null
        ? null
        : ascending
        ? 'sorted ascending'
        : 'sorted descending';
    final label = sortLabel == null
        ? column.label
        : '${column.label}, $sortLabel';

    final child = canSort
        ? _SortHeader(
            key: StoneTable.headerKey(index),
            label: column.label,
            semanticsLabel: label,
            ascending: ascending,
            onTap: () => _sort(index),
          )
        : Padding(
            key: StoneTable.headerKey(index),
            padding: const EdgeInsets.symmetric(
              horizontal: BombFlowerSpacing.sm,
            ),
            child: Text(
              column.label,
              textAlign: column.textAlign,
              style: BombFlowerTypography.tableHeader.copyWith(
                color: palette.textMuted,
              ),
            ),
          );

    if (column.width != null) {
      return SizedBox(width: column.width, child: child);
    }
    return Expanded(flex: column.flex, child: child);
  }

  Widget _buildRow(int index, BombFlowerTheme palette) {
    final row = widget.rows[index];
    final selected = widget.selectedIndex == index;
    final focused = _hasFocus && _focusedRow == index;
    final rowLabel = widget.columns
        .map((column) => '${column.label}: ${column.cell(row)}')
        .join('. ');
    final semanticsLabel = selected ? '$rowLabel. Selected.' : rowLabel;

    return Semantics(
      container: true,
      button: widget.onRowTap != null,
      selected: selected,
      label: semanticsLabel,
      onTap: widget.onRowTap == null ? null : () => _selectRow(index),
      excludeSemantics: true,
      child: MouseRegion(
        cursor: widget.onRowTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onRowTap == null ? null : () => _selectRow(index),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                key: StoneTable.rowKey(index),
                constraints: const BoxConstraints(
                  minHeight: BombFlowerSpacing.tableRowHeight,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: BombFlowerSpacing.md,
                  vertical: BombFlowerSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: selected ? palette.selection : Colors.transparent,
                  border: Border(bottom: BorderSide(color: palette.border)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 20,
                      child: selected
                          ? Icon(
                              Icons.check,
                              size: 14,
                              color: palette.accentInk,
                            )
                          : null,
                    ),
                    for (
                      var columnIndex = 0;
                      columnIndex < widget.columns.length;
                      columnIndex++
                    )
                      _buildCell(row, widget.columns[columnIndex], palette),
                  ],
                ),
              ),
              if (focused)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: FocusRingPainter(
                        color: palette.focusOnLight,
                        radius: BombFlowerRadii.sm,
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

  Widget _buildCell(
    T row,
    StoneTableColumn<T> column,
    BombFlowerTheme palette,
  ) {
    final text = Text(
      column.cell(row),
      textAlign: column.textAlign,
      style: BombFlowerTypography.table.copyWith(color: palette.textPrimary),
    );
    if (column.width != null) {
      return SizedBox(width: column.width, child: text);
    }
    return Expanded(flex: column.flex, child: text);
  }
}

class _SortHeader extends StatefulWidget {
  const _SortHeader({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.ascending,
    required this.onTap,
  });

  final String label;
  final String semanticsLabel;
  final bool? ascending;
  final VoidCallback onTap;

  @override
  State<_SortHeader> createState() => _SortHeaderState();
}

class _SortHeaderState extends State<_SortHeader> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final active = widget.ascending != null;
    final icon = widget.ascending == null
        ? Icons.unfold_more
        : widget.ascending!
        ? Icons.arrow_upward
        : Icons.arrow_downward;
    final color = active ? palette.accentInk : palette.textMuted;

    return Semantics(
      container: true,
      button: true,
      label: widget.semanticsLabel,
      hint: 'Sort by ${widget.label}',
      onTap: widget.onTap,
      focusable: true,
      focused: _focused,
      excludeSemantics: true,
      child: FocusableActionDetector(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        onShowHoverHighlight: (value) {
          if (_hovered != value) setState(() => _hovered = value);
        },
        onShowFocusHighlight: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Container(
                  constraints: const BoxConstraints(
                    minHeight: BombFlowerSpacing.minHitTarget,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: BombFlowerSpacing.sm,
                    vertical: BombFlowerSpacing.xxs,
                  ),
                  color: _hovered
                      ? BombFlowerColors.hoverPaper
                      : Colors.transparent,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          widget.label,
                          style: BombFlowerTypography.tableHeader.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: BombFlowerSpacing.xs),
                      Icon(icon, size: 12, color: color),
                    ],
                  ),
                ),
                if (_focused)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: FocusRingPainter(
                          color: palette.focusOnLight,
                          radius: BombFlowerRadii.xs,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.message, required this.palette});

  final String message;
  final BombFlowerTheme palette;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 96),
      child: Center(
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
      ),
    );
  }
}
