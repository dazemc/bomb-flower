import 'package:material_ui/material_ui.dart';

import 'bomb_flower_colors.dart';
import 'bomb_flower_spacing.dart';
import 'bomb_flower_typography.dart';

/// Semantic Bomb Flower surface bundle.
///
/// This wraps the design-token contract as a [ThemeExtension] so widgets can
/// read parchment, stone, wood, and brass roles without reaching into the raw
/// [BombFlowerColors] constants. The palette is the single source of truth; the
/// extension only names roles.
class BombFlowerTheme extends ThemeExtension<BombFlowerTheme> {
  const BombFlowerTheme({
    this.background = BombFlowerColors.canopy0,
    this.chrome = BombFlowerColors.canopy1,
    this.chromeRaised = BombFlowerColors.canopy2,
    this.surface = BombFlowerColors.parchment,
    this.surfaceRaised = BombFlowerColors.parchmentRaised,
    this.surfaceSunken = BombFlowerColors.parchmentSunken,
    this.border = BombFlowerColors.stone,
    this.borderStrong = BombFlowerColors.stoneDark,
    this.wood = BombFlowerColors.wood,
    this.woodDark = BombFlowerColors.woodDark,
    this.accent = BombFlowerColors.brass,
    this.accentHover = BombFlowerColors.brassHover,
    this.accentPressed = BombFlowerColors.brassPressed,
    this.accentInk = BombFlowerColors.brassInk,
    this.textPrimary = BombFlowerColors.ink,
    this.textSecondary = BombFlowerColors.inkSecondary,
    this.textMuted = BombFlowerColors.inkMuted,
    this.textOnDark = BombFlowerColors.bone,
    this.textMutedOnDark = BombFlowerColors.boneMuted,
    this.focus = BombFlowerColors.brassFocus,
    this.focusOnLight = BombFlowerColors.focusOnLight,
    this.selection = BombFlowerColors.selection,
    this.selectionInk = BombFlowerColors.ink,
    this.disabledSurface = BombFlowerColors.parchmentDisabled,
    this.disabledText = BombFlowerColors.textDisabled,
    this.success = BombFlowerColors.success,
    this.warning = BombFlowerColors.warning,
    this.danger = BombFlowerColors.danger,
    this.info = BombFlowerColors.info,
    this.textScale = 1,
    this.density = 1,
  });

  final Color background;
  final Color chrome;
  final Color chromeRaised;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color border;
  final Color borderStrong;
  final Color wood;
  final Color woodDark;
  final Color accent;
  final Color accentHover;
  final Color accentPressed;
  final Color accentInk;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textOnDark;
  final Color textMutedOnDark;
  final Color focus;
  final Color focusOnLight;
  final Color selection;
  final Color selectionInk;
  final Color disabledSurface;
  final Color disabledText;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final double textScale;
  final double density;

  static const BombFlowerTheme standard = BombFlowerTheme();

  @override
  BombFlowerTheme copyWith({
    Color? background,
    Color? chrome,
    Color? chromeRaised,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? border,
    Color? borderStrong,
    Color? wood,
    Color? woodDark,
    Color? accent,
    Color? accentHover,
    Color? accentPressed,
    Color? accentInk,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textOnDark,
    Color? textMutedOnDark,
    Color? focus,
    Color? focusOnLight,
    Color? selection,
    Color? selectionInk,
    Color? disabledSurface,
    Color? disabledText,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    double? textScale,
    double? density,
  }) {
    return BombFlowerTheme(
      background: background ?? this.background,
      chrome: chrome ?? this.chrome,
      chromeRaised: chromeRaised ?? this.chromeRaised,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      wood: wood ?? this.wood,
      woodDark: woodDark ?? this.woodDark,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentPressed: accentPressed ?? this.accentPressed,
      accentInk: accentInk ?? this.accentInk,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textOnDark: textOnDark ?? this.textOnDark,
      textMutedOnDark: textMutedOnDark ?? this.textMutedOnDark,
      focus: focus ?? this.focus,
      focusOnLight: focusOnLight ?? this.focusOnLight,
      selection: selection ?? this.selection,
      selectionInk: selectionInk ?? this.selectionInk,
      disabledSurface: disabledSurface ?? this.disabledSurface,
      disabledText: disabledText ?? this.disabledText,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      textScale: textScale ?? this.textScale,
      density: density ?? this.density,
    );
  }

