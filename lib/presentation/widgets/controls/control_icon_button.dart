import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../common/procedural_painters.dart';

/// Compact square icon button used by dense editing controls.
///
/// The hit target is exactly [size] (32 px by default), never a padded 48 px
/// Material button that would break the 36 px field rhythm. It is reachable by
/// Tab and activates with Enter or Space. A 2 px brass focus ring is drawn
/// outside the resting box.
class ControlIconButton extends StatefulWidget {
  const ControlIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.tooltip,
    this.size = BombFlowerSpacing.minHitTarget,
    this.iconSize = 16,
    this.autofocus = false,
    this.outlined = true,
    this.foregroundColor,
    this.focusColor,
    this.borderColor,
    this.hoverColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  /// Screen-reader name. Never pass an internal id here.
  final String semanticLabel;

  /// Pointer tooltip. Falls back to [semanticLabel].
  final String? tooltip;

  final double size;
  final double iconSize;
  final bool autofocus;
  final bool outlined;

  /// Optional overrides for dark chrome placements such as toasts.
  final Color? foregroundColor;
  final Color? focusColor;
  final Color? borderColor;
  final Color? hoverColor;

  @override
  State<ControlIconButton> createState() => _ControlIconButtonState();
}

class _ControlIconButtonState extends State<ControlIconButton> {
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
    final border = !widget.outlined
        ? Colors.transparent
        : _hovered && _enabled
        ? widget.borderColor ?? palette.borderStrong
        : widget.borderColor ?? BombFlowerColors.stone;
    final background = _pressed && _enabled
        ? BombFlowerColors.parchmentSunken
        : _hovered && _enabled
        ? widget.hoverColor ?? BombFlowerColors.parchmentRaised
        : Colors.transparent;

    final visual = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: AnimatedContainer(
              duration: duration,
              curve: BombFlowerMotion.hoverCurve,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
                border: Border.all(color: border),
              ),
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: _enabled
                    ? widget.foregroundColor ?? palette.textPrimary
                    : palette.disabledText,
              ),
            ),
          ),
          if (_focused && _enabled)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: FocusRingPainter(
                    color: widget.focusColor ?? palette.focusOnLight,
                    radius: BombFlowerRadii.sm,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: true,
      enabled: _enabled,
      focusable: _enabled,
      focused: _focused,
      label: widget.semanticLabel,
      onTap: _enabled ? _activate : null,
      excludeSemantics: true,
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
        child: Tooltip(
          message: widget.tooltip ?? widget.semanticLabel,
          excludeFromSemantics: true,
          child: MouseRegion(
            cursor: _enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _enabled ? _activate : null,
              onTapDown: _enabled
                  ? (_) => setState(() => _pressed = true)
                  : null,
              onTapUp: _enabled
                  ? (_) => setState(() => _pressed = false)
                  : null,
              onTapCancel: _enabled
                  ? () => setState(() => _pressed = false)
                  : null,
              child: visual,
            ),
          ),
        ),
      ),
    );
  }
}
