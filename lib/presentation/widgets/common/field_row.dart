import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';

/// Form row: label, control, helper text, and inline error.
///
/// The error replaces the helper rather than stacking under it. Labels remain
/// full contrast when the control is disabled; disabled values are the
/// control's responsibility.
class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.label,
    required this.child,
    this.helper,
    this.error,
    this.isRequired = false,
    this.isReadOnly = false,
    this.counter,
    this.semanticValue,
    this.maxWidth = 420,
  });

  final String label;
  final Widget child;
  final String? helper;
  final String? error;
  final bool isRequired;
  final bool isReadOnly;
  final String? counter;
  final String? semanticValue;

  /// Normal text fields stop at 420 px; descriptions may pass 720.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final hasError = error != null;

    return Semantics(
      container: true,
      label: label,
      value: semanticValue,
      hint: hasError ? error : helper,
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (isRequired) ...<Widget>[
                    Container(
                      width: 3,
                      height: 3,
                      decoration: const BoxDecoration(
                        color: BombFlowerColors.brassInk,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: BombFlowerSpacing.sm),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: BombFlowerTypography.label.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  if (isReadOnly) ...<Widget>[
                    const SizedBox(width: BombFlowerSpacing.sm),
                    Icon(
                      Icons.lock_outline,
                      size: 12,
                      color: palette.textMuted,
                    ),
                    const SizedBox(width: BombFlowerSpacing.xs),
                    Text(
                      'Read-only',
                      style: BombFlowerTypography.caption.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: BombFlowerSpacing.sm),
              SizedBox(width: double.infinity, child: child),
              if (hasError) ...<Widget>[
                const SizedBox(height: BombFlowerSpacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: _InlineErrorGlyph(),
                    ),
                    const SizedBox(width: BombFlowerSpacing.xs),
                    Expanded(
                      child: Text(
                        error!,
                        style: BombFlowerTypography.caption.copyWith(
                          color: palette.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (helper != null) ...<Widget>[
                const SizedBox(height: BombFlowerSpacing.xs),
                Text(
                  helper!,
                  style: BombFlowerTypography.caption.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ],
              if (counter != null) ...<Widget>[
                const SizedBox(height: BombFlowerSpacing.xs),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    counter!,
                    style: BombFlowerTypography.mono.copyWith(
                      fontSize: BombFlowerTypography.captionSize,
                      height: 16 / 11,
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineErrorGlyph extends StatelessWidget {
  const _InlineErrorGlyph();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(14),
      painter: const _InlineErrorPainter(),
    );
  }
}

class _InlineErrorPainter extends CustomPainter {
  const _InlineErrorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BombFlowerColors.danger
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, 6.2, paint);
    canvas.drawLine(Offset(center.dx, 3.7), Offset(center.dx, 7.8), paint);
    canvas.drawCircle(
      Offset(center.dx, 10.2),
      0.7,
      Paint()..color = BombFlowerColors.danger,
    );
  }

  @override
  bool shouldRepaint(_InlineErrorPainter oldDelegate) => false;
}