  @override
  BombFlowerTheme lerp(covariant BombFlowerTheme? other, double t) {
    if (other == null) return this;
    return BombFlowerTheme(
      background: _lerpColor(background, other.background, t),
      chrome: _lerpColor(chrome, other.chrome, t),
      chromeRaised: _lerpColor(chromeRaised, other.chromeRaised, t),
      surface: _lerpColor(surface, other.surface, t),
      surfaceRaised: _lerpColor(surfaceRaised, other.surfaceRaised, t),
      surfaceSunken: _lerpColor(surfaceSunken, other.surfaceSunken, t),
      border: _lerpColor(border, other.border, t),
      borderStrong: _lerpColor(borderStrong, other.borderStrong, t),
      wood: _lerpColor(wood, other.wood, t),
      woodDark: _lerpColor(woodDark, other.woodDark, t),
      accent: _lerpColor(accent, other.accent, t),
      accentHover: _lerpColor(accentHover, other.accentHover, t),
      accentPressed: _lerpColor(accentPressed, other.accentPressed, t),
      accentInk: _lerpColor(accentInk, other.accentInk, t),
      textPrimary: _lerpColor(textPrimary, other.textPrimary, t),
      textSecondary: _lerpColor(textSecondary, other.textSecondary, t),
      textMuted: _lerpColor(textMuted, other.textMuted, t),
      textOnDark: _lerpColor(textOnDark, other.textOnDark, t),
      textMutedOnDark: _lerpColor(textMutedOnDark, other.textMutedOnDark, t),
      focus: _lerpColor(focus, other.focus, t),
      focusOnLight: _lerpColor(focusOnLight, other.focusOnLight, t),
      selection: _lerpColor(selection, other.selection, t),
      selectionInk: _lerpColor(selectionInk, other.selectionInk, t),
      disabledSurface: _lerpColor(disabledSurface, other.disabledSurface, t),
      disabledText: _lerpColor(disabledText, other.disabledText, t),
      success: _lerpColor(success, other.success, t),
      warning: _lerpColor(warning, other.warning, t),
      danger: _lerpColor(danger, other.danger, t),
      info: _lerpColor(info, other.info, t),
      textScale: _lerpDouble(textScale, other.textScale, t),
      density: _lerpDouble(density, other.density, t),
    );
  }

  static Color _lerpColor(Color a, Color b, double t) {
    return Color.lerp(a, b, t) ?? a;
  }

  static double _lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }
}

/// Read the semantic Bomb Flower surface bundle from the ambient theme.
extension BombFlowerThemeAccess on BuildContext {
  BombFlowerTheme get bombFlowerTheme {
    return Theme.of(this).extension<BombFlowerTheme>() ??
        BombFlowerTheme.standard;
  }
}

