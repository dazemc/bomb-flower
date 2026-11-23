import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../common/procedural_painters.dart';

/// A 20 px rune checkbox with a brass check stroke on a parchment plate.
///
/// The mark sits inside a 32 x 32 px hit target. A null [value] with
/// [tristate] reads as mixed and cycles through null, true, false and back.
/// Space and Enter both activate it.
class RuneCheckbox extends StatefulWidget {
  const RuneCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.tristate = false,
    this.autofocus = false,
  });

  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final String? label;
  final bool tristate;
  final bool autofocus;

  static const double markSize = 20;
  static const double hitSize = BombFlowerSpacing.minHitTarget;

  static const Key markKey = ValueKey<String>('rune-checkbox-mark');
  static const Key controlKey = ValueKey<String>('rune-checkbox-control');

  @override
  State<RuneCheckbox> createState() => _RuneCheckboxState();
}

class _RuneCheckboxState extends State<RuneCheckbox> {
  bool _hovered = false;
  bool _focused = false;

  bool get _enabled => widget.onChanged != null;

  bool get _mixed => widget.tristate && widget.value == null;

  void _cycle() {
    if (!_enabled) return;
    final bool? next;
    if (!widget.tristate) {
      next = !(widget.value ?? false);
    } else if (widget.value == null) {
      next = true;
    } else if (widget.value!) {
      next = false;
    } else {
      next = null;
    }
    widget.onChanged!(next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final labelColor = _enabled ? palette.textPrimary : palette.disabledText;

    final mark = SizedBox(
      key: RuneCheckbox.controlKey,
      width: RuneCheckbox.hitSize,
      height: RuneCheckbox.hitSize,
      child: Center(
        child: SizedBox(
          width: RuneCheckbox.markSize,
          height: RuneCheckbox.markSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  key: RuneCheckbox.markKey,
                  painter: _RuneMarkPainter(
                    value: widget.value,
                    mixed: _mixed,
                    hovered: _hovered && _enabled,
                    enabled: _enabled,
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
                        radius: BombFlowerRadii.xs,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      checked: widget.value ?? false,
      mixed: _mixed,
      enabled: _enabled,
      focusable: _enabled,
      focused: _focused,
      label: widget.label ?? 'Checkbox',
      onTap: _enabled ? _cycle : null,
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
              _cycle();
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
            onTap: _enabled ? _cycle : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: RuneCheckbox.hitSize,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  mark,
                  if (widget.label != null) ...<Widget>[
                    const SizedBox(width: BombFlowerSpacing.md),
                    Flexible(
                      child: Text(
                        widget.label!,
                        style: BombFlowerTypography.body.copyWith(
                          color: labelColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RuneMarkPainter extends CustomPainter {
  const _RuneMarkPainter({
    required this.value,
    required this.mixed,
    required this.hovered,
    required this.enabled,
  });

  final bool? value;
  final bool mixed;
  final bool hovered;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.75),
      const Radius.circular(3),
    );
    final fill = !enabled
        ? BombFlowerColors.parchmentDisabled
        : (value == true || mixed)
        ? BombFlowerColors.parchmentRaised
        : BombFlowerColors.parchmentSunken;
    canvas.drawRRect(rrect, Paint()..color = fill);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hovered && enabled ? 1.6 : 1
        ..color = hovered && enabled
            ? BombFlowerColors.stoneDark
            : BombFlowerColors.stone,
    );

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = enabled
          ? BombFlowerColors.brassInk
          : BombFlowerColors.stoneLight;

    if (value == true) {
      final check = Path()
        ..moveTo(size.width * 0.26, size.height * 0.52)
        ..lineTo(size.width * 0.44, size.height * 0.7)
        ..lineTo(size.width * 0.76, size.height * 0.3);
      canvas.drawPath(check, stroke);
    } else if (mixed) {
      canvas.drawLine(
        Offset(size.width * 0.28, size.height * 0.42),
        Offset(size.width * 0.72, size.height * 0.42),
        stroke,
      );
      canvas.drawLine(
        Offset(size.width * 0.28, size.height * 0.62),
        Offset(size.width * 0.72, size.height * 0.62),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_RuneMarkPainter oldDelegate) {
    return value != oldDelegate.value ||
        mixed != oldDelegate.mixed ||
        hovered != oldDelegate.hovered ||
        enabled != oldDelegate.enabled;
  }
}
