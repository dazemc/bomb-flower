import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import 'control_icon_button.dart';

/// Tone for a [StoneToast]. Every tone also prints a word and a distinct glyph.
enum StoneToastTone { success, info, warning, danger }

extension StoneToastTonePresentation on StoneToastTone {
  String get label {
    return switch (this) {
      StoneToastTone.success => 'Success',
      StoneToastTone.info => 'Notice',
      StoneToastTone.warning => 'Warning',
      StoneToastTone.danger => 'Error',
    };
  }

  IconData get icon {
    return switch (this) {
      StoneToastTone.success => Icons.check_circle_outline,
      StoneToastTone.info => Icons.info_outline,
      StoneToastTone.warning => Icons.warning_amber_outlined,
      StoneToastTone.danger => Icons.error_outline,
    };
  }
}

/// A stone-and-parchment notification card. Use [ToastHost] to queue it; this
/// widget is public so a tab can render a static example if needed.
class StoneToast extends StatelessWidget {
  const StoneToast({
    super.key,
    required this.message,
    required this.tone,
    this.onDismiss,
    this.dismissButtonKey,
  });

  final String message;
  final StoneToastTone tone;
  final VoidCallback? onDismiss;
  final Key? dismissButtonKey;

  static const Key messageKey = ValueKey<String>('stone-toast-message');

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final accent = _toneColor(tone);
    final border = _toneBorder(tone, palette);

    return Container(
      decoration: BoxDecoration(
        color: palette.chromeRaised,
        borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
        border: Border.all(color: border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: BombFlowerColors.shadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(
        BombFlowerSpacing.lg,
        BombFlowerSpacing.md,
        BombFlowerSpacing.md,
        BombFlowerSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(tone.icon, size: 18, color: accent),
          ),
          const SizedBox(width: BombFlowerSpacing.md),
          Expanded(
            child: Semantics(
              key: StoneToast.messageKey,
              container: true,
              liveRegion: true,
              label: '${tone.label}: $message',
              excludeSemantics: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    tone.label.toUpperCase(),
                    style: BombFlowerTypography.overline.copyWith(
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: BombFlowerSpacing.xxs),
                  Text(
                    message,
                    style: BombFlowerTypography.body.copyWith(
                      color: palette.textOnDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onDismiss != null) ...<Widget>[
            const SizedBox(width: BombFlowerSpacing.sm),
            ControlIconButton(
              key: dismissButtonKey,
              icon: Icons.close,
              size: BombFlowerSpacing.minHitTarget,
              iconSize: 15,
              semanticLabel: 'Dismiss ${tone.label.toLowerCase()} notification',
              tooltip: 'Dismiss',
              foregroundColor: palette.textOnDark,
              focusColor: palette.focus,
              borderColor: BombFlowerColors.stoneLight,
              hoverColor: palette.chromeRaised,
              onPressed: onDismiss,
            ),
          ],
        ],
      ),
    );
  }

  Color _toneColor(StoneToastTone tone) {
    return switch (tone) {
      StoneToastTone.success => BombFlowerColors.successLight,
      StoneToastTone.info => BombFlowerColors.infoLight,
      StoneToastTone.warning => BombFlowerColors.warningLight,
      StoneToastTone.danger => BombFlowerColors.dangerLight,
    };
  }

  Color _toneBorder(StoneToastTone tone, BombFlowerTheme palette) {
    return switch (tone) {
      StoneToastTone.success => palette.success,
      StoneToastTone.info => palette.info,
      StoneToastTone.warning => palette.warning,
      StoneToastTone.danger => palette.danger,
    };
  }
}

class _ToastRequest {
  const _ToastRequest({
    required this.id,
    required this.message,
    required this.tone,
    required this.duration,
  });

  final int id;
  final String message;
  final StoneToastTone tone;
  final Duration duration;
}

/// Overlay queue for [StoneToast], independent of [ScaffoldMessenger].
///
/// New toasts appear bottom-right, at most three at once; further requests wait
/// in a FIFO queue. Each visible toast auto-dismisses after its duration unless
/// the pointer is over it or keyboard focus is inside it. The dismiss button
/// remains available throughout.
class ToastHost extends StatefulWidget {
  const ToastHost({
    super.key,
    required this.child,
    this.maxVisible = 3,
    this.defaultDuration = const Duration(seconds: 4),
  }) : assert(maxVisible >= 1 && maxVisible <= 3, 'maxVisible is 1..3');

  final Widget child;
  final int maxVisible;
  final Duration defaultDuration;

  static Key dismissKey(int id) => ValueKey<String>('stone-toast-dismiss-$id');

  /// The nearest host state, if this context is below a [ToastHost].
  static ToastHostState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<ToastHostState>();
  }

  static ToastHostState of(BuildContext context) {
    final state = maybeOf(context);
    if (state == null) {
      throw FlutterError(
        'ToastHost.of() was called with a context that does not contain a '
        'ToastHost. Wrap the subtree in a ToastHost first.',
      );
    }
    return state;
  }

  @override
  State<ToastHost> createState() => ToastHostState();
}

class ToastHostState extends State<ToastHost> {
  final List<_ToastRequest> _visible = <_ToastRequest>[];
  final List<_ToastRequest> _pending = <_ToastRequest>[];
  int _nextId = 0;