/// Builds the single Bomb Flower [ThemeData].
///
/// Every slot that stock Material would otherwise seed with purple is bound
/// explicitly to a design token. The app never uses stock AppBar, Card, FAB,
/// NavigationRail, or SnackBar chrome; those slots exist only so third-party
/// behaviour primitives cannot leak the default look.
abstract final class BombFlowerThemeData {
  static ThemeData build() {
    final scheme = _colorScheme();
    final textTheme = _textTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: BombFlowerColors.canopy0,
      canvasColor: BombFlowerColors.canopy1,
      cardColor: BombFlowerColors.parchment,
      dividerColor: BombFlowerColors.stone,
      disabledColor: BombFlowerColors.textDisabled,
      focusColor: BombFlowerColors.brassFocus,
      hoverColor: BombFlowerColors.hoverPaper,
      highlightColor: Colors.transparent,
      hintColor: BombFlowerColors.inkMuted,
      shadowColor: BombFlowerColors.shadow,
      unselectedWidgetColor: BombFlowerColors.stone,
      splashColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: textTheme,
      primaryTextTheme: textTheme.apply(
        bodyColor: BombFlowerColors.bone,
        displayColor: BombFlowerColors.bone,
      ),
      iconTheme: const IconThemeData(color: BombFlowerColors.ink, size: 18),
      primaryIconTheme: const IconThemeData(
        color: BombFlowerColors.bone,
        size: 18,
      ),
      dividerTheme: const DividerThemeData(
        color: BombFlowerColors.stone,
        thickness: 1,
        space: 1,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: BombFlowerColors.brassInk,
        selectionColor: BombFlowerColors.selection,
        selectionHandleColor: BombFlowerColors.brassInk,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: BombFlowerColors.parchmentRaised,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: BombFlowerSpacing.lg,
          vertical: BombFlowerSpacing.md,
        ),
        constraints: const BoxConstraints(
          minHeight: BombFlowerSpacing.fieldHeight,
        ),
        hintStyle: BombFlowerTypography.body.copyWith(
          color: BombFlowerColors.inkMuted,
        ),
        labelStyle: BombFlowerTypography.label.copyWith(
          color: BombFlowerColors.ink,
        ),
        floatingLabelStyle: BombFlowerTypography.label.copyWith(
          color: BombFlowerColors.ink,
        ),
        helperStyle: BombFlowerTypography.caption.copyWith(
          color: BombFlowerColors.inkMuted,
        ),
        errorStyle: BombFlowerTypography.caption.copyWith(
          color: BombFlowerColors.danger,
        ),
        counterStyle: BombFlowerTypography.mono.copyWith(
          fontSize: BombFlowerTypography.captionSize,
          color: BombFlowerColors.inkMuted,
        ),
        prefixStyle: BombFlowerTypography.body.copyWith(
          color: BombFlowerColors.ink,
        ),
        suffixStyle: BombFlowerTypography.body.copyWith(
          color: BombFlowerColors.inkMuted,
        ),
        suffixIconColor: BombFlowerColors.inkMuted,
        prefixIconColor: BombFlowerColors.inkMuted,
        border: _inputBorder(BombFlowerColors.stone),
        enabledBorder: _inputBorder(BombFlowerColors.stone),
        focusedBorder: _inputBorder(BombFlowerColors.focusOnLight, width: 2),
        errorBorder: _inputBorder(BombFlowerColors.danger, width: 2),
        focusedErrorBorder: _inputBorder(BombFlowerColors.danger, width: 2),
        disabledBorder: _inputBorder(
          BombFlowerColors.stone.withValues(alpha: 0.5),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: BombFlowerColors.canopy2,
          border: Border.all(color: BombFlowerColors.stoneLight),
          borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
        ),
        textStyle: BombFlowerTypography.body.copyWith(
          fontSize: 13,
          height: 18 / 13,
          color: BombFlowerColors.bone,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: BombFlowerSpacing.lg,
          vertical: BombFlowerSpacing.md,
        ),
        margin: const EdgeInsets.all(BombFlowerSpacing.md),
        constraints: const BoxConstraints(maxWidth: 280),
        waitDuration: const Duration(milliseconds: 500),
        exitDuration: const Duration(milliseconds: 80),
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thickness: WidgetStatePropertyAll<double>(10),
        radius: Radius.circular(5),
        thumbColor: WidgetStatePropertyAll<Color>(BombFlowerColors.stone),
        trackColor: WidgetStatePropertyAll<Color>(Colors.transparent),
        trackVisibility: WidgetStatePropertyAll<bool>(false),
        interactive: true,
        minThumbLength: 32,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: BombFlowerColors.parchment,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: BombFlowerColors.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BombFlowerRadii.md),
          side: const BorderSide(color: BombFlowerColors.stone),
        ),
        titleTextStyle: BombFlowerTypography.h2.copyWith(
          color: BombFlowerColors.ink,
        ),
        contentTextStyle: BombFlowerTypography.body.copyWith(
          color: BombFlowerColors.inkSecondary,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: BombFlowerColors.parchment,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: false,
        dragHandleColor: BombFlowerColors.stone,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(BombFlowerRadii.md),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: BombFlowerColors.canopy2,
        contentTextStyle: BombFlowerTypography.body.copyWith(
          color: BombFlowerColors.bone,
        ),
        actionTextColor: BombFlowerColors.brassHover,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BombFlowerRadii.md),
          side: const BorderSide(color: BombFlowerColors.stoneLight),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: BombFlowerColors.canopy0,
        foregroundColor: BombFlowerColors.bone,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: BombFlowerTypography.h3.copyWith(
          color: BombFlowerColors.bone,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: BombFlowerColors.brass,
        foregroundColor: BombFlowerColors.ink,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll<double>(0),
          backgroundColor: const WidgetStatePropertyAll<Color>(
            BombFlowerColors.brass,
          ),
          foregroundColor: const WidgetStatePropertyAll<Color>(
            BombFlowerColors.ink,
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
              side: const BorderSide(color: BombFlowerColors.brassInk),
            ),
          ),
          textStyle: WidgetStatePropertyAll<TextStyle>(
            BombFlowerTypography.button,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll<Color>(
            BombFlowerColors.brassInk,
          ),
          overlayColor: const WidgetStatePropertyAll<Color>(
            BombFlowerColors.hoverPaper,
          ),
          textStyle: WidgetStatePropertyAll<TextStyle>(
            BombFlowerTypography.button,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll<Color>(
            BombFlowerColors.ink,
          ),
          side: const WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: BombFlowerColors.stone),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
            ),
          ),
          textStyle: WidgetStatePropertyAll<TextStyle>(
            BombFlowerTypography.button,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll<Color>(
            BombFlowerColors.ink,
          ),
          overlayColor: const WidgetStatePropertyAll<Color>(
            BombFlowerColors.hoverPaper,
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: BombFlowerColors.brass,
        linearTrackColor: BombFlowerColors.parchmentSunken,
        circularTrackColor: BombFlowerColors.parchmentSunken,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      extensions: const <ThemeExtension<dynamic>>[BombFlowerTheme.standard],
    );
  }

  static ColorScheme _colorScheme() {
    return ColorScheme.fromSeed(
      seedColor: BombFlowerColors.brass,
      brightness: Brightness.dark,
    ).copyWith(
      primary: BombFlowerColors.brass,
      onPrimary: BombFlowerColors.ink,
      primaryContainer: BombFlowerColors.selection,
      onPrimaryContainer: BombFlowerColors.ink,
      secondary: BombFlowerColors.brassInk,
      onSecondary: BombFlowerColors.parchment,
      secondaryContainer: BombFlowerColors.parchmentSunken,
      onSecondaryContainer: BombFlowerColors.ink,
      tertiary: BombFlowerColors.success,
      onTertiary: BombFlowerColors.bone,
      tertiaryContainer: BombFlowerColors.successSurface,
      onTertiaryContainer: BombFlowerColors.successInk,
      error: BombFlowerColors.danger,
      onError: BombFlowerColors.bone,
      errorContainer: BombFlowerColors.dangerSurface,
      onErrorContainer: BombFlowerColors.dangerInk,
      surface: BombFlowerColors.parchment,
      onSurface: BombFlowerColors.ink,
      onSurfaceVariant: BombFlowerColors.inkSecondary,
      surfaceContainerLowest: BombFlowerColors.canopy0,
      surfaceContainerLow: BombFlowerColors.canopy1,
      surfaceContainer: BombFlowerColors.parchment,
      surfaceContainerHigh: BombFlowerColors.parchmentRaised,
      surfaceContainerHighest: BombFlowerColors.parchmentSunken,
      outline: BombFlowerColors.stone,
      outlineVariant: BombFlowerColors.divider,
      shadow: BombFlowerColors.shadow,
      scrim: BombFlowerColors.scrim,
      inverseSurface: BombFlowerColors.canopy2,
      onInverseSurface: BombFlowerColors.bone,
      inversePrimary: BombFlowerColors.brassHover,
      surfaceTint: Colors.transparent,
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme() {
    return TextTheme(
      displayLarge: BombFlowerTypography.display.copyWith(
        color: BombFlowerColors.ink,
      ),
      displayMedium: BombFlowerTypography.h1.copyWith(
        color: BombFlowerColors.ink,
      ),
      displaySmall: BombFlowerTypography.h2.copyWith(
        color: BombFlowerColors.ink,
      ),
      headlineLarge: BombFlowerTypography.h1.copyWith(
        color: BombFlowerColors.ink,
      ),
      headlineMedium: BombFlowerTypography.h1.copyWith(
        color: BombFlowerColors.ink,
      ),
      headlineSmall: BombFlowerTypography.h2.copyWith(
        color: BombFlowerColors.ink,
      ),
      titleLarge: BombFlowerTypography.h2.copyWith(color: BombFlowerColors.ink),
      titleMedium: BombFlowerTypography.h3.copyWith(
        color: BombFlowerColors.ink,
      ),
      titleSmall: BombFlowerTypography.bodyStrong.copyWith(
        color: BombFlowerColors.ink,
      ),
      bodyLarge: BombFlowerTypography.body.copyWith(
        color: BombFlowerColors.ink,
      ),
      bodyMedium: BombFlowerTypography.body.copyWith(
        color: BombFlowerColors.ink,
      ),
      bodySmall: BombFlowerTypography.caption.copyWith(
        color: BombFlowerColors.inkMuted,
      ),
      labelLarge: BombFlowerTypography.button.copyWith(
        color: BombFlowerColors.ink,
      ),
      labelMedium: BombFlowerTypography.label.copyWith(
        color: BombFlowerColors.ink,
      ),
      labelSmall: BombFlowerTypography.overline.copyWith(
        color: BombFlowerColors.inkMuted,
      ),
    );
  }
}
