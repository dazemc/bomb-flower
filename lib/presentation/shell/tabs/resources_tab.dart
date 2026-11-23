import 'package:material_ui/material_ui.dart' hide Banner;

import '../../../domain/core/field_value.dart';
import '../../../domain/fields/field_groups.dart';
import '../../../domain/formatting/hearts.dart';
import '../../../domain/formatting/scalars.dart';
import '../../../domain/validation/field_validators.dart';
import '../../../domain/validation/validation_result.dart';
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
import '../../widgets/data/stat_tile.dart';
import 'placeholder_tab.dart';

/// Vitals, currency, and capacity upgrades for the open save.
///
/// Every scalar is edited through [FieldEditor], so one committed value yields
/// exactly one `SetScalar`. The tab never clamps a value to an invented bound
/// and never fabricates a field: cross-field findings are reported as banners,
/// a field the save does not hold shows "Not stored in this save", and ammo is
/// not rendered because ammunition counts are not stored in this save.
class ResourcesTab extends StatelessWidget {
  /// Creates the resources tab.
  const ResourcesTab({super.key});

  /// Numeric entry key for `PlayerStatus.Life`.
  static const Key lifeFieldKey = ValueKey<String>('resources-life');

  /// Numeric entry key for `PlayerStatus.MaxLife`.
  static const Key maxLifeFieldKey = ValueKey<String>('resources-max-life');

  /// Numeric entry key for `PlayerStatus.MP`.
  static const Key mpFieldKey = ValueKey<String>('resources-mp');

  /// Numeric entry key for `PlayerStatus.MPMax`.
  static const Key mpMaxFieldKey = ValueKey<String>('resources-mp-max');

  /// Numeric entry key for `PlayerStatus.CurrentRupee`.
  static const Key rupeesFieldKey = ValueKey<String>('resources-rupees');

  /// Read-out key for the heart interpretation of Life and MaxLife.
  static const Key heartsReadoutKey = ValueKey<String>('resources-hearts');

  /// Read-out key for the formatted rupee count.
  static const Key rupeesReadoutKey = ValueKey<String>(
    'resources-rupees-readout',
  );

  /// Banner key for hard health errors.
  static const Key healthErrorsKey = ValueKey<String>(
    'resources-health-errors',
  );

  /// Banner key for advisory health findings.
  static const Key healthWarningsKey = ValueKey<String>(
    'resources-health-warnings',
  );

  /// Banner key for rupee findings.
  static const Key rupeesWarningKey = ValueKey<String>(
    'resources-rupees-warning',
  );

  /// Text key for the wallet-capacity caveat.
  static const Key rupeesCaveatKey = ValueKey<String>(
    'resources-rupees-caveat',
  );

  /// Banner key for the always-visible ammo caveat.
  static const Key ammoNoticeKey = ValueKey<String>('resources-ammo-notice');

  /// Key for the field editor of capacity upgrade [label].
  static Key upgradeFieldKey(String label) =>
      ValueKey<String>('resources-upgrade-$label');

  @override
  Widget build(BuildContext context) {
    final source = SaveTabScope.maybeOf(context);
    if (source == null || !source.isOpen) {
      return const TabPageFrame(
        child: EmptyState(
          title: 'Open a save to begin',
          message:
              'Open a save folder to edit health, magic, rupees, and capacity '
              'upgrades.',
        ),
      );
    }

    return AnimatedBuilder(
      animation: source.changes,
      builder: (context, _) => _ResourcesDashboard(source: source),
    );
  }
}

/// Wallet caveat shown with rupees. The 500 cap is a game convention only.
const String _walletCaveat =
    'Wallet capacity is not stored in this save. 500 is only the vanilla '
    'large-wallet convention, not a stored maximum.';

/// Ammo caveat shown on every resources view.
const String _ammoCaveat = 'Ammo counts are not stored in this save.';

const Set<String> _healthLabels = <String>{
  'PlayerStatus.Life',
  'PlayerStatus.MaxLife',
};

const Set<String> _magicLabels = <String>{
  'PlayerStatus.MP',
  'PlayerStatus.MPMax',
};

const Set<String> _rupeeLabels = <String>{'PlayerStatus.CurrentRupee'};

/// Every boolean upgrade or blessing label the tab may render.
const List<String> _upgradeLabels = <String>[
  'IsGet.Item_FairyBless_DefenseDouble',
  'IsGet.Item_FairyBless_MP',
  'IsGet.Item_FairyBless_MPDouble',
  'GoronCity_GetBombBag_fromGoron006',
  'MiniGame_Diving_ShilverScale_First',
  'MiniGame_Fishing_GetGoldScale',
  'MiniGame_HitTarget_HrlCity_Get_BulletBag',
  'MiniGame_HitTarget_Kakariko_Get_Quiver',
  'MiniGame_HorseBackArchery_Get_Quiver',
  'Npc_Zora_002_Adult_GoldScale',
];

