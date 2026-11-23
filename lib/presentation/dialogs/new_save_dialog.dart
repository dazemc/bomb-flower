import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart' hide Banner;

import '../../data/newsave/new_save_writer.dart';
import '../../data/system/directory_picker.dart';
import '../../domain/newsave/new_save_builder.dart';
import '../../domain/newsave/new_save_spec.dart';
import '../../domain/save/progress_layout.dart';
import '../../domain/schema/gamedata_schema.dart';
import '../theme/bomb_flower_colors.dart';
import '../theme/bomb_flower_spacing.dart';
import '../theme/bomb_flower_typography.dart';
import '../widgets/common/banner.dart';
import '../widgets/common/brass_button.dart';
import '../widgets/common/confirm_dialog.dart';
import '../widgets/controls/labelled_field.dart';
import 'save_dialog_frame.dart';

/// Loads the GameData schema the builder needs.
typedef GameDataSchemaLoader = Future<GameDataSchema> Function();

/// Writes one built new save under a destination root.
typedef NewSavePersist = Future<NewSaveWriteResult> Function({
  required String rootDirectory,
  required NewSaveBuild build,
  bool allowOverwrite,
});

/// Where a created save went, returned only when the user picks "Open this
/// save".
final class NewSaveOutcome {
  /// Creates an outcome.
  const NewSaveOutcome({
    required this.rootDirectory,
    required this.progressPath,
    required this.captionPath,
    required this.progressLength,
    required this.captionLength,
  });

  /// The destination root the user chose.
  final String rootDirectory;

  /// Path of the written `slot_00/progress.sav`.
  final String progressPath;

  /// Path of the written `slot_00/caption.sav`.
  final String captionPath;

  /// Length of `progress.sav` in bytes.
  final int progressLength;

  /// Length of `caption.sav` in bytes.
  final int captionLength;
}

/// Creates one schema-default `slot_00` save and reports where it went.
///
/// The dialog never inspects folders itself: the [`NewSaveWriter`] refuses a
/// non-empty destination with [NewSaveWriteException.destinationNotEmpty], and
/// this dialog asks before retrying with `allowOverwrite: true`.
class NewSaveDialog extends StatefulWidget {
  /// Creates the dialog.
  const NewSaveDialog({
    super.key,
    this.schemaLoader,
    this.persist,
    this.directoryPicker,
    this.initialRoot = '',
  });

  /// Loads the schema; defaults to the bundled `gamedata_110.json` asset.
  final GameDataSchemaLoader? schemaLoader;

  /// Writes the build; defaults to [NewSaveWriter.write].
  final NewSavePersist? persist;

  /// Native folder chooser; defaults to [SystemDirectoryPicker].
  final DirectoryPicker? directoryPicker;

  /// Pre-fills the destination field.
  final String initialRoot;

  /// Shows the dialog and returns the outcome, or `null` when it is dismissed.
  static Future<NewSaveOutcome?> show(
    BuildContext context, {
    GameDataSchemaLoader? schemaLoader,
    NewSavePersist? persist,
    DirectoryPicker? directoryPicker,
    String? initialRoot,
  }) {
    return showDialog<NewSaveOutcome>(
      context: context,
      barrierColor: BombFlowerColors.scrim,
      builder: (dialogContext) => NewSaveDialog(
        schemaLoader: schemaLoader,
        persist: persist,
        directoryPicker: directoryPicker,
        initialRoot: initialRoot ?? '',
      ),
    );
  }

  @override
  State<NewSaveDialog> createState() => _NewSaveDialogState();
}

class _NewSaveDialogState extends State<NewSaveDialog> {
  static final NewSaveWriter _defaultWriter = NewSaveWriter();

  late final TextEditingController _root;
  late final Future<GameDataSchema> _schema;
  bool _creating = false;
  String? _error;
  String? _info;
  NewSaveWriteResult? _result;

  DirectoryPicker get _picker =>
      widget.directoryPicker ?? const SystemDirectoryPicker();

  @override
  void initState() {
    super.initState();
    _root = TextEditingController(text: widget.initialRoot);
    _schema = (widget.schemaLoader ?? _loadBundledSchema)();
  }

  @override
  void dispose() {
    _root.dispose();
    super.dispose();
  }

