/// WCAG 2.1 contrast guard for the Deep Canopy theme.
///
/// This is a **paint-site** guard, not a token cross-product. Every entry names
/// the widget and line that actually paints the pair, and the pair itself is
/// read from that code; a token combination that no widget uses is not a
/// defect and is deliberately absent. When a value changes, the failure names
/// the offending site and its measured ratio.
///
/// Thresholds follow WCAG 2.1 SC 1.4.3 (text) and SC 1.4.11 (non-text):
///
/// * normal text: 4.5:1 - body 14, bodyStrong 14, label 12, button 13,
///   table 13, caption 11, overline 10, mono 11, and h3 18 w600, because
///   18 px is below the 18.66 px (14 pt) bold large-text floor;
/// * large text: 3:1 - display 36, h1 28 w600, h2 22 w600;
/// * UI component (border, icon, focus ring, state indicator): 3:1.
///
/// Translucent foregrounds are alpha-composited over the backing surface
/// before measuring (that is where the nav rail's 0.90 shortcut hint lives).
///
/// Explicit non-pairs:
/// * There are **no breadcrumbs** in this codebase. No breadcrumb token,
///   surface, or pair is modelled here.
/// * Disabled states are excluded: WCAG 1.4.11 exempts inactive controls, so
///   `textDisabled` on `parchmentDisabled`, the 0.5-alpha disabled field
///   borders, and the disabled toggle/checkbox/slider stone are not asserted.
/// * Purely ornamental rules are excluded: `divider` on parchment inside a
///   `ParchmentPanel` (parchment_panel.dart:147,152), the brass double rule
///   (section_header.dart:155), the brass thumb's engraved inner rim over
///   brassDeep (brass_toggle.dart:316, 2.12:1) and the primary button's
///   brassInk hairline over brassDeep (brass_button.dart:245, 2.12:1). They
///   group content or add depth but do not identify a control; the panel
///   `stone` border and the brass fill do that job and are asserted.
/// * The wood hairlines in the title bar are also ornamental: the action
///   button border (file_action_bar.dart:252, woodLight on wood, 1.46:1) and
///   the window-button hover fills (app_title_bar.dart:435-443). The bone
///   glyphs inside them are asserted at 3:1 and identify the controls.
/// * Two real sites remain unfixed because their files belong to another lane;
///   they are reported, not asserted, so this guard stays green on this
///   worktree: the primary focus ring `focusOnLight` on the canopy
///   (brass_button.dart:148) and the hex editor's `stone` hint/borders on its
///   canopy surfaces (hex_editor.dart:1122,1135).
library;

import 'dart:math' as math;

import 'package:bomb_flower/presentation/theme/bomb_flower_colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// WCAG size class and the ratio it requires.
enum _TextClass {
  normal(4.5, 'normal text, 4.5:1'),
  large(3.0, 'large text, 3:1'),
  component(3.0, 'UI component, 3:1');

  const _TextClass(this.minRatio, this.label);

  final double minRatio;
  final String label;
}

/// One pair a widget actually paints, with the site that paints it.
final class _Pair {
  const _Pair(this.site, this.foreground, this.background, this.textClass);

  final String site;
  final Color foreground;
  final Color background;
  final _TextClass textClass;
}

void main() {
  group('Deep Canopy contrast guard', () {
    test('the WCAG helpers are not silently broken', () {
      // A broken luminance or ratio function would make every pair "pass".
      expect(_contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)),
          closeTo(21.0, 0.01));
      expect(_contrast(BombFlowerColors.bone, BombFlowerColors.canopy0),
          closeTo(14.89, 0.02));
      expect(_contrast(BombFlowerColors.ink, BombFlowerColors.canopy0),
          closeTo(1.06, 0.02));
      // 90% boneMuted over wood, composited, is the nav rail hint.
      final hint = _composite(
        BombFlowerColors.boneMuted.withValues(alpha: 0.90),
        BombFlowerColors.wood,
      );
      expect(_contrast(hint, BombFlowerColors.wood), closeTo(4.72, 0.03));
    });

    test('every painted pair clears its WCAG 2.1 threshold', () {
      final failures = <String>[];
      for (final pair in _paintedPairs) {
        final foreground = _composite(pair.foreground, pair.background);
        final ratio = _contrast(foreground, pair.background);
        if (ratio + 0.005 < pair.textClass.minRatio) {
          final composited = pair.foreground.toARGB32() >> 24 != 0xff
              ? ' (composited)'
              : '';
          failures.add(
            '${pair.site}\n'
            '    ${_hex(pair.foreground)} on ${_hex(pair.background)}'
            '$composited = ${ratio.toStringAsFixed(2)}:1, '
            'needs ${pair.textClass.label}',
          );
        }
      }
      expect(
        failures,
        isEmpty,
        reason:
            '\n${failures.length} contrast failure(s):\n${failures.join('\n')}\n',
      );
    });
  });
}

