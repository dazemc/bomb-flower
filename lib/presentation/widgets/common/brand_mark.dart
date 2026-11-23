import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';

/// Red-orange for the stamens. Chosen for this drawing, not sampled from any
/// reference: `danger` (#A63A2E) reads too brown against the green bulb.
const Color _stamenOrange = Color(0xFFC0442A);

// ---------------------------------------------------------------------------
// Design grid: 26 x 20 units, 1.30:1 landscape. The widget treats `size` as
// the width and derives height = size / 1.30, so the title-bar slot stays
// 24 logical pixels wide (and 18.5 tall). All ink sits between x 2.4 and 22.8
// and y 2.2 and 19.2, i.e. about 20.4 x 17.1 units.
// ---------------------------------------------------------------------------

const double _canvasWidth = 26;
const double _canvasHeight = 20;
const double _canvasAspect = _canvasWidth / _canvasHeight;

/// Squat bulb: 12.6 x 11.0 units, i.e. 1.145:1 wider than tall. No tip, no
/// stem, no taper; the bottom is a plain oval.
const Offset _bulbCentre = Offset(12.6, 12.0);
const double _bulbRadiusX = 6.3;
const double _bulbRadiusY = 5.5;

/// Rosette: five short, wide leaves hugging the base, only their outer halves
/// visible. The angles are screen angles (90 = straight down) and each reach
/// is the distance from the rosette origin, so the ring is wider than it is
/// deep. At small sizes only three leaves (left, down, right) are drawn.
const Offset _rosetteOrigin = Offset(12.6, 13.4);
const List<double> _rosetteAngles = <double>[0, 45, 90, 135, 180];
const List<double> _rosetteReaches = <double>[10.2, 7.6, 5.8, 7.6, 10.2];
const double _rosetteInner = 4.3;
const double _rosetteHalfWidth = 1.35;

/// Collar: a short horizontal band over the top of the bulb, with six studs
/// along its upper edge at detailed sizes only.
const Offset _collarCentre = Offset(12.6, 7.9);
const double _collarWidth = 7.4;
const double _collarHeight = 1.7;
const double _collarRadius = 0.5;
const double _studSize = 0.8;
const int _studCount = 6;
const double _studFirstX = 9.6;
const double _studSpacing = 1.2;

/// Three stamens at -35, 0 and +35 degrees from vertical, 4.4 units long,
/// each ending in an anther dot at detailed sizes only.
const double _stamenLength = 4.4;
const double _stamenSpread = 0.6108652381980153; // 35 degrees in radians
const Offset _stamenLeftBase = Offset(11.0, 7.6);
const Offset _stamenMidBase = Offset(12.6, 7.6);
const Offset _stamenRightBase = Offset(14.2, 7.6);
const double _antherRadius = 0.75;

/// Size at which studs, anthers and the two extra rosette leaves turn on.
const double _detailThreshold = 32;

/// Colour roles for one tone of the mark.
class _MarkTones {
  const _MarkTones({
    required this.bulb,
    required this.rim,
    required this.collar,
    required this.stud,
    required this.rosette,
  });

  final Color bulb;
  final Color rim;
  final Color collar;
  final Color stud;
  final Color rosette;

  /// Title-bar tone: near-black bulb on wood, brass collar, dark-green leaves.
  static const _MarkTones dark = _MarkTones(
    bulb: BombFlowerColors.canopy0,
    // boneMuted at 50% alpha, written out so the table stays const.
    rim: Color(0x80A9B5A2),
    collar: BombFlowerColors.brass,
    stud: BombFlowerColors.brassPressed,
    rosette: BombFlowerColors.canopyHover,
  );

  /// Parchment tone: deep-green bulb, ink-gold collar, success-family leaves.
  static const _MarkTones parchment = _MarkTones(
    bulb: BombFlowerColors.canopy2,
    rim: BombFlowerColors.stoneDark,
    collar: BombFlowerColors.brassPressed,
    stud: BombFlowerColors.brassInk,
    rosette: BombFlowerColors.success,
  );
}

