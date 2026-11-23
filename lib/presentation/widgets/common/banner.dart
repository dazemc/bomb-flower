import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart' hide Banner;

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import 'procedural_painters.dart';

enum BannerVariant { success, warning, danger, info }

/// Inline status banner. Tinted paper surface, 3 px left accent, glyph plus
/// words, optional action and a 32 px dismiss target.
class Banner extends StatefulWidget {
  const Banner({
    super.key,
    required this.title,
    this.message,
    this.variant = BannerVariant.info,
    this.action,
    this.onDismiss,
  });

  final String title;
  final String? message;
  final BannerVariant variant;
  final Widget? action;
  final VoidCallback? onDismiss;

  @override
  State<Banner> createState() => _BannerState();
}

class _BannerState extends State<Banner> {
  bool _dismissFocused = false;

  @override
  Widget build(BuildContext context) {
    final spec = _BannerSpec.forVariant(widget.variant);
    final palette = context.bombFlowerTheme;

    return Semantics(
      container: true,
      liveRegion: true,
      explicitChildNodes: true,
      label: [
        widget.title,
        if (widget.message != null) widget.message!,
      ].join('. '),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 40),
        decoration: BoxDecoration(
          color: spec.surface,
          borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
          border: Border.all(color: spec.accent.withValues(alpha: 0.4)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: spec.accent,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(BombFlowerRadii.sm),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BombFlowerSpacing.lg,
                  vertical: BombFlowerSpacing.md,
                ),
                child: Icon(
                  switch (widget.variant) {
                    BannerVariant.success => Icons.check_circle_outline,
                    BannerVariant.warning => Icons.warning_amber_outlined,
                    BannerVariant.danger => Icons.error_outline,
                    BannerVariant.info => Icons.info_outline,
                  },
                  size: 16,
                  color: spec.accent,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: BombFlowerSpacing.md,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.title,
                        style: BombFlowerTypography.bodyStrong.copyWith(
                          fontSize: 13,
                          height: 18 / 13,
                          color: spec.ink,
                        ),
                      ),
                      if (widget.message != null)
                        Text(
                          widget.message!,
                          style: BombFlowerTypography.body.copyWith(
                            fontSize: 13,
                            height: 18 / 13,
                            color: palette.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.action != null)
                Padding(
                  padding: const EdgeInsets.only(right: BombFlowerSpacing.sm),
                  child: Center(child: widget.action),
                ),
              if (widget.onDismiss != null)
                Semantics(
                  key: const Key('banner-dismiss'),
                  button: true,
                  label: 'Dismiss notification',
                  child: FocusableActionDetector(
                    shortcuts: const <ShortcutActivator, Intent>{
                      SingleActivator(LogicalKeyboardKey.enter):
                          ActivateIntent(),
                      SingleActivator(LogicalKeyboardKey.space):
                          ActivateIntent(),
                    },
                    actions: <Type, Action<Intent>>{
                      ActivateIntent: CallbackAction<ActivateIntent>(
                        onInvoke: (_) {
                          widget.onDismiss!();
                          return null;
                        },
                      ),
                    },
                    onShowFocusHighlight: (value) {
                      setState(() => _dismissFocused = value);
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onDismiss,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            SizedBox(
                              width: BombFlowerSpacing.minHitTarget,
                              height: BombFlowerSpacing.minHitTarget,
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: palette.textMuted,
                              ),
                            ),
                            if (_dismissFocused)
                              Positioned.fill(
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
                        ),
                      ),
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

class _BannerSpec {
  const _BannerSpec({
    required this.surface,
    required this.accent,
    required this.ink,
  });

  final Color surface;
  final Color accent;
  final Color ink;

  static _BannerSpec forVariant(BannerVariant variant) {
    return switch (variant) {
      BannerVariant.success => const _BannerSpec(
        surface: BombFlowerColors.successSurface,
        accent: BombFlowerColors.success,
        ink: BombFlowerColors.successInk,
      ),
      BannerVariant.warning => const _BannerSpec(
        surface: BombFlowerColors.warningSurface,
        accent: BombFlowerColors.warning,
        ink: BombFlowerColors.warningInk,
      ),
      BannerVariant.danger => const _BannerSpec(
        surface: BombFlowerColors.dangerSurface,
        accent: BombFlowerColors.danger,
        ink: BombFlowerColors.dangerInk,
      ),
      BannerVariant.info => const _BannerSpec(
        surface: BombFlowerColors.infoSurface,
        accent: BombFlowerColors.info,
        ink: BombFlowerColors.infoInk,
      ),
    };
  }
}
