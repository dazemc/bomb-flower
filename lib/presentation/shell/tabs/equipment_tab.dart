import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart' hide Banner;

import '../../../domain/catalogue/actor_catalogue.dart';
import '../../../domain/core/edit_command.dart';
import '../../../domain/core/field_metadata.dart';
import '../../../domain/core/field_value.dart';
import '../../../domain/fields/field_groups.dart';
import '../../../domain/validation/field_validators.dart';
import '../../bloc/shell/tab_definition.dart';
import '../../tabs_support/save_tab_scope.dart';
import '../../tabs_support/save_tab_source.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../../widgets/common/banner.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/field_row.dart';
import '../../widgets/common/parchment_panel.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/selectors/searchable_select.dart';
import 'placeholder_tab.dart';

/// Equipped-slot editing against the verified actor catalogue.
///
/// The tab renders exactly the `PlayerStatus.Equip*` and
/// `PlayerStatus.AnotherEraEquip*` String64 slots the [SaveTabSource] reports.
/// Each slot's options are derived from the catalogue by the slot's own verified
/// actor family; a slot with no verified actor family shows its stored text
/// read-only. Nothing is invented or clamped: an actor is only written when it
/// is an exact catalogue name with the slot's prefix, and a rejected value
/// leaves the save untouched.
class EquipmentTab extends StatelessWidget {
  /// Creates the equipment tab.
  const EquipmentTab({super.key, this.catalogue});

  /// Optional injected actor catalogue; when null the bundled asset is loaded.
  final ActorCatalogue? catalogue;

  /// Searchable-select key for the slot named [label].
  static Key slotSelectKey(String label) =>
      ValueKey<String>('equipment-slot-select-$label');

  /// Stored-text key for the slot named [label].
  static Key slotStoredKey(String label) =>
      ValueKey<String>('equipment-slot-stored-$label');

  /// Custom actor entry key for the slot named [label].
  static Key customInputKey(String label) =>
      ValueKey<String>('equipment-slot-custom-$label');

  /// Custom actor submit key for the slot named [label].
  static Key customApplyKey(String label) =>
      ValueKey<String>('equipment-slot-apply-$label');

  /// Banner key shown when the actor catalogue asset cannot be loaded.
  static const Key catalogueUnavailableKey = ValueKey<String>(
    'equipment-catalogue-unavailable',
  );

  /// Tile key shown when the save stores no equipment slot at all.
  static const Key slotsNotStoredKey = ValueKey<String>(
    'equipment-slots-not-stored',
  );

  @override
  Widget build(BuildContext context) {
    final source = SaveTabScope.maybeOf(context);
    if (source == null || !source.isOpen) {
      return const TabPageFrame(
        child: EmptyState(
          title: 'Open a save to begin',
          message:
              'Open a save folder to read and edit the equipped sword, '
              'shield, armor, boots, gauntlets, and ocarina.',
        ),
      );
    }

    return AnimatedBuilder(
      animation: source.changes,
      builder: (context, _) =>
          _EquipmentDashboard(source: source, catalogue: catalogue),
    );
  }
}

/// The verified actor families a slot may be mapped to.
enum _SlotFamily { sword, shield, tunic, boots, ocarina, handArmor, headArmor }

/// How one slot's verified actors are recognised.
final class _SlotRule {
  const _SlotRule({required this.title, this.prefix, this.entryKind});

  /// Human noun used in helper and error text.
  final String title;

  /// Exact game-string prefix, when the family is prefix-defined.
  final String? prefix;

  /// Catalogue `kind`, when the family is category-defined.
  final String? entryKind;

  /// Whether [entry] belongs to this slot's verified family.
  bool matches(ActorEntry entry) {
    final namePrefix = prefix;
    final kind = entryKind;
    return (namePrefix == null || entry.name.startsWith(namePrefix)) &&
        (kind == null || entry.kind == kind);
  }
}

const _SlotRule _swordRule = _SlotRule(title: 'sword', prefix: 'Weapon_Sword_');
const _SlotRule _shieldRule = _SlotRule(
  title: 'shield',
  prefix: 'Weapon_Shield_',
);
const _SlotRule _tunicRule = _SlotRule(title: 'tunic', entryKind: 'tunic');
const _SlotRule _bootsRule = _SlotRule(title: 'boots', entryKind: 'boots');
const _SlotRule _ocarinaRule = _SlotRule(
  title: 'ocarina',
  prefix: 'Item_Ocarina_',
);
const _SlotRule _handArmorRule = _SlotRule(
  title: 'gauntlet',
  prefix: 'Armor_Adult_Gauntlet_',
);