/// Original vector bomb-flower mark and the fallback for the bundled artwork.
///
/// Squat bulb, studded collar, three stamens and a low leaf rosette. Decorative:
/// semantics are excluded, and callers supply any label.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 24,
    this.onDark = true,
    this.monochrome = false,
    this.tone = BombFlowerColors.bone,
    this.bulbColor,
    this.rimColor,
    this.collarColor,
    this.studColor,
    this.stamenColor,
    this.antherColor,
    this.rosetteColor,
  });

  /// Width in logical pixels; the height is `size / 1.30`.
  final double size;

  /// True on the wood/canopy chassis, false on parchment.
  final bool onDark;

  /// Paint the whole silhouette in [tone] via `BlendMode.srcIn`.
  final bool monochrome;

  /// The single ink colour used when [monochrome] is true.
  final Color tone;

  final Color? bulbColor;
  final Color? rimColor;
  final Color? collarColor;
  final Color? studColor;
  final Color? stamenColor;
  final Color? antherColor;
  final Color? rosetteColor;

  @override
  Widget build(BuildContext context) {
    final tones = onDark ? _MarkTones.dark : _MarkTones.parchment;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(size, size / _canvasAspect),
          painter: BrandMarkPainter(
            bulbColor: bulbColor ?? tones.bulb,
            rimColor: rimColor ?? tones.rim,
            collarColor: collarColor ?? tones.collar,
            studColor: studColor ?? tones.stud,
            stamenColor: stamenColor ?? _stamenOrange,
            antherColor: antherColor ?? _stamenOrange,
            rosetteColor: rosetteColor ?? tones.rosette,
            monochrome: monochrome,
            tone: tone,
          ),
        ),
      ),
    );
  }
}

/// Paints [BrandMark] on the 26 x 20 design grid. Public and const so tests
/// can assert on the painter and on its repaint decision.
class BrandMarkPainter extends CustomPainter {
  const BrandMarkPainter({
    required this.bulbColor,
    required this.rimColor,
    required this.collarColor,
    required this.studColor,
    required this.stamenColor,
    required this.antherColor,
    required this.rosetteColor,
    this.monochrome = false,
    this.tone = BombFlowerColors.bone,
  });

  /// Title-bar tone, full colour.
  const BrandMarkPainter.dark()
    : this(
        bulbColor: BombFlowerColors.canopy0,
        rimColor: const Color(0x80A9B5A2),
        collarColor: BombFlowerColors.brass,
        studColor: BombFlowerColors.brassPressed,
        stamenColor: _stamenOrange,
        antherColor: _stamenOrange,
        rosetteColor: BombFlowerColors.canopyHover,
      );

  /// Parchment tone, full colour.
  const BrandMarkPainter.parchment()
    : this(
        bulbColor: BombFlowerColors.canopy2,
        rimColor: BombFlowerColors.stoneDark,
        collarColor: BombFlowerColors.brassPressed,
        studColor: BombFlowerColors.brassInk,
        stamenColor: _stamenOrange,
        antherColor: _stamenOrange,
        rosetteColor: BombFlowerColors.success,
      );

  final Color bulbColor;
  final Color rimColor;
  final Color collarColor;
  final Color studColor;
  final Color stamenColor;
  final Color antherColor;
  final Color rosetteColor;

  final bool monochrome;
  final Color tone;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = size.width / _canvasWidth;
    if (scale <= 0) return;
    final detail = size.width >= _detailThreshold;

