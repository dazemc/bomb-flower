import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import 'brass_button.dart';

/// Panel-level error plate: message, retry, and collapsed technical details.
///
/// Raw exception text is never the primary message; it is available only under
/// the details expander. Unaffected panels stay usable.
class ErrorState extends StatefulWidget {
  const ErrorState({
    super.key,
    this.title = "Couldn't read this section",
    required this.message,
    this.details,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.onCopyDetails,
  });

  final String title;
  final String message;
  final String? details;
  final VoidCallback? onRetry;
  final String retryLabel;
  final VoidCallback? onCopyDetails;

  @override
  State<ErrorState> createState() => _ErrorStateState();
}

class _ErrorStateState extends State<ErrorState> {
  bool _detailsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final details = widget.details;

    return Semantics(
      container: true,
      liveRegion: true,
      label: '${widget.title}. ${widget.message}',
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: BombFlowerColors.dangerSurface,
          borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
          border: Border.all(
            color: BombFlowerColors.danger.withValues(alpha: 0.4),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                width: 3,
                decoration: const BoxDecoration(
                  color: BombFlowerColors.danger,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(BombFlowerRadii.sm),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(BombFlowerSpacing.xxl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const _ErrorPlateGlyph(),
                          const SizedBox(width: BombFlowerSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  widget.title,
                                  style: BombFlowerTypography.h3.copyWith(
                                    color: BombFlowerColors.dangerInk,
                                  ),
                                ),
                                const SizedBox(height: BombFlowerSpacing.xs),
                                Text(
                                  widget.message,
                                  style: BombFlowerTypography.body.copyWith(
                                    color: palette.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: BombFlowerSpacing.xl),
                      Wrap(
                        spacing: BombFlowerSpacing.md,
                        runSpacing: BombFlowerSpacing.md,
                        children: <Widget>[
                          if (widget.onRetry != null)
                            BrassButton(
                              label: widget.retryLabel,
                              icon: Icons.refresh,
                              onPressed: widget.onRetry,
                            ),
                          if (details != null)
                            BrassButton(
                              label: _detailsExpanded
                                  ? 'Hide details'
                                  : 'Show details',
                              variant: BrassButtonVariant.text,
                              onPressed: () {
                                setState(
                                  () => _detailsExpanded = !_detailsExpanded,
                                );
                              },
                            ),
                          if (details != null && widget.onCopyDetails != null)
                            BrassButton(
                              label: 'Copy details',
                              variant: BrassButtonVariant.text,
                              onPressed: widget.onCopyDetails,
                            ),
                        ],
                      ),
                      if (details != null && _detailsExpanded) ...<Widget>[
                        const SizedBox(height: BombFlowerSpacing.lg),
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 132),
                          padding: const EdgeInsets.all(BombFlowerSpacing.lg),
                          decoration: BoxDecoration(
                            color: BombFlowerColors.parchmentSunken,
                            borderRadius: BorderRadius.circular(
                              BombFlowerRadii.sm,
                            ),
                            border: Border.all(
                              color: BombFlowerColors.stone.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          child: Scrollbar(
                            child: SingleChildScrollView(
                              child: SelectableText(
                                details,
                                style: BombFlowerTypography.mono.copyWith(
                                  fontSize: 11,
                                  height: 16 / 11,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorPlateGlyph extends StatelessWidget {
  const _ErrorPlateGlyph();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Error',
      child: CustomPaint(
        size: const Size.square(20),
        painter: const _ErrorPlateGlyphPainter(),
      ),
    );
  }
}

class _ErrorPlateGlyphPainter extends CustomPainter {
  const _ErrorPlateGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BombFlowerColors.danger
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, 9, paint);
    canvas.drawLine(Offset(center.dx, 5.2), Offset(center.dx, 11.2), paint);
    canvas.drawCircle(
      Offset(center.dx, 14.4),
      0.9,
      Paint()..color = BombFlowerColors.danger,
    );
  }

  @override
  bool shouldRepaint(_ErrorPlateGlyphPainter oldDelegate) => false;
}
