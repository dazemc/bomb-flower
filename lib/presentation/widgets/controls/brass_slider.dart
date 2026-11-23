import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../common/procedural_painters.dart';

class _SliderNudgeIntent extends Intent {
  const _SliderNudgeIntent(this.steps);

  final double steps;
}

class _SliderJumpIntent extends Intent {
  const _SliderJumpIntent({required this.toMax});

  final bool toMax;
}

/// An engraved brass slider with a live numeric readout.
///
/// The 32 px interaction band is the Tab stop. Arrow keys nudge by one
/// division (or 1% of the range when continuous), Page Up/Down by ten, and
/// Home/End jump to the stops. The value is always printed, never carried by
/// the thumb position or colour alone.
class BrassSlider extends StatefulWidget {
  const BrassSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.label,
    this.valueLabel,
    this.enabled = true,
    this.autofocus = false,
  }) : assert(min < max, 'min must be smaller than max');

  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;

  /// Number of discrete intervals. A null or non-positive value is continuous.
  final int? divisions;

  final String? label;

  /// Overrides the printed numeric readout, for example 'Lv. 3'.
  final String? valueLabel;

  final bool enabled;
  final bool autofocus;

  static const double trackHeight = BombFlowerSpacing.minHitTarget;
  static const Key trackKey = ValueKey<String>('brass-slider-track');
  static const Key readoutKey = ValueKey<String>('brass-slider-readout');

  @override
  State<BrassSlider> createState() => _BrassSliderState();
}

class _BrassSliderState extends State<BrassSlider> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'BrassSlider');
  bool _focused = false;
  bool _hovered = false;
  bool _dragging = false;

  bool get _enabled => widget.enabled && widget.onChanged != null;

  int? get _divisions => widget.divisions != null && widget.divisions! > 0
      ? widget.divisions
      : null;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  double get _stepSize {
    final divisions = _divisions;
    if (divisions != null) return (widget.max - widget.min) / divisions;
    return (widget.max - widget.min) / 100;
  }

  double _clean(double value) {
    return double.parse(value.toStringAsFixed(6));
  }

  double _snap(double raw) {
    final clamped = raw.clamp(widget.min, widget.max).toDouble();
    final divisions = _divisions;
    if (divisions == null) return _clean(clamped);
    final step = (widget.max - widget.min) / divisions;
    final index = ((clamped - widget.min) / step)
        .round()
        .clamp(0, divisions)
        .toInt();
    return _clean(widget.min + step * index);
  }

  void _emit(double raw) {
    if (!_enabled) return;
    final next = _snap(raw);
    if (next == _clean(widget.value)) return;
    widget.onChanged!(next);
  }

  void _nudge(double steps) {
    if (!_enabled) return;
    _emit(widget.value + _stepSize * steps);
  }

  void _jump({required bool toMax}) {
    if (!_enabled) return;
    _emit(toMax ? widget.max : widget.min);
  }

  void _handlePosition(Offset localPosition, double width) {
    const inset = 10.0;
    final usable = width - inset * 2;
    if (usable <= 0) return;
    final fraction = ((localPosition.dx - inset) / usable)
        .clamp(0.0, 1.0)
        .toDouble();
    _emit(widget.min + fraction * (widget.max - widget.min));
  }

  String _formatValue(double value) {
    final cleaned = _clean(value);
    if (cleaned == cleaned.roundToDouble()) return cleaned.toInt().toString();
    return cleaned.toString();
  }

  String get _readout => widget.valueLabel ?? _formatValue(widget.value);

  String _readoutFor(double raw) => _formatValue(_snap(raw));

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final labelColor = _enabled ? palette.textPrimary : palette.disabledText;
    final readoutColor = _enabled ? palette.accentInk : palette.disabledText;
    final duration = BombFlowerMotion.adaptive(context, BombFlowerMotion.hover);

    final header = Wrap(
      spacing: BombFlowerSpacing.md,
      runSpacing: BombFlowerSpacing.xs,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (widget.label != null)
          Text(
            widget.label!,
            style: BombFlowerTypography.label.copyWith(color: labelColor),
          ),
        Text(
          _readout,
          key: BrassSlider.readoutKey,
          style: BombFlowerTypography.mono.copyWith(
            fontSize: BombFlowerTypography.labelSize,
            height:
                BombFlowerTypography.labelLineHeight /
                BombFlowerTypography.labelSize,
            fontWeight: FontWeight.w700,
            color: readoutColor,
          ),
        ),
      ],
    );

    final track = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return FocusableActionDetector(
          enabled: _enabled,
          autofocus: widget.autofocus,
          focusNode: _focusNode,
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.arrowLeft): _SliderNudgeIntent(
              -1,
            ),
            SingleActivator(LogicalKeyboardKey.arrowRight): _SliderNudgeIntent(
              1,
            ),
            SingleActivator(LogicalKeyboardKey.arrowDown): _SliderNudgeIntent(
              -1,
            ),
            SingleActivator(LogicalKeyboardKey.arrowUp): _SliderNudgeIntent(1),
            SingleActivator(LogicalKeyboardKey.pageDown): _SliderNudgeIntent(
              -10,
            ),
            SingleActivator(LogicalKeyboardKey.pageUp): _SliderNudgeIntent(10),
            SingleActivator(LogicalKeyboardKey.home): _SliderJumpIntent(
              toMax: false,
            ),
            SingleActivator(LogicalKeyboardKey.end): _SliderJumpIntent(
              toMax: true,
            ),
          },
          actions: <Type, Action<Intent>>{
            _SliderNudgeIntent: CallbackAction<_SliderNudgeIntent>(
              onInvoke: (intent) {
                _nudge(intent.steps);
                return null;
              },
            ),
            _SliderJumpIntent: CallbackAction<_SliderJumpIntent>(
              onInvoke: (intent) {
                _jump(toMax: intent.toMax);
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
              onTapDown: _enabled
                  ? (details) {
                      _focusNode.requestFocus();
                      _handlePosition(details.localPosition, width);
                    }
                  : null,
              onHorizontalDragStart: _enabled
                  ? (details) {
                      _focusNode.requestFocus();
                      setState(() => _dragging = true);
                      _handlePosition(details.localPosition, width);
                    }
                  : null,
              onHorizontalDragUpdate: _enabled
                  ? (details) => _handlePosition(details.localPosition, width)
                  : null,
              onHorizontalDragEnd: _enabled
                  ? (_) => setState(() => _dragging = false)
                  : null,
              onHorizontalDragCancel: _enabled
                  ? () => setState(() => _dragging = false)
                  : null,
              child: SizedBox(
                key: BrassSlider.trackKey,
                width: width,
                height: BrassSlider.trackHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BrassSliderPainter(
                          value: _snap(widget.value),
                          min: widget.min,
                          max: widget.max,
                          divisions: _divisions,
                          enabled: _enabled,
                          hovered: _hovered,
                          dragging: _dragging,
                        ),
                      ),
                    ),
                    if (_focused && _enabled)
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
        );
      },
    );

    return Semantics(
      container: true,
      slider: true,
      enabled: _enabled,
      focusable: _enabled,
      focused: _focused,
      label: widget.label ?? 'Slider',
      value: _readout,
      increasedValue: _readoutFor(widget.value + _stepSize),
      decreasedValue: _readoutFor(widget.value - _stepSize),
      onIncrease: _enabled ? () => _nudge(1) : null,
      onDecrease: _enabled ? () => _nudge(-1) : null,
      excludeSemantics: true,
      child: AnimatedOpacity(
        opacity: _enabled ? 1 : 0.6,
        duration: duration,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            header,
            const SizedBox(height: BombFlowerSpacing.xs),
            track,
          ],
        ),
      ),
    );
  }
}

