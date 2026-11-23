import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import 'procedural_painters.dart';

enum BrassButtonVariant { primary, secondary, destructive, text }

/// Carved brass / stone button with explicit rest, hover, pressed, disabled,
/// and keyboard-focus states.
///
/// [onPressed] being null disables the control: it leaves the tab order, keeps
/// its semantics, and uses a hatch instead of opacity reduction.
///
/// [height] and [iconSize] exist so one invitation can be deliberately larger
/// than the 36 px, 16 px-icon default without changing that default anywhere.
class BrassButton extends StatefulWidget {
  const BrassButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = BrassButtonVariant.primary,
    this.icon,
    this.semanticsLabel,
    this.autofocus = false,
    this.minWidth,
    this.height,
    this.iconSize,
    this.onDark = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final BrassButtonVariant variant;
  final IconData? icon;
  final String? semanticsLabel;
  final bool autofocus;
  final double? minWidth;

  /// Control height; null keeps [BombFlowerSpacing.buttonHeight].
  final double? height;

  /// Leading icon size; null keeps the 16 px default.
  final double? iconSize;

  /// Whether the control is painted over the dark canopy, not parchment.
  ///
  /// Only the transparent-background variants change: secondary and text use
  /// the on-dark ink pair, secondary gets a lighter border, and the secondary
  /// hover/pressed wash becomes the dark-surface overlay. Filled variants and
  /// the disabled state keep their tokens, so parchment call sites are
  /// unaffected by the default `false`.
  final bool onDark;

  @override
  State<BrassButton> createState() => _BrassButtonState();
}

class _BrassButtonState extends State<BrassButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  void _activate() {
    if (_enabled) widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final duration = BombFlowerMotion.adaptive(context, BombFlowerMotion.hover);
    final background = _background(palette);
    final foreground = _foreground(palette);
    final border = _border(palette);
    final gradient = _gradient();
    final radius = BorderRadius.circular(BombFlowerRadii.sm);

    final button = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        AnimatedScale(
          scale: _pressed && _enabled ? 0.99 : 1,
          duration: BombFlowerMotion.adaptive(context, BombFlowerMotion.press),
          curve: BombFlowerMotion.pressCurve,
          child: AnimatedContainer(
            duration: duration,
            curve: BombFlowerMotion.hoverCurve,
            height: widget.height ?? BombFlowerSpacing.buttonHeight,
            constraints: BoxConstraints(
              minWidth: widget.minWidth ?? BombFlowerSpacing.minHitTarget,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: BombFlowerSpacing.xl,
            ),
            decoration: BoxDecoration(
              color: gradient == null ? background : null,
              gradient: gradient,
              borderRadius: radius,
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (widget.icon != null) ...<Widget>[
                  Icon(
                    widget.icon,
                    size: widget.iconSize ?? 16,
                    color: foreground,
                  ),
                  const SizedBox(width: BombFlowerSpacing.md),
                ],
                Text(
                  widget.label,
                  style: BombFlowerTypography.button.copyWith(
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!_enabled)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: const HatchPainter(
                  radius: BombFlowerRadii.sm,
                  color: BombFlowerColors.ink,
                ),
              ),
            ),
          ),
        if (_focused && _enabled)
          Positioned(
            left: -3,
            top: -3,
            right: -3,
            bottom: -3,
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
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticsLabel ?? widget.label,
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
              _activate();
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
            onTap: _enabled ? _activate : null,
            onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel: _enabled
                ? () => setState(() => _pressed = false)
                : null,
            child: button,
          ),
        ),
      ),
    );
  }

  Color _background(BombFlowerTheme palette) {
    if (!_enabled) return palette.disabledSurface;
    return switch (widget.variant) {
      BrassButtonVariant.primary => Colors.transparent,
      BrassButtonVariant.secondary =>
        widget.onDark
            ? (_pressed || _hovered
                  ? BombFlowerColors.hoverDark
                  : Colors.transparent)
            : _pressed
            ? BombFlowerColors.parchmentSunken
            : _hovered
            ? BombFlowerColors.parchmentRaised
            : Colors.transparent,
      BrassButtonVariant.destructive =>
        _pressed
            ? BombFlowerColors.dangerPressed
            : BombFlowerColors.dangerStrong,
      BrassButtonVariant.text =>
        _pressed
            ? BombFlowerColors.parchmentSunken
            : _hovered
            ? BombFlowerColors.hoverPaper
            : Colors.transparent,
    };
  }

  Color _foreground(BombFlowerTheme palette) {
    if (!_enabled) return palette.disabledText;
    return switch (widget.variant) {
      BrassButtonVariant.primary => BombFlowerColors.ink,
      BrassButtonVariant.secondary =>
        widget.onDark ? palette.textOnDark : palette.textPrimary,
      BrassButtonVariant.destructive => BombFlowerColors.bone,
      BrassButtonVariant.text =>
        widget.onDark ? palette.textOnDark : palette.accentInk,
    };
  }

  Color _border(BombFlowerTheme palette) {
    if (!_enabled) {
      return BombFlowerColors.stone.withValues(alpha: 0.5);
    }
    return switch (widget.variant) {
      BrassButtonVariant.primary => BombFlowerColors.brassInk,
      BrassButtonVariant.secondary =>
        widget.onDark ? BombFlowerColors.stoneLight : palette.border,
      BrassButtonVariant.destructive => BombFlowerColors.danger,
      BrassButtonVariant.text => Colors.transparent,
    };
  }

  Gradient? _gradient() {
    if (!_enabled || widget.variant != BrassButtonVariant.primary) {
      return null;
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: _pressed
          ? const <Color>[
              BombFlowerColors.brassPressed,
              BombFlowerColors.brass,
              BombFlowerColors.brassDeep,
            ]
          : _hovered
          ? const <Color>[
              BombFlowerColors.brassHover,
              BombFlowerColors.brassHover,
              BombFlowerColors.brass,
              BombFlowerColors.brassDeep,
            ]
          : const <Color>[
              BombFlowerColors.brassDeep,
              BombFlowerColors.brassHover,
              BombFlowerColors.brass,
              BombFlowerColors.brassDeep,
            ],
      stops: _pressed
          ? const <double>[0, 0.55, 1]
          : _hovered
          ? const <double>[0, 0.35, 0.72, 1]
          : const <double>[0, 0.35, 0.55, 1],
    );
  }
}
