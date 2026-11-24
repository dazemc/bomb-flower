import 'dart:async';

import 'package:material_ui/material_ui.dart' hide Banner;

import '../../../build_info.dart';
import '../../../data/system/directory_picker.dart';
import '../../../data/system/longshot_launcher.dart';
import '../../bloc/shell/tab_definition.dart';
import '../../settings/settings_store.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../../widgets/common/banner.dart';
import '../../widgets/common/brass_button.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_state.dart';
import '../../widgets/common/parchment_panel.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/controls/brass_slider.dart';
import '../../widgets/controls/brass_toggle.dart';
import '../../widgets/selectors/searchable_select.dart';
import 'placeholder_tab.dart';

export '../../settings/settings_store.dart';

/// What the caption says when preferences are written to disk.
const String persistedCaption =
    'Preferences are stored for this operating-system user and survive a '
    'restart. Text scale applies as soon as you change it. While it is set, it '
    'replaces the platform text scale rather than multiplying it, so the '
    'editor renders at exactly the chosen size.';

/// What the caption says when only the in-memory fallback store is in use.
const String memoryCaption =
    'Preferences are held in memory for this session only: this build was '
    'given no persistent store, so changes are lost when the app closes.';

/// Editor preferences: recent saves, backup policy, slot default, motion, and
/// text scale.
///
/// Every control writes through the injected [SettingsStore] exactly once per
/// committed change. A failed save is reported and never silently treated as
/// persisted; the control keeps the value the user chose.
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, this.store, this.launcherPicker});

  /// Persistence boundary. Defaults to a fresh [InMemorySettingsStore].
  final SettingsStore? store;

  /// Native file chooser for the launcher path. Defaults to
  /// [PlatformFilePicker], read at pick time so tests never load the plugin.
  final FilePicker? launcherPicker;

  /// Caption stating whether preferences survive a restart, and the trade-off
  /// of the editor's own text scale.
  static const Key persistenceCaptionKey = Key('settings-persistence');
  static const Key clearRecentKey = Key('settings-clear-recent');
  static const Key backupPolicyKey = Key('settings-backup-policy');
  static const Key newestDefaultKey = Key('settings-newest-default');
  static const Key reduceMotionKey = Key('settings-reduce-motion');
  static const Key textScaleKey = Key('settings-text-scale');
  static const Key launcherPathKey = Key('settings-launcher-path');
  static const Key launcherPathSaveKey = Key('settings-launcher-path-save');
  static const Key launcherPathChooseKey = Key('settings-launcher-path-choose');
  static const Key launcherPathEmptyKey = Key('settings-launcher-path-empty');
  static const Key saveFailedKey = Key('settings-save-failed');
  static const Key nativeDialogWarningKey = Key(
    'settings-native-dialog-warning',
  );

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late SettingsStore _store;
  EditorPreferences? _preferences;
  Object? _loadError;
  bool _saveFailed = false;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? InMemorySettingsStore();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(SettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      _store = widget.store ?? InMemorySettingsStore();
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() {
      _loadError = null;
      _preferences = null;
    });
    try {
      final loaded = await _store.load();
      if (!mounted || token != _loadToken) return;
      setState(() => _preferences = loaded);
    } on Object catch (error) {
      if (!mounted || token != _loadToken) return;
      setState(() => _loadError = error);
    }
  }

  /// Applies [next] locally and writes it once. A failure keeps the local value
  /// and surfaces the danger banner instead of pretending the save succeeded.
  Future<void> _persist(EditorPreferences next) async {
    setState(() {
      _preferences = next;
      _saveFailed = false;
    });
    try {
      await _store.save(next);
    } on Object {
      if (!mounted) return;
      setState(() => _saveFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final definition = ShellTab.settings.definition;
    final palette = context.bombFlowerTheme;

    return TabPageFrame(
      child: ParchmentPanel(
        grainSeed: 12,
        padding: const EdgeInsets.fromLTRB(
          BombFlowerSpacing.panelPadding,
          0,
          BombFlowerSpacing.panelPadding,
          BombFlowerSpacing.panelPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              eyebrow: definition.eyebrow,
              title: definition.title,
              description: definition.purpose,
            ),
            Text(
              _store.isPersistent ? persistedCaption : memoryCaption,
              key: SettingsTab.persistenceCaptionKey,
              style: BombFlowerTypography.caption.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.xl),
            if (_saveFailed) ...<Widget>[
              const Banner(
                key: SettingsTab.saveFailedKey,
                title: 'Could not save preferences',
                message:
                    'The value is shown as you set it, but the store rejected '
                    'the write. Try the change again once the store is '
                    'available.',
                variant: BannerVariant.danger,
              ),
              const SizedBox(height: BombFlowerSpacing.xl),
            ],
            ..._buildBody(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context) {
    final error = _loadError;
    if (error != null) {
      return <Widget>[
        ErrorState(
          title: "Couldn't read preferences",
          message: 'The settings store did not return a value.',
          details: error.toString(),
          onRetry: () => unawaited(_load()),
          retryLabel: 'Retry',
        ),
      ];
    }

    final preferences = _preferences;
    if (preferences == null) {
      return <Widget>[const LoadingState(label: 'Reading preferences…')];
    }

    return _buildControls(context, preferences);
  }

  List<Widget> _buildControls(
    BuildContext context,
    EditorPreferences preferences,
  ) {
    final palette = context.bombFlowerTheme;

    return <Widget>[
      _SettingSection(
        title: 'Recent saves',
        caption: 'Paths only; clearing removes them from this list.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (preferences.recentPaths.isEmpty)
              Text(
                'No recent save folders recorded.',
                style: BombFlowerTypography.body.copyWith(
                  color: palette.textMuted,
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final path in preferences.recentPaths)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: BombFlowerSpacing.xs,
                      ),
                      child: Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BombFlowerTypography.mono.copyWith(
                          fontSize: 12,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: BombFlowerSpacing.md),
            BrassButton(
              key: SettingsTab.clearRecentKey,
              label: 'Clear recent paths',
              icon: Icons.clear_all,
              variant: BrassButtonVariant.secondary,
              onPressed: preferences.recentPaths.isEmpty
                  ? null
                  : () => unawaited(
                      _persist(preferences.copyWith(recentPaths: <String>[])),
                    ),
            ),
          ],
        ),
      ),
      _SettingSection(
        title: 'Backup policy',
        caption:
            'Decides whether a backup is written before a save is overwritten.',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SearchableSelect<BackupPolicy>(
            key: SettingsTab.backupPolicyKey,
            items: BackupPolicy.values,
            itemLabel: _backupPolicyLabel,
            value: preferences.backupPolicy,
            label: 'When overwriting a save',
            onChanged: (policy) =>
                unawaited(_persist(preferences.copyWith(backupPolicy: policy))),
          ),
        ),
      ),
      _SettingSection(
        title: 'Slot selection',
        caption: 'Applies when a save folder is opened.',
        child: BrassToggle(
          key: SettingsTab.newestDefaultKey,
          value: preferences.makeNewestSlotDefault,
          label: 'Make the newest slot the default',
          onChanged: (value) => unawaited(
            _persist(preferences.copyWith(makeNewestSlotDefault: value)),
          ),
        ),
      ),
      _SettingSection(
        title: 'Accessibility',
        caption: 'Editor-level motion and text size.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            BrassToggle(
              key: SettingsTab.reduceMotionKey,
              value: preferences.reducedMotion,
              label: 'Reduce motion',
              description: 'applies on the next launch',
              onChanged: (value) => unawaited(
                _persist(preferences.copyWith(reducedMotion: value)),
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.lg),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: BrassSlider(
                key: SettingsTab.textScaleKey,
                value: preferences.textScale,
                min: 1,
                max: 1.5,
                divisions: 5,
                label: 'Text scale',
                valueLabel: _formatTextScale(preferences.textScale),
                // BrassSlider has no change-end callback, so every committed
                // step saves once.
                onChanged: (value) =>
                    unawaited(_persist(preferences.copyWith(textScale: value))),
              ),
            ),
          ],
        ),
      ),
      _SettingSection(
        title: 'Longshot launcher',
        caption:
            'The launcher executable the title-bar Launch action starts. '
            'Point it at the Longshot Launcher AppImage or its installed '
            'equivalent.',
        child: _LauncherPathRow(
          path: preferences.launcherPath,
          picker: widget.launcherPicker ?? const PlatformFilePicker(),
          onSave: (path) {
            unawaited(_persist(preferences.copyWith(launcherPath: path)));
          },
        ),
      ),
      _SettingSection(
        title: 'System file dialog (Linux)',
        caption:
            'Opening a save always uses the in-app browser. The system dialog '
            'is only the Browse fallback in Save As and Duplicate.',
        child: const Banner(
          key: SettingsTab.nativeDialogWarningKey,
          variant: BannerVariant.warning,
          title: 'The system dialog is fragile on Linux here',
          message:
              'With the custom window frame it can open with an unclickable '
              'sidebar (issue #273): the frame styles every window, including '
              'the dialog\'s. Prefer the in-app browser. See '
              'docs/LIMITATIONS.md §15 for the mechanism.',
        ),
      ),
      _SettingSection(
        title: 'About',
        caption: 'Identifies the running build.',
        child: Text(
          'Build $kBuildId',
          key: const Key('settings-build-id'),
          style: BombFlowerTypography.mono.copyWith(
            fontSize: 12,
            color: palette.textPrimary,
          ),
        ),
      ),
    ];
  }
}