/// Honest absence of a verified actor for the head-armor slot.
const String _headArmorNote = 'No verified head-armor actor in the catalogue';

/// The label prefix every equipment slot shares.
const String _equipPrefix = 'PlayerStatus.Equip';

/// The label prefix of the alternative-era equipment slots.
const String _anotherEraPrefix = 'PlayerStatus.AnotherEraEquip';

bool _isSlotView(TabFieldView view) {
  final descriptor = view.descriptor;
  return descriptor.kind == FieldKind.string &&
      (descriptor.label.startsWith(_equipPrefix) ||
          descriptor.label.startsWith(_anotherEraPrefix));
}

/// Equipment slots the source reports, in source order.
List<TabFieldView> _slotViews(SaveTabSource source) {
  final grouped = source
      .viewsFor(EditorTabGroup.equipment)
      .where(_isSlotView)
      .toList(growable: false);
  if (grouped.isNotEmpty) {
    return grouped;
  }
  return source.allViews.where(_isSlotView).toList(growable: false);
}

String _slotSuffix(String label) {
  return label.startsWith('PlayerStatus.')
      ? label.substring('PlayerStatus.'.length)
      : label;
}

_SlotFamily? _familyOf(String label) {
  return switch (_slotSuffix(label)) {
    'EquipWeapon' || 'AnotherEraEquipWeapon' => _SlotFamily.sword,
    'EquipShield' || 'AnotherEraEquipShield' => _SlotFamily.shield,
    'EquipArmor' => _SlotFamily.tunic,
    'EquipBoot' => _SlotFamily.boots,
    'EquipOcarina' => _SlotFamily.ocarina,
    'EquipHandArmor' => _SlotFamily.handArmor,
    'EquipHeadArmor' => _SlotFamily.headArmor,
    _ => null,
  };
}

_SlotRule? _ruleFor(_SlotFamily family) {
  return switch (family) {
    _SlotFamily.sword => _swordRule,
    _SlotFamily.shield => _shieldRule,
    _SlotFamily.tunic => _tunicRule,
    _SlotFamily.boots => _bootsRule,
    _SlotFamily.ocarina => _ocarinaRule,
    _SlotFamily.handArmor => _handArmorRule,
    _SlotFamily.headArmor => null,
  };
}

String _disabledReason(FieldDescriptor descriptor) {
  if (descriptor.readOnly) {
    return 'Read-only field';
  }
  return '${descriptor.confidence.name} fields cannot be edited';
}

String? _actorError(
  String name,
  _SlotRule rule,
  ActorCatalogue catalogue,
  int slotLength,
) {
  if (name.isEmpty) {
    return 'Enter an actor name or choose None (empty slot).';
  }
  final lengthCap = slotLength - 1;
  final allowed = lengthCap < maxEquipmentActorLength
      ? lengthCap
      : maxEquipmentActorLength;
  final ascii = validatePrintableAscii(
    name,
    maxLength: allowed,
    field: 'equipment',
  );
  if (ascii.issues.isNotEmpty) {
    return ascii.issues.first.message;
  }
  final prefix = rule.prefix;
  if (prefix != null && !name.startsWith(prefix)) {
    return '"$name" must start with "$prefix" to be stored as a '
        '${rule.title} actor.';
  }
  if (!catalogue.isValidActorString(name)) {
    return '"$name" is not a verified ${rule.title} actor in the catalogue.';
  }
  final entry = catalogue.byName(name);
  if (entry == null || !rule.matches(entry)) {
    return '"$name" is not a verified ${rule.title} actor in the catalogue.';
  }
  return null;
}

/// One synthetic or catalogue-backed choice offered by a slot.
final class _ActorChoice {
  const _ActorChoice.actor(ActorEntry this.entry);
  const _ActorChoice.none() : entry = null;

  /// Catalogue entry, or null for the synthetic empty-slot choice.
  final ActorEntry? entry;

  /// Label the select shows and searches.
  String get label => entry?.displayName ?? 'None (empty slot)';

  /// Secondary text: the exact stored game string.
  String get subtitle => entry?.name ?? 'Writes NUL bytes to clear the slot';
}

