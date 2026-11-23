import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';

/// Builds the paper silhouette: rounded on three corners with one 8 px
/// clipped notch at the top-right ("page corner").
Path bombFlowerPanelPath(
  Size size, {
  double radius = BombFlowerRadii.md,
  double notch = BombFlowerRadii.panelNotch,
}) {
  final w = size.width;
  final h = size.height;
  final r = math.min(radius, math.min(w, h) / 2);
  final cut = math.min(notch, math.max(0.0, w - r * 2));

  return Path()
    ..moveTo(r, 0)
    ..lineTo(w - cut, 0)
    ..lineTo(w, cut)
    ..lineTo(w, h - r)
    ..quadraticBezierTo(w, h, w - r, h)
    ..lineTo(r, h)
    ..quadraticBezierTo(0, h, 0, h - r)
    ..lineTo(0, r)
    ..quadraticBezierTo(0, 0, r, 0)
    ..close();
}

class ParchmentClipper extends CustomClipper<Path> {
  const ParchmentClipper({
    this.radius = BombFlowerRadii.md,
    this.notch = BombFlowerRadii.panelNotch,
  });

  final double radius;
  final double notch;

  @override
  Path getClip(Size size) {
    return bombFlowerPanelPath(size, radius: radius, notch: notch);
  }

  @override
  bool shouldReclip(ParchmentClipper oldClipper) {
    return radius != oldClipper.radius || notch != oldClipper.notch;
  }
}

/// Procedural paper grain for parchment panels.
///
/// The layer is deterministic for a given [seed] so rebuilds never shimmer.
/// It is meant to sit inside a [RepaintBoundary]: painting is skipped unless
/// size, tokens, or seed change. Texture stays under 4% opacity.
class ParchmentTexturePainter extends CustomPainter {
  const ParchmentTexturePainter({
    required this.fill,
    this.seed = 1,
    this.radius = BombFlowerRadii.md,
    this.notch = BombFlowerRadii.panelNotch,
    this.borderColor,
    this.selected = false,
    this.showTexture = true,
    this.maxSpeckles = 1100,
  });

  final Color fill;
  final int seed;
  final double radius;
  final double notch;
  final Color? borderColor;
  final bool selected;
  final bool showTexture;
  final int maxSpeckles;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = bombFlowerPanelPath(size, radius: radius, notch: notch);
    canvas.drawPath(path, Paint()..color = fill);

    if (showTexture) {
      canvas.save();
      canvas.clipPath(path);
      _paintWash(canvas, size);
      _paintSpeckles(canvas, size);
      _paintFibers(canvas, size);
      canvas.restore();
    }

