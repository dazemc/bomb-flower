import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../theme/bomb_flower_spacing.dart';
import 'shell_state.dart';
import 'tab_definition.dart';

/// Owns navigation selection, rail collapse, window-chrome gating, and the
/// global status/validation placeholders. No save data is read or written.
class ShellCubit extends Cubit<ShellState> {
  ShellCubit({bool windowChromeEnabled = true})
    : super(ShellState(windowChromeEnabled: windowChromeEnabled));

  /// Automatic rail collapse threshold. Below 1280 logical pixels the rail
  /// becomes 64 px icon-only, per the delivery contract.
  static const double navCollapseBreakpoint =
      BombFlowerSpacing.compactBreakpoint;

  void selectTab(ShellTab tab) {
    if (state.activeTab == tab) return;
    emit(state.copyWith(activeTab: tab));
  }

  /// Selects by navigation order (0..10). Out-of-range indices are ignored.
  void selectTabByIndex(int index) {
    if (index < 0 || index >= ShellTab.values.length) return;
    selectTab(ShellTab.values[index]);
  }

  /// Wraps around both ends; keeps keyboard cycling predictable.
  void cycleTab(int delta) {
    if (delta == 0) return;
    final count = ShellTab.values.length;
    final current = state.activeTab.index;
    final next = (current + delta) % count;
    selectTab(ShellTab.values[next < 0 ? next + count : next]);
  }

  /// Applies the responsive collapse threshold. The shell also derives this
  /// from LayoutBuilder so the correct width paints on the first frame.
  void setViewportWidth(double width) {
    if (!width.isFinite) return;
    final collapsed = width < navCollapseBreakpoint;
    if (collapsed == state.navCollapsed) return;
    emit(state.copyWith(navCollapsed: collapsed));
  }

  /// Handles a direct tab jump or Ctrl+Tab cycle. Returns true if consumed.
  ///
  /// Callers are responsible for not forwarding Alt-chords while a text field
  /// has focus; the shell checks before invoking this.
  bool handleShortcut({
    required LogicalKeyboardKey key,
    bool alt = false,
    bool ctrl = false,
    bool shift = false,
    bool meta = false,
  }) {
    final cycle = shellCycleDeltaForShortcut(
      key: key,
      alt: alt,
      ctrl: ctrl,
      shift: shift,
      meta: meta,
    );
    if (cycle != null) {
      cycleTab(cycle);
      return true;
    }

    final tab = shellTabForShortcut(
      key: key,
      alt: alt,
      ctrl: ctrl,
      shift: shift,
      meta: meta,
    );
    if (tab == null) return false;
    selectTab(tab);
    return true;
  }
}
