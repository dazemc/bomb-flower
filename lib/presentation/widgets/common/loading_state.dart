import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';

/// Blocking loading state: carved-rune pulse, label, optional real determinate
/// progress. Never fakes a percentage.
///
/// Honors [MediaQuery.disableAnimations]: the mark becomes static and the
/// looping opacity stops entirely.
class LoadingState extends StatefulWidget {
  const LoadingState({
    super.key,
    this.label = 'Reading save…',
    this.detail,
    this.progress,
    this.onDark = false,
  });

  final String label;
  final String? detail;

  /// A real 0..1 value from the operation, or null for indeterminate.
  final double? progress;
  final bool onDark;

  @override
  State<LoadingState> createState() => _LoadingStateState();
}

class _LoadingStateState extends State<LoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: BombFlowerMotion.runePulse,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce == _reducedMotion && (_controller.isAnimating || reduce)) {
      return;
    }
    _reducedMotion = reduce;
    if (reduce) {
      _controller
        ..stop()
        ..value = 0.5;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final primary = widget.onDark ? palette.textOnDark : palette.textPrimary;
    final muted = widget.onDark ? palette.textMutedOnDark : palette.textMuted;
    final highlight = widget.onDark
        ? BombFlowerColors.brass
        : BombFlowerColors.brassInk;
    final base = widget.onDark
        ? BombFlowerColors.boneMuted
        : BombFlowerColors.stone;

    return Semantics(
      container: true,
      liveRegion: true,
      label: widget.detail == null
          ? widget.label
          : '${widget.label}. ${widget.detail}',
      value: widget.progress == null
          ? null
          : '${(widget.progress! * 100).round()}%',
      excludeSemantics: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(BombFlowerSpacing.huge),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final t = _reducedMotion ? 0.5 : _controller.value;
                      final pulse =
                          0.4 + 0.45 * (0.5 - 0.5 * math.cos(2 * math.pi * t));
                      return CustomPaint(
                        size: const Size.square(48),
                        painter: RunePulsePainter(
                          baseColor: base,
                          highlightColor: highlight,
                          pulse: pulse,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: BombFlowerSpacing.xl),
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: BombFlowerTypography.bodyStrong.copyWith(
                    color: primary,
                  ),
                ),
                if (widget.detail != null) ...<Widget>[
                  const SizedBox(height: BombFlowerSpacing.xs),
                  Text(
                    widget.detail!,
                    textAlign: TextAlign.center,
                    style: BombFlowerTypography.caption.copyWith(color: muted),
                  ),
                ],
                if (widget.progress != null) ...<Widget>[
                  const SizedBox(height: BombFlowerSpacing.xl),
                  _DeterminateBar(value: widget.progress!.clamp(0, 1)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeterminateBar extends StatelessWidget {
  const _DeterminateBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 4,
      child: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: BombFlowerColors.parchmentSunken,
                borderRadius: BorderRadius.all(Radius.circular(2)),
                border: Border.fromBorderSide(
                  BorderSide(color: BombFlowerColors.stone),
                ),
              ),
            ),
          ),
          FractionallySizedBox(
            widthFactor: value,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: BombFlowerColors.brass,
                borderRadius: BorderRadius.all(Radius.circular(2)),
                border: Border.fromBorderSide(
                  BorderSide(color: BombFlowerColors.brassInk),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three concentric dashed rune arcs with a center seed dot.
class RunePulsePainter extends CustomPainter {
  const RunePulsePainter({
    required this.baseColor,
    required this.highlightColor,
    this.pulse = 0.4,
  });

  final Color baseColor;
  final Color highlightColor;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = baseColor.withValues(alpha: 0.42);
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = highlightColor.withValues(alpha: pulse);

    const radii = <double>[8, 14, 20];
    for (var ring = 0; ring < radii.length; ring++) {
      final radius = radii[ring];
      final rect = Rect.fromCircle(center: center, radius: radius);
      for (var segment = 0; segment < 3; segment++) {
        final start = ring * 0.55 + segment * (2 * math.pi / 3);
        final path = Path()..addArc(rect, start, 70 * math.pi / 180);
        canvas.drawPath(path, basePaint);
        canvas.drawPath(path, highlightPaint);
      }
    }

    canvas.drawCircle(
      center,
      3.5,
      Paint()..color = highlightColor.withValues(alpha: pulse),
    );
    canvas.drawCircle(
      center,
      3.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = baseColor.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(RunePulsePainter oldDelegate) {
    return baseColor != oldDelegate.baseColor ||
        highlightColor != oldDelegate.highlightColor ||
        pulse != oldDelegate.pulse;
  }
}
