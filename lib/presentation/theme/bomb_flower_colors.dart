import 'package:material_ui/material_ui.dart';

/// The single Bomb Flower palette.
///
/// Values are ported verbatim from the Deep Canopy design contract. There is
/// no light/dark variant: warm parchment content sits on a dark canopy chassis
/// with a scarce brass accent. Gold-colored text on paper must use
/// [brassInk]; [brass] is for dark surfaces and fills.
abstract final class BombFlowerColors {
  // Background layers.
  static const canopy0 = Color(0xFF101A12);
  static const canopy1 = Color(0xFF16241B);
  static const canopy2 = Color(0xFF1E2F23);
  static const canopyHover = Color(0xFF22352A);
  static const canopyPressed = Color(0xFF2A4031);
  static const scrim = Color(0xB80A0F0B);
  static const shadow = Color(0xFF0B120C);

  // Paper surfaces.
  static const parchment = Color(0xFFEFE3C8);
  static const parchmentRaised = Color(0xFFF6EDD8);
  static const parchmentSunken = Color(0xFFE3D3B0);
  static const parchmentAlt = Color(0xFFE8DABC);
  static const parchmentDisabled = Color(0xFFD8C9A9);

  // Borders, stone, and wood.
  static const stone = Color(0xFF6E6A5C);

  /// The light stone hairline.
  ///
  /// Darkened from #A39C89 to #87806D so a 1 px border clears 3:1 on parchment
  /// (2.15:1 -> 3.09:1) while still clearing it on the canopy (5.16:1 ->
  /// 3.59:1), where it outlines tooltips and snackbars. See
  /// test/presentation/theme/contrast_test.dart.
  static const stoneLight = Color(0xFF87806D);

  static const stoneDark = Color(0xFF4A473D);
  static const wood = Color(0xFF4A3423);
  static const woodLight = Color(0xFF6B4A2F);
  static const woodDark = Color(0xFF2E2016);
  static const woodEdge = Color(0xFF8A6A45);
  static const divider = Color(0xFFC9BCA1);

  /// The canopy divider.
  ///
  /// Raised from #33463A to #607A69: it is the status footer's top border and
  /// its inner separators, and 1.60:1 on canopy1 could not show a region edge.
  /// Now 3.44:1 on canopy1, 3.81:1 on canopy0, and 3.02:1 on canopy2.
  static const dividerDark = Color(0xFF607A69);

  // Brass / gold.
  static const brass = Color(0xFFC9A227);
  static const brassHover = Color(0xFFE2C257);
  static const brassPressed = Color(0xFFA8861C);
  static const brassInk = Color(0xFF6B4E00);
  static const brassFocus = Color(0xFFF0C75E);
  static const focusOnLight = Color(0xFF7A5A00);
  static const focusOnBrass = Color(0xFF241C12);
  static const selection = Color(0xFFE8CD7A);
  static const selectionDark = Color(0xFF5C4A1E);

  /// Deepest stop of the primary brass gradient.
  ///
  /// Raised from #8C7420 to #A5811E so [ink] on the darkest stop clears the
  /// 4.5:1 normal-text threshold (3.71:1 -> 4.61:1); the other stops are
  /// brighter still. See test/presentation/theme/contrast_test.dart.
  static const brassDeep = Color(0xFFA5811E);

  // Text.
  static const ink = Color(0xFF241C12);
  static const inkSecondary = Color(0xFF4A3D2A);
  static const inkMuted = Color(0xFF5C4F3A);
  static const bone = Color(0xFFF2EAD9);
  static const boneMuted = Color(0xFFA9B5A2);
  static const textDisabled = Color(0xFF5C4F3A);
  static const textDisabledOnDark = Color(0xFF8A9587);

  // Status and feedback.
  static const success = Color(0xFF2F6B45);
  static const successLight = Color(0xFF8FC9A3);
  static const successSurface = Color(0xFFDDEDD9);
  static const successInk = Color(0xFF24543A);
  static const warning = Color(0xFF8A5A12);
  static const warningLight = Color(0xFFE0B45E);
  static const warningSurface = Color(0xFFF3E2B8);
  static const warningInk = Color(0xFF6B4508);
  static const danger = Color(0xFFA63A2E);
  static const dangerStrong = Color(0xFF8E2F24);
  static const dangerPressed = Color(0xFF7A241B);
  static const dangerLight = Color(0xFFE88B7D);
  static const dangerSurface = Color(0xFFF2D9D3);
  static const dangerInk = Color(0xFF8E2F24);
  static const info = Color(0xFF2E5F7A);
  static const infoLight = Color(0xFF8FC3DD);
  static const infoSurface = Color(0xFFD9E8EF);
  static const infoInk = Color(0xFF244C63);
  static const heartFill = Color(0xFFA63A2E);
  static const heartEmpty = Color(0xFF6E6A5C);

  // Alpha overlays for hover states.
  static const hoverPaper = Color(0x0F241C12);
  static const hoverDark = Color(0x14F2EAD9);

  /// Every palette value in declaration order.
  ///
  /// Kept in sync with the design contract so tests can prove the full
  /// 60-token set is present rather than only the handful the shell uses.
  static const List<Color> all = <Color>[
    canopy0,
    canopy1,
    canopy2,
    canopyHover,
    canopyPressed,
    scrim,
    shadow,
    parchment,
    parchmentRaised,
    parchmentSunken,
    parchmentAlt,
    parchmentDisabled,
    stone,
    stoneLight,
    stoneDark,
    wood,
    woodLight,
    woodDark,
    woodEdge,
    divider,
    dividerDark,
    brass,
    brassHover,
    brassPressed,
    brassInk,
    brassFocus,
    focusOnLight,
    focusOnBrass,
    selection,
    selectionDark,
    brassDeep,
    ink,
    inkSecondary,
    inkMuted,
    bone,
    boneMuted,
    textDisabled,
    textDisabledOnDark,
    success,
    successLight,
    successSurface,
    successInk,
    warning,
    warningLight,
    warningSurface,
    warningInk,
    danger,
    dangerStrong,
    dangerPressed,
    dangerLight,
    dangerSurface,
    dangerInk,
    info,
    infoLight,
    infoSurface,
    infoInk,
    heartFill,
    heartEmpty,
    hoverPaper,
    hoverDark,
  ];
}
