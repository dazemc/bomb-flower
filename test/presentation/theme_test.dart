import 'package:bomb_flower/presentation/theme/bomb_flower_colors.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_spacing.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_typography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('palette', () {
    test('ports all 60 Deep Canopy tokens in order', () {
      const expected = <int>[
        0xFF101A12,
        0xFF16241B,
        0xFF1E2F23,
        0xFF22352A,
        0xFF2A4031,
        0xB80A0F0B,
        0xFF0B120C,
        0xFFEFE3C8,
        0xFFF6EDD8,
        0xFFE3D3B0,
        0xFFE8DABC,
        0xFFD8C9A9,
        0xFF6E6A5C,
        0xFFA39C89,
        0xFF4A473D,
        0xFF4A3423,
        0xFF6B4A2F,
        0xFF2E2016,
        0xFF8A6A45,
        0xFFC9BCA1,
        0xFF33463A,
        0xFFC9A227,
        0xFFE2C257,
        0xFFA8861C,
        0xFF6B4E00,
        0xFFF0C75E,
        0xFF7A5A00,
        0xFF241C12,
        0xFFE8CD7A,
        0xFF5C4A1E,
        0xFFA5811E,
        0xFF241C12,
        0xFF4A3D2A,
        0xFF5C4F3A,
        0xFFF2EAD9,
        0xFFA9B5A2,
        0xFF5C4F3A,
        0xFF8A9587,
        0xFF2F6B45,
        0xFF8FC9A3,
        0xFFDDEDD9,
        0xFF24543A,
        0xFF8A5A12,
        0xFFE0B45E,
        0xFFF3E2B8,
        0xFF6B4508,
        0xFFA63A2E,
        0xFF8E2F24,
        0xFF7A241B,
        0xFFE88B7D,
        0xFFF2D9D3,
        0xFF8E2F24,
        0xFF2E5F7A,
        0xFF8FC3DD,
        0xFFD9E8EF,
        0xFF244C63,
        0xFFA63A2E,
        0xFF6E6A5C,
        0x0F241C12,
        0x14F2EAD9,
      ];

      expect(BombFlowerColors.all, hasLength(60));
      expect(
        BombFlowerColors.all.map((color) => color.toARGB32()).toList(),
        expected,
      );
    });

    test('role aliases preserve the contract values', () {
      expect(BombFlowerColors.canopy0, const Color(0xFF101A12));
      expect(BombFlowerColors.parchment, const Color(0xFFEFE3C8));
      expect(BombFlowerColors.stone, const Color(0xFF6E6A5C));
      expect(BombFlowerColors.wood, const Color(0xFF4A3423));
      expect(BombFlowerColors.brass, const Color(0xFFC9A227));
      expect(BombFlowerColors.brassInk, const Color(0xFF6B4E00));
      expect(BombFlowerColors.ink, const Color(0xFF241C12));
      expect(BombFlowerColors.bone, const Color(0xFFF2EAD9));
      expect(BombFlowerColors.dangerStrong, const Color(0xFF8E2F24));
    });
  });

  group('type, space, motion', () {
    test('type scale matches the design contract', () {
      expect(BombFlowerTypography.displayFamily, 'Noto Serif');
      expect(BombFlowerTypography.bodyFamily, 'Noto Sans');
      expect(BombFlowerTypography.monoFamily, 'Noto Sans Mono');

      expect(BombFlowerTypography.display.fontSize, 36);
      expect(BombFlowerTypography.display.height, closeTo(44 / 36, 0.0001));
      expect(BombFlowerTypography.display.fontWeight, FontWeight.w600);
      expect(BombFlowerTypography.h1.fontSize, 28);
      expect(BombFlowerTypography.h1.height, closeTo(34 / 28, 0.0001));
      expect(BombFlowerTypography.h2.fontSize, 22);
      expect(BombFlowerTypography.h3.fontSize, 18);
      expect(BombFlowerTypography.body.fontSize, 14);
      expect(BombFlowerTypography.body.height, closeTo(21 / 14, 0.0001));
      expect(BombFlowerTypography.label.fontSize, 12);
      expect(BombFlowerTypography.button.fontSize, 13);
      expect(BombFlowerTypography.table.fontSize, 13);
      expect(BombFlowerTypography.table.fontFeatures, isNotEmpty);
      expect(
        BombFlowerTypography.mono.fontFamily,
        BombFlowerTypography.monoFamily,
      );
      expect(BombFlowerTypography.caption.fontSize, 11);
      expect(BombFlowerTypography.overline.fontSize, 10);
      expect(BombFlowerTypography.overline.fontWeight, FontWeight.w700);
    });

    test('spacing, shell, radii, and motion tokens are present', () {
      expect(BombFlowerSpacing.titleBarHeight, 44);
      expect(BombFlowerSpacing.footerHeight, 28);
      expect(BombFlowerSpacing.navRailWidth, 232);
      expect(BombFlowerSpacing.navRailIconOnlyWidth, 64);
      expect(BombFlowerSpacing.minWindowWidth, 1100);
      expect(BombFlowerSpacing.minWindowHeight, 700);
      expect(BombFlowerSpacing.contentMaxWidth, 1680);
      expect(BombFlowerSpacing.compactBreakpoint, 1280);
      expect(BombFlowerSpacing.buttonHeight, 36);
      expect(BombFlowerSpacing.minHitTarget, 32);
      expect(BombFlowerRadii.md, 6);
      expect(BombFlowerRadii.panelNotch, 8);
      expect(BombFlowerMotion.tabMs, 180);
      expect(BombFlowerMotion.runePulseMs, 1800);
      expect(BombFlowerMotion.reducedMotionMs, 80);
      expect(BombFlowerMotion.standardCurve, const Cubic(0.2, 0.7, 0.2, 1.0));
    });
  });

  group('ThemeData', () {
    late ThemeData theme;

    setUp(() {
      theme = BombFlowerThemeData.build();
    });

    test('binds shell surfaces, text, and interaction colors', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, BombFlowerColors.canopy0);
      expect(theme.canvasColor, BombFlowerColors.canopy1);
      expect(theme.cardColor, BombFlowerColors.parchment);
      expect(theme.dividerColor, BombFlowerColors.stone);
      expect(theme.focusColor, BombFlowerColors.brassFocus);
      expect(theme.hoverColor, BombFlowerColors.hoverPaper);
      expect(theme.highlightColor, Colors.transparent);
      expect(theme.colorScheme.error, BombFlowerColors.danger);
      expect(theme.disabledColor, BombFlowerColors.textDisabled);
      expect(theme.visualDensity, VisualDensity.compact);
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(theme.splashFactory, NoSplash.splashFactory);
    });

    test('has no default Material purple in the color scheme', () {
      const defaultPurples = <int>{
        0xFF6750A4,
        0xFF9A82DB,
        0xFFD0BCFF,
        0xFF7F67BE,
        0xFFEADDFF,
        0xFF21005D,
        0xFF4F378B,
        0xFFE8DEF8,
        0xFF1D192B,
      };
      final scheme = theme.colorScheme;
      final usedColors = <Color>[
        scheme.primary,
        scheme.onPrimary,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        scheme.secondary,
        scheme.onSecondary,
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        scheme.tertiary,
        scheme.onTertiary,
        scheme.error,
        scheme.onError,
        scheme.errorContainer,
        scheme.onErrorContainer,
        scheme.surface,
        scheme.onSurface,
        scheme.outline,
        scheme.shadow,
        scheme.scrim,
        scheme.inverseSurface,
        scheme.inversePrimary,
        scheme.surfaceTint,
      ];

      expect(
        usedColors
            .map((color) => color.toARGB32())
            .toSet()
            .intersection(defaultPurples),
        isEmpty,
      );
      expect(scheme.primary, BombFlowerColors.brass);
      expect(scheme.onPrimary, BombFlowerColors.ink);
      expect(scheme.surface, BombFlowerColors.parchment);
      expect(scheme.onSurface, BombFlowerColors.ink);
      expect(scheme.error, BombFlowerColors.danger);
      expect(scheme.primaryContainer, BombFlowerColors.selection);
      expect(scheme.outline, BombFlowerColors.stone);
      expect(scheme.surfaceTint, Colors.transparent);
    });

    test('maps the full text theme to the type scale', () {
      final text = theme.textTheme;
      expect(text.displayLarge?.fontFamily, 'Noto Serif');
      expect(text.displayLarge?.fontSize, 36);
      expect(text.displayLarge?.height, closeTo(44 / 36, 0.0001));
      expect(text.headlineMedium?.fontSize, 28);
      expect(text.titleLarge?.fontSize, 22);
      expect(text.titleMedium?.fontSize, 18);
      expect(text.bodyMedium?.fontSize, 14);
      expect(text.bodySmall?.fontSize, 11);
      expect(text.labelLarge?.fontSize, 13);
      expect(text.labelMedium?.fontSize, 12);
      expect(text.labelSmall?.fontSize, 10);
      expect(text.labelSmall?.letterSpacing, 1.2);
      expect(text.bodyMedium?.color, BombFlowerColors.ink);
      expect(text.bodySmall?.color, BombFlowerColors.inkMuted);
    });

    test('binds inputs, selection, tooltip, scrollbar, and dialogs', () {
      final input = theme.inputDecorationTheme;
      expect(input.filled, isTrue);
      expect(input.fillColor, BombFlowerColors.parchmentRaised);
      expect(input.constraints?.minHeight, 36);
      final enabledBorder = input.enabledBorder! as OutlineInputBorder;
      expect(enabledBorder.borderSide.color, BombFlowerColors.stone);
      expect(enabledBorder.borderRadius, BorderRadius.circular(4));
      final focusedBorder = input.focusedBorder! as OutlineInputBorder;
      expect(focusedBorder.borderSide.width, 2);
      expect(focusedBorder.borderSide.color, BombFlowerColors.focusOnLight);
      final errorBorder = input.errorBorder! as OutlineInputBorder;
      expect(errorBorder.borderSide.color, BombFlowerColors.danger);

      expect(
        theme.textSelectionTheme.selectionColor,
        BombFlowerColors.selection,
      );
      expect(theme.textSelectionTheme.cursorColor, BombFlowerColors.brassInk);

      final tooltipDecoration = theme.tooltipTheme.decoration! as BoxDecoration;
      expect(tooltipDecoration.color, BombFlowerColors.canopy2);
      final tooltipBorder = tooltipDecoration.border! as Border;
      expect(tooltipBorder.top.color, BombFlowerColors.stoneLight);
      expect(theme.tooltipTheme.textStyle?.color, BombFlowerColors.bone);

      expect(
        theme.scrollbarTheme.thumbColor?.resolve(<WidgetState>{}),
        BombFlowerColors.stone,
      );
      expect(theme.scrollbarTheme.thickness?.resolve(<WidgetState>{}), 10);
      expect(theme.scrollbarTheme.radius, const Radius.circular(5));

      expect(theme.dialogTheme.backgroundColor, BombFlowerColors.parchment);
      final dialogShape = theme.dialogTheme.shape! as RoundedRectangleBorder;
      expect(dialogShape.borderRadius, BorderRadius.circular(6));
      expect(dialogShape.side.color, BombFlowerColors.stone);
    });

    test('exposes the semantic theme extension and lerp', () {
      final extension = theme.extension<BombFlowerTheme>();
      expect(extension, isNotNull);
      expect(extension, BombFlowerTheme.standard);
      expect(extension!.surface, BombFlowerColors.parchment);
      expect(extension.border, BombFlowerColors.stone);
      expect(extension.accent, BombFlowerColors.brass);

      final lighter = extension.copyWith(
        surface: BombFlowerColors.parchmentRaised,
      );
      final lerped = extension.lerp(lighter, 0.5);
      expect(lerped.surface, isNot(extension.surface));
      expect(lerped.surface, isNot(lighter.surface));
    });
  });
}