List<_ActorChoice> _choicesFor(ActorCatalogue catalogue, _SlotRule rule) {
  return <_ActorChoice>[
    const _ActorChoice.none(),
    for (final entry in catalogue.all)
      if (rule.matches(entry)) _ActorChoice.actor(entry),
  ];
}

_ActorChoice? _choiceFor(String stored, List<_ActorChoice> choices) {
  if (stored.isEmpty) {
    return choices.first;
  }
  for (final choice in choices) {
    if (choice.entry?.name == stored) {
      return choice;
    }
  }
  return null;
}

class _EquipmentDashboard extends StatefulWidget {
  const _EquipmentDashboard({required this.source, this.catalogue});

  final SaveTabSource source;
  final ActorCatalogue? catalogue;

  @override
  State<_EquipmentDashboard> createState() => _EquipmentDashboardState();
}

class _EquipmentDashboardState extends State<_EquipmentDashboard> {
  Future<ActorCatalogue>? _catalogueFuture;

  @override
  void initState() {
    super.initState();
    _loadCatalogue();
  }

  @override
  void didUpdateWidget(_EquipmentDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalogue != widget.catalogue) {
      _loadCatalogue();
    }
  }

  void _loadCatalogue() {
    _catalogueFuture = widget.catalogue == null
        ? rootBundle
              .loadString('assets/catalogue/actors.json')
              .then(loadActorCatalogue)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final views = _slotViews(widget.source);
    final injected = widget.catalogue;
    if (injected != null) {
      return _page(context, views, injected, catalogueUnavailable: false);
    }

    return FutureBuilder<ActorCatalogue>(
      future: _catalogueFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _page(context, views, null, catalogueUnavailable: true);
        }
        final loaded = snapshot.data;
        if (loaded == null) {
          return _page(context, views, null, isLoading: true);
        }
        return _page(context, views, loaded, catalogueUnavailable: false);
      },
    );
  }

  Widget _page(
    BuildContext context,
    List<TabFieldView> views,
    ActorCatalogue? catalogue, {
    bool catalogueUnavailable = false,
    bool isLoading = false,
  }) {
    final definition = ShellTab.equipment.definition;
    final palette = context.bombFlowerTheme;

    return TabPageFrame(
      child: ParchmentPanel(
        grainSeed: 6,
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
              isModified: widget.source.isDirty,
            ),
            Text(
              'Equipment slots are 64-byte actor-name strings, not numeric '
              'item ids. Options come only from the verified actor catalogue.',
              style: BombFlowerTypography.caption.copyWith(
                color: palette.textMuted,
              ),
            ),
            if (catalogueUnavailable) ...<Widget>[
              const SizedBox(height: BombFlowerSpacing.lg),
              const Banner(
                key: EquipmentTab.catalogueUnavailableKey,
                title: 'Actor catalogue unavailable',
                message:
                    'The bundled actor catalogue could not be loaded, so every '
                    'slot is shown read-only. No actor options are fabricated.',
                variant: BannerVariant.warning,
              ),
            ],
            const SizedBox(height: BombFlowerSpacing.xl),
            Text(
              'Equipped slots',
              style: BombFlowerTypography.h3.copyWith(
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Text(
                'Each slot lists only actors the catalogue verifies for that '
                'slot family. A custom name is rejected unless it is an exact '
                'catalogue entry.',
                style: BombFlowerTypography.caption.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.lg),
            if (isLoading)
              Text(
                'Loading actor catalogue…',
                style: BombFlowerTypography.body.copyWith(
                  color: palette.textMuted,
                ),
              )
            else if (views.isEmpty)
              const Banner(
                key: EquipmentTab.slotsNotStoredKey,
                title: 'Not stored in this save',
                message:
                    'The save reports no PlayerStatus.Equip or '
                    'PlayerStatus.AnotherEraEquip String64 slot.',
                variant: BannerVariant.warning,
              )
            else
              for (final view in views) ...<Widget>[
                _EquipmentSlotField(
                  view: view,
                  source: widget.source,
                  catalogue: catalogue,
                ),
                const SizedBox(height: BombFlowerSpacing.xxl),
              ],
          ],
        ),
      ),
    );
  }
}

class _EquipmentSlotField extends StatefulWidget {
  const _EquipmentSlotField({
    required this.view,
    required this.source,
    required this.catalogue,
  });

  final TabFieldView view;
  final SaveTabSource source;
  final ActorCatalogue? catalogue;

