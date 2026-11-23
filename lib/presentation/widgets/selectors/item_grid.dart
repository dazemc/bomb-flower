import 'dart:math' as math;

import 'package:flutter/services.dart'
    show KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../common/procedural_painters.dart';

/// A six-by-four inventory-style grid with 72 px parchment slots.
///
/// The whole grid is one Tab stop. Arrow keys move a roving slot highlight and
/// select filled slots, Home/End jump to the edges, and Enter/Space select the
/// highlighted slot. Every slot has its own semantic button with the item name
/// and status, plus a pointer tooltip. Modified and invalid states carry
/// distinct corner glyphs, never colour alone.
class ItemGrid<T> extends StatefulWidget {
  const ItemGrid({
    super.key,
    required this.items,
    this.selectedIndex,
    this.onSelected,
    this.columns = BombFlowerSpacing.inventoryColumns,
    this.rows = BombFlowerSpacing.inventoryRows,
    this.slotBuilder,
    this.itemLabel,
    this.modifiedSlots = const <int>{},
    this.invalidSlots = const <int>{},
    this.emptySlotLabel = 'Empty slot',
    this.autofocus = false,
  }) : assert(columns > 0, 'columns must be positive'),
       assert(rows > 0, 'rows must be positive');

  final List<T> items;
  final int? selectedIndex;
  final ValueChanged<int>? onSelected;
  final int columns;
  final int rows;
  final Widget Function(BuildContext context, T item, int index)? slotBuilder;
  final String Function(T item)? itemLabel;
  final Set<int> modifiedSlots;
  final Set<int> invalidSlots;
  final String emptySlotLabel;
  final bool autofocus;

  static Key slotKey(int index) => ValueKey<String>('item-grid-slot-$index');

  static const Key gridKey = ValueKey<String>('item-grid');

  @override
  State<ItemGrid<T>> createState() => _ItemGridState<T>();
}