/// Alpha-composites [foreground] over an opaque [background].
Color _composite(Color foreground, Color background) {
  final fg = foreground.toARGB32();
  final alpha = ((fg >> 24) & 0xff) / 255.0;
  if (alpha >= 0.999) {
    return foreground;
  }
  final bg = background.toARGB32();
  int mix(int shift) {
    final f = (fg >> shift) & 0xff;
    final b = (bg >> shift) & 0xff;
    return (f * alpha + b * (1 - alpha)).round();
  }

  return Color.fromARGB(255, mix(16), mix(8), mix(0));
}

/// WCAG 2.1 relative luminance of an opaque colour.
double _luminance(Color color) {
  final argb = color.toARGB32();
  return 0.2126 * _channel((argb >> 16) & 0xff) +
      0.7152 * _channel((argb >> 8) & 0xff) +
      0.0722 * _channel(argb & 0xff);
}

double _channel(int value) {
  final c = value / 255.0;
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG 2.1 contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(Color color) {
  final argb = color.toARGB32();
  final rgb = (argb & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase();
  final alpha = (argb >> 24) & 0xff;
  return alpha == 0xff ? '#$rgb' : '#$rgb@${(alpha / 255).toStringAsFixed(2)}';
}

/// Every entry below is a pair the app actually paints.
final List<_Pair> _paintedPairs = <_Pair>[
  // --- Empty / no-save screen: EmptyState defaults to onDark, sits on canopy0.
  const _Pair(
    'empty_state.dart:75 title (h3 18 w600)',
    BombFlowerColors.bone,
    BombFlowerColors.canopy0,
    _TextClass.normal,
  ),
  const _Pair(
    'empty_state.dart:83 message (body 14)',
    BombFlowerColors.boneMuted,
    BombFlowerColors.canopy0,
    _TextClass.normal,
  ),
  const _Pair(
    'empty_state.dart:111 Ctrl+O hint (caption 11)',
    BombFlowerColors.boneMuted,
    BombFlowerColors.canopy0,
    _TextClass.normal,
  ),

  // --- BrassButton: the label is painted over every gradient stop of the
  // primary face (brass_button.dart:260-278), so every stop is a pair.
  const _Pair(
    'brass_button.dart:274 primary label over brassDeep (button 13 w600)',
    BombFlowerColors.ink,
    BombFlowerColors.brassDeep,
    _TextClass.normal,
  ),
  const _Pair(
    'brass_button.dart:275 primary label over brassHover (button 13 w600)',
    BombFlowerColors.ink,
    BombFlowerColors.brassHover,
    _TextClass.normal,
  ),
  const _Pair(
    'brass_button.dart:276 primary label over brass (button 13 w600)',
    BombFlowerColors.ink,
    BombFlowerColors.brass,
    _TextClass.normal,
  ),
  const _Pair(
    'brass_button.dart:262 pressed label over brassPressed (button 13 w600)',
    BombFlowerColors.ink,
    BombFlowerColors.brassPressed,
    _TextClass.normal,
  ),
  // The fill, not the brassInk hairline, is what identifies the control on
  // the canopy; the hairline sits between two brass tones.
  const _Pair(
    'brass_button.dart:274 primary fill vs canopy ground',
    BombFlowerColors.brassDeep,
    BombFlowerColors.canopy0,
    _TextClass.component,
  ),
  const _Pair(
    'brass_button.dart:233 secondary label on paper (button 13 w600)',
    BombFlowerColors.ink,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'brass_button.dart:213 secondary hover fill (button 13 w600)',
    BombFlowerColors.ink,
    BombFlowerColors.parchmentRaised,
    _TextClass.normal,
  ),
  const _Pair(
    'brass_button.dart:211 secondary pressed fill (button 13 w600)',
    BombFlowerColors.ink,
    BombFlowerColors.parchmentSunken,
    _TextClass.normal,
  ),
  const _Pair(
    'brass_button.dart:233 secondary label on canopy (app_shell onDark)',
    BombFlowerColors.bone,
    BombFlowerColors.canopy0,
    _TextClass.normal,
  ),
  const _Pair(
    'brass_button.dart:247 secondary border on canopy (app_shell onDark)',
    BombFlowerColors.stoneLight,
    BombFlowerColors.canopy0,
    _TextClass.component,
  ),
  const _Pair(
    'brass_button.dart:234 destructive label (button 13 w600)',
    BombFlowerColors.bone,
    BombFlowerColors.dangerStrong,
    _TextClass.normal,
  ),
  const _Pair(
    'brass_button.dart:217 destructive pressed label (button 13 w600)',
    BombFlowerColors.bone,
    BombFlowerColors.dangerPressed,
    _TextClass.normal,
  ),
  const _Pair(
    'brass_button.dart:236 text variant label on paper (button 13 w600)',
    BombFlowerColors.brassInk,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'brass_button.dart:221 text variant pressed fill (button 13 w600)',
    BombFlowerColors.brassInk,
    BombFlowerColors.parchmentSunken,
    _TextClass.normal,
  ),
  const _Pair(
    'brass_button.dart:202 disabled label on disabled surface (button 13)',
    BombFlowerColors.textDisabled,
    BombFlowerColors.parchmentDisabled,
    _TextClass.normal,
  ),

  // --- Title bar: WoodGrainPainter(woodDark -> wood) plus woodLight grain
  // bands (procedural_painters.dart:250,259). wood is the lightest band, so it
  // is the worst stop for light text.
  const _Pair(
    'app_title_bar.dart:306 save name (button 13)',
    BombFlowerColors.bone,
    BombFlowerColors.wood,
    _TextClass.normal,
  ),
  const _Pair(
    'app_title_bar.dart:306 save name top stop (button 13)',
    BombFlowerColors.bone,
    BombFlowerColors.woodDark,
    _TextClass.normal,
  ),
  const _Pair(
    'app_title_bar.dart:306 save name over woodLight grain band (button 13)',
    BombFlowerColors.bone,
    BombFlowerColors.woodLight,
    _TextClass.normal,
  ),
  const _Pair(
    'app_title_bar.dart:366 BOMB FLOWER wordmark (label 12 w700)',
    BombFlowerColors.bone,
    BombFlowerColors.wood,
    _TextClass.normal,
  ),
  const _Pair(
    'app_title_bar.dart:366 wordmark top stop (label 12 w700)',
    BombFlowerColors.bone,
    BombFlowerColors.woodDark,
    _TextClass.normal,
  ),
  const _Pair(
    'app_title_bar.dart:503 window glyph stroke over woodLight band',
    BombFlowerColors.bone,
    BombFlowerColors.woodLight,
    _TextClass.component,
  ),
  const _Pair(
    'app_title_bar.dart:514 window focus ring',
    BombFlowerColors.brassFocus,
    BombFlowerColors.wood,
    _TextClass.component,
  ),
  const _Pair(
    'app_title_bar.dart:514 window focus ring top stop',
    BombFlowerColors.brassFocus,
    BombFlowerColors.woodDark,
    _TextClass.component,
  ),
  const _Pair(
    'app_title_bar.dart:459 close glyph on hover fill',
    BombFlowerColors.bone,
    BombFlowerColors.dangerStrong,
    _TextClass.component,
  ),
  const _Pair(
    'app_title_bar.dart:463 close button focus ring on hover fill',
    BombFlowerColors.brassFocus,
    BombFlowerColors.dangerStrong,
    _TextClass.component,
  ),
  const _Pair(
    'file_action_bar.dart:251 action glyph',
    BombFlowerColors.bone,
    BombFlowerColors.wood,
    _TextClass.component,
  ),

  // --- Status footer.
  const _Pair(
    'shell_status_footer.dart:60 validation summary (caption 11)',
    BombFlowerColors.boneMuted,
    BombFlowerColors.canopy1,
    _TextClass.normal,
  ),
  const _Pair(
    'shell_status_footer.dart:72 save path (caption 11)',
    BombFlowerColors.boneMuted,
    BombFlowerColors.canopy1,
    _TextClass.normal,
  ),
  const _Pair(
    'shell_status_footer.dart:83 revision (mono 11)',
    BombFlowerColors.boneMuted,
    BombFlowerColors.canopy1,
    _TextClass.normal,
  ),
  const _Pair(
    'shell_status_footer.dart:23 healthy dot',
    BombFlowerColors.successLight,
    BombFlowerColors.canopy1,
    _TextClass.component,
  ),
  const _Pair(
    'shell_status_footer.dart:22 warning dot',
    BombFlowerColors.warningLight,
    BombFlowerColors.canopy1,
    _TextClass.component,
  ),
  const _Pair(
    'shell_status_footer.dart:25 error dot',
    BombFlowerColors.dangerLight,
    BombFlowerColors.canopy1,
    _TextClass.component,
  ),
  const _Pair(
    'shell_status_footer.dart:36 footer top border',
    BombFlowerColors.dividerDark,
    BombFlowerColors.canopy1,
    _TextClass.component,
  ),
  const _Pair(
    'shell_status_footer.dart:102 footer separator',
    BombFlowerColors.dividerDark,
    BombFlowerColors.canopy1,
    _TextClass.component,
  ),

  // --- Nav rail: WoodGrainPainter(wood -> woodDark); wood is the light stop.
  const _Pair(
    'shell_nav_rail.dart:75 group overline (overline 10)',
    BombFlowerColors.boneMuted,
    BombFlowerColors.wood,
    _TextClass.normal,
  ),
  const _Pair(
    'shell_nav_rail.dart:75 group overline bottom stop (overline 10)',
    BombFlowerColors.boneMuted,
    BombFlowerColors.woodDark,
    _TextClass.normal,
  ),
  const _Pair(
    'shell_nav_rail.dart:136 unselected label (button 13)',
    BombFlowerColors.boneMuted,
    BombFlowerColors.wood,
    _TextClass.normal,
  ),
  // 0.90 alpha hint, composited over the gradient.
  _Pair(
    'shell_nav_rail.dart:142 shortcut hint at 0.90 alpha over wood (overline 10)',
    BombFlowerColors.boneMuted.withValues(alpha: 0.90),
    BombFlowerColors.wood,
    _TextClass.normal,
  ),
  _Pair(
    'shell_nav_rail.dart:142 shortcut hint at 0.90 alpha over woodDark',
    BombFlowerColors.boneMuted.withValues(alpha: 0.90),
    BombFlowerColors.woodDark,
    _TextClass.normal,
  ),
  const _Pair(
    'shell_nav_rail.dart:180 selected plate label (button 13)',
    BombFlowerColors.ink,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'shell_nav_rail.dart:142 selected shortcut hint (overline 10)',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'shell_nav_rail.dart:137 selected icon',
    BombFlowerColors.brassInk,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),
  const _Pair(
    'shell_nav_rail.dart:233 selected edge bar',
    BombFlowerColors.brass,
    BombFlowerColors.wood,
    _TextClass.component,
  ),
  const _Pair(
    'shell_nav_rail.dart:245 nav focus ring',
    BombFlowerColors.brassFocus,
    BombFlowerColors.wood,
    _TextClass.component,
  ),

  // --- StoneTable on a parchment panel.
  const _Pair(
    'stone_table.dart:289 header label (table header 11)',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchmentSunken,
    _TextClass.normal,
  ),
  const _Pair(
    'stone_table.dart:483 collapsed sort label (table header 11)',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchmentSunken,
    _TextClass.normal,
  ),
  const _Pair(
    'stone_table.dart:387 cell text (table 13)',
    BombFlowerColors.ink,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'stone_table.dart:336 selected row cell text (table 13)',
    BombFlowerColors.ink,
    BombFlowerColors.selection,
    _TextClass.normal,
  ),
  const _Pair(
    'stone_table.dart:348 selected row check icon',
    BombFlowerColors.brassInk,
    BombFlowerColors.selection,
    _TextClass.component,
  ),
  const _Pair(
    'stone_table.dart:427 active sort icon',
    BombFlowerColors.brassInk,
    BombFlowerColors.parchmentSunken,
    _TextClass.component,
  ),
  const _Pair(
    'stone_table.dart:528 empty body icon',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),
  const _Pair(
    'stone_table.dart:534 empty body message (body 14)',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'stone_table.dart:337 row divider',
    BombFlowerColors.stone,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),
  const _Pair(
    'stone_table.dart:228 header rule',
    BombFlowerColors.stone,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),
  const _Pair(
    'stone_table.dart:366 row focus ring',
    BombFlowerColors.focusOnLight,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),
  const _Pair(
    'stone_table.dart:497 sort header focus ring',
    BombFlowerColors.focusOnLight,
    BombFlowerColors.parchmentSunken,
    _TextClass.component,
  ),

  // --- ParchmentPanel.
  const _Pair(
    'parchment_panel.dart:125 panel title (h3 18 w600)',
    BombFlowerColors.ink,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'parchment_panel.dart:135 panel meta (caption 11)',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'parchment_panel.dart:57 panel border',
    BombFlowerColors.stone,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),
  const _Pair(
    'parchment_panel.dart:57 selected panel border',
    BombFlowerColors.brassInk,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),
  const _Pair(
    'parchment_panel.dart:59 hovered panel border',
    BombFlowerColors.stoneDark,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),

  // --- Dialogs (ThemeData.dialogTheme + ConfirmDialog).
  const _Pair(
    'bomb_flower_theme.dart:341 dialog title (h2 22 w600)',
    BombFlowerColors.ink,
    BombFlowerColors.parchment,
    _TextClass.large,
  ),
  const _Pair(
    'bomb_flower_theme.dart:344 dialog content (body 14)',
    BombFlowerColors.inkSecondary,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'bomb_flower_theme.dart:339 dialog border',
    BombFlowerColors.stone,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),
  const _Pair(
    'confirm_dialog.dart:74 accent rule',
    BombFlowerColors.brassInk,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),
  const _Pair(
    'confirm_dialog.dart:95 neutral glyph',
    BombFlowerColors.brassInk,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),
  const _Pair(
    'confirm_dialog.dart:103 title (h2 22 w600)',
    BombFlowerColors.ink,
    BombFlowerColors.parchment,
    _TextClass.large,
  ),
  const _Pair(
    'confirm_dialog.dart:115 message (body 14)',
    BombFlowerColors.inkSecondary,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'confirm_dialog.dart:126 destructive detail (label 12)',
    BombFlowerColors.danger,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),

  // --- Text inputs: ThemeData.inputDecorationTheme on parchmentRaised.
  const _Pair(
    'bomb_flower_theme.dart:271 input label (label 12)',
    BombFlowerColors.ink,
    BombFlowerColors.parchmentRaised,
    _TextClass.normal,
  ),
  const _Pair(
    'bomb_flower_theme.dart:268 input hint (body 14)',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchmentRaised,
    _TextClass.normal,
  ),
  const _Pair(
    'bomb_flower_theme.dart:277 input helper (caption 11)',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchmentRaised,
    _TextClass.normal,
  ),
  const _Pair(
    'bomb_flower_theme.dart:280 input error (caption 11)',
    BombFlowerColors.danger,
    BombFlowerColors.parchmentRaised,
    _TextClass.normal,
  ),
  const _Pair(
    'bomb_flower_theme.dart:284 input counter (mono 11)',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchmentRaised,
    _TextClass.normal,
  ),
  const _Pair(
    'bomb_flower_theme.dart:287 input prefix (body 14)',
    BombFlowerColors.ink,
    BombFlowerColors.parchmentRaised,
    _TextClass.normal,
  ),
  const _Pair(
    'bomb_flower_theme.dart:290 input suffix (body 14)',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchmentRaised,
    _TextClass.normal,
  ),
  const _Pair(
    'bomb_flower_theme.dart:295 input enabled border',
    BombFlowerColors.stone,
    BombFlowerColors.parchmentRaised,
    _TextClass.component,
  ),
  const _Pair(
    'bomb_flower_theme.dart:296 input focused border',
    BombFlowerColors.focusOnLight,
    BombFlowerColors.parchmentRaised,
    _TextClass.component,
  ),
  const _Pair(
    'bomb_flower_theme.dart:297 input error border',
    BombFlowerColors.danger,
    BombFlowerColors.parchmentRaised,
    _TextClass.component,
  ),

  // --- Tooltip and snackbar, both canopy2.
  const _Pair(
    'bomb_flower_theme.dart:312 tooltip text (body 13)',
    BombFlowerColors.bone,
    BombFlowerColors.canopy2,
    _TextClass.normal,
  ),
  const _Pair(
    'bomb_flower_theme.dart:306 tooltip border',
    BombFlowerColors.stoneLight,
    BombFlowerColors.canopy2,
    _TextClass.component,
  ),
  const _Pair(
    'bomb_flower_theme.dart:364 snackbar text (body 14)',
    BombFlowerColors.bone,
    BombFlowerColors.canopy2,
    _TextClass.normal,
  ),
  const _Pair(
    'bomb_flower_theme.dart:366 snackbar action (label 12)',
    BombFlowerColors.brassHover,
    BombFlowerColors.canopy2,
    _TextClass.normal,
  ),
  const _Pair(
    'bomb_flower_theme.dart:371 snackbar border',
    BombFlowerColors.stoneLight,
    BombFlowerColors.canopy2,
    _TextClass.component,
  ),

  // --- StoneToast on the chrome-raised canopy2 card.
  const _Pair(
    'toast.dart:100 success tone word (overline 10 w700)',
    BombFlowerColors.successLight,
    BombFlowerColors.canopy2,
    _TextClass.normal,
  ),
  const _Pair(
    'toast.dart:100 info tone word (overline 10 w700)',
    BombFlowerColors.infoLight,
    BombFlowerColors.canopy2,
    _TextClass.normal,
  ),
  const _Pair(
    'toast.dart:100 warning tone word (overline 10 w700)',
    BombFlowerColors.warningLight,
    BombFlowerColors.canopy2,
    _TextClass.normal,
  ),
  const _Pair(
    'toast.dart:100 danger tone word (overline 10 w700)',
    BombFlowerColors.dangerLight,
    BombFlowerColors.canopy2,
    _TextClass.normal,
  ),
  const _Pair(
    'toast.dart:107 toast body (body 14)',
    BombFlowerColors.bone,
    BombFlowerColors.canopy2,
    _TextClass.normal,
  ),
  const _Pair(
    'toast.dart:63 success tone border',
    BombFlowerColors.successLight,
    BombFlowerColors.canopy2,
    _TextClass.component,
  ),
  const _Pair(
    'toast.dart:63 info tone border',
    BombFlowerColors.infoLight,
    BombFlowerColors.canopy2,
    _TextClass.component,
  ),
  const _Pair(
    'toast.dart:63 warning tone border',
    BombFlowerColors.warningLight,
    BombFlowerColors.canopy2,
    _TextClass.component,
  ),
  const _Pair(
    'toast.dart:63 danger tone border',
    BombFlowerColors.dangerLight,
    BombFlowerColors.canopy2,
    _TextClass.component,
  ),
  const _Pair(
    'toast.dart:123 dismiss glyph',
    BombFlowerColors.bone,
    BombFlowerColors.canopy2,
    _TextClass.component,
  ),
  const _Pair(
    'toast.dart:125 dismiss button border',
    BombFlowerColors.stoneLight,
    BombFlowerColors.canopy2,
    _TextClass.component,
  ),

  // --- LoadingState: parchment by default, canopy when onDark.
  const _Pair(
    'loading_state.dart:124 label on paper (bodyStrong 14)',
    BombFlowerColors.ink,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'loading_state.dart:133 detail on paper (caption 11)',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'loading_state.dart:124 label on canopy (bodyStrong 14)',
    BombFlowerColors.bone,
    BombFlowerColors.canopy0,
    _TextClass.normal,
  ),
  const _Pair(
    'loading_state.dart:133 detail on canopy (caption 11)',
    BombFlowerColors.boneMuted,
    BombFlowerColors.canopy0,
    _TextClass.normal,
  ),
  const _Pair(
    'loading_state.dart:176 determinate progress fill',
    BombFlowerColors.brassInk,
    BombFlowerColors.parchmentSunken,
    _TextClass.component,
  ),
  const _Pair(
    'loading_state.dart:167 progress track border',
    BombFlowerColors.stone,
    BombFlowerColors.parchmentSunken,
    _TextClass.component,
  ),

  // --- Banner: tinted paper surface, accent glyph, ink title.
  const _Pair(
    'banner.dart:101 success title (body 13 w600)',
    BombFlowerColors.successInk,
    BombFlowerColors.successSurface,
    _TextClass.normal,
  ),
  const _Pair(
    'banner.dart:101 warning title (body 13 w600)',
    BombFlowerColors.warningInk,
    BombFlowerColors.warningSurface,
    _TextClass.normal,
  ),
  const _Pair(
    'banner.dart:101 danger title (body 13 w600)',
    BombFlowerColors.dangerInk,
    BombFlowerColors.dangerSurface,
    _TextClass.normal,
  ),
  const _Pair(
    'banner.dart:101 info title (body 13 w600)',
    BombFlowerColors.infoInk,
    BombFlowerColors.infoSurface,
    _TextClass.normal,
  ),
  const _Pair(
    'banner.dart:110 success message (body 13)',
    BombFlowerColors.inkSecondary,
    BombFlowerColors.successSurface,
    _TextClass.normal,
  ),
  const _Pair(
    'banner.dart:110 warning message (body 13)',
    BombFlowerColors.inkSecondary,
    BombFlowerColors.warningSurface,
    _TextClass.normal,
  ),
  const _Pair(
    'banner.dart:110 danger message (body 13)',
    BombFlowerColors.inkSecondary,
    BombFlowerColors.dangerSurface,
    _TextClass.normal,
  ),
  const _Pair(
    'banner.dart:110 info message (body 13)',
    BombFlowerColors.inkSecondary,
    BombFlowerColors.infoSurface,
    _TextClass.normal,
  ),
  const _Pair(
    'banner.dart:84 success glyph',
    BombFlowerColors.success,
    BombFlowerColors.successSurface,
    _TextClass.component,
  ),
  const _Pair(
    'banner.dart:84 warning glyph',
    BombFlowerColors.warning,
    BombFlowerColors.warningSurface,
    _TextClass.component,
  ),
  const _Pair(
    'banner.dart:84 danger glyph',
    BombFlowerColors.danger,
    BombFlowerColors.dangerSurface,
    _TextClass.component,
  ),
  const _Pair(
    'banner.dart:84 info glyph',
    BombFlowerColors.info,
    BombFlowerColors.infoSurface,
    _TextClass.component,
  ),
  const _Pair(
    'banner.dart:159 success dismiss glyph',
    BombFlowerColors.inkMuted,
    BombFlowerColors.successSurface,
    _TextClass.component,
  ),
  const _Pair(
    'banner.dart:159 warning dismiss glyph',
    BombFlowerColors.inkMuted,
    BombFlowerColors.warningSurface,
    _TextClass.component,
  ),
  const _Pair(
    'banner.dart:159 danger dismiss glyph',
    BombFlowerColors.inkMuted,
    BombFlowerColors.dangerSurface,
    _TextClass.component,
  ),
  const _Pair(
    'banner.dart:159 info dismiss glyph',
    BombFlowerColors.inkMuted,
    BombFlowerColors.infoSurface,
    _TextClass.component,
  ),
  const _Pair(
    'banner.dart:167 dismiss focus ring',
    BombFlowerColors.focusOnLight,
    BombFlowerColors.dangerSurface,
    _TextClass.component,
  ),

  // --- RuneChip badges.
  const _Pair(
    'rune_chip.dart:131 neutral chip label (caption 11 w700)',
    BombFlowerColors.ink,
    BombFlowerColors.parchmentSunken,
    _TextClass.normal,
  ),
  const _Pair(
    'rune_chip.dart:130 neutral chip border',
    BombFlowerColors.stone,
    BombFlowerColors.parchmentSunken,
    _TextClass.component,
  ),
  const _Pair(
    'rune_chip.dart:105 unknown chip label (caption 11 w700)',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchmentSunken,
    _TextClass.normal,
  ),
  const _Pair(
    'rune_chip.dart:104 unknown chip border',
    BombFlowerColors.stone,
    BombFlowerColors.parchmentSunken,
    _TextClass.component,
  ),
  const _Pair(
    'rune_chip.dart:93 modified chip label (caption 11 w700)',
    BombFlowerColors.brassInk,
    BombFlowerColors.selection,
    _TextClass.normal,
  ),
  const _Pair(
    'rune_chip.dart:92 modified chip border',
    BombFlowerColors.brassInk,
    BombFlowerColors.selection,
    _TextClass.component,
  ),
  const _Pair(
    'rune_chip.dart:99 invalid chip label (caption 11 w700)',
    BombFlowerColors.dangerInk,
    BombFlowerColors.dangerSurface,
    _TextClass.normal,
  ),
  const _Pair(
    'rune_chip.dart:111 info chip label (caption 11 w700)',
    BombFlowerColors.infoInk,
    BombFlowerColors.infoSurface,
    _TextClass.normal,
  ),
  const _Pair(
    'rune_chip.dart:117 success chip label (caption 11 w700)',
    BombFlowerColors.successInk,
    BombFlowerColors.successSurface,
    _TextClass.normal,
  ),
  const _Pair(
    'rune_chip.dart:123 warning chip label (caption 11 w700)',
    BombFlowerColors.warningInk,
    BombFlowerColors.warningSurface,
    _TextClass.normal,
  ),

  // --- ErrorState plate on parchment.
  const _Pair(
    'error_state.dart:87 plate title (h3 18 w600)',
    BombFlowerColors.dangerInk,
    BombFlowerColors.dangerSurface,
    _TextClass.normal,
  ),
  const _Pair(
    'error_state.dart:94 plate message (body 14)',
    BombFlowerColors.ink,
    BombFlowerColors.dangerSurface,
    _TextClass.normal,
  ),
  const _Pair(
    'error_state.dart:157 details text (mono 11)',
    BombFlowerColors.inkSecondary,
    BombFlowerColors.parchmentSunken,
    _TextClass.normal,
  ),
  const _Pair(
    'error_state.dart:63 accent bar',
    BombFlowerColors.danger,
    BombFlowerColors.dangerSurface,
    _TextClass.component,
  ),
  const _Pair(
    'error_state.dart:197 plate glyph stroke',
    BombFlowerColors.danger,
    BombFlowerColors.dangerSurface,
    _TextClass.component,
  ),

  // --- ItemGrid slot plates.
  const _Pair(
    'item_grid.dart:376 empty slot dashed border',
    BombFlowerColors.stone,
    BombFlowerColors.parchmentSunken,
    _TextClass.component,
  ),
  const _Pair(
    'item_grid.dart:385 filled slot border',
    BombFlowerColors.stone,
    BombFlowerColors.parchmentAlt,
    _TextClass.component,
  ),
  const _Pair(
    'item_grid.dart:384 selected slot border',
    BombFlowerColors.brassInk,
    BombFlowerColors.selection,
    _TextClass.component,
  ),
  const _Pair(
    'item_grid.dart:217 slot label (caption 11)',
    BombFlowerColors.inkSecondary,
    BombFlowerColors.parchmentAlt,
    _TextClass.normal,
  ),
  const _Pair(
    'item_grid.dart:274 selected slot label (caption 11)',
    BombFlowerColors.brassInk,
    BombFlowerColors.selection,
    _TextClass.normal,
  ),
  const _Pair(
    'item_grid.dart:296 actionable slot danger label (caption 11)',
    BombFlowerColors.danger,
    BombFlowerColors.parchmentAlt,
    _TextClass.normal,
  ),
  const _Pair(
    'item_grid.dart:306 slot focus ring',
    BombFlowerColors.focusOnLight,
    BombFlowerColors.selection,
    _TextClass.component,
  ),

  // --- FieldRow labels and help on parchment.
  const _Pair(
    'field_row.dart:75 field label (label 12)',
    BombFlowerColors.ink,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'field_row.dart:90 read-only caption (caption 11)',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'field_row.dart:112 inline error (caption 11)',
    BombFlowerColors.danger,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'field_row.dart:123 helper (caption 11)',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'field_row.dart:136 counter (mono 11)',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),

  // --- ControlIconButton defaults on paper, and its dark overrides.
  const _Pair(
    'control_icon_button.dart:95 button border on paper',
    BombFlowerColors.stone,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),
  const _Pair(
    'control_icon_button.dart:101 glyph on paper',
    BombFlowerColors.ink,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),
  const _Pair(
    'control_icon_button.dart:111 focus ring on paper',
    BombFlowerColors.focusOnLight,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),

  // --- Toggle, checkbox, slider tracks and glyphs on paper.
  const _Pair(
    'brass_toggle.dart:65 toggle label (label 12)',
    BombFlowerColors.ink,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'brass_toggle.dart:67 toggle sublabel (caption 11)',
    BombFlowerColors.inkMuted,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'brass_toggle.dart:241 track fill, on',
    BombFlowerColors.stoneDark,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),
  const _Pair(
    'brass_toggle.dart:241 track fill, off',
    BombFlowerColors.stone,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),
  const _Pair(
    'brass_toggle.dart:265 hovered track border',
    BombFlowerColors.stoneLight,
    BombFlowerColors.parchment,
    _TextClass.component,
  ),
  const _Pair(
    'rune_checkbox.dart:67 checkbox label (label 12)',
    BombFlowerColors.ink,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'rune_checkbox.dart:221 checked glyph',
    BombFlowerColors.brassInk,
    BombFlowerColors.parchmentRaised,
    _TextClass.component,
  ),
  const _Pair(
    'rune_checkbox.dart:212 checkbox border',
    BombFlowerColors.stone,
    BombFlowerColors.parchmentSunken,
    _TextClass.component,
  ),
  const _Pair(
    'brass_slider.dart:147 slider readout (label 12)',
    BombFlowerColors.brassInk,
    BombFlowerColors.parchment,
    _TextClass.normal,
  ),
  const _Pair(
    'brass_slider.dart:372 slider track border',
    BombFlowerColors.stone,
    BombFlowerColors.parchmentSunken,
    _TextClass.component,
  ),

  // --- Selection and focus accents exposed by ThemeData.
  const _Pair(
    'bomb_flower_theme.dart:253 text selection highlight',
    BombFlowerColors.ink,
    BombFlowerColors.selection,
    _TextClass.normal,
  ),
  const _Pair(
    'bomb_flower_theme.dart:226 focus ring on canopy2 overlay',
    BombFlowerColors.brassFocus,
    BombFlowerColors.canopy2,
    _TextClass.component,
  ),
  const _Pair(
    'bomb_flower_theme.dart:226 focus ring on canopy0',
    BombFlowerColors.brassFocus,
    BombFlowerColors.canopy0,
    _TextClass.component,
  ),

  // --- HexEditor read-only danger styling on its own canopy surfaces.
  _Pair(
    'hex_editor.dart:507 READ-ONLY word on its 16% danger tint over canopyDeep',
    BombFlowerColors.dangerLight,
    _composite(
      BombFlowerColors.dangerLight.withValues(alpha: 0.16),
      BombFlowerColors.canopy0,
    ),
    _TextClass.normal,
  ),
  _Pair(
    'hex_editor.dart:501 READ-ONLY border on its 16% danger tint over canopyDeep',
    BombFlowerColors.dangerLight,
    _composite(
      BombFlowerColors.dangerLight.withValues(alpha: 0.16),
      BombFlowerColors.canopy0,
    ),
    _TextClass.component,
  ),
  _Pair(
    'hex_editor.dart:1509 invalid byte glyph on its 28% wash over canopyRaised',
    BombFlowerColors.dangerLight,
    _composite(
      BombFlowerColors.danger.withValues(alpha: 0.28),
      BombFlowerColors.canopy1,
    ),
    _TextClass.normal,
  ),
  const _Pair(
    'hex_editor.dart:1086 error glyph on canopyDeep',
    BombFlowerColors.dangerLight,
    BombFlowerColors.canopy0,
    _TextClass.component,
  ),
  const _Pair(
    'hex_editor.dart:1139 input error text on canopyHigh',
    BombFlowerColors.dangerLight,
    BombFlowerColors.canopy2,
    _TextClass.normal,
  ),
  const _Pair(
    'hex_editor.dart:1146 error border on canopyHigh',
    BombFlowerColors.dangerLight,
    BombFlowerColors.canopy2,
    _TextClass.component,
  ),
];