  @override
  State<_EquipmentSlotField> createState() => _EquipmentSlotFieldState();
}

class _EquipmentSlotFieldState extends State<_EquipmentSlotField> {
  late final TextEditingController _customController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _customController = TextEditingController();
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _apply(String name) {
    final descriptor = widget.view.descriptor;
    final bytes = Uint8List(descriptor.span.length);
    for (var index = 0; index < name.length; index++) {
      bytes[index] = name.codeUnitAt(index);
    }
    if (_error != null) {
      setState(() => _error = null);
    }
    widget.source.edit(
      SetBytes(descriptor.id, target: descriptor.span, bytes: bytes),
    );
  }

  void _submitCustom(_SlotRule rule, ActorCatalogue catalogue) {
    final name = _customController.text.trim();
    final error = _actorError(
      name,
      rule,
      catalogue,
      widget.view.descriptor.span.length,
    );
    if (error != null) {
      if (error != _error) {
        setState(() => _error = error);
      }
      return;
    }
    _apply(name);
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final descriptor = view.descriptor;
    final label = descriptor.label;
    final stored = switch (view.value) {
      StringValue(:final value) => value,
      _ => null,
    };

    if (!descriptor.isEditable) {
      return _readOnly(
        label: label,
        stored: stored,
        helper: _disabledReason(descriptor),
      );
    }
    if (stored == null) {
      return _readOnly(label: label, stored: null, helper: 'No decoded value');
    }

    final family = _familyOf(label);
    final rule = family == null ? null : _ruleFor(family);
    if (family == _SlotFamily.headArmor) {
      return _readOnly(label: label, stored: stored, helper: _headArmorNote);
    }
    final catalogue = widget.catalogue;
    if (rule == null) {
      return _readOnly(
        label: label,
        stored: stored,
        helper:
            'No verified actor rule for this slot; stored text is '
            'read-only.',
      );
    }
    if (catalogue == null) {
      return _readOnly(
        label: label,
        stored: stored,
        helper: 'Actor catalogue unavailable; stored text is read-only.',
      );
    }

    final choices = _choicesFor(catalogue, rule);
    final selected = _choiceFor(stored, choices);

    return FieldRow(
      label: label,
      error: _error,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _StoredValue(label: label, stored: stored),
          const SizedBox(height: BombFlowerSpacing.md),
          SearchableSelect<_ActorChoice>(
            key: EquipmentTab.slotSelectKey(label),
            items: choices,
            itemLabel: (_ActorChoice choice) => choice.label,
            itemSubtitle: (_ActorChoice choice) => choice.subtitle,
            search: (_ActorChoice choice) =>
                '${choice.label} ${choice.entry?.name ?? ''}',
            hintText: 'Choose a verified ${rule.title} actor',
            value: selected,
            onChanged: (_ActorChoice choice) =>
                _apply(choice.entry?.name ?? ''),
          ),
          const SizedBox(height: BombFlowerSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: EquipmentTab.customInputKey(label),
                  controller: _customController,
                  maxLines: 1,
                  textInputAction: TextInputAction.done,
                  style: BombFlowerTypography.mono.copyWith(
                    color: context.bombFlowerTheme.textPrimary,
                  ),
                  onSubmitted: (_) => _submitCustom(rule, catalogue),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Custom actor name',
                  ),
                ),
              ),
              const SizedBox(width: BombFlowerSpacing.sm),
              TextButton(
                key: EquipmentTab.customApplyKey(label),
                onPressed: () => _submitCustom(rule, catalogue),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _readOnly({
    required String label,
    required String? stored,
    required String helper,
  }) {
    return FieldRow(
      label: label,
      isReadOnly: true,
      helper: helper,
      child: _StoredValue(label: label, stored: stored),
    );
  }
}

class _StoredValue extends StatelessWidget {
  const _StoredValue({required this.label, required this.stored});

  final String label;
  final String? stored;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final text = stored == null
        ? 'Not stored in this save'
        : stored!.isEmpty
        ? 'None'
        : stored!;

    return Container(
      key: EquipmentTab.slotStoredKey(label),
      constraints: const BoxConstraints(
        minHeight: BombFlowerSpacing.fieldHeight,
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(
        horizontal: BombFlowerSpacing.lg,
        vertical: BombFlowerSpacing.md,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        text,
        style: BombFlowerTypography.mono.copyWith(color: palette.textPrimary),
      ),
    );
  }
}
