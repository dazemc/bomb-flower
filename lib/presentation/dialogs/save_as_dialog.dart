import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart' hide Banner;

import '../../data/system/directory_picker.dart';
import '../bloc/save_session/save_session_ui_state.dart';
import '../theme/bomb_flower_colors.dart';
import '../theme/bomb_flower_spacing.dart';
import '../theme/bomb_flower_typography.dart';
import '../widgets/common/banner.dart';
import '../widgets/common/brass_button.dart';
import '../widgets/controls/rune_checkbox.dart';
import 'dialog_copy.dart';
import 'dialog_paths.dart';
import 'save_dialog_frame.dart';
import 'slot_rotation_warning.dart';

/// The confirmed destination of a Save As.
final class SaveAsRequest extends Equatable {
  /// Creates a request.
  const SaveAsRequest({
    required this.destinationPath,
    required this.overwrite,
    required this.markNewest,
  });

  /// Destination root.
  final String destinationPath;

  /// Whether the user checked the overwrite box.
  final bool overwrite;

  /// Whether to stamp the edited progress.sav afterwards.
  final bool markNewest;

  @override
  List<Object?> get props => <Object?>[destinationPath, overwrite, markNewest];
}

/// Asks for a Save As destination and the export options.
class SaveAsDialog extends StatefulWidget {
  /// Creates the dialog.
  const SaveAsDialog({
    super.key,
    required this.project,
    required this.probe,
    this.directoryPicker,
  });

  /// The project being copied.
  final SaveProjectUi project;

  /// Filesystem inspector port.
  final SaveFolderProbe probe;

  /// Optional native folder chooser.
  final DirectoryPicker? directoryPicker;

  /// Shows the dialog and returns the confirmed request, or `null`.
  static Future<SaveAsRequest?> show(
    BuildContext context, {
    required SaveProjectUi project,
    required SaveFolderProbe probe,
    DirectoryPicker? directoryPicker,
  }) {
    return showDialog<SaveAsRequest>(
      context: context,
      barrierColor: BombFlowerColors.scrim,
      builder: (dialogContext) => SaveAsDialog(
        project: project,
        probe: probe,
        directoryPicker: directoryPicker,
      ),
    );
  }

  @override
  State<SaveAsDialog> createState() => _SaveAsDialogState();
}

class _SaveAsDialogState extends State<SaveAsDialog> {
  late final TextEditingController _destination;
  SaveFolderInfo? _info;
  String? _pickerHint;
  bool _checking = false;
  bool _overwrite = false;
  bool _markNewest = true;
  int _sequence = 0;