class _ItemGridState<T> extends State<ItemGrid<T>> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'ItemGrid');
  int _focusedIndex = 0;
  int? _hoveredIndex;
  bool _hasFocus = false;

  int get _slotCount =>
      math.max(widget.rows * widget.columns, widget.items.length);

  int get _effectiveRows => (_slotCount / widget.columns).ceil();

  @override
  void initState() {
    super.initState();
    _focusedIndex = widget.selectedIndex ?? 0;
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(ItemGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_slotCount == 0) {
      _focusedIndex = 0;
    } else if (_focusedIndex >= _slotCount) {
      _focusedIndex = _slotCount - 1;
    }
    if (widget.selectedIndex != oldWidget.selectedIndex &&
        widget.selectedIndex != null &&
        !_hasFocus) {
      _focusedIndex = widget.selectedIndex!.clamp(0, _slotCount - 1).toInt();
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

  void _select(int index) {
    if (index < 0 || index >= widget.items.length) return;
    _focusNode.requestFocus();
    setState(() => _focusedIndex = index);
    widget.onSelected?.call(index);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final column = _focusedIndex % widget.columns;
    final row = _focusedIndex ~/ widget.columns;
    int? next;

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (column > 0) next = _focusedIndex - 1;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (column < widget.columns - 1 && _focusedIndex + 1 < _slotCount) {
        next = _focusedIndex + 1;
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (row > 0) next = _focusedIndex - widget.columns;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (row + 1 < _effectiveRows) {
        next = _focusedIndex + widget.columns;
      }
    } else if (key == LogicalKeyboardKey.home) {
      next = row * widget.columns;
    } else if (key == LogicalKeyboardKey.end) {
      next = math.min((row + 1) * widget.columns - 1, _slotCount - 1);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      _select(_focusedIndex);
      return KeyEventResult.handled;
    }

    if (next == null || next == _focusedIndex) return KeyEventResult.handled;
    setState(() => _focusedIndex = next!);
    if (next < widget.items.length) {
      widget.onSelected?.call(next);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = BombFlowerSpacing.itemSlotGap;
        final available = constraints.maxWidth - gap * (widget.columns - 1);
        final natural = available / widget.columns;
        final slotSize = natural
            .clamp(1.0, BombFlowerSpacing.itemSlotSize)
            .toDouble();

        return Semantics(
          container: true,
          label:
              'Item grid, ${widget.items.length} of $_slotCount slots filled',
          child: Focus(
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            onKeyEvent: _handleKey,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: slotSize * widget.columns + gap * (widget.columns - 1),
                child: GridView.builder(
                  key: ItemGrid.gridKey,
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  primary: false,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: widget.columns,
                    crossAxisSpacing: gap,
                    mainAxisSpacing: gap,
                    mainAxisExtent: slotSize,
                  ),
                  itemCount: _slotCount,
                  itemBuilder: (context, index) {
                    return _buildSlot(context, index, slotSize);
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSlot(BuildContext context, int index, double slotSize) {
    final palette = context.bombFlowerTheme;
    final item = index < widget.items.length ? widget.items[index] : null;
    final label = item == null
        ? widget.emptySlotLabel
        : widget.itemLabel?.call(item) ?? item.toString();
    final selected = widget.selectedIndex == index;
    final focused = _hasFocus && _focusedIndex == index;
    final hovered = _hoveredIndex == index;
    final modified = item != null && widget.modifiedSlots.contains(index);
    final invalid = item != null && widget.invalidSlots.contains(index);
    final status = <String>[if (modified) 'modified', if (invalid) 'invalid'];
    final semanticsLabel = item == null
        ? 'Slot ${index + 1}, ${widget.emptySlotLabel}'
        : 'Slot ${index + 1}, $label'
              '${status.isEmpty ? '' : ', ${status.join(', ')}'}';

    final content = item == null
        ? null
        : widget.slotBuilder?.call(context, item, index) ??
              _DefaultSlotContent(label: label, color: palette.textSecondary);

    final slot = SizedBox(
      key: ItemGrid.slotKey(index),
      width: slotSize,
      height: slotSize,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Semantics(
          container: true,
          button: item != null && widget.onSelected != null,
          selected: selected,
          enabled: item != null,
          label: semanticsLabel,
          onTap: item == null ? null : () => _select(index),
          excludeSemantics: true,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hoveredIndex = index),
            onExit: (_) {
              if (_hoveredIndex == index) {
                setState(() => _hoveredIndex = null);
              }
            },
            cursor: item == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: item == null ? null : () => _select(index),
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _SlotPlatePainter(
                        filled: item != null,
                        selected: selected,
                        hovered: hovered,
                        enabled: item != null,
                      ),
                    ),
                  ),
                  if (content != null)
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(BombFlowerSpacing.sm),
                        child: content,
                      ),
                    ),
                  if (selected)
                    Positioned(
                      left: BombFlowerSpacing.xs,
                      bottom: BombFlowerSpacing.xs,
                      child: Icon(
                        Icons.check,
                        size: 12,
                        color: palette.accentInk,
                      ),
                    ),
                  if (modified)
                    Positioned(
                      top: 3,
                      right: 3,
                      child: CustomPaint(
                        size: const Size.square(9),
                        painter: _CornerMarkPainter(
                          color: palette.accentInk,
                          kind: _CornerMarkKind.modified,
                        ),
                      ),
                    ),
                  if (invalid)
                    Positioned(
                      top: 3,
                      left: 3,
                      child: CustomPaint(
                        size: const Size.square(10),
                        painter: _CornerMarkPainter(
                          color: palette.danger,
                          kind: _CornerMarkKind.invalid,
                        ),
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
        ),
      ),
    );

    return slot;
  }
}

class _DefaultSlotContent extends StatelessWidget {
  const _DefaultSlotContent({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: BombFlowerTypography.caption.copyWith(color: color),
      ),
    );
  }
}

class _SlotPlatePainter extends CustomPainter {
  const _SlotPlatePainter({
    required this.filled,
    required this.selected,
    required this.hovered,
    required this.enabled,
  });

  final bool filled;
  final bool selected;
  final bool hovered;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.75),
      const Radius.circular(BombFlowerRadii.sm),
    );
    final fill = !enabled
        ? BombFlowerColors.parchmentDisabled
        : selected
        ? BombFlowerColors.selection
        : hovered
        ? BombFlowerColors.parchmentRaised
        : filled
        ? BombFlowerColors.parchmentAlt
        : BombFlowerColors.parchmentSunken;
    canvas.drawRRect(rrect, Paint()..color = fill);

    if (!filled) {
      _drawDashedBorder(canvas, rrect, BombFlowerColors.stoneLight);
    } else {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1
          ..color = selected
              ? BombFlowerColors.brassInk
              : BombFlowerColors.stone,
      );
    }

    // Top inner highlight, like the parchment panels.
    canvas.drawLine(
      Offset(rrect.left + 3, 1.5),
      Offset(rrect.right - 3, 1.5),
      Paint()
        ..strokeWidth = 1
        ..color = BombFlowerColors.parchmentRaised.withValues(alpha: 0.7),
    );
  }

  void _drawDashedBorder(Canvas canvas, RRect rrect, Color color) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 4, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 8;
      }
    }
  }

  @override
  bool shouldRepaint(_SlotPlatePainter oldDelegate) {
    return filled != oldDelegate.filled ||
        selected != oldDelegate.selected ||
        hovered != oldDelegate.hovered ||
        enabled != oldDelegate.enabled;
  }
}

enum _CornerMarkKind { modified, invalid }

class _CornerMarkPainter extends CustomPainter {
  const _CornerMarkPainter({required this.color, required this.kind});

  final Color color;
  final _CornerMarkKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final center = Offset(size.width / 2, size.height / 2);

    if (kind == _CornerMarkKind.modified) {
      final path = Path()
        ..moveTo(center.dx, 0.8)
        ..lineTo(size.width - 0.8, center.dy)
        ..lineTo(center.dx, size.height - 0.8)
        ..lineTo(0.8, center.dy)
        ..close();
      canvas.drawPath(path, paint);
    } else {
      final path = Path()
        ..moveTo(center.dx, 0.8)
        ..lineTo(size.width - 0.8, size.height - 0.8)
        ..lineTo(0.8, size.height - 0.8)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawLine(
        Offset(center.dx, size.height * 0.42),
        Offset(center.dx, size.height * 0.68),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CornerMarkPainter oldDelegate) {
    return color != oldDelegate.color || kind != oldDelegate.kind;
  }
}
