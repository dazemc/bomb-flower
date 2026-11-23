import 'dart:async';

import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey;
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:material_ui/material_ui.dart' hide Banner;

import '../../data/system/directory_lister.dart';
import '../../data/system/directory_picker.dart';
import '../../data/system/profile_path.dart';
import '../theme/bomb_flower_colors.dart';
import '../theme/bomb_flower_spacing.dart';
import '../theme/bomb_flower_typography.dart';
import '../shell/tabs/settings_tab.dart';
import '../widgets/common/banner.dart';
import '../widgets/common/brass_button.dart';
import 'save_dialog_frame.dart';

/// In-app save-folder browser: the one open-save dialog.
///
/// It pairs the typed `open-save-path` field with the keyed listing
/// (`open-save-entry-<name>`), parent (`open-save-parent`), validity
/// (`open-save-valid`), blocked (`open-save-blocked-reason`) and error
/// (`open-save-listing-error`) affordances. `open_save_dialog.dart` re-exports
/// this widget so every caller keeps one import path and one implementation.
///
/// It lists one directory at a time through [DirectoryLister]; no host process,
/// and therefore no system dialog, is ever started from here. The start folder
/// comes from [resolveOpenSaveStartFolder], which discovers a real profile
/// rather than assuming a platform path.
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
    this.settingsStore,
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

  /// Preferences store for the "Show hidden" toggle.
  final SettingsStore? settingsStore;

  /// Pre-filled start folder.
  final String? initialPath;

  /// Shows the dialog and returns the chosen folder, or `null`.
  static Future<String?> show(
    BuildContext context, {
    required SaveFolderProbe probe,
    required RecentPathsStore recentPaths,
    String? initialPath,
    DirectoryLister? directoryLister,
    SettingsStore? settingsStore,
  }) {
    return showDialog<String>(
      context: context,
      barrierColor: BombFlowerColors.scrim,
      barrierDismissible: true,
      builder: (dialogContext) => OpenSaveDialog(
        probe: probe,
        recentPaths: recentPaths,
        directoryLister: directoryLister,
        settingsStore: settingsStore ?? InMemorySettingsStore(),
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
  bool _showHidden = false;
  bool _submitted = false;
  bool _loggedMetrics = false;
  int _sequence = 0;

  /// Why no start folder could be resolved, or `null` before/after a listing.
  ///
  /// A null start folder is not guessed: it is reported under
  /// `open-save-listing-error` instead of leaving the listing area blank.
  String? _startFolderError;

  final GlobalKey _panelKey = GlobalKey();
  final GlobalKey _cancelRectKey = GlobalKey();
  final GlobalKey _openRectKey = GlobalKey();

  late final SettingsStore _settings =
      widget.settingsStore ?? InMemorySettingsStore();

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
    // Distinguishes an Open pop from Cancel/Esc/scrim when reading a field log.
    debugPrint('[open-picker] disposed submit=$_submitted');
    _pathController.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final preferences = await _settings.load();
    if (!mounted) {
      return;
    }
    _showHidden = preferences.showHiddenEntries;
    final initial = widget.initialPath?.trim();
    final lastUsed = preferences.recentPaths.isEmpty
        ? null
        : preferences.recentPaths.first;
    final start = initial != null && initial.isNotEmpty
        ? initial
        : await resolveOpenSaveStartFolder(
            lastUsedPath: lastUsed,
            lister: _lister,
          );
    if (start == null || start.isEmpty) {
      // Nothing is guessed: leave the field empty for the human to type a path,
      // and say so under the listing-error key rather than rendering nothing.
      if (!mounted) {
        return;
      }
      setState(() {
        _startFolderError =
            'No save folder was found. Type the path to the folder that '
            'contains slot_00…slot_09.';
      });
      return;
    }
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
    final listing = await _lister.list(
      trimmed,
      includeHidden: _showHidden,
    );
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
      if (selected.isSlotDirectory && listing.isProfile) {
        return listing.path;
      }
      if (selected.isDirectory && selected.containsSlots) {
        return selected.path;
      }
    }
    return listing.isProfile ? listing.path : null;
  }

  /// A single tap on a plain folder descends; a profile folder, a slot folder,
  /// or a file is selected. Double-click and Enter still descend.
  void _tapEntry(DirectoryEntry entry) {
    if (entry.isDirectory &&
        !entry.containsSlots &&
        !entry.isSlotDirectory) {
      _descend(entry);
      return;
    }
    _select(entry);
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
    final listing = _listing;
    final parent = listing?.parentPath;
    if (listing == null || parent == null || parent == listing.path) {
      return;
    }
    debugPrint('[open-picker] up -> $parent');
    unawaited(_navigate(parent));
  }

  void _submitTypedPath() {
    unawaited(_navigate(_pathController.text));
  }

  Future<void> _setShowHidden(bool value) async {
    setState(() => _showHidden = value);
    final preferences = await _settings.load();
    await _settings.save(preferences.copyWith(showHiddenEntries: value));
    if (!mounted) {
      return;
    }
    final current = _listing?.path ?? _pathController.text;
    await _navigate(current);
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
    _submitted = true;
    debugPrint('[open-picker] chose=$target');
    Navigator.of(context).pop(target);
  }

  /// Synchronous close; no await and no work that can fail.
  void _cancel() {
    Navigator.of(context).pop<Object?>(null);
  }

  String _rectLabel(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return 'unavailable';
    }
    final origin = box.localToGlobal(Offset.zero);
    return '$origin&${box.size}';
  }

  String _appWindowValue(Object? Function() read) {
    try {
      return '${read()}';
    } catch (_) {
      return 'unavailable';
    }
  }

  void _logMetricsOnce(BuildContext context) {
    if (_loggedMetrics) {
      return;
    }
    _loggedMetrics = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      debugPrint(
        '[open-picker] metrics '
        'dpr=${MediaQuery.devicePixelRatioOf(context)} '
        'size=${MediaQuery.sizeOf(context)} '
        'viewPhysical=${View.of(context).physicalSize} '
        'viewDpr=${View.of(context).devicePixelRatio} '
        'media=${MediaQuery.sizeOf(context)} '
        'appWindowSize=${_appWindowValue(() => appWindow.size)} '
        'appWindowScale=${_appWindowValue(() => appWindow.scaleFactor)} '
        'requestedMin=Size(800.0, 600.0) '
        'panel=${_rectLabel(_panelKey)} '
        'cancel=${_rectLabel(_cancelRectKey)} '
        'open=${_rectLabel(_openRectKey)}',
      );
    });
  }

  Widget _actionSlot({
    required GlobalKey rectKey,
    required String label,
    required Widget child,
  }) {
    return SizedBox(
      key: rectKey,
      child: Listener(
        onPointerDown: (event) {
          final result = HitTestResult();
          WidgetsBinding.instance.hitTestInView(
            result,
            event.position,
            View.of(context).viewId,
          );
          debugPrint(
            '[open-picker] pointerdown $label at=${event.position} hits='
            '${result.path.take(5).map((entry) => entry.target.runtimeType).toList()}',
          );
        },
        child: child,
      ),
    );
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
      onTap: canOpen ? () => _tapEntry(entry) : null,
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
    final listing = _listing;
    final parent = listing?.parentPath;
    final enabled = listing != null && parent != null && parent != listing.path;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Parent folder',
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        // Single purpose: only onTap, so there is no double-tap recognizer to
        // delay the tap or reinterpret a second click. This control can never
        // pop the route; it only navigates the listing.
        child: InkWell(
          key: const Key('open-save-parent'),
          onTap: enabled ? _goToParent : null,
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
      // No start folder resolved, or the field was submitted empty: never a
      // blank panel, and the existing listing-error key carries the message.
      final failure = _startFolderError;
      return Text(
        failure ??
            'No folder is listed yet. Type the path to the folder that '
                'contains slot_00…slot_09.',
        key: const Key('open-save-listing-error'),
        style: BombFlowerTypography.caption.copyWith(
          color: failure == null
              ? BombFlowerColors.inkMuted
              : BombFlowerColors.dangerInk,
        ),
      );
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
            'This folder has no openable slot (slot_00…slot_09 with '
            'progress.sav). Open the profile folder that contains them.',
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
    _logMetricsOnce(context);
    final target = _openTarget;
    return SaveDialogFrame(
      panelKey: _panelKey,
      title: 'Open save folder',
      subtitle: 'Choose the folder that holds the slot folders, not a slot '
          'itself.',
      icon: Icons.folder_open_outlined,
      footer: SaveDialogActions(
        children: <Widget>[
          _actionSlot(
            rectKey: _cancelRectKey,
            label: 'cancel',
            child: BrassButton(
              key: const Key('open-save-cancel'),
              label: 'Cancel',
              variant: BrassButtonVariant.secondary,
              height: 44,
              minWidth: 160,
              onPressed: _cancel,
            ),
          ),
          _actionSlot(
            rectKey: _openRectKey,
            label: 'open',
            child: BrassButton(
              key: const Key('open-save-submit'),
              label: 'Open',
              icon: Icons.folder_open,
              height: 44,
              minWidth: 160,
              onPressed: target == null ? null : _submit,
            ),
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
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Show hidden folders',
                  style: BombFlowerTypography.caption.copyWith(
                    color: BombFlowerColors.inkSecondary,
                  ),
                ),
              ),
              Switch(
                key: const Key('open-save-show-hidden'),
                value: _showHidden,
                onChanged: (value) => unawaited(_setShowHidden(value)),
              ),
            ],
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
