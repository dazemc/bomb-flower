import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import 'procedural_painters.dart';

/// A carved parchment sheet: stone border, one clipped page corner, optional
/// deterministic paper grain cached in a [RepaintBoundary].
///
/// Panels are flat at rest. Elevation is reserved for detached popovers and
/// modals, never in-page content.
class ParchmentPanel extends StatefulWidget {
  const ParchmentPanel({
    super.key,
    this.child,
    this.title,
    this.meta,
    this.headerAction,
    this.footer,
    this.padding = const EdgeInsets.all(BombFlowerSpacing.panelPadding),
    this.selected = false,
    this.interactive = false,
    this.onTap,
    this.grainSeed = 1,
    this.showTexture = true,
    this.backgroundColor,
  });

  final Widget? child;
  final String? title;
  final String? meta;
  final Widget? headerAction;
  final Widget? footer;

  /// Padding around [child]. Ignored when [child] is null.
  final EdgeInsetsGeometry padding;
  final bool selected;
  final bool interactive;
  final VoidCallback? onTap;
  final int grainSeed;
  final bool showTexture;
  final Color? backgroundColor;

  @override
  State<ParchmentPanel> createState() => _ParchmentPanelState();
}

class _ParchmentPanelState extends State<ParchmentPanel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final interactive = widget.interactive && widget.onTap != null;
    final restingBorder = widget.selected ? palette.accentInk : palette.border;
    final border = interactive && _hovered
        ? palette.borderStrong
        : restingBorder;

    return Semantics(
      container: true,
      button: interactive ? true : null,
      label: widget.title,
      onTap: interactive ? widget.onTap : null,
      child: MouseRegion(
        cursor: interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: interactive ? (_) => setState(() => _hovered = true) : null,
        onExit: interactive ? (_) => setState(() => _hovered = false) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: interactive ? widget.onTap : null,
          child: RepaintBoundary(
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: border),
              duration: BombFlowerMotion.adaptive(
                context,
                BombFlowerMotion.hover,
              ),
              builder: (context, animatedBorder, child) {
                return CustomPaint(
                  painter: ParchmentTexturePainter(
                    fill: widget.backgroundColor ?? palette.surface,
                    seed: widget.grainSeed,
                    borderColor: animatedBorder ?? border,
                    selected: widget.selected,
                    showTexture: widget.showTexture,
                  ),
                  child: child,
                );
              },
              child: ClipPath(
                clipper: const ParchmentClipper(),
                child: _buildContents(context, palette),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContents(BuildContext context, BombFlowerTheme palette) {
    final hasHeader = widget.title != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (hasHeader) ...<Widget>[
          SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: BombFlowerSpacing.xl,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.title!,
                      style: BombFlowerTypography.h3.copyWith(
                        color: palette.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.meta != null) ...<Widget>[
                    const SizedBox(width: BombFlowerSpacing.md),
                    Text(
                      widget.meta!,
                      style: BombFlowerTypography.caption.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                  if (widget.headerAction != null) ...<Widget>[
                    const SizedBox(width: BombFlowerSpacing.md),
                    widget.headerAction!,
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: BombFlowerColors.divider),
        ],
        if (widget.child != null)
          Padding(padding: widget.padding, child: widget.child),
        if (widget.footer != null) ...<Widget>[
          const Divider(height: 1, color: BombFlowerColors.divider),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BombFlowerSpacing.xl,
              vertical: BombFlowerSpacing.lg,
            ),
            child: widget.footer,
          ),
        ],
      ],
    );
  }
}
