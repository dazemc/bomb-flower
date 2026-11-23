import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart' hide Banner;

import '../../../domain/core/edit_command.dart';
import '../../../domain/core/field_value.dart';
import '../../../domain/fields/field_groups.dart';
import '../../../domain/world/world_catalogue.dart' as world;
import '../../bloc/shell/tab_definition.dart';
import '../../tabs_support/field_editor.dart';
import '../../tabs_support/save_tab_scope.dart';
import '../../tabs_support/save_tab_source.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../../widgets/common/banner.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/parchment_panel.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/controls/numeric_field.dart';
import '../../widgets/data/stat_tile.dart';
import '../../widgets/selectors/searchable_select.dart';
import 'placeholder_tab.dart';

/// Player placement, scene, dungeon, and age editing.
///
/// The tab renders only the fields the [SaveTabSource] reports. Position and
/// rotation are edited through byte writes because their stored shapes are not
/// plain scalars; scene selection writes the exact catalogue key into the
/// fixed-width string field. Nothing is clamped, inferred, or fabricated: a
/// field the save does not hold shows "Not stored in this save", and a field
/// the layout does not consider editable renders through [FieldEditor]'s
/// explicit disabled reason.
class PlayerWorldTab extends StatelessWidget {
  /// Creates the player and world tab.
  const PlayerWorldTab({super.key, this.catalogue});

  /// Optional injected map catalogue; when null the bundled asset is loaded.
  final world.WorldCatalogue? catalogue;

  /// Numeric entry key for the X position component.
  static const Key positionXKey = ValueKey<String>('player-world-position-x');

  /// Numeric entry key for the Y position component.
  static const Key positionYKey = ValueKey<String>('player-world-position-y');

  /// Numeric entry key for the Z position component.
  static const Key positionZKey = ValueKey<String>('player-world-position-z');

  /// Numeric entry key for the rotation in degrees.
  static const Key rotationFieldKey = ValueKey<String>('player-world-rotation');

  /// Read-out key for the formatted rotation in degrees.
  static const Key rotationDegreesKey = ValueKey<String>(
    'player-world-rotation-degrees',
  );

  /// Warning key shown when the rotation is outside a half turn.
  static const Key rotationWarningKey = ValueKey<String>(
    'player-world-rotation-warning',
  );

  /// Text key shown when the stored rotation bits are NaN or infinite.
  static const Key rotationNotDecodableKey = ValueKey<String>(
    'player-world-rotation-not-decodable',
  );

  /// Searchable-select key for the current scene.
  static const Key sceneSelectKey = ValueKey<String>('player-world-scene');

  /// Warning key shown when the stored scene is not in the catalogue.
  static const Key sceneUnknownKey = ValueKey<String>(
    'player-world-scene-unknown',
  );

  /// Banner key shown when the catalogue asset cannot be loaded.
  static const Key sceneUnavailableKey = ValueKey<String>(
    'player-world-scene-unavailable',
  );

  /// Text key for the stored scene shown read-only on catalogue failure.
  static const Key sceneStoredTextKey = ValueKey<String>(
    'player-world-scene-stored',
  );

  @override
  Widget build(BuildContext context) {
    final source = SaveTabScope.maybeOf(context);
    if (source == null || !source.isOpen) {
      return const TabPageFrame(
        child: EmptyState(
          title: 'Open a save to begin',
          message:
              'Open a save folder to edit the saved position, rotation, '
              'scene, dungeon, and age.',
        ),
      );
    }

    return AnimatedBuilder(
      animation: source.changes,
      builder: (context, _) =>
          _PlayerWorldDashboard(source: source, catalogue: catalogue),
    );
  }
}

/// Labels the adapter may map to the player/world group.
const Set<String> _playerWorldLabels = <String>{
  'Player_Pos_For_Map',
  'Player_Rot_For_Map',
  'DungeonRoom',
  'Sequence_CurrentBanc',
  'Sequence_IsChildhood',
};

