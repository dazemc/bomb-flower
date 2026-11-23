import 'package:material_ui/material_ui.dart';

/// Spacing, control sizes, and layout constants. Base unit is 4 px.
abstract final class BombFlowerSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 20;
  static const double xxxl = 24;
  static const double huge = 32;
  static const double giant = 40;
  static const double colossal = 48;
  static const double vast = 64;

  // Shell.
  static const double titleBarHeight = 44;
  static const double footerHeight = 28;
  static const double navRailWidth = 232;
  static const double navRailCompactWidth = 208;
  static const double navRailIconOnlyWidth = 64;
  static const double navItemHeight = 40;
  static const double navItemCollapsedHeight = 44;
  static const double minWindowWidth = 1100;
  static const double minWindowHeight = 700;
  static const double contentMaxWidth = 1680;
  static const double contentGutter = 24;
  static const double contentGutterWide = 32;

  // Controls.
  static const double fieldHeight = 36;
  static const double fieldCompactHeight = 32;
  static const double buttonHeight = 36;
  static const double titleBarButtonWidth = 40;
  static const double minHitTarget = 32;
  static const double titleBarHitTarget = 44;
  static const double panelPadding = 20;
  static const double sectionGap = 24;
  static const double tableRowHeight = 36;
  static const double tableRowCompactHeight = 32;
  static const double tableHeaderHeight = 32;
  static const double itemSlotSize = 72;
  static const double itemSlotMinSize = 56;
  static const double itemSlotMaxSize = 80;
  static const double itemSlotGap = 8;
  static const int inventoryColumns = 6;
  static const int inventoryRows = 4;

  // Responsive breakpoints.
  static const double compactBreakpoint = 1280;
  static const double wideBreakpoint = 1600;
  static const double ultrawideBreakpoint = 1920;
}

/// Corner radii. Panels also use an 8 px clipped top-right notch.
abstract final class BombFlowerRadii {
  static const double none = 0;
  static const double xs = 2;
  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double xl = 12;
  static const double pill = 999;

  /// Clipped paper corner used by [ParchmentPanel] analogues.
  static const double panelNotch = 8;
}

/// Motion tokens. Durations are milliseconds; curves are the cubic control
/// points from the design contract.
abstract final class BombFlowerMotion {
  static const int hoverMs = 90;
  static const int pressMs = 60;
  static const int tabMs = 180;
  static const int panelMs = 220;
  static const int dropdownInMs = 120;
  static const int dropdownOutMs = 90;
  static const int modalInMs = 160;
  static const int modalOutMs = 120;
  static const int toastInMs = 180;
  static const int toastOutMs = 140;
  static const int dirtyFlashMs = 480;
  static const int valueMs = 240;
  static const int skeletonMs = 1600;
  static const int runePulseMs = 1800;
  static const int reducedMotionMs = 80;

  static const Duration hover = Duration(milliseconds: hoverMs);
  static const Duration press = Duration(milliseconds: pressMs);
  static const Duration tab = Duration(milliseconds: tabMs);
  static const Duration panel = Duration(milliseconds: panelMs);
  static const Duration dropdownIn = Duration(milliseconds: dropdownInMs);
  static const Duration dropdownOut = Duration(milliseconds: dropdownOutMs);
  static const Duration modalIn = Duration(milliseconds: modalInMs);
  static const Duration modalOut = Duration(milliseconds: modalOutMs);
  static const Duration toastIn = Duration(milliseconds: toastInMs);
  static const Duration toastOut = Duration(milliseconds: toastOutMs);
  static const Duration value = Duration(milliseconds: valueMs);
  static const Duration runePulse = Duration(milliseconds: runePulseMs);
  static const Duration reducedMotion = Duration(milliseconds: reducedMotionMs);

  static const Cubic hoverCurve = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Cubic pressCurve = Cubic(0.3, 0.0, 0.6, 1.0);
  static const Cubic standardCurve = Cubic(0.2, 0.7, 0.2, 1.0);
  static const Cubic emphasisCurve = Cubic(0.4, 0.0, 0.2, 1.0);

  /// A motion duration that collapses to the reduced-motion token when the
  /// platform or app asks for less animation.
  static Duration adaptive(BuildContext context, Duration normal) {
    return MediaQuery.disableAnimationsOf(context) ? reducedMotion : normal;
  }
}

/// Elevation levels are semantic; actual shadows are drawn by panel chrome.
abstract final class BombFlowerElevation {
  static const int flat = 0;
  static const int panel = 1;
  static const int popover = 2;
  static const int modal = 3;
}
