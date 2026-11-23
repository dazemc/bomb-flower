import 'dart:async';

import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart' hide Banner;

import '../../data/system/directory_lister.dart';
import '../../data/system/directory_picker.dart';
import '../theme/bomb_flower_colors.dart';
import '../theme/bomb_flower_spacing.dart';
import '../theme/bomb_flower_typography.dart';
import '../widgets/common/banner.dart';
import '../widgets/common/brass_button.dart';
import 'save_dialog_frame.dart';

/// In-app save-folder chooser.
///
/// The dialog lists one directory at a time through [DirectoryLister]; no host
/// process, and therefore no system dialog, is ever started from here.
///
/// CANCEL HARD RULE: Escape, the Cancel button, and a scrim tap each pop the
/// route with `null` synchronously. No cancel path awaits anything, so Cancel
/// keeps working while a listing is still in flight and the dialog can never
/// wedge behind a slow or dead filesystem.
class OpenSaveDialog extends StatefulWidget {
  /// Creates the dialog.
  const OpenSaveDialog({
    super.key,
    required this.probe,
    required this.recentPaths,
    this.directoryLister,
    this.initialPath,
  });

  /// Folder inspector kept for API compatibility with the open workflow.
  ///
  /// Phase 1 of the picker lists directories through [directoryLister]; this
  /// port stays in the signature because callers already supply it.
  final SaveFolderProbe probe;

  /// Recent-folder port. Open records the chosen folder without awaiting it.
  final RecentPathsStore recentPaths;

  /// Directory listing port. Null uses the real filesystem.
  final DirectoryLister? directoryLister;

  /// Pre-filled start folder.
  final String? initialPath;

  /// Shows the dialog and returns the chosen folder, or `null`.
  static Future<String?> show(
    BuildContext context, {
    required SaveFolderProbe probe,
    required RecentPathsStore recentPaths,
    String? initialPath,
    DirectoryLister? directoryLister,
  }) {
    return showDialog<String>(
      context: context,
      barrierColor: BombFlowerColors.scrim,
      barrierDismissible: true,
      builder: (dialogContext) => OpenSaveDialog(
        probe: probe,
        recentPaths: recentPaths,
        directoryLister: directoryLister,
        initialPath: initialPath,
      ),
    );
  }

  @override
  State<OpenSaveDialog> createState() => _OpenSaveDialogState();
}

class _OpenSaveDialogState extends State<OpenSaveDialog> {
  late final TextEditingController _pathController;
  final FocusNode _listFocus = FocusNode(debugLabel: 'open-save-list');
  DirectoryListing? _listing;
  String? _selectedPath;
  bool _loading = false;
  int _sequence = 0;