  @override
  void initState() {
    super.initState();
    _destination = TextEditingController();
  }

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
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
      info = SaveFolderInfo(
        path: trimmed,
        exists: false,
        isDirectory: false,
        parentExists: true,
      );
    }
    if (!mounted || sequence != _sequence) {
      return;
    }
    setState(() {
      _info = info;
      _checking = false;
      if (!info.exists) {
        _overwrite = false;
      }
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
        title: 'Save As destination',
        initialPath: _destination.text.trim(),
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
    _destination.text = picked;
    _destination.selection = TextSelection.collapsed(offset: picked.length);
    await _validate(picked);
  }

  String? get _validationMessage {
    final path = _destination.text.trim();
    if (path.isEmpty) {
      return 'Enter a destination folder.';
    }
    if (sameSavePath(path, widget.project.path)) {
      return 'Choose a folder different from the open save folder.';
    }
    if (_checking) {
      return null;
    }
    final info = _info;
    if (info == null) {
      return null;
    }
    if (!info.isCreatable) {
      return 'That path is a file. Choose a folder instead.';
    }
    return null;
  }

  bool get _overwriteRequired => _info?.exists == true;
  bool get _showNewestOption {
    final active = widget.project.activeSlot;
    return active != null && isProgressSlotId(active);
  }

  bool get _canSubmit =>
      !_checking &&
      _info != null &&
      _validationMessage == null &&
      (!_overwriteRequired || _overwrite);

  Future<void> _submit() async {
    if (!_canSubmit) {
      return;
    }
    final request = SaveAsRequest(
      destinationPath: _destination.text.trim(),
      overwrite: _overwrite,
      markNewest: _showNewestOption && _markNewest,
    );
    Navigator.of(context).pop(request);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.project.activeSlot;
    final info = _info;
    final message = _validationMessage;
    return SaveDialogFrame(
      title: 'Save As',
      subtitle: 'Write the current edits to a new folder.',
      icon: Icons.drive_file_move_outline,
      footer: SaveDialogActions(
        children: <Widget>[
          const SaveDialogCancelButton(key: Key('save-as-cancel')),
          BrassButton(
            key: const Key('save-as-submit'),
            label: 'Save As',
            icon: Icons.save_alt,
            onPressed: _canSubmit ? _submit : null,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Source: ${widget.project.path}',
            style: BombFlowerTypography.caption.copyWith(
              color: BombFlowerColors.inkMuted,
            ),
          ),
          const SizedBox(height: BombFlowerSpacing.lg),
          TextField(
            key: const Key('save-as-path'),
            controller: _destination,
            autofocus: true,
            textInputAction: TextInputAction.next,
            onChanged: (value) => unawaited(_validate(value)),
            decoration: const InputDecoration(
              labelText: 'Destination folder',
              hintText: '/path/to/new/save/folder',
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
              key: const Key('save-as-error'),
              variant: BannerVariant.danger,
              title: 'Cannot use this destination',
              message: message,
            ),
          ],
          if (!_checking &&
              info != null &&
              info.exists &&
              info.isDirectory &&
              message == null) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.lg),
            Banner(
              key: const Key('save-as-exists'),
              variant: BannerVariant.warning,
              title: 'This folder already exists',
              message:
                  'Saving here can replace matching slot files. Check the box '
                  'below to confirm the overwrite.',
            ),
            const SizedBox(height: BombFlowerSpacing.md),
            RuneCheckbox(
              key: const Key('save-as-overwrite'),
              value: _overwrite,
              label: 'Overwrite the existing slot files in this folder',
              onChanged: (value) {
                setState(() => _overwrite = value ?? false);
              },
            ),
          ],
          if (!_checking &&
              info != null &&
              info.exists &&
              !info.containsSaveSlots &&
              message == null) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.sm),
            Text(
              'No slot_* folders in this destination; a new save layout will '
              'be written.',
              style: BombFlowerTypography.caption.copyWith(
                color: BombFlowerColors.inkMuted,
              ),
            ),
          ],
          if (!_checking &&
              info != null &&
              !info.exists &&
              !info.parentExists) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.sm),
            Text(
              'The parent folder does not exist yet; the export creates the '
              'missing folders.',
              style: BombFlowerTypography.caption.copyWith(
                color: BombFlowerColors.inkMuted,
              ),
            ),
          ],
          const SizedBox(height: BombFlowerSpacing.lg),
          Row(
            children: <Widget>[
              BrassButton(
                key: const Key('save-as-browse'),
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
              key: const Key('save-as-picker-hint'),
              style: BombFlowerTypography.caption.copyWith(
                color: BombFlowerColors.warningInk,
              ),
            ),
          ],
          const SizedBox(height: BombFlowerSpacing.xxl),
          _SlotWritePreview(slots: widget.project.openSlots),
          if (!widget.project.isActiveSlotNewest &&
              widget.project.newestSlot != null) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.lg),
            SlotRotationWarning(project: widget.project),
          ],
          if (_showNewestOption) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.lg),
            RuneCheckbox(
              key: const Key('save-as-mark-newest'),
              value: _markNewest,
              label: SaveWorkflowCopy.makeNewestLabel,
              onChanged: (value) {
                setState(() => _markNewest = value ?? false);
              },
            ),
            const SizedBox(height: BombFlowerSpacing.xs),
            Text(
              SaveWorkflowCopy.newestSlotExplanation,
              style: BombFlowerTypography.caption.copyWith(
                color: BombFlowerColors.inkMuted,
              ),
            ),
          ],
          const SizedBox(height: BombFlowerSpacing.lg),
          Text(
            SaveWorkflowCopy.gameClampsInvalidValues,
            key: const Key('save-as-clamp-copy'),
            style: BombFlowerTypography.caption.copyWith(
              color: BombFlowerColors.inkSecondary,
            ),
          ),
          const SizedBox(height: BombFlowerSpacing.sm),
          Text(
            SaveWorkflowCopy.noChecksum,
            key: const Key('save-as-no-checksum-copy'),
            style: BombFlowerTypography.caption.copyWith(
              color: BombFlowerColors.inkSecondary,
            ),
          ),
          if (active != null) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.sm),
            Text(
              'Active slot: ${active.value}.',
              style: BombFlowerTypography.caption.copyWith(
                color: BombFlowerColors.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SlotWritePreview extends StatelessWidget {
  const _SlotWritePreview({required this.slots});

  final List<SaveSlotUi> slots;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BombFlowerSpacing.lg),
      decoration: BoxDecoration(
        color: BombFlowerColors.parchmentSunken,
        borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
        border: Border.all(color: BombFlowerColors.stone),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Slots that will be written',
            style: BombFlowerTypography.label.copyWith(
              color: BombFlowerColors.ink,
            ),
          ),
          const SizedBox(height: BombFlowerSpacing.sm),
          if (slots.isEmpty)
            Text(
              'No slots are open.',
              style: BombFlowerTypography.caption.copyWith(
                color: BombFlowerColors.inkMuted,
              ),
            )
          else
            for (final slot in slots)
              Padding(
                padding: const EdgeInsets.only(bottom: BombFlowerSpacing.xxs),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        slot.relativePath,
                        key: Key('save-as-slot-${slot.id.value}'),
                        style: BombFlowerTypography.mono.copyWith(
                          fontSize: 11,
                          height: 16 / 11,
                          color: BombFlowerColors.inkSecondary,
                        ),
                      ),
                    ),
                    Text(
                      slot.isDirty
                          ? '${slot.changedFieldCount} changed'
                          : 'unchanged',
                      style: BombFlowerTypography.caption.copyWith(
                        color: slot.isDirty
                            ? BombFlowerColors.brassInk
                            : BombFlowerColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