  static Future<GameDataSchema> _loadBundledSchema() {
    return GameDataSchema.load(
      () => rootBundle.loadString('assets/schema/gamedata_110.json'),
    );
  }

  Future<void> _choose() async {
    if (_creating) {
      return;
    }
    final picked = await _picker.pickDirectory(
      title: 'Choose where to create the save',
      initialPath: _root.text.trim(),
    );
    if (!mounted || picked == null) {
      return;
    }
    final trimmed = picked.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _root.text = trimmed;
    _root.selection = TextSelection.collapsed(offset: trimmed.length);
    setState(() {
      _error = null;
      _info = null;
    });
  }

  Future<void> _create({bool allowOverwrite = false}) async {
    if (_creating) {
      return;
    }
    final root = _root.text.trim();
    if (root.isEmpty) {
      setState(() {
        _error = 'Enter a destination folder.';
        _info = null;
      });
      return;
    }

    setState(() {
      _creating = true;
      _error = null;
      _info = null;
    });

    final persist = widget.persist ?? _defaultWriter.write;
    try {
      final schema = await _schema;
      if (!mounted) {
        return;
      }
      final build = NewSaveBuilder.build(
        schema: schema,
        spec: NewSaveSpec.preset(NewSavePreset.schemaDefaults),
      );
      final result = await persist(
        rootDirectory: root,
        build: build,
        allowOverwrite: allowOverwrite,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _creating = false;
        _result = result;
      });
    } on NewSaveWriteException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _creating = false);
      if (error.code == NewSaveWriteException.destinationNotEmpty &&
          !allowOverwrite) {
        await _confirmReplace(root);
        return;
      }
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _creating = false;
        _error = '$error';
      });
    }
  }

  Future<void> _confirmReplace(String root) async {
    final replace = await ConfirmDialog.show(
      context,
      destructive: true,
      title: 'Replace the existing slot_00?',
      message:
          'This folder already contains files. Replacing writes '
          '$root/slot_00/progress.sav and caption.sav and keeps .bak copies '
          'of the previous files.',
      confirmLabel: 'Replace slot_00',
      cancelLabel: 'Keep existing files',
    );
    if (!mounted) {
      return;
    }
    if (!replace) {
      setState(() {
        _info =
            'Nothing was written. Choose another folder or keep the '
            'existing files.';
      });
      return;
    }
    await _create(allowOverwrite: true);
  }

  void _openResult(NewSaveWriteResult result) {
    Navigator.of(context).pop(
      NewSaveOutcome(
        rootDirectory: result.rootDirectory,
        progressPath: result.progressPath,
        captionPath: result.captionPath,
        progressLength: result.progressLength,
        captionLength: result.captionLength,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return PopScope(
      canPop: !_creating,
      child: SaveDialogFrame(
        title: 'Create a new save',
        subtitle: 'Verified schema defaults',
        icon: Icons.add_box_outlined,
        maxWidth: 620,
        footer: result == null
            ? SaveDialogActions(
                children: <Widget>[
                  const SaveDialogCancelButton(key: Key('new-save-cancel')),
                  BrassButton(
                    key: const Key('new-save-create'),
                    label: _creating ? 'Creating…' : 'Create save',
                    icon: Icons.add_box_outlined,
                    onPressed: _creating ? null : () => _create(),
                  ),
                ],
              )
            : null,
        child: result == null ? _buildForm() : _buildSuccess(result),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Banner(
          key: Key('new-save-never-loaded'),
          variant: BannerVariant.warning,
          title: 'A created save has never been loaded by the game',
          message:
              'The codecs and engine can read these bytes, which is not proof '
              'the game will. Cloning a save the game already accepts is the '
              'safer path.',
        ),
        const SizedBox(height: BombFlowerSpacing.xl),
        Text(
          'slot_00 (fixed by the format builder)',
          key: const Key('new-save-slot'),
          style: BombFlowerTypography.mono.copyWith(
            color: BombFlowerColors.ink,
          ),
        ),
        const SizedBox(height: BombFlowerSpacing.sm),
        Text(
          'The builder writes exactly one slot_00 folder and stores no '
          'profile or player name; the schema has no verified field for one.',
          style: BombFlowerTypography.caption.copyWith(
            color: BombFlowerColors.inkMuted,
          ),
        ),
        const SizedBox(height: BombFlowerSpacing.xl),
        LabelledField(
          label: 'Destination folder',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('new-save-root'),
                  controller: _root,
                  autofocus: false,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: '/path/to/save/folder',
                  ),
                ),
              ),
              const SizedBox(width: BombFlowerSpacing.md),
              BrassButton(
                key: const Key('new-save-choose'),
                label: 'Choose…',
                variant: BrassButtonVariant.secondary,
                onDark: false,
                onPressed: _creating ? null : _choose,
              ),
            ],
          ),
        ),
        const SizedBox(height: BombFlowerSpacing.lg),
        Text(
          'progress.sav ${_withThousands(ProgressLayout.sampleFileLength)} B '
          'plus caption.sav',
          key: const Key('new-save-size'),
          style: BombFlowerTypography.caption.copyWith(
            color: BombFlowerColors.inkMuted,
          ),
        ),
        if (_info != null) ...<Widget>[
          const SizedBox(height: BombFlowerSpacing.lg),
          Text(
            _info!,
            key: const Key('new-save-info'),
            style: BombFlowerTypography.caption.copyWith(
              color: BombFlowerColors.inkMuted,
            ),
          ),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: BombFlowerSpacing.lg),
          Banner(
            key: const Key('new-save-error'),
            variant: BannerVariant.danger,
            title: 'The save was not created',
            message: _error,
          ),
        ],
      ],
    );
  }

  Widget _buildSuccess(NewSaveWriteResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          key: const Key('new-save-success'),
          padding: const EdgeInsets.all(BombFlowerSpacing.lg),
          decoration: BoxDecoration(
            color: BombFlowerColors.successSurface,
            borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
            border: Border.all(color: BombFlowerColors.success),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Created slot_00',
                style: BombFlowerTypography.h3.copyWith(
                  color: BombFlowerColors.successInk,
                ),
              ),
              const SizedBox(height: BombFlowerSpacing.md),
              Text(
                result.progressPath,
                key: const Key('new-save-progress-path'),
                style: BombFlowerTypography.mono.copyWith(
                  fontSize: 11,
                  height: 16 / 11,
                  color: BombFlowerColors.inkSecondary,
                ),
              ),
              const SizedBox(height: BombFlowerSpacing.xxs),
              Text(
                result.captionPath,
                key: const Key('new-save-caption-path'),
                style: BombFlowerTypography.mono.copyWith(
                  fontSize: 11,
                  height: 16 / 11,
                  color: BombFlowerColors.inkSecondary,
                ),
              ),
              const SizedBox(height: BombFlowerSpacing.md),
              Text(
                'progress.sav '
                '${_withThousands(result.progressLength)} B · '
                'caption.sav ${_withThousands(result.captionLength)} B',
                key: const Key('new-save-written-size'),
                style: BombFlowerTypography.caption.copyWith(
                  color: BombFlowerColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: BombFlowerSpacing.xl),
        SaveDialogActions(
          children: <Widget>[
            BrassButton(
              key: const Key('new-save-close'),
              label: 'Close',
              variant: BrassButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
            BrassButton(
              key: const Key('new-save-open'),
              label: 'Open this save',
              icon: Icons.folder_open,
              onPressed: () => _openResult(result),
            ),
          ],
        ),
      ],
    );
  }

  static String _withThousands(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final remaining = digits.length - i;
      buffer.write(digits[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }
}

/// Exposes an optional creator for a new save to the subtree below it.
///
/// The empty state uses this seam so a first-run page can offer "Create a new
/// save" without importing the shell. A missing scope simply returns `null`.
class NewSaveScope extends InheritedWidget {
  /// Creates a new-save scope.
  const NewSaveScope({super.key, required this.create, required super.child});

  /// Opens the new-save dialog, or `null` when this subtree has no creator.
  final Future<void> Function(BuildContext context)? create;

  /// The nearest creator, or `null` when no [NewSaveScope] is above [context].
  static Future<void> Function(BuildContext context)? maybeOf(
    BuildContext context,
  ) {
    return context.dependOnInheritedWidgetOfExactType<NewSaveScope>()?.create;
  }

  @override
  bool updateShouldNotify(NewSaveScope oldWidget) => create != oldWidget.create;
}
