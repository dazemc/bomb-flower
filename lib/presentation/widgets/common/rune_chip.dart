import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_typography.dart';

enum RuneChipVariant {
  modified,
  invalid,
  unknown,
  info,
  success,
  warning,
  neutral,
}

/// Stamped tag with a glyph and a text label. Status is never color-only:
/// every variant carries its own mark and always-visible words.
class RuneChip extends StatelessWidget {
  const RuneChip({
    super.key,
    required this.label,
    required this.variant,
    this.semanticLabel,
    this.compact = false,
  });

  final String label;
  final RuneChipVariant variant;
  final String? semanticLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final spec = _ChipSpec.forVariant(variant);
    final height = compact ? 18.0 : 20.0;

    return Semantics(
      container: true,
      label: semanticLabel ?? '${label.toLowerCase()}, ${spec.description}',
      excludeSemantics: true,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: BombFlowerSpacing.sm),
        decoration: BoxDecoration(
          color: spec.fill,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: spec.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CustomPaint(
              size: const Size.square(10),
              painter: _ChipGlyphPainter(variant: variant, color: spec.ink),
            ),
            const SizedBox(width: BombFlowerSpacing.xs),
            Text(
              label.toUpperCase(),
              style: BombFlowerTypography.caption.copyWith(
                fontSize: 11,
                height: 14 / 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: spec.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipSpec {
  const _ChipSpec({
    required this.fill,
    required this.border,
    required this.ink,
    required this.description,
  });

  final Color fill;
  final Color border;
  final Color ink;
  final String description;

  static _ChipSpec forVariant(RuneChipVariant variant) {
    return switch (variant) {
      RuneChipVariant.modified => const _ChipSpec(
        fill: BombFlowerColors.selection,
        border: BombFlowerColors.brassInk,
        ink: BombFlowerColors.brassInk,
        description: 'modified',
      ),
      RuneChipVariant.invalid => const _ChipSpec(
        fill: BombFlowerColors.dangerSurface,
        border: BombFlowerColors.dangerInk,
        ink: BombFlowerColors.dangerInk,
        description: 'invalid',
      ),
      RuneChipVariant.unknown => const _ChipSpec(
        fill: BombFlowerColors.parchmentSunken,
        border: BombFlowerColors.stone,
        ink: BombFlowerColors.inkMuted,
        description: 'unknown',
      ),
      RuneChipVariant.info => const _ChipSpec(
        fill: BombFlowerColors.infoSurface,
        border: BombFlowerColors.info,
        ink: BombFlowerColors.infoInk,
        description: 'information',
      ),
      RuneChipVariant.success => const _ChipSpec(
        fill: BombFlowerColors.successSurface,
        border: BombFlowerColors.success,
        ink: BombFlowerColors.successInk,
        description: 'success',
      ),
      RuneChipVariant.warning => const _ChipSpec(
        fill: BombFlowerColors.warningSurface,
        border: BombFlowerColors.warning,
        ink: BombFlowerColors.warningInk,
        description: 'warning',
      ),
      RuneChipVariant.neutral => const _ChipSpec(
        fill: BombFlowerColors.parchmentSunken,
        // Stone, not divider: a 1 px chip boundary has to clear 3:1 on the
        // sunken plate (divider measured 1.3:1, stone measures 3.66:1).
        border: BombFlowerColors.stone,
        ink: BombFlowerColors.ink,
        description: 'count',
      ),
    };
  }
}

class _ChipGlyphPainter extends CustomPainter {
  const _ChipGlyphPainter({required this.variant, required this.color});

  final RuneChipVariant variant;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final center = Offset(size.width / 2, size.height / 2);

    switch (variant) {
      case RuneChipVariant.modified:
        canvas.drawCircle(center, 2.2, Paint()..color = color);
        canvas.drawCircle(center, 4.2, paint);
      case RuneChipVariant.invalid:
        canvas.drawLine(Offset(center.dx, 1.4), Offset(center.dx, 5.8), paint);
        canvas.drawCircle(Offset(center.dx, 8.5), 0.9, Paint()..color = color);
      case RuneChipVariant.unknown:
        final path = Path()
          ..moveTo(3.1, 3.4)
          ..quadraticBezierTo(3.1, 0.8, 5.2, 0.8)
          ..quadraticBezierTo(7.2, 0.8, 7.2, 2.8)
          ..quadraticBezierTo(7.2, 4.2, 5.3, 4.9)
          ..quadraticBezierTo(5.0, 5.1, 5.0, 6.1);
        canvas.drawPath(path, paint);
        canvas.drawCircle(const Offset(5.0, 8.4), 0.9, Paint()..color = color);
      case RuneChipVariant.info:
        canvas.drawLine(const Offset(5, 4.2), const Offset(5, 8.6), paint);
        canvas.drawCircle(const Offset(5, 1.7), 0.95, Paint()..color = color);
      case RuneChipVariant.success:
        final path = Path()
          ..moveTo(1.8, 5.2)
          ..lineTo(4.2, 7.6)
          ..lineTo(8.4, 2.6);
        canvas.drawPath(path, paint);
      case RuneChipVariant.warning:
        final path = Path()
          ..moveTo(5, 1.2)
          ..lineTo(9.1, 8.5)
          ..lineTo(0.9, 8.5)
          ..close();
        canvas.drawPath(path, paint);
        canvas.drawLine(const Offset(5, 3.8), const Offset(5, 6.0), paint);
        canvas.drawCircle(const Offset(5, 7.2), 0.6, Paint()..color = color);
      case RuneChipVariant.neutral:
        canvas.drawLine(const Offset(1.5, 5), const Offset(8.5, 5), paint);
    }
  }

  @override
  bool shouldRepaint(_ChipGlyphPainter oldDelegate) {
    return variant != oldDelegate.variant || color != oldDelegate.color;
  }
}
