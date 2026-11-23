import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../common/procedural_painters.dart';

/// A carved stone track with a brass thumb.
///
/// The visual switch is 44 x 24 px inside a 44 x 32 px hit target. It is a
/// single Tab stop and toggles with Space or Enter. The value is carried by the
/// thumb position, the visible [label], and the [Semantics] toggled state, so
/// colour is never the only signal. Movement collapses to the reduced-motion
/// token when the platform asks for less animation.
class BrassToggle extends StatefulWidget {
  const BrassToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.enabled = true,
    this.autofocus = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final String? description;
  final bool enabled;
  final bool autofocus;

  static const double trackWidth = 44;
  static const double trackHeight = 24;
  static const double hitHeight = 32;
  static const double thumbSize = 18;

  static const Key trackKey = ValueKey<String>('brass-toggle-track');
  static const Key controlKey = ValueKey<String>('brass-toggle-control');

  @override
  State<BrassToggle> createState() => _BrassToggleState();
}

class _BrassToggleState extends State<BrassToggle> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.enabled && widget.onChanged != null;

  void _toggle() {
    if (_enabled) widget.onChanged!(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final duration = BombFlowerMotion.adaptive(
      context,
      BombFlowerMotion.modalIn,
    );
    final labelColor = _enabled ? palette.textPrimary : palette.disabledText;
    final descriptionColor = _enabled
        ? palette.textMuted
        : palette.disabledText;

    final switchVisual = SizedBox(
      key: BrassToggle.controlKey,
      width: BrassToggle.trackWidth,
      height: BrassToggle.hitHeight,
      child: Center(
        child: SizedBox(
          width: BrassToggle.trackWidth,
          height: BrassToggle.trackHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  key: BrassToggle.trackKey,
                  painter: _ToggleTrackPainter(
                    on: widget.value,
                    hovered: _hovered && _enabled,
                    enabled: _enabled,
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: duration,
                curve: BombFlowerMotion.standardCurve,
                left: widget.value
                    ? BrassToggle.trackWidth -
                          BrassToggle.thumbSize -
                          BombFlowerSpacing.xxs -
                          1
                    : BombFlowerSpacing.xxs + 1,
                top: (BrassToggle.trackHeight - BrassToggle.thumbSize) / 2,
                width: BrassToggle.thumbSize,
                height: BrassToggle.thumbSize,
                child: AnimatedScale(
                  scale: _pressed && _enabled ? 0.92 : 1,
                  duration: BombFlowerMotion.adaptive(
                    context,
                    BombFlowerMotion.press,
                  ),
                  curve: BombFlowerMotion.pressCurve,
                  child: CustomPaint(
                    painter: _ToggleThumbPainter(enabled: _enabled),
                  ),
                ),
              ),
              if (_focused && _enabled)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: FocusRingPainter(
                        color: palette.focusOnLight,
                        radius: BombFlowerRadii.lg,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final hasText = widget.label != null || widget.description != null;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        switchVisual,
        if (hasText) ...<Widget>[
          const SizedBox(width: BombFlowerSpacing.md),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (widget.label != null)
                  Text(
                    widget.label!,
                    style: BombFlowerTypography.label.copyWith(
                      color: labelColor,
                    ),
                  ),
                if (widget.description != null)
                  Text(
                    widget.description!,
                    style: BombFlowerTypography.caption.copyWith(
                      color: descriptionColor,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );

    return Semantics(
      container: true,
      toggled: widget.value,
      enabled: _enabled,
      focusable: _enabled,
      focused: _focused,
      label: widget.label ?? 'Toggle',
      hint: widget.description,
      onTap: _enabled ? _toggle : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: _enabled,
        autofocus: widget.autofocus,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggle();
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
          cursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _enabled ? _toggle : null,
            onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel: _enabled
                ? () => setState(() => _pressed = false)
                : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: BrassToggle.hitHeight,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleTrackPainter extends CustomPainter {
  const _ToggleTrackPainter({
    required this.on,
    required this.hovered,
    required this.enabled,
  });

  final bool on;
  final bool hovered;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(size.height / 2),
    );
    final fill = enabled
        ? (on ? BombFlowerColors.stoneDark : BombFlowerColors.stone)
        : BombFlowerColors.parchmentDisabled;
    canvas.drawRRect(rrect, Paint()..color = fill);

    // A single inset shadow line gives the track its carved depth; it is not a
    // state signal and stays in both positions.
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawLine(
      Offset(0, 1.5),
      Offset(size.width, 1.5),
      Paint()
        ..color = BombFlowerColors.ink.withValues(alpha: 0.28)
        ..strokeWidth = 1.6,
    );
    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = enabled
            ? (hovered
                  ? BombFlowerColors.stoneLight
                  : BombFlowerColors.stoneDark)
            : BombFlowerColors.stoneLight,
    );
  }

  @override
  bool shouldRepaint(_ToggleTrackPainter oldDelegate) {
    return on != oldDelegate.on ||
        hovered != oldDelegate.hovered ||
        enabled != oldDelegate.enabled;
  }
}

class _ToggleThumbPainter extends CustomPainter {
  const _ToggleThumbPainter({required this.enabled});

  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final colors = enabled
        ? const <Color>[
            BombFlowerColors.brassHover,
            BombFlowerColors.brass,
            BombFlowerColors.brassDeep,
          ]
        : const <Color>[
            BombFlowerColors.stoneLight,
            BombFlowerColors.stone,
            BombFlowerColors.stoneDark,
          ];
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: colors,
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius - 0.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = enabled
            ? BombFlowerColors.brassInk
            : BombFlowerColors.stoneDark,
    );
    // Engraved grip: a vertical line that travels with the thumb.
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 0.42),
      Offset(center.dx, center.dy + radius * 0.42),
      Paint()
        ..color = BombFlowerColors.ink.withValues(alpha: enabled ? 0.3 : 0.18)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ToggleThumbPainter oldDelegate) {
    return enabled != oldDelegate.enabled;
  }
}
