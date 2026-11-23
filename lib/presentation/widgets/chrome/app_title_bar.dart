import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_typography.dart';
import '../common/procedural_painters.dart';
import '../common/seed_pod_mark.dart';

/// Height of the custom title bar, in logical pixels.
const double kAppTitleBarHeight = BombFlowerSpacing.titleBarHeight;

/// Frameless window chrome: wood grain, brand mark, save identity slot, dirty
/// indicator slot, and the three window controls.
///
/// [interactive] must be false in widget tests. The bar still lays out and
/// paints, but every native bitsdojo call becomes a no-op.
class AppTitleBar extends StatelessWidget {
  const AppTitleBar({
    super.key,
    this.interactive = true,
    this.isDirty = false,
    this.saveName,
  });

  final bool interactive;
  final bool isDirty;

  /// Current save identity. Null means no file is open; the center slot says so
  /// rather than inventing a filename.
  final String? saveName;

  void _startDragging() {
    if (interactive) appWindow.startDragging();
  }

  void _minimize() {
    if (interactive) appWindow.minimize();
  }

  void _maximizeOrRestore() {
    if (interactive) appWindow.maximizeOrRestore();
  }

  void _close() {
    if (interactive) appWindow.close();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kAppTitleBarHeight,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: const WoodGrainPainter(
            top: BombFlowerColors.woodDark,
            bottom: BombFlowerColors.wood,
            seed: 5,
          ),
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => _startDragging(),
              onDoubleTap: _maximizeOrRestore,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: BombFlowerSpacing.xl),
                  const SeedPodMark(
                    size: 24,
                    color: BombFlowerColors.bone,
                    accentColor: BombFlowerColors.brass,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'BOMB FLOWER',
                    style: BombFlowerTypography.label.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: BombFlowerColors.bone,
                    ),
                  ),
                  const SizedBox(width: BombFlowerSpacing.xl),
                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              saveName ?? 'No save open',
                              key: const Key('title-bar-save-name'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BombFlowerTypography.button.copyWith(
                                color: BombFlowerColors.bone,
                              ),
                            ),
                          ),
                          const SizedBox(width: BombFlowerSpacing.sm),
                          Semantics(
                            label: isDirty ? 'Unsaved changes' : null,
                            child: Container(
                              key: const Key('title-bar-dirty-indicator'),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDirty
                                    ? BombFlowerColors.brass
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _TitleBarButton(
                    tooltip: 'Minimize',
                    semanticsLabel: 'Minimize window',
                    onPressed: _minimize,
                    glyph: _WindowGlyph.minimize,
                  ),
                  _TitleBarButton(
                    tooltip: 'Maximize',
                    semanticsLabel: 'Maximize or restore window',
                    onPressed: _maximizeOrRestore,
                    glyph: _WindowGlyph.maximize,
                  ),
                  _TitleBarButton(
                    tooltip: 'Close',
                    semanticsLabel: 'Close window',
                    onPressed: _close,
                    glyph: _WindowGlyph.close,
                    danger: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _WindowGlyph { minimize, maximize, close }

class _TitleBarButton extends StatefulWidget {
  const _TitleBarButton({
    required this.tooltip,
    required this.semanticsLabel,
    required this.onPressed,
    required this.glyph,
    this.danger = false,
  });

  final String tooltip;
  final String semanticsLabel;
  final VoidCallback onPressed;
  final _WindowGlyph glyph;
  final bool danger;

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final fill = _pressed
        ? widget.danger
              ? BombFlowerColors.dangerPressed
              : BombFlowerColors.canopyPressed
        : _hovered
        ? widget.danger
              ? BombFlowerColors.dangerStrong
              : BombFlowerColors.canopyHover
        : Colors.transparent;

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: Tooltip(
        message: widget.tooltip,
        child: FocusableActionDetector(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed();
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
            cursor: SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {},
              onPanUpdate: (_) {},
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: widget.onPressed,
              child: SizedBox(
                width: BombFlowerSpacing.titleBarButtonWidth,
                height: kAppTitleBarHeight,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: AnimatedContainer(
                        duration: BombFlowerMotion.adaptive(
                          context,
                          BombFlowerMotion.hover,
                        ),
                        color: fill,
                      ),
                    ),
                    Center(
                      child: CustomPaint(
                        size: const Size.square(12),
                        painter: _WindowGlyphPainter(
                          glyph: widget.glyph,
                          color: BombFlowerColors.bone,
                        ),
                      ),
                    ),
                    if (_focused)
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: const FocusRingPainter(
                                color: BombFlowerColors.brassFocus,
                                radius: BombFlowerRadii.sm,
                              ),
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
      ),
    );
  }
}

class _WindowGlyphPainter extends CustomPainter {
  const _WindowGlyphPainter({required this.glyph, required this.color});

  final _WindowGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 16;
    canvas.save();
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (glyph) {
      case _WindowGlyph.minimize:
        canvas.drawLine(const Offset(4, 11), const Offset(12, 11), paint);
      case _WindowGlyph.maximize:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(4, 4, 8, 8),
            const Radius.circular(1.5),
          ),
          paint,
        );
      case _WindowGlyph.close:
        paint.strokeWidth = 1.4;
        canvas.drawLine(const Offset(4, 4), const Offset(12, 12), paint);
        canvas.drawLine(const Offset(12, 4), const Offset(4, 12), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WindowGlyphPainter oldDelegate) {
    return glyph != oldDelegate.glyph || color != oldDelegate.color;
  }
}