Map<String, TabFieldView> _viewsByLabel(SaveTabSource source) {
  final grouped = source.viewsFor(EditorTabGroup.playerWorld);
  final views = grouped.isNotEmpty
      ? grouped
      : source.allViews.where(
          (TabFieldView view) =>
              _playerWorldLabels.contains(view.descriptor.label),
        );

  final byLabel = <String, TabFieldView>{};
  for (final view in views) {
    final label = view.descriptor.label;
    if (_playerWorldLabels.contains(label)) {
      byLabel.putIfAbsent(label, () => view);
    }
  }
  return byLabel;
}

class _PlayerWorldDashboard extends StatelessWidget {
  const _PlayerWorldDashboard({required this.source, this.catalogue});

  final SaveTabSource source;
  final world.WorldCatalogue? catalogue;

  @override
  Widget build(BuildContext context) {
    final definition = ShellTab.playerWorld.definition;
    final byLabel = _viewsByLabel(source);

    return TabPageFrame(
      child: ParchmentPanel(
        grainSeed: 5,
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
              isModified: source.isDirty,
            ),
            _Group(
              title: 'Placement',
              description:
                  'World position and facing, stored as little-endian '
                  'float32 values.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _PositionField(
                    view: byLabel['Player_Pos_For_Map'],
                    source: source,
                  ),
                  const SizedBox(height: BombFlowerSpacing.xl),
                  _RotationField(
                    view: byLabel['Player_Rot_For_Map'],
                    source: source,
                  ),
                ],
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.xxxl),
            _Group(
              title: 'Scene',
              description:
                  'The stored Sequence_CurrentBanc map key, matched against '
                  'the verified 80-map catalogue.',
              child: _SceneField(
                view: byLabel['Sequence_CurrentBanc'],
                source: source,
                catalogue: catalogue,
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.xxxl),
            _Group(
              title: 'Progress',
              description: 'Dungeon room and child/adult state.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _StandardField(
                    view: byLabel['DungeonRoom'],
                    label: 'Dungeon room',
                    source: source,
                  ),
                  const SizedBox(height: BombFlowerSpacing.xl),
                  _StandardField(
                    view: byLabel['Sequence_IsChildhood'],
                    label: 'Childhood',
                    source: source,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;

    return Column(
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
            description,
            style: BombFlowerTypography.caption.copyWith(
              color: palette.textMuted,
            ),
          ),
        ),
        const SizedBox(height: BombFlowerSpacing.lg),
        child,
      ],
    );
  }
}

class _StandardField extends StatelessWidget {
  const _StandardField({
    required this.view,
    required this.label,
    required this.source,
  });

  final TabFieldView? view;
  final String label;
  final SaveTabSource source;

  @override
  Widget build(BuildContext context) {
    final field = view;
    if (field == null) {
      return _MissingField(label: label);
    }
    return FieldEditor(view: field, source: source);
  }
}

class _MissingField extends StatelessWidget {
  const _MissingField({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return StatTile(
      key: ValueKey<String>('player-world-missing-$label'),
      label: label,
      value: '—',
      unit: 'Not stored in this save',
      icon: Icons.help_outline,
      severity: StatSeverity.warning,
      help: 'The save does not contain this field.',
    );
  }
}

/// Three editable components committed together as one 12-byte write.
///
/// The other two components come from the current value, not from the bytes of
/// the component being edited, so editing X never disturbs Y or Z.
class _PositionField extends StatefulWidget {
  const _PositionField({required this.view, required this.source});

  final TabFieldView? view;
  final SaveTabSource source;

  @override
  State<_PositionField> createState() => _PositionFieldState();
}

class _PositionFieldState extends State<_PositionField> {
  List<double> _components = const <double>[0, 0, 0];

  @override
  void initState() {
    super.initState();
    final components = _componentsOf(widget.view?.value);
    if (components != null) {
      _components = components;
    }
  }

  @override
  void didUpdateWidget(_PositionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view?.value != widget.view?.value) {
      final components = _componentsOf(widget.view?.value);
      if (components != null) {
        _components = components;
      }
    }
  }