class _BrassSliderPainter extends CustomPainter {
  const _BrassSliderPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.enabled,
    required this.hovered,
    required this.dragging,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool enabled;
  final bool hovered;
  final bool dragging;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 10.0;
    final centerY = size.height / 2;
    final left = inset;
    final right = size.width - inset;
    final usable = right - left;
    if (usable <= 0) return;

    final fraction = max == min
        ? 0.0
        : ((value - min) / (max - min)).clamp(0.0, 1.0).toDouble();
    final thumbX = left + usable * fraction;

    final groove = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, centerY - 2, usable, 4),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      groove,
      Paint()
        ..color = enabled
            ? BombFlowerColors.parchmentSunken
            : BombFlowerColors.parchmentDisabled,
    );
    canvas.drawRRect(
      groove,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = BombFlowerColors.stone,
    );

    final active = Rect.fromLTWH(left, centerY - 2, thumbX - left, 4);
    if (active.width > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(active, const Radius.circular(2)),
        Paint()
          ..shader = LinearGradient(
            colors: enabled
                ? const <Color>[
                    BombFlowerColors.brassDeep,
                    BombFlowerColors.brass,
                  ]
                : const <Color>[
                    BombFlowerColors.stoneLight,
                    BombFlowerColors.stone,
                  ],
          ).createShader(active),
      );
    }

    if (divisions != null && divisions! > 1 && divisions! <= 24) {
      final tickPaint = Paint()
        ..strokeWidth = 1
        ..color = BombFlowerColors.stoneDark.withValues(alpha: 0.55);
      for (var i = 1; i < divisions!; i++) {
        final x = left + usable * (i / divisions!);
        canvas.drawLine(
          Offset(x, centerY + 4),
          Offset(x, centerY + 7),
          tickPaint,
        );
      }
    }

    final radius = dragging
        ? 8.0
        : hovered
        ? 7.5
        : 7.0;
    canvas.drawCircle(
      Offset(thumbX, centerY),
      radius,
      Paint()
        ..shader =
            RadialGradient(
              center: const Alignment(-0.35, -0.4),
              radius: 1.1,
              colors: enabled
                  ? const <Color>[
                      BombFlowerColors.brassHover,
                      BombFlowerColors.brass,
                      BombFlowerColors.brassDeep,
                    ]
                  : const <Color>[
                      BombFlowerColors.stoneLight,
                      BombFlowerColors.stone,
                    ],
            ).createShader(
              Rect.fromCircle(center: Offset(thumbX, centerY), radius: radius),
            ),
    );
    canvas.drawCircle(
      Offset(thumbX, centerY),
      radius - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = BombFlowerColors.brassInk,
    );
  }

  @override
  bool shouldRepaint(_BrassSliderPainter oldDelegate) {
    return value != oldDelegate.value ||
        min != oldDelegate.min ||
        max != oldDelegate.max ||
        divisions != oldDelegate.divisions ||
        enabled != oldDelegate.enabled ||
        hovered != oldDelegate.hovered ||
        dragging != oldDelegate.dragging;
  }
}
