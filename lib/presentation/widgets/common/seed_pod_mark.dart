import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';

/// Original geometric seed-pod mark: a tapered pod with a five-leaf calyx
/// (three leaves at small sizes) and one brass seed notch.
///
/// Drawn entirely from cubic Béziers and circles. It is decorative: the widget
/// is excluded from semantics, and callers supply any accessible label.
class SeedPodMark extends StatelessWidget {
  const SeedPodMark({
    super.key,
    this.size = 24,
    this.color = BombFlowerColors.stone,
    this.accentColor = BombFlowerColors.brass,
    this.filled = false,
  });

  final double size;
  final Color color;
  final Color accentColor;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(size),
          painter: _SeedPodPainter(
            color: color,
            accentColor: accentColor,
            filled: filled,
          ),
        ),
      ),
    );
  }
}

class _SeedPodPainter extends CustomPainter {
  const _SeedPodPainter({
    required this.color,
    required this.accentColor,
    required this.filled,
  });

  final Color color;
  final Color accentColor;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = size.shortestSide / 24;
    canvas.save();
    canvas.scale(scale);

    final leafCount = size.shortestSide < 20 ? 3 : 5;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 / scale.clamp(0.6, 2.5)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final leafFill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.05);

    final calyx = const Offset(12, 7.6);
    for (var i = 0; i < leafCount; i++) {
      final spread = 0.5;
      final angle = -math.pi / 2 + (i - (leafCount - 1) / 2) * spread;
      final leaf = _leafPath(calyx, angle, 6.3, 2.05);
      canvas.drawPath(leaf, leafFill);
      canvas.drawPath(leaf, stroke);
    }

    // Pod body.
    final pod = Path()
      ..moveTo(12, 21)
      ..cubicTo(9.0, 19.1, 6.7, 15.2, 7.2, 11.5)
      ..cubicTo(7.5, 9.0, 9.2, 7.3, 12, 7.1)
      ..cubicTo(14.8, 7.3, 16.5, 9.0, 16.8, 11.5)
      ..cubicTo(17.3, 15.2, 15.0, 19.1, 12, 21)
      ..close();
    if (filled) {
      canvas.drawPath(pod, Paint()..color = color.withValues(alpha: 0.10));
    }
    canvas.drawPath(pod, stroke);

    // Calyx seam.
    canvas.drawLine(
      const Offset(7.4, 8.2),
      const Offset(16.6, 8.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1 / scale.clamp(0.6, 2.5)
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.75),
    );

    // The seed notch: one small brass circle and a short stem line.
    canvas.drawCircle(
      const Offset(12, 14.6),
      1.05,
      Paint()..color = accentColor,
    );
    canvas.drawLine(
      const Offset(12, 15.9),
      const Offset(12, 18.1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9 / scale.clamp(0.6, 2.5)
        ..strokeCap = StrokeCap.round
        ..color = accentColor.withValues(alpha: 0.9),
    );

    canvas.restore();
  }

  Path _leafPath(Offset origin, double angle, double length, double width) {
    final direction = Offset(math.cos(angle), math.sin(angle));
    final normal = Offset(-direction.dy, direction.dx);
    final tip = origin + direction * length;
    final shoulder = origin + direction * (length * 0.48);

    return Path()
      ..moveTo(origin.dx, origin.dy)
      ..cubicTo(
        (shoulder + normal * width).dx,
        (shoulder + normal * width).dy,
        (tip - normal * width * 0.3).dx,
        (tip - normal * width * 0.3).dy,
        tip.dx,
        tip.dy,
      )
      ..cubicTo(
        (tip + normal * width * 0.3).dx,
        (tip + normal * width * 0.3).dy,
        (shoulder - normal * width).dx,
        (shoulder - normal * width).dy,
        origin.dx,
        origin.dy,
      )
      ..close();
  }

  @override
  bool shouldRepaint(_SeedPodPainter oldDelegate) {
    return color != oldDelegate.color ||
        accentColor != oldDelegate.accentColor ||
        filled != oldDelegate.filled;
  }
}