  void _setComponent(int index, num value) {
    final next = List<double>.of(_components);
    next[index] = value.toDouble();
    setState(() => _components = next);
    _commit();
  }

  void _commit() {
    final descriptor = widget.view?.descriptor;
    if (descriptor == null || descriptor.span.length != 12) {
      return;
    }
    final data = ByteData(12)
      ..setFloat32(0, _components[0], Endian.little)
      ..setFloat32(4, _components[1], Endian.little)
      ..setFloat32(8, _components[2], Endian.little);
    widget.source.edit(
      SetBytes(
        descriptor.id,
        target: descriptor.span,
        bytes: data.buffer.asUint8List(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    if (view == null) {
      return const _MissingField(label: 'Position');
    }
    final descriptor = view.descriptor;
    final components = _componentsOf(view.value);
    if (!descriptor.isEditable ||
        view.value == null ||
        descriptor.span.length != 12 ||
        components == null) {
      return FieldEditor(view: view, source: widget.source);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Position',
          style: BombFlowerTypography.bodyStrong.copyWith(
            color: context.bombFlowerTheme.textPrimary,
          ),
        ),
        const SizedBox(height: BombFlowerSpacing.md),
        Wrap(
          spacing: BombFlowerSpacing.lg,
          runSpacing: BombFlowerSpacing.md,
          children: <Widget>[
            SizedBox(
              width: 220,
              child: NumericField(
                key: PlayerWorldTab.positionXKey,
                label: 'X',
                value: _components[0],
                onChanged: (num next) => _setComponent(0, next),
              ),
            ),
            SizedBox(
              width: 220,
              child: NumericField(
                key: PlayerWorldTab.positionYKey,
                label: 'Y',
                value: _components[1],
                onChanged: (num next) => _setComponent(1, next),
              ),
            ),
            SizedBox(
              width: 220,
              child: NumericField(
                key: PlayerWorldTab.positionZKey,
                label: 'Z',
                value: _components[2],
                onChanged: (num next) => _setComponent(2, next),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Rotation is stored as raw little-endian float32 bits inside an integer
/// field. The UI decodes those bits to radians, shows degrees, and writes the
/// float32 bits of the entered degrees back with a single scalar write.
class _RotationField extends StatelessWidget {
  const _RotationField({required this.view, required this.source});

  final TabFieldView? view;
  final SaveTabSource source;

  @override
  Widget build(BuildContext context) {
    final field = view;
    if (field == null) {
      return const _MissingField(label: 'Rotation');
    }
    final descriptor = field.descriptor;
    final value = field.value;
    if (!descriptor.isEditable || value == null) {
      return FieldEditor(view: field, source: source);
    }
    if (value is! IntValue || descriptor.span.length != 4) {
      return FieldEditor(view: field, source: source);
    }

    final radians = _float32FromBits(value.value);
    if (radians == null || !radians.isFinite) {
      return _notDecodable(context);
    }
    final degrees = radians * 180 / math.pi;
    final palette = context.bombFlowerTheme;
    final outsideHalfTurn = degrees.abs() > 180;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Rotation',
          style: BombFlowerTypography.bodyStrong.copyWith(
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: BombFlowerSpacing.md),
        Wrap(
          spacing: BombFlowerSpacing.lg,
          runSpacing: BombFlowerSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 220,
              child: NumericField(
                key: PlayerWorldTab.rotationFieldKey,
                label: 'Degrees',
                value: degrees,
                unit: '°',
                validator: _validateDegrees,
                onChanged: (num next) {
                  final nextRadians = next * math.pi / 180;
                  source.edit(
                    SetScalar(descriptor.id, _float32Bits(nextRadians)),
                  );
                },
              ),
            ),
            Text(
              '${degrees.toStringAsFixed(3)}°',
              key: PlayerWorldTab.rotationDegreesKey,
              style: BombFlowerTypography.mono.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
        if (outsideHalfTurn) ...<Widget>[
          const SizedBox(height: BombFlowerSpacing.md),
          Banner(
            key: PlayerWorldTab.rotationWarningKey,
            title: 'Rotation outside ±180°',
            message:
                'The stored rotation reads ${degrees.toStringAsFixed(3)}°. '
                'Edits are written exactly as entered; nothing is clamped.',
            variant: BannerVariant.warning,
          ),
        ],
      ],
    );
  }

  Widget _notDecodable(BuildContext context) {
    final palette = context.bombFlowerTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Rotation',
          style: BombFlowerTypography.bodyStrong.copyWith(
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: BombFlowerSpacing.md),
        Container(
          constraints: const BoxConstraints(
            minHeight: BombFlowerSpacing.fieldHeight,
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(
            horizontal: BombFlowerSpacing.lg,
            vertical: BombFlowerSpacing.md,
          ),
          decoration: BoxDecoration(
            color: palette.disabledSurface,
            borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
            border: Border.all(color: palette.border),
          ),
          child: Text(
            'not decodable',
            key: PlayerWorldTab.rotationNotDecodableKey,
            style: BombFlowerTypography.body.copyWith(
              color: palette.disabledText,
            ),
          ),
        ),
        const SizedBox(height: BombFlowerSpacing.sm),
        Text(
          'The stored float32 bits are NaN or infinite, so the editor is '
          'disabled. Nothing is clamped or guessed.',
          style: BombFlowerTypography.caption.copyWith(
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}

String? _validateDegrees(num? value) {
  if (value == null) {
    return 'Enter a number.';
  }
  final radians = value * math.pi / 180;
  final decoded = _float32FromBits(_float32Bits(radians));
  if (decoded == null || !decoded.isFinite) {
    return 'Rotation does not fit a 32-bit float.';
  }
  return null;
}

List<double>? _componentsOf(FieldValue? value) {
  return switch (value) {
    VectorValue(:final components) when components.length == 3 => <double>[
      components[0],
      components[1],
      components[2],
    ],
    PositionValue(:final x, :final y, :final z) => <double>[x, y, z],
    _ => null,
  };
}

double? _float32FromBits(int bits) {
  if (bits < 0 || bits > 0xffffffff) {
    return null;
  }
  final data = ByteData(4)..setUint32(0, bits, Endian.little);
  return data.getFloat32(0, Endian.little);
}

int _float32Bits(double value) {
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  return data.getUint32(0, Endian.little);
}

class _SceneField extends StatefulWidget {
  const _SceneField({
    required this.view,
    required this.source,
    required this.catalogue,
  });

  final TabFieldView? view;
  final SaveTabSource source;
  final world.WorldCatalogue? catalogue;

  @override
  State<_SceneField> createState() => _SceneFieldState();
}

class _SceneFieldState extends State<_SceneField> {
  Future<world.WorldCatalogue>? _catalogueFuture;
  String? _writeError;

  @override
  void initState() {
    super.initState();
    _catalogueFuture = _loadCatalogue();
  }

  @override
  void didUpdateWidget(_SceneField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalogue == null && widget.catalogue != null) {
      _catalogueFuture = null;
    } else if (oldWidget.catalogue != null && widget.catalogue == null) {
      _catalogueFuture = _loadCatalogue();
    }
  }

  Future<world.WorldCatalogue>? _loadCatalogue() {
    if (widget.catalogue != null) {
      return null;
    }
    return rootBundle
        .loadString('assets/world/scenes.json')
        .then(world.loadWorldCatalogue);
  }

  void _selectMap(world.MapEntry entry) {
    final descriptor = widget.view?.descriptor;
    if (descriptor == null) {
      return;
    }
    if (entry.key.length >= descriptor.span.length) {
      setState(() {
        _writeError =
            'The scene key "${entry.key}" needs a NUL terminator and does not '
            'fit the ${descriptor.span.length}-byte field.';
      });
      return;
    }

    final bytes = Uint8List(descriptor.span.length);
    for (var index = 0; index < entry.key.length; index++) {
      bytes[index] = entry.key.codeUnitAt(index);
    }
    if (_writeError != null) {
      setState(() => _writeError = null);
    }
    widget.source.edit(
      SetBytes(descriptor.id, target: descriptor.span, bytes: bytes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    if (view == null) {
      return const _MissingField(label: 'Current scene');
    }
    final descriptor = view.descriptor;
    final value = view.value;
    if (!descriptor.isEditable ||
        value is! StringValue ||
        descriptor.span.length < 2) {
      return FieldEditor(view: view, source: widget.source);
    }

    final error = _writeError;
    final catalogue = widget.catalogue;
    if (catalogue != null) {
      return _withCatalogue(context, view, catalogue, error);
    }

    return FutureBuilder<world.WorldCatalogue>(
      future: _catalogueFuture,
      builder:
          (BuildContext context, AsyncSnapshot<world.WorldCatalogue> snapshot) {
            if (snapshot.hasError) {
              return _unavailable(context, value.value, error);
            }
            final loaded = snapshot.data;
            if (loaded == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Scene',
                    style: BombFlowerTypography.bodyStrong.copyWith(
                      color: context.bombFlowerTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: BombFlowerSpacing.md),
                  Text(
                    'Loading world catalogue…',
                    style: BombFlowerTypography.body.copyWith(
                      color: context.bombFlowerTheme.textMuted,
                    ),
                  ),
                ],
              );
            }
            return _withCatalogue(context, view, loaded, error);
          },
    );
  }

  Widget _withCatalogue(
    BuildContext context,
    TabFieldView view,
    world.WorldCatalogue catalogue,
    String? error,
  ) {
    final stored = (view.value! as StringValue).value;
    final selected = catalogue.byKey(stored);
    final unknown = stored.isNotEmpty && selected == null;
    final palette = context.bombFlowerTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SearchableSelect<world.MapEntry>(
          key: PlayerWorldTab.sceneSelectKey,
          items: catalogue.maps,
          label: 'Scene',
          hintText: 'Select a map',
          itemLabel: (world.MapEntry entry) => entry.displayName,
          itemSubtitle: (world.MapEntry entry) => entry.key,
          search: (world.MapEntry entry) => '${entry.displayName} ${entry.key}',
          value: selected,
          onChanged: _selectMap,
        ),
        if (stored.isNotEmpty && selected != null) ...<Widget>[
          const SizedBox(height: BombFlowerSpacing.sm),
          Text(
            'Stored key: $stored',
            style: BombFlowerTypography.caption.copyWith(
              color: palette.textMuted,
            ),
          ),
        ],
        if (unknown) ...<Widget>[
          const SizedBox(height: BombFlowerSpacing.md),
          Banner(
            key: PlayerWorldTab.sceneUnknownKey,
            title: 'Unknown scene',
            message:
                'The save stores "$stored", which is not in the verified map '
                'catalogue. Choose a known scene to replace it.',
            variant: BannerVariant.warning,
          ),
        ],
        if (error != null) ...<Widget>[
          const SizedBox(height: BombFlowerSpacing.md),
          Banner(
            title: 'Scene not written',
            message: error,
            variant: BannerVariant.danger,
          ),
        ],
      ],
    );
  }

  Widget _unavailable(BuildContext context, String stored, String? error) {
    final palette = context.bombFlowerTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Banner(
          key: PlayerWorldTab.sceneUnavailableKey,
          title: 'World catalogue unavailable',
          message:
              'The bundled map catalogue could not be loaded, so the scene is '
              'shown read-only. No map entries are fabricated.',
          variant: BannerVariant.warning,
        ),
        const SizedBox(height: BombFlowerSpacing.md),
        Text(
          'Scene',
          style: BombFlowerTypography.bodyStrong.copyWith(
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: BombFlowerSpacing.xs),
        Text(
          stored.isEmpty ? '(empty)' : stored,
          key: PlayerWorldTab.sceneStoredTextKey,
          style: BombFlowerTypography.mono.copyWith(color: palette.textPrimary),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: BombFlowerSpacing.md),
          Banner(
            title: 'Scene not written',
            message: error,
            variant: BannerVariant.danger,
          ),
        ],
      ],
    );
  }
}
