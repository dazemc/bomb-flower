import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../controls/control_icon_button.dart';
import 'compare_action.dart';

/// Compact shell action group: open, save, save-as, duplicate, reset, undo/redo.
///
/// Enablement is decided by the caller, which owns the session: a null callback
/// renders the action disabled. The group is icon-only so it fits the 44 px
/// title bar without competing with the save name at 1100 px wide; every icon
/// carries the label as its tooltip and screen-reader name.
///
/// Below [collapseBreakpoint] the eight icons collapse into one overflow menu so
/// the brand and save identity keep their room.
class FileActionBar extends StatelessWidget {
  /// Creates the action group.
  const FileActionBar({
    super.key,
    required this.onOpen,
    required this.onSave,
    required this.onSaveAs,
    required this.onDuplicate,
    required this.onReset,
    required this.onUndo,
    required this.onRedo,
    this.disabledReason,
  });

  /// Window width below which the actions collapse into one overflow menu.
  static const double collapseBreakpoint = 1280;

  /// Opens the save-folder dialog.
  final VoidCallback? onOpen;

  /// Saves in place; null when nothing changed.
  final VoidCallback? onSave;

  /// Opens the Save As destination dialog.
  final VoidCallback? onSaveAs;

  /// Writes one slot's original bytes to a chosen destination.
  final VoidCallback? onDuplicate;

  /// Restores a slot from its retained backup, after confirmation.
  final VoidCallback? onReset;

  /// Steps back through the edit history.
  final VoidCallback? onUndo;

  /// Steps forward through the edit history.
  final VoidCallback? onRedo;

  /// Why every action is disabled, appended to each tooltip when set.
  final String? disabledReason;

  /// Tooltip for [label], including [disabledReason] when provided.
  String _tooltip(String label, VoidCallback? action) {
    final reason = disabledReason;
    if (action == null && reason != null && reason.isNotEmpty) {
      return '$label — $reason';
    }
    return label;
  }

  /// The seven actions in display order.
  ///
  /// One list feeds both the wide row and the collapsed menu so the keys,
  /// labels and enablement can never drift apart.
  List<_FileAction> _actions() {
    return <_FileAction>[
      _FileAction(
        key: const Key('shell-action-open'),
        label: 'Open',
        icon: Icons.folder_open_outlined,
        onPressed: onOpen,
      ),
      _FileAction(
        key: const Key('shell-action-save'),
        label: 'Save',
        icon: Icons.save_outlined,
        onPressed: onSave,
      ),
      _FileAction(
        key: const Key('shell-action-save-as'),
        label: 'Save As…',
        icon: Icons.drive_file_move_outline,
        onPressed: onSaveAs,
      ),
      _FileAction(
        key: const Key('shell-action-duplicate'),
        label: 'Duplicate',
        icon: Icons.copy_all_outlined,
        onPressed: onDuplicate,
      ),
      _FileAction(
        key: const Key('shell-action-reset'),
        label: 'Reset slot…',
        icon: Icons.restore_outlined,
        onPressed: onReset,
      ),
      _FileAction(
        key: const Key('shell-action-undo'),
        label: 'Undo',
        icon: Icons.undo,
        onPressed: onUndo,
      ),
      _FileAction(
        key: const Key('shell-action-redo'),
        label: 'Redo',
        icon: Icons.redo,
        onPressed: onRedo,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions();
    final collapsed =
        MediaQuery.sizeOf(context).width < collapseBreakpoint;
    return Row(
      key: const Key('file-action-bar'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (collapsed) _overflowMenu(actions) else _actionRow(actions),
      ],
    );
  }

  Widget _actionRow(List<_FileAction> actions) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var index = 0; index < actions.length; index++) ...<Widget>[
          // Keep the edit-history pair visually separate from the file actions.
          if (index == 5) const _ActionDivider(),
          _action(actions[index]),
          if (index == 4) const CompareAction(),
        ],
      ],
    );
  }

  Widget _action(_FileAction action) {
    return _Action(
      key: action.key,
      label: action.label,
      icon: action.icon,
      onPressed: action.onPressed,
      tooltip: _tooltip(action.label, action.onPressed),
    );
  }

  Widget _overflowMenu(List<_FileAction> actions) {
    return MenuAnchor(
      menuChildren: <Widget>[
        for (var index = 0; index < actions.length; index++) ...<Widget>[
          Tooltip(
            message: _tooltip(actions[index].label, actions[index].onPressed),
            child: MenuItemButton(
              key: actions[index].key,
              leadingIcon: Icon(actions[index].icon, size: 16),
              onPressed: actions[index].onPressed,
              child: Text(actions[index].label),
            ),
          ),
          if (index == 4) const CompareMenuAction(),
        ],
      ],
      builder: (context, controller, child) => _action(
        _FileAction(
          key: const Key('shell-action-overflow'),
          label: 'File actions',
          icon: Icons.more_horiz,
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        ),
      ),
    );
  }
}

/// One label/icon/callback triple shared by the row and the overflow menu.
class _FileAction {
  const _FileAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final Key key;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
}

class _Action extends StatelessWidget {
  const _Action({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ControlIconButton(
        icon: icon,
        onPressed: onPressed,
        semanticLabel: label,
        tooltip: tooltip,
        iconSize: 15,
        foregroundColor: BombFlowerColors.bone,
        borderColor: BombFlowerColors.woodLight,
        hoverColor: BombFlowerColors.canopyHover,
        focusColor: BombFlowerColors.brassFocus,
      ),
    );
  }
}

class _ActionDivider extends StatelessWidget {
  const _ActionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: BombFlowerSpacing.sm),
      color: BombFlowerColors.woodLight,
    );
  }
}