/// The exact labels this tab may render, used by the `allViews` fallback.
final Set<String> _resourceLabels = <String>{
  ..._healthLabels,
  ..._magicLabels,
  ..._rupeeLabels,
  ..._upgradeLabels,
};

Map<String, TabFieldView> _viewsByLabel(SaveTabSource source) {
  final grouped = source.viewsFor(EditorTabGroup.resources);
  final views = grouped.isNotEmpty
      ? grouped
      : source.allViews.where(
          (TabFieldView view) =>
              _resourceLabels.contains(view.descriptor.label),
        );

  final byLabel = <String, TabFieldView>{};
  for (final view in views) {
    final label = view.descriptor.label;
    if (_resourceLabels.contains(label)) {
      byLabel.putIfAbsent(label, () => view);
    }
  }
  return byLabel;
}

class _ResourcesDashboard extends StatelessWidget {
  const _ResourcesDashboard({required this.source});

  final SaveTabSource source;

  @override
  Widget build(BuildContext context) {
    final definition = ShellTab.resources.definition;
    final byLabel = _viewsByLabel(source);

    final life = _intOf(byLabel['PlayerStatus.Life']?.value);
    final maxLife = _intOf(byLabel['PlayerStatus.MaxLife']?.value);
    final mp = _intOf(byLabel['PlayerStatus.MP']?.value);
    final mpMax = _intOf(byLabel['PlayerStatus.MPMax']?.value);
    final rupees = _intOf(byLabel['PlayerStatus.CurrentRupee']?.value);

    final healthIssues = <ValidationIssue>[
      if (life != null && maxLife != null)
        ...validateLife(life, maxLife).issues,
      if (maxLife != null) ...validateMaxLife(maxLife).issues,
    ];
    final healthErrors = healthIssues
        .where((ValidationIssue issue) => issue.severity == Severity.error)
        .toList(growable: false);
    final healthWarnings = healthIssues
        .where((ValidationIssue issue) => issue.severity == Severity.warning)
        .toList(growable: false);

    final rupeeIssues = rupees == null
        ? const <ValidationIssue>[]
        : validateRupees(rupees).issues;

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
              isModified: source.isDirty,
            ),
            Banner(
              key: ResourcesTab.ammoNoticeKey,
              title: 'Ammo and consumable counts',
              message: _ammoCaveat,
              variant: BannerVariant.info,
            ),
            const SizedBox(height: BombFlowerSpacing.xxxl),
            _ResourcesCard(
              title: 'Health',
              description:
                  'Life and maximum life are stored as signed 32-bit quarter '
                  'hearts; four units make one heart.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _FieldSlot(
                    view: byLabel['PlayerStatus.Life'],
                    label: 'Life',
                    fieldKey: ResourcesTab.lifeFieldKey,
                    source: source,
                  ),
                  const SizedBox(height: BombFlowerSpacing.xl),
                  _FieldSlot(
                    view: byLabel['PlayerStatus.MaxLife'],
                    label: 'Max life',
                    fieldKey: ResourcesTab.maxLifeFieldKey,
                    source: source,
                  ),
                  if (_heartsText(life, maxLife) case final text?) ...<Widget>[
                    const SizedBox(height: BombFlowerSpacing.md),
                    Text(
                      text,
                      key: ResourcesTab.heartsReadoutKey,
                      style: BombFlowerTypography.mono.copyWith(
                        color: context.bombFlowerTheme.textSecondary,
                      ),
                    ),
                  ],
                  if (healthErrors.isNotEmpty) ...<Widget>[
                    const SizedBox(height: BombFlowerSpacing.md),
                    Banner(
                      key: ResourcesTab.healthErrorsKey,
                      title: 'Health values conflict',
                      message: _issueText(healthErrors),
                      variant: BannerVariant.danger,
                    ),
                  ],
                  if (healthWarnings.isNotEmpty) ...<Widget>[
                    const SizedBox(height: BombFlowerSpacing.md),
                    Banner(
                      key: ResourcesTab.healthWarningsKey,
                      title: 'Health outside vanilla conventions',
                      message: _issueText(healthWarnings),
                      variant: BannerVariant.warning,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.xxxl),
            _ResourcesCard(
              title: 'Magic',
              description:
                  'Both values are raw stored units; no magic-power unit is '
                  'inferred.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _FieldSlot(
                    view: byLabel['PlayerStatus.MP'],
                    label: 'MP',
                    fieldKey: ResourcesTab.mpFieldKey,
                    source: source,
                  ),
                  const SizedBox(height: BombFlowerSpacing.xl),
                  _FieldSlot(
                    view: byLabel['PlayerStatus.MPMax'],
                    label: 'MP max',
                    fieldKey: ResourcesTab.mpMaxFieldKey,
                    source: source,
                  ),
                  if (mp != null && mpMax != null) ...<Widget>[
                    const SizedBox(height: BombFlowerSpacing.md),
                    Text(
                      'Stored: $mp / $mpMax raw units',
                      style: BombFlowerTypography.mono.copyWith(
                        color: context.bombFlowerTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.xxxl),
            _ResourcesCard(
              title: 'Rupees',
              description:
                  'The stored rupee count. Nothing is clamped to a wallet '
                  'capacity.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _FieldSlot(
                    view: byLabel['PlayerStatus.CurrentRupee'],
                    label: 'Rupees',
                    fieldKey: ResourcesTab.rupeesFieldKey,
                    source: source,
                  ),
                  if (rupees != null) ...<Widget>[
                    const SizedBox(height: BombFlowerSpacing.md),
                    StatTile(
                      key: ResourcesTab.rupeesReadoutKey,
                      label: 'Rupees',
                      value: formatRupees(rupees),
                      icon: Icons.paid_outlined,
                      help: 'The stored count, formatted for reading.',
                    ),
                  ],
                  const SizedBox(height: BombFlowerSpacing.md),
                  Text(
                    _walletCaveat,
                    key: ResourcesTab.rupeesCaveatKey,
                    style: BombFlowerTypography.caption.copyWith(
                      color: context.bombFlowerTheme.textMuted,
                    ),
                  ),
                  if (rupeeIssues.isNotEmpty) ...<Widget>[
                    const SizedBox(height: BombFlowerSpacing.md),
                    Banner(
                      key: ResourcesTab.rupeesWarningKey,
                      title: 'Rupee count outside vanilla conventions',
                      message: _issueText(rupeeIssues),
                      variant:
                          rupeeIssues.any(
                            (ValidationIssue issue) =>
                                issue.severity == Severity.error,
                          )
                          ? BannerVariant.danger
                          : BannerVariant.warning,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.xxxl),
            _ResourcesCard(
              title: 'Upgrades',
              description:
                  'Capacity upgrades and fairy blessings. A field whose '
                  'meaning is not verified stays read-only.',
              child: Wrap(
                spacing: BombFlowerSpacing.xl,
                runSpacing: BombFlowerSpacing.xl,
                children: <Widget>[
                  for (final label in _upgradeLabels)
                    SizedBox(
                      width: 320,
                      child: _FieldSlot(
                        view: byLabel[label],
                        label: label,
                        fieldKey: ResourcesTab.upgradeFieldKey(label),
                        source: source,
                      ),
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

class _ResourcesCard extends StatelessWidget {
  const _ResourcesCard({
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BombFlowerSpacing.xl),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
        border: Border.all(color: palette.border),
      ),
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
              description,
              style: BombFlowerTypography.caption.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),
          const SizedBox(height: BombFlowerSpacing.lg),
          child,
        ],
      ),
    );
  }
}

/// One scalar slot: a [FieldEditor] when the save holds the field, otherwise an
/// explicit "Not stored in this save" tile. No value is ever invented.
class _FieldSlot extends StatelessWidget {
  const _FieldSlot({
    required this.view,
    required this.label,
    required this.fieldKey,
    required this.source,
  });

  final TabFieldView? view;
  final String label;
  final Key fieldKey;
  final SaveTabSource source;

  @override
  Widget build(BuildContext context) {
    final field = view;
    if (field == null) {
      return StatTile(
        key: ValueKey<String>('resources-missing-$label'),
        label: label,
        value: '—',
        unit: 'Not stored in this save',
        icon: Icons.help_outline,
        severity: StatSeverity.warning,
        help: 'The save does not contain this field.',
      );
    }
    return KeyedSubtree(
      key: fieldKey,
      child: FieldEditor(view: field, source: source),
    );
  }
}

int? _intOf(FieldValue? value) => value is IntValue ? value.value : null;

/// Heart text for two non-negative quarter-heart counts, or `null` when either
/// is absent or negative. Negative health is a validation problem, not a
/// display problem.
String? _heartsText(int? life, int? maxLife) {
  if (life == null || maxLife == null || life < 0 || maxLife < 0) {
    return null;
  }
  final current = HeartsDisplay.fromQuarterHearts(life);
  final maximum = HeartsDisplay.fromQuarterHearts(maxLife);
  return '${current.text} / ${maximum.text}';
}

String _issueText(List<ValidationIssue> issues) =>
    issues.map((ValidationIssue issue) => issue.message).join('\n');