String _backupPolicyLabel(BackupPolicy policy) {
  return switch (policy) {
    BackupPolicy.always => 'Always keep a backup',
    BackupPolicy.ask => 'Ask before overwriting',
    BackupPolicy.never => 'Never keep a backup',
  };
}

String _formatTextScale(double value) {
  final fixed = value.toStringAsFixed(2);
  final trimmed = fixed.endsWith('0')
      ? fixed.substring(0, fixed.length - 1)
      : fixed;
  return '${trimmed}x';
}

/// Editable launcher path, kept in step with the persisted preference without
/// overwriting what the user is currently typing.
///
/// There is no "reset to a default" affordance: no default path exists. When
/// the field is empty the row says so with the same sentence the title bar
/// shows, and offers the native chooser that fills and saves it.
class _LauncherPathRow extends StatefulWidget {
  const _LauncherPathRow({
    required this.path,
    required this.picker,
    required this.onSave,
  });

  /// The persisted path, which seeds the field and drives the empty state.
  final String path;

  /// Native chooser; only reached when the user presses Choose….
  final FilePicker picker;

  /// Writes the trimmed path once per commit.
  final void Function(String path) onSave;

  @override
  State<_LauncherPathRow> createState() => _LauncherPathRowState();
}

class _LauncherPathRowState extends State<_LauncherPathRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.path,
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(_LauncherPathRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow a reloaded value, but never fight the user mid-typing.
    if (widget.path != oldWidget.path && !_focusNode.hasFocus) {
      _controller.text = widget.path;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit() {
    widget.onSave(_controller.text.trim());
  }

  Future<void> _choose() async {
    final picked = await widget.picker.pickFile(
      title: 'Choose the Longshot launcher',
      initialPath: _controller.text.trim(),
    );
    if (!mounted) {
      return;
    }
    final trimmed = picked?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }
    _controller.text = trimmed;
    widget.onSave(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final isConfigured = widget.path.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: TextField(
            key: SettingsTab.launcherPathKey,
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _commit(),
            decoration: const InputDecoration(
              labelText: 'Launcher executable',
              hintText: '/path/to/LongshotLauncher-x86_64.AppImage',
            ),
          ),
        ),
        if (!isConfigured) ...<Widget>[
          const SizedBox(height: BombFlowerSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              kNoLongshotLauncherConfigured,
              key: SettingsTab.launcherPathEmptyKey,
              style: BombFlowerTypography.caption.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),
        ],
        const SizedBox(height: BombFlowerSpacing.md),
        Wrap(
          spacing: BombFlowerSpacing.md,
          runSpacing: BombFlowerSpacing.sm,
          children: <Widget>[
            BrassButton(
              key: SettingsTab.launcherPathSaveKey,
              label: 'Use this path',
              icon: Icons.check,
              variant: BrassButtonVariant.secondary,
              onPressed: _commit,
            ),
            BrassButton(
              key: SettingsTab.launcherPathChooseKey,
              label: 'Choose…',
              icon: Icons.folder_open,
              variant: BrassButtonVariant.text,
              onPressed: () => unawaited(_choose()),
            ),
          ],
        ),
      ],
    );
  }
}

/// One titled preference group inside the settings panel.
class _SettingSection extends StatelessWidget {
  const _SettingSection({
    required this.title,
    required this.caption,
    required this.child,
  });

  final String title;
  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: BombFlowerSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: BombFlowerTypography.h3.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: BombFlowerSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              caption,
              style: BombFlowerTypography.caption.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),
          const SizedBox(height: BombFlowerSpacing.md),
          child,
        ],
      ),
    );
  }
}
