import 'dart:async';

import 'package:material_ui/material_ui.dart' hide Banner;

import '../../data/system/directory_picker.dart';
import '../theme/bomb_flower_colors.dart';
import '../theme/bomb_flower_spacing.dart';
import '../theme/bomb_flower_typography.dart';
import '../widgets/common/banner.dart';
import '../widgets/common/brass_button.dart';
import 'dialog_paths.dart';
import 'save_dialog_frame.dart';

/// Opens a save folder with live validation, recent paths, and Browse.
///
/// The typed path is always available; Browse is a convenience that degrades
/// to a hint when no native picker is wired or returns nothing.
class OpenSaveDialog extends StatefulWidget {
  /// Creates the dialog.
  const OpenSaveDialog({
    super.key,
    required this.probe,
    required this.recentPaths,
    this.directoryPicker,
    this.initialPath,
  });

  /// Filesystem inspector port.
  final SaveFolderProbe probe;

  /// Recent-folder port.
  final RecentPathsStore recentPaths;

  /// Optional native folder chooser.
  final DirectoryPicker? directoryPicker;

  /// Pre-filled path.
  final String? initialPath;

  /// Shows the dialog and returns the selected folder, or `null`.
  static Future<String?> show(
    BuildContext context, {
    required SaveFolderProbe probe,
    required RecentPathsStore recentPaths,
    DirectoryPicker? directoryPicker,
    String? initialPath,
  }) {
    return showDialog<String>(
      context: context,
      barrierColor: BombFlowerColors.scrim,
      builder: (dialogContext) => OpenSaveDialog(
        probe: probe,
        recentPaths: recentPaths,
        directoryPicker: directoryPicker,
        initialPath: initialPath,
      ),
    );
  }

  @override
  State<OpenSaveDialog> createState() => _OpenSaveDialogState();
}

