import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../bloc/save_session/save_session_cubit.dart';
import '../../bloc/save_session/save_session_ui_state.dart';
import '../../dialogs/compare_save_dialog.dart';
import '../../theme/bomb_flower_colors.dart';
import '../controls/control_icon_button.dart';

/// The one tooltip/screen-reader phrasing shared by both comparison entries.
const String _compareTooltip = 'Compare original and edited save';

/// Icon-only title-bar action that opens the original-versus-edited comparison.
///
/// The action reads the ambient [SaveSessionCubit] so a bar pumped without a
/// provider renders disabled instead of throwing. It is enabled only while an
/// open project differs from its open-time original.
final class CompareAction extends StatelessWidget {
  /// Creates the comparison action.
  const CompareAction({super.key});

  @override
  Widget build(BuildContext context) {
    return _compareState(
      context,
      (context, enabled) => Padding(
        key: const Key('shell-action-compare'),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ControlIconButton(
          icon: Icons.compare_arrows,
          onPressed: enabled ? () => _show(context) : null,
          semanticLabel: 'Compare',
          tooltip: _compareTooltip,
          iconSize: 15,
          foregroundColor: BombFlowerColors.bone,
          borderColor: BombFlowerColors.woodLight,
          hoverColor: BombFlowerColors.canopyHover,
          focusColor: BombFlowerColors.brassFocus,
        ),
      ),
    );
  }
}

/// The same comparison action inside the collapsed overflow menu.
final class CompareMenuAction extends StatelessWidget {
  /// Creates the menu entry.
  const CompareMenuAction({super.key});

  @override
  Widget build(BuildContext context) {
    return _compareState(
      context,
      (context, enabled) => MenuItemButton(
        key: const Key('shell-action-compare'),
        leadingIcon: const Icon(Icons.compare_arrows, size: 16),
        onPressed: enabled ? () => _show(context) : null,
        child: const Text('Compare'),
      ),
    );
  }
}

/// Builds [build] with the session's current enablement.
///
/// A missing provider means "no session", which is a disabled action rather
/// than an error, so the bar always lays out.
Widget _compareState(
  BuildContext context,
  Widget Function(BuildContext context, bool enabled) build,
) {
  final cubit = _sessionOf(context);
  if (cubit == null) {
    return build(context, false);
  }
  return BlocBuilder<SaveSessionCubit, SaveSessionUiState>(
    bloc: cubit,
    builder: (context, state) =>
        build(context, cubit.openProject?.dirty.differsFromOriginal ?? false),
  );
}

/// The injected session, or null when this bar has no provider.
SaveSessionCubit? _sessionOf(BuildContext context) {
  try {
    return context.read<SaveSessionCubit>();
  } on ProviderNotFoundException {
    return null;
  }
}

/// Opens the dialog for the project currently in the session, if any.
void _show(BuildContext context) {
  final cubit = _sessionOf(context);
  final project = cubit?.openProject;
  if (cubit == null || project == null) {
    return;
  }
  unawaited(
    CompareSaveDialog.show(
      context,
      project: project,
      slotLabel: _activeSlotLabel(cubit.state),
    ),
  );
}

/// The active slot carried by the current state, or null when there is none.
String? _activeSlotLabel(SaveSessionUiState state) {
  return switch (state) {
    SaveSessionReady(:final project) => project.activeSlot?.value,
    SaveSessionSaving(:final project) => project.activeSlot?.value,
    SaveSessionSaved(:final project) => project?.activeSlot?.value,
    SaveSessionPendingDiscard(:final project) => project.activeSlot?.value,
    SaveSessionError(:final project) => project?.activeSlot?.value,
    SaveSessionClosed() || SaveSessionOpening() => null,
  };
}