  DirectoryLister get _lister =>
      widget.directoryLister ?? const IoDirectoryLister();

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.initialPath ?? '');
    // Resolve the start folder off the first frame: the dialog paints at once
    // and a slow filesystem cannot delay Cancel.
    unawaited(_start());
  }

  @override
  void dispose() {
    _pathController.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final initial = widget.initialPath?.trim();
    final start = initial != null && initial.isNotEmpty
        ? initial
        : (_lister.homeDirectory ?? '/');
    await _navigate(start);
  }

  Future<void> _navigate(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final sequence = ++_sequence;
    setState(() {
      _loading = true;
      _selectedPath = null;
    });
    final listing = await _lister.list(trimmed);
    // A newer navigation, or a closed dialog, discards this result.
    if (!mounted || sequence != _sequence) {
      return;
    }
    setState(() {
      _listing = listing;
      _loading = false;
      _pathController.text = listing.path;
      _pathController.selection = TextSelection.collapsed(
        offset: listing.path.length,
      );
    });
  }

  DirectoryEntry? get _selectedEntry {
    final listing = _listing;
    final selected = _selectedPath;
    if (listing == null || selected == null) {
      return null;
    }
    for (final entry in listing.entries) {
      if (entry.path == selected) {
        return entry;
      }
    }
    return null;
  }

  /// Only a folder that directly contains a slot folder can be opened: the
  /// current folder, a selected child that holds slots, or the folder holding
  /// a selected `slot_NN` child.
  String? get _openTarget {
    final listing = _listing;
    if (_loading || listing == null || listing.error != null) {
      return null;
    }
    final selected = _selectedEntry;
    if (selected != null) {
      if (selected.isDirectory && selected.containsSlots) {
        return selected.path;
      }
      if (selected.isSlotDirectory) {
        return listing.path;
      }
    }
    return listing.isProfile ? listing.path : null;
  }

  void _select(DirectoryEntry entry) {
    setState(() => _selectedPath = entry.path);
    _listFocus.requestFocus();
  }

  void _descend(DirectoryEntry entry) {
    if (entry.isDirectory) {
      unawaited(_navigate(entry.path));
    }
  }

  void _goToParent() {
    final parent = _listing?.parentPath;
    if (parent != null) {
      unawaited(_navigate(parent));
    }
  }

  void _submitTypedPath() {
    unawaited(_navigate(_pathController.text));
  }

  void _activateSelection() {
    final entry = _selectedEntry;
    if (entry != null) {
      _descend(entry);
    }
  }

  void _submit() {
    final target = _openTarget;
    if (target == null) {
      return;
    }
    // Recorded, never awaited: Open must return immediately.
    unawaited(widget.recentPaths.add(target));
    Navigator.of(context).pop(target);
  }

  KeyEventResult _handleListKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter) {
      _activateSelection();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _entryRow(DirectoryEntry entry) {
    final isSelected = entry.path == _selectedPath;
    final canOpen = entry.isDirectory;
    final color = canOpen ? BombFlowerColors.ink : BombFlowerColors.inkMuted;
    return InkWell(
      key: Key('open-save-entry-${entry.name}'),
      onTap: canOpen ? () => _select(entry) : null,
      onDoubleTap: canOpen ? () => _descend(entry) : null,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? BombFlowerColors.parchmentSunken
              : Colors.transparent,
          border: isSelected
              ? Border.all(color: BombFlowerColors.brassInk, width: 1.5)
              : null,
          borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: BombFlowerSpacing.md,
          vertical: BombFlowerSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              entry.isDirectory
                  ? Icons.folder_outlined
                  : Icons.insert_drive_file_outlined,
              size: 16,
              color: canOpen
                  ? BombFlowerColors.inkSecondary
                  : BombFlowerColors.inkMuted,
            ),
            const SizedBox(width: BombFlowerSpacing.sm),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BombFlowerTypography.caption.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _parentRow() {
    final parent = _listing?.parentPath;
    final enabled = parent != null;
    return InkWell(
      key: const Key('open-save-parent'),
      onTap: enabled ? _goToParent : null,
      onDoubleTap: enabled ? _goToParent : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BombFlowerSpacing.md,
          vertical: BombFlowerSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.drive_folder_upload_outlined,
              size: 16,
              color: enabled
                  ? BombFlowerColors.inkSecondary
                  : BombFlowerColors.inkMuted,
            ),
            const SizedBox(width: BombFlowerSpacing.sm),
            Text(
              '..',
              style: BombFlowerTypography.caption.copyWith(
                color: enabled
                    ? BombFlowerColors.ink
                    : BombFlowerColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listingBody() {
    final listing = _listing;
    if (listing == null) {
      if (_loading) {
        return Text(
          'Reading folder…',
          style: BombFlowerTypography.caption.copyWith(
            color: BombFlowerColors.inkMuted,
          ),
        );
      }
      return const SizedBox.shrink();
    }
    if (listing.error != null) {
      return Text(
        listing.error!,
        key: const Key('open-save-listing-error'),
        style: BombFlowerTypography.caption.copyWith(
          color: BombFlowerColors.dangerInk,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _parentRow(),
        Container(
          height: 280,
          decoration: BoxDecoration(
            color: BombFlowerColors.parchmentRaised,
            borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
            border: Border.all(color: BombFlowerColors.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: Focus(
            focusNode: _listFocus,
            onKeyEvent: _handleListKey,
            child: ListView.builder(
              key: const Key('open-save-list'),
              padding: EdgeInsets.zero,
              itemCount: listing.entries.length,
              itemBuilder: (context, index) => _entryRow(listing.entries[index]),
            ),
          ),
        ),
        if (_selectedEntry case final selected?) ...<Widget>[
          const SizedBox(height: BombFlowerSpacing.sm),
          Text(
            'Selected: ${selected.path}'
            '${selected.containsSlots ? ' (contains save slots)' : ''}',
            key: const Key('open-save-selected'),
            style: BombFlowerTypography.caption.copyWith(
              color: BombFlowerColors.inkSecondary,
            ),
          ),
        ],
        if (listing.isProfile) ...<Widget>[
          const SizedBox(height: BombFlowerSpacing.lg),
          Banner(
            key: const Key('open-save-valid'),
            variant: BannerVariant.success,
            title: 'Save folder found',
            message:
                'Contains ${listing.slotNames.length} slot '
                '${listing.slotNames.length == 1 ? 'folder' : 'folders'}: '
                '${listing.slotNames.join(', ')}.',
          ),
        ] else if (!_loading) ...<Widget>[
          const SizedBox(height: BombFlowerSpacing.sm),
          Text(
            'This folder has no slot_00…slot_09 folders. Open the folder that '
            'contains them.',
            key: const Key('open-save-blocked-reason'),
            style: BombFlowerTypography.caption.copyWith(
              color: BombFlowerColors.inkMuted,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = _openTarget;
    return SaveDialogFrame(
      title: 'Open save folder',
      subtitle: 'Choose the folder that holds the slot folders, not a slot '
          'itself.',
      icon: Icons.folder_open_outlined,
      footer: SaveDialogActions(
        children: <Widget>[
          const SaveDialogCancelButton(key: Key('open-save-cancel')),
          BrassButton(
            key: const Key('open-save-submit'),
            label: 'Open',
            icon: Icons.folder_open,
            onPressed: target == null ? null : _submit,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            key: const Key('open-save-path'),
            controller: _pathController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitTypedPath(),
            decoration: const InputDecoration(
              labelText: 'Save folder',
              hintText: '/path/to/save/folder',
            ),
          ),
          if (_loading) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.sm),
            Text(
              'Reading folder…',
              style: BombFlowerTypography.caption.copyWith(
                color: BombFlowerColors.inkMuted,
              ),
            ),
          ],
          const SizedBox(height: BombFlowerSpacing.md),
          _listingBody(),
        ],
      ),
    );
  }
}