class _OpenSaveDialogState extends State<OpenSaveDialog> {
  late final TextEditingController _pathController;
  List<String> _recent = const <String>[];
  SaveFolderInfo? _info;
  String? _pickerHint;
  bool _checking = false;
  int _sequence = 0;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.initialPath ?? '');
    unawaited(_loadRecent());
    final initial = widget.initialPath?.trim();
    if (initial != null && initial.isNotEmpty) {
      unawaited(_validate(initial));
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final paths = await widget.recentPaths.read();
    if (!mounted) {
      return;
    }
    setState(() => _recent = paths);
  }

  Future<void> _validate(String value) async {
    final trimmed = value.trim();
    final sequence = ++_sequence;
    if (trimmed.isEmpty) {
      setState(() {
        _info = null;
        _checking = false;
      });
      return;
    }
    setState(() => _checking = true);
    SaveFolderInfo info;
    try {
      info = await widget.probe.inspect(trimmed);
    } catch (_) {
      info = SaveFolderInfo(path: trimmed, exists: false, isDirectory: false);
    }
    if (!mounted || sequence != _sequence) {
      return;
    }
    setState(() {
      _info = info;
      _checking = false;
    });
  }

  Future<void> _browse() async {
    final picker = widget.directoryPicker;
    if (picker == null) {
      setState(
        () => _pickerHint =
            'No system folder picker is wired in this build. Type the path '
            'above, or install zenity, kdialog, or qarma.',
      );
      return;
    }
    setState(() => _pickerHint = null);
    String? picked;
    try {
      picked = await picker.pickDirectory(
        title: 'Open save folder',
        initialPath: _pathController.text.trim(),
      );
    } catch (_) {
      picked = null;
    }
    if (!mounted) {
      return;
    }
    if (picked == null || picked.trim().isEmpty) {
      setState(
        () => _pickerHint =
            'No folder was selected. If no system dialog appeared, type the '
            'path above.',
      );
      return;
    }
    _pathController.text = picked;
    _pathController.selection = TextSelection.collapsed(offset: picked.length);
    await _validate(picked);
  }

  Future<void> _submit() async {
    if (!_canOpen) {
      return;
    }
    final path = _pathController.text.trim();
    await widget.recentPaths.add(path);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(path);
  }

  void _chooseRecent(String path) {
    _pathController.text = path;
    _pathController.selection = TextSelection.collapsed(offset: path.length);
    unawaited(_validate(path));
  }

  String? get _blockingMessage {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      return 'Enter a save folder path.';
    }
    if (_checking) {
      return null;
    }
    final info = _info;
    if (info == null) {
      return null;
    }
    if (!info.exists) {
      return 'That folder does not exist.';
    }
    if (!info.isDirectory) {
      return 'That path is a file, not a save folder.';
    }
    if (!info.containsSaveSlots) {
      return 'No slot_* folders were found — this does not look like a save '
          'folder.';
    }
    return null;
  }

  bool get _canOpen => !_checking && (_info?.isSaveRoot ?? false);

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final message = _blockingMessage;
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
            onPressed: _canOpen ? _submit : null,
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
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (value) => unawaited(_validate(value)),
            onSubmitted: (_) => unawaited(_submit()),
            decoration: const InputDecoration(
              labelText: 'Save folder',
              hintText: '/path/to/save/folder',
            ),
          ),
          if (_checking) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.md),
            Text(
              'Checking folder…',
              style: BombFlowerTypography.caption.copyWith(
                color: BombFlowerColors.inkMuted,
              ),
            ),
          ],
          if (!_checking && message != null) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.lg),
            Banner(
              key: const Key('open-save-error'),
              variant: BannerVariant.danger,
              title: 'Cannot open this folder',
              message: message,
            ),
          ],
          if (!_checking && info != null && info.isSaveRoot) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.lg),
            Banner(
              key: const Key('open-save-valid'),
              variant: BannerVariant.success,
              title: 'Save folder found',
              message:
                  'Contains ${info.slotDirectories.length} slot '
                  '${info.slotDirectories.length == 1 ? 'folder' : 'folders'}: '
                  '${info.slotDirectories.join(', ')}.',
            ),
          ],
          const SizedBox(height: BombFlowerSpacing.lg),
          Row(
            children: <Widget>[
              BrassButton(
                key: const Key('open-save-browse'),
                label: 'Browse…',
                icon: Icons.folder_open,
                variant: BrassButtonVariant.secondary,
                onPressed: _browse,
              ),
              const SizedBox(width: BombFlowerSpacing.lg),
              Expanded(
                child: Text(
                  'Browse uses zenity, kdialog, or qarma when available.',
                  style: BombFlowerTypography.caption.copyWith(
                    color: BombFlowerColors.inkMuted,
                  ),
                ),
              ),
            ],
          ),
          if (_pickerHint != null) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.sm),
            Text(
              _pickerHint!,
              key: const Key('open-save-picker-hint'),
              style: BombFlowerTypography.caption.copyWith(
                color: BombFlowerColors.warningInk,
              ),
            ),
          ],
          const SizedBox(height: BombFlowerSpacing.xxl),
          const Divider(height: 1, color: BombFlowerColors.divider),
          const SizedBox(height: BombFlowerSpacing.lg),
          Text(
            'Recent folders',
            style: BombFlowerTypography.label.copyWith(
              color: BombFlowerColors.inkSecondary,
            ),
          ),
          const SizedBox(height: BombFlowerSpacing.sm),
          if (_recent.isEmpty)
            Text(
              'No recent folders yet.',
              style: BombFlowerTypography.caption.copyWith(
                color: BombFlowerColors.inkMuted,
              ),
            )
          else
            for (var index = 0; index < _recent.length; index++)
              Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: _recent[index],
                  child: BrassButton(
                    key: Key('open-save-recent-$index'),
                    label: shortPathLabel(_recent[index]),
                    icon: Icons.history,
                    variant: BrassButtonVariant.text,
                    onPressed: () => _chooseRecent(_recent[index]),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
