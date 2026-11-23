import 'package:material_ui/material_ui.dart';

/// Font stacks and type metrics from the Deep Canopy design contract.
///
/// The app ships no font files. Families are the open fonts commonly present
/// on Linux desktops, with explicit open fallbacks so UI text never silently
/// becomes serif. Line heights are expressed as `height = lineHeight / size`.
abstract final class BombFlowerTypography {
  static const String displayFamily = 'Noto Serif';
  static const List<String> displayFallback = <String>[
    'Liberation Serif',
    'DejaVu Serif',
    'serif',
  ];

  static const String bodyFamily = 'Noto Sans';
  static const List<String> bodyFallback = <String>[
    'Liberation Sans',
    'DejaVu Sans',
    'sans-serif',
  ];

  static const String monoFamily = 'Noto Sans Mono';
  static const List<String> monoFallback = <String>[
    'DejaVu Sans Mono',
    'Liberation Mono',
    'monospace',
  ];

  // Display: 36/44, 600, -0.4.
  static const double displaySize = 36;
  static const double displayLineHeight = 44;
  static const FontWeight displayWeight = FontWeight.w600;
  static const double displayTracking = -0.4;

  // H1: 28/34, 600, -0.2.
  static const double h1Size = 28;
  static const double h1LineHeight = 34;
  static const FontWeight h1Weight = FontWeight.w600;
  static const double h1Tracking = -0.2;

  // H2: 22/28, 600, 0.
  static const double h2Size = 22;
  static const double h2LineHeight = 28;
  static const FontWeight h2Weight = FontWeight.w600;
  static const double h2Tracking = 0;

  // H3: 18/24, 600, +0.1.
  static const double h3Size = 18;
  static const double h3LineHeight = 24;
  static const FontWeight h3Weight = FontWeight.w600;
  static const double h3Tracking = 0.1;

  // Body: 14/21, 400.
  static const double bodySize = 14;
  static const double bodyLineHeight = 21;
  static const FontWeight bodyWeight = FontWeight.w400;
  static const double bodyTracking = 0;

  // Body strong: 14/21, 600.
  static const double bodyStrongSize = 14;
  static const double bodyStrongLineHeight = 21;
  static const FontWeight bodyStrongWeight = FontWeight.w600;

  // Label: 12/16, 600, +0.6.
  static const double labelSize = 12;
  static const double labelLineHeight = 16;
  static const FontWeight labelWeight = FontWeight.w600;
  static const double labelTracking = 0.6;

  // Button: 13/16, 600, +0.2.
  static const double buttonSize = 13;
  static const double buttonLineHeight = 16;
  static const FontWeight buttonWeight = FontWeight.w600;
  static const double buttonTracking = 0.2;

  // Table cell: 13/18, 400.
  static const double tableSize = 13;
  static const double tableLineHeight = 18;
  static const FontWeight tableWeight = FontWeight.w400;

  // Table header: 11/16, 700, +0.7.
  static const double tableHeaderSize = 11;
  static const double tableHeaderLineHeight = 16;
  static const FontWeight tableHeaderWeight = FontWeight.w700;
  static const double tableHeaderTracking = 0.7;

  // Mono: 13/20, 400.
  static const double monoSize = 13;
  static const double monoLineHeight = 20;
  static const FontWeight monoWeight = FontWeight.w400;

  // Caption: 11/15, 400, +0.1.
  static const double captionSize = 11;
  static const double captionLineHeight = 15;
  static const FontWeight captionWeight = FontWeight.w400;
  static const double captionTracking = 0.1;

  // Overline: 10/14, 700, +1.2.
  static const double overlineSize = 10;
  static const double overlineLineHeight = 14;
  static const FontWeight overlineWeight = FontWeight.w700;
  static const double overlineTracking = 1.2;

  static const TextStyle display = TextStyle(
    fontFamily: displayFamily,
    fontFamilyFallback: displayFallback,
    fontSize: displaySize,
    height: displayLineHeight / displaySize,
    fontWeight: displayWeight,
    letterSpacing: displayTracking,
  );

  static const TextStyle h1 = TextStyle(
    fontFamily: displayFamily,
    fontFamilyFallback: displayFallback,
    fontSize: h1Size,
    height: h1LineHeight / h1Size,
    fontWeight: h1Weight,
    letterSpacing: h1Tracking,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: displayFamily,
    fontFamilyFallback: displayFallback,
    fontSize: h2Size,
    height: h2LineHeight / h2Size,
    fontWeight: h2Weight,
    letterSpacing: h2Tracking,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: displayFamily,
    fontFamilyFallback: displayFallback,
    fontSize: h3Size,
    height: h3LineHeight / h3Size,
    fontWeight: h3Weight,
    letterSpacing: h3Tracking,
  );

  static const TextStyle body = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: bodySize,
    height: bodyLineHeight / bodySize,
    fontWeight: bodyWeight,
    letterSpacing: bodyTracking,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: bodyStrongSize,
    height: bodyStrongLineHeight / bodyStrongSize,
    fontWeight: bodyStrongWeight,
    letterSpacing: bodyTracking,
  );

  static const TextStyle label = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: labelSize,
    height: labelLineHeight / labelSize,
    fontWeight: labelWeight,
    letterSpacing: labelTracking,
  );

  static const TextStyle button = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: buttonSize,
    height: buttonLineHeight / buttonSize,
    fontWeight: buttonWeight,
    letterSpacing: buttonTracking,
  );

  static const TextStyle table = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: tableSize,
    height: tableLineHeight / tableSize,
    fontWeight: tableWeight,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextStyle tableHeader = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: tableHeaderSize,
    height: tableHeaderLineHeight / tableHeaderSize,
    fontWeight: tableHeaderWeight,
    letterSpacing: tableHeaderTracking,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    fontSize: monoSize,
    height: monoLineHeight / monoSize,
    fontWeight: monoWeight,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextStyle caption = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: captionSize,
    height: captionLineHeight / captionSize,
    fontWeight: captionWeight,
    letterSpacing: captionTracking,
  );

  static const TextStyle overline = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: overlineSize,
    height: overlineLineHeight / overlineSize,
    fontWeight: overlineWeight,
    letterSpacing: overlineTracking,
  );
}