  int get visibleCount => _visible.length;
  int get pendingCount => _pending.length;

  /// Enqueues a toast and returns its id. At most [ToastHost.maxVisible] are
  /// rendered; the rest wait in order.
  int show(
    String message, {
    StoneToastTone tone = StoneToastTone.info,
    Duration? duration,
  }) {
    final request = _ToastRequest(
      id: _nextId++,
      message: message,
      tone: tone,
      duration: duration ?? widget.defaultDuration,
    );
    setState(() {
      if (_visible.length < widget.maxVisible) {
        _visible.add(request);
      } else {
        _pending.add(request);
      }
    });
    return request.id;
  }

  /// Dismisses a visible toast or cancels a queued one.
  void dismiss(int id) {
    setState(() {
      final visibleAt = _visible.indexWhere((toast) => toast.id == id);
      if (visibleAt >= 0) {
        _visible.removeAt(visibleAt);
        _promotePending();
        return;
      }
      _pending.removeWhere((toast) => toast.id == id);
    });
  }

  void dismissAll() {
    setState(() {
      _visible.clear();
      _pending.clear();
    });
  }

  void _promotePending() {
    while (_visible.length < widget.maxVisible && _pending.isNotEmpty) {
      _visible.add(_pending.removeAt(0));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _visible.isEmpty,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final available = math.max(
                  1.0,
                  constraints.maxWidth - BombFlowerSpacing.huge,
                );
                final width = math.min(420.0, available);
                return Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(BombFlowerSpacing.xl),
                    child: SizedBox(
                      width: width,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (var index = 0; index < _visible.length; index++)
                            Padding(
                              padding: EdgeInsets.only(
                                top: index == 0 ? 0 : BombFlowerSpacing.md,
                              ),
                              child: _TimedToast(
                                key: ValueKey<int>(_visible[index].id),
                                request: _visible[index],
                                dismissKey: ToastHost.dismissKey(
                                  _visible[index].id,
                                ),
                                onDismiss: () => dismiss(_visible[index].id),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TimedToast extends StatefulWidget {
  const _TimedToast({
    super.key,
    required this.request,
    required this.dismissKey,
    required this.onDismiss,
  });

  final _ToastRequest request;
  final Key dismissKey;
  final VoidCallback onDismiss;

  @override
  State<_TimedToast> createState() => _TimedToastState();
}

class _TimedToastState extends State<_TimedToast> {
  Timer? _timer;
  bool _hovered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (_hovered || _focused) return;
    _timer = Timer(widget.request.duration, widget.onDismiss);
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (_focused == focused) return;
        _focused = focused;
        if (focused) {
          _pause();
        } else {
          _restartTimer();
        }
      },
      child: MouseRegion(
        onEnter: (_) {
          if (_hovered) return;
          _hovered = true;
          _pause();
        },
        onExit: (_) {
          if (!_hovered) return;
          _hovered = false;
          _restartTimer();
        },
        child: StoneToast(
          message: widget.request.message,
          tone: widget.request.tone,
          dismissButtonKey: widget.dismissKey,
          onDismiss: widget.onDismiss,
        ),
      ),
    );
  }
}