    final border = borderColor;
    if (border != null) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1
          ..color = border,
      );
    }

    if (selected) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawRect(
        Rect.fromLTWH(0, size.height * 0.18, 3, size.height * 0.64),
        Paint()..color = BombFlowerColors.brassInk,
      );
      canvas.restore();
    }

    // One-pixel inner top highlight; decorative, not a functional boundary.
    canvas.drawLine(
      Offset(radius + 1, 1),
      Offset(size.width - notch - 1, 1),
      Paint()
        ..strokeWidth = 1
        ..color = BombFlowerColors.parchmentRaised.withValues(alpha: 0.7),
    );
  }

  void _paintWash(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * 0.72, size.height * 0.72),
      Paint()
        ..shader =
            RadialGradient(
              center: Alignment.topLeft,
              radius: 1.1,
              colors: <Color>[
                BombFlowerColors.bone.withValues(alpha: 0.03),
                BombFlowerColors.bone.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromLTWH(0, 0, size.width * 0.72, size.height * 0.72),
            ),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.28,
        size.height * 0.28,
        size.width * 0.72,
        size.height * 0.72,
      ),
      Paint()
        ..shader =
            RadialGradient(
              center: Alignment.bottomRight,
              radius: 1.1,
              colors: <Color>[
                BombFlowerColors.stoneDark.withValues(alpha: 0.02),
                BombFlowerColors.stoneDark.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromLTWH(
                size.width * 0.28,
                size.height * 0.28,
                size.width * 0.72,
                size.height * 0.72,
              ),
            ),
    );
  }

  void _paintSpeckles(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final area = size.width * size.height;
    final count = (area / 700).round().clamp(240, maxSpeckles);
    final paint = Paint();

    for (var i = 0; i < count; i++) {
      final light = rng.nextBool();
      final base = light
          ? BombFlowerColors.parchmentRaised
          : BombFlowerColors.ink;
      paint.color = base.withValues(alpha: 0.015 + rng.nextDouble() * 0.025);
      final point = Offset(
        rng.nextDouble() * size.width,
        rng.nextDouble() * size.height,
      );
      canvas.drawCircle(point, 0.5 + rng.nextDouble() * 0.9, paint);
    }
  }

  void _paintFibers(Canvas canvas, Size size) {
    final rng = math.Random(seed + 91);
    final count = 10 + rng.nextInt(5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = BombFlowerColors.ink.withValues(alpha: 0.017);

    for (var i = 0; i < count; i++) {
      final y = rng.nextDouble() * size.height;
      final path = Path()..moveTo(-4, y);
      var x = -4.0;
      while (x < size.width + 4) {
        final step = 28 + rng.nextDouble() * 56;
        path.quadraticBezierTo(
          x + step / 2,
          y + (rng.nextDouble() - 0.5) * 3,
          x + step,
          y + (rng.nextDouble() - 0.5) * 1.4,
        );
        x += step;
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(ParchmentTexturePainter oldDelegate) {
    return fill != oldDelegate.fill ||
        seed != oldDelegate.seed ||
        radius != oldDelegate.radius ||
        notch != oldDelegate.notch ||
        borderColor != oldDelegate.borderColor ||
        selected != oldDelegate.selected ||
        showTexture != oldDelegate.showTexture ||
        maxSpeckles != oldDelegate.maxSpeckles;
  }
}

/// Wood grain for the title bar and nav rail.
class WoodGrainPainter extends CustomPainter {
  const WoodGrainPainter({
    required this.top,
    required this.bottom,
    this.seed = 3,
    this.showBrassInlay = false,
  });

  final Color top;
  final Color bottom;
  final int seed;
  final bool showBrassInlay;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[top, bottom],
        ).createShader(Offset.zero & size),
    );

    final rng = math.Random(seed);
    final bands = 7 + rng.nextInt(4);
    for (var i = 0; i < bands; i++) {
      final y = (i + 0.6) * size.height / bands;
      final color = switch (i % 3) {
        0 => BombFlowerColors.woodLight,
        1 => BombFlowerColors.woodDark,
        _ => BombFlowerColors.wood,
      };
      final path = Path()..moveTo(-8, y);
      var x = -8.0;
      while (x < size.width + 8) {
        final step = 36 + rng.nextDouble() * 52;
        path.quadraticBezierTo(
          x + step / 2,
          y + (rng.nextDouble() - 0.5) * 2.2,
          x + step,
          y + (rng.nextDouble() - 0.5) * 0.9,
        );
        x += step;
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.22 + rng.nextDouble() * 0.13),
      );
    }

    canvas.drawLine(
      const Offset(0, 0.5),
      Offset(size.width, 0.5),
      Paint()
        ..strokeWidth = 1
        ..color = BombFlowerColors.woodEdge,
    );
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..strokeWidth = 1
        ..color = BombFlowerColors.stoneDark,
    );

    if (showBrassInlay) {
      canvas.drawLine(
        const Offset(0, 8.5),
        Offset(size.width, 8.5),
        Paint()
          ..strokeWidth = 2
          ..color = BombFlowerColors.brass.withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(WoodGrainPainter oldDelegate) {
    return top != oldDelegate.top ||
        bottom != oldDelegate.bottom ||
        seed != oldDelegate.seed ||
        showBrassInlay != oldDelegate.showBrassInlay;
  }
}

/// Dark canopy grain behind the scrollable content well.
class CanopyTexturePainter extends CustomPainter {
  const CanopyTexturePainter({this.seed = 17});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[BombFlowerColors.canopy1, BombFlowerColors.canopy0],
        ).createShader(Offset.zero & size),
    );

    final rng = math.Random(seed);
    final paint = Paint();
    final count = (size.width * size.height / 1500).round().clamp(240, 1400);
    for (var i = 0; i < count; i++) {
      paint.color = BombFlowerColors.bone.withValues(
        alpha: 0.006 + rng.nextDouble() * 0.009,
      );
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
        0.5 + rng.nextDouble(),
        paint,
      );
    }

    final striation = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = BombFlowerColors.bone.withValues(alpha: 0.01);
    var x = rng.nextDouble() * 48;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), striation);
      x += 48 + rng.nextDouble() * 48;
    }
  }

  @override
  bool shouldRepaint(CanopyTexturePainter oldDelegate) {
    return seed != oldDelegate.seed;
  }
}

/// 45-degree disabled hatch at 4% ink. Never rely on opacity alone.
class HatchPainter extends CustomPainter {
  const HatchPainter({
    this.color = BombFlowerColors.ink,
    this.radius = BombFlowerRadii.sm,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
    );
    final paint = Paint()
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.04);
    for (var x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(HatchPainter oldDelegate) {
    return color != oldDelegate.color || radius != oldDelegate.radius;
  }
}

/// 2 px keyboard focus ring drawn outside the control's box.
class FocusRingPainter extends CustomPainter {
  const FocusRingPainter({
    required this.color,
    this.radius = BombFlowerRadii.sm,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
        Radius.circular(radius + 1),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(FocusRingPainter oldDelegate) {
    return color != oldDelegate.color || radius != oldDelegate.radius;
  }
}