    canvas.save();
    canvas.scale(scale);
    if (monochrome) {
      const bounds = Rect.fromLTWH(0, 0, _canvasWidth, _canvasHeight);
      canvas.saveLayer(bounds, Paint());
      _paintGeometry(
        canvas,
        detail: detail,
        maskOnly: true,
        unitsPerPixel: 1 / scale,
      );
      canvas.drawRect(
        bounds,
        Paint()
          ..color = tone
          ..blendMode = BlendMode.srcIn,
      );
      canvas.restore();
    } else {
      _paintGeometry(
        canvas,
        detail: detail,
        maskOnly: false,
        unitsPerPixel: 1 / scale,
      );
    }
    canvas.restore();
  }

  void _paintGeometry(
    Canvas canvas, {
    required bool detail,
    required bool maskOnly,
    required double unitsPerPixel,
  }) {
    // One logical pixel expressed in grid units. Rims never drop below a
    // logical pixel; at 16 px they thicken instead of disappearing.
    final rimWidth = math.max(0.8, unitsPerPixel);
    final stamenWidth = math.max(1.35, unitsPerPixel);

    final leafColor = maskOnly ? tone : rosetteColor;
    final bulbFill = maskOnly ? tone : bulbColor;
    final collarPaint = Paint()..color = maskOnly ? tone : collarColor;
    final studPaint = Paint()..color = maskOnly ? tone : studColor;
    final stamenPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stamenWidth
      ..strokeCap = StrokeCap.round
      ..color = maskOnly ? tone : stamenColor;
    final antherPaint = Paint()..color = maskOnly ? tone : antherColor;

    // Rosette first: the bulb hides the inner halves of the leaves.
    final leafCount = detail ? _rosetteAngles.length : 3;
    for (var i = 0; i < leafCount; i++) {
      final index = detail ? i : i * 2;
      canvas.drawPath(
        _rosetteLeaf(_rosetteAngles[index], _rosetteReaches[index]),
        Paint()..color = leafColor,
      );
    }

    // Squat bulb.
    final bulb = Path()
      ..addOval(
        Rect.fromCenter(
          center: _bulbCentre,
          width: _bulbRadiusX * 2,
          height: _bulbRadiusY * 2,
        ),
      );
    canvas.drawPath(bulb, Paint()..color = bulbFill);
    canvas.drawPath(
      bulb,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimWidth
        ..color = maskOnly ? tone : rimColor,
    );

    // Collar band.
    final collar = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: _collarCentre,
        width: _collarWidth,
        height: _collarHeight,
      ),
      const Radius.circular(_collarRadius),
    );
    canvas.drawRRect(collar, collarPaint);

    // Studs along the collar's upper edge, detailed sizes only.
    if (detail) {
      for (var i = 0; i < _studCount; i++) {
        final x = _studFirstX + _studSpacing * i;
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(x, _collarCentre.dy - _collarHeight / 2),
            width: _studSize,
            height: _studSize,
          ),
          studPaint,
        );
      }
    }

    // Three stamens fanning out of the collar, -35 / 0 / +35 from vertical.
    for (final stamen in _stamens) {
      _drawStamen(canvas, stamen.base, stamen.offset, stamenPaint);
    }

    // Anthers, detailed sizes only.
    if (detail) {
      for (final stamen in _stamens) {
        canvas.drawCircle(
          _stamenTip(stamen.base, stamen.offset),
          _antherRadius,
          antherPaint,
        );
      }
    }
  }

  static const List<({Offset base, double offset})> _stamens =
      <({Offset base, double offset})>[
        (base: _stamenLeftBase, offset: -_stamenSpread),
        (base: _stamenMidBase, offset: 0),
        (base: _stamenRightBase, offset: _stamenSpread),
      ];

  void _drawStamen(Canvas canvas, Offset base, double offset, Paint paint) {
    final tip = _stamenTip(base, offset);
    // A gentle outward bow, so the three strokes read as a fan rather than
    // three straight wires.
    final mid = Offset(
      base.dx + (tip.dx - base.dx) * 0.5 + (offset == 0 ? 0 : offset * 0.35),
      base.dy + (tip.dy - base.dy) * 0.5,
    );
    canvas.drawPath(
      Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, tip.dx, tip.dy),
      paint,
    );
  }

  Offset _stamenTip(Offset base, double offset) {
    // `offset` is the angle from vertical: 0 points straight up.
    return base +
        Offset(
          math.sin(offset) * _stamenLength,
          -math.cos(offset) * _stamenLength,
        );
  }

  /// A short, wide leaf radiating from the rosette origin at [angle].
  Path _rosetteLeaf(double angle, double reach) {
    final direction = Offset(math.cos(angle), math.sin(angle));
    final normal = Offset(-direction.dy, direction.dx);
    final base = _rosetteOrigin + direction * _rosetteInner;
    final shoulder =
        _rosetteOrigin +
        direction * (_rosetteInner + (reach - _rosetteInner) * 0.55);
    final tipNear = _rosetteOrigin + direction * (reach * 0.9);
    final apex = _rosetteOrigin + direction * reach;

    return Path()
      ..moveTo(base.dx, base.dy)
      ..cubicTo(
        (base + normal * _rosetteHalfWidth).dx,
        (base + normal * _rosetteHalfWidth).dy,
        (shoulder + normal * _rosetteHalfWidth).dx,
        (shoulder + normal * _rosetteHalfWidth).dy,
        (tipNear + normal * _rosetteHalfWidth * 0.55).dx,
        (tipNear + normal * _rosetteHalfWidth * 0.55).dy,
      )
      ..quadraticBezierTo(apex.dx, apex.dy, (tipNear - normal * _rosetteHalfWidth * 0.55).dx, (tipNear - normal * _rosetteHalfWidth * 0.55).dy)
      ..cubicTo(
        (shoulder - normal * _rosetteHalfWidth).dx,
        (shoulder - normal * _rosetteHalfWidth).dy,
        (base - normal * _rosetteHalfWidth).dx,
        (base - normal * _rosetteHalfWidth).dy,
        base.dx,
        base.dy,
      )
      ..close();
  }

  @override
  bool shouldRepaint(BrandMarkPainter oldDelegate) {
    return bulbColor != oldDelegate.bulbColor ||
        rimColor != oldDelegate.rimColor ||
        collarColor != oldDelegate.collarColor ||
        studColor != oldDelegate.studColor ||
        stamenColor != oldDelegate.stamenColor ||
        antherColor != oldDelegate.antherColor ||
        rosetteColor != oldDelegate.rosetteColor ||
        monochrome != oldDelegate.monochrome ||
        tone != oldDelegate.tone;
  }
}
