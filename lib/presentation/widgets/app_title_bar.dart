import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';

/// Height of the custom title bar, in logical pixels.
const double kAppTitleBarHeight = 44;

/// Custom window chrome for the frameless Linux window.
///
/// Set [interactive] to false in widget tests: the bar still lays out and
/// responds visually, but never touches the native bitsdojo window.
class AppTitleBar extends StatelessWidget {
  const AppTitleBar({super.key, this.interactive = true});

  final bool interactive;

  void _startDragging() {
    if (interactive) appWindow.startDragging();
  }

  void _minimize() {
    if (interactive) appWindow.minimize();
  }

  void _maximizeOrRestore() {
    if (interactive) appWindow.maximizeOrRestore();
  }

  void _close() {
    if (interactive) appWindow.close();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kAppTitleBarHeight,
      child: Material(
        color: const Color(0xFF173A28),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _startDragging(),
          onDoubleTap: _maximizeOrRestore,
          child: Row(
            children: [
              const SizedBox(width: 14),
              const Icon(
                Icons.local_florist,
                size: 16,
                color: Color(0xFF8FD6A8),
              ),
              const SizedBox(width: 8),
              const Text(
                'Bomb Flower',
                style: TextStyle(
                  color: Color(0xFFE6EFE3),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              _TitleBarButton(
                tooltip: 'Minimize',
                icon: Icons.remove,
                onPressed: _minimize,
              ),
              _TitleBarButton(
                tooltip: 'Maximize',
                icon: Icons.crop_square,
                onPressed: _maximizeOrRestore,
              ),
              _TitleBarButton(
                tooltip: 'Close',
                icon: Icons.close,
                onPressed: _close,
                danger: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleBarButton extends StatefulWidget {
  const _TitleBarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.danger
        ? const Color(0xFFA33A3A)
        : const Color(0xFF24513A);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onPressed,
          hoverColor: Colors.transparent,
          child: Container(
            width: 46,
            height: kAppTitleBarHeight,
            color: _hovered ? hoverColor : Colors.transparent,
            child: Icon(widget.icon, size: 16, color: const Color(0xFFE6EFE3)),
          ),
        ),
      ),
    );
  }
}
