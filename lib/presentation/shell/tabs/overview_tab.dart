import 'package:material_ui/material_ui.dart' hide Banner;

import '../../../domain/core/field_value.dart';
import '../../../domain/core/identity.dart';
import '../../../domain/fields/field_groups.dart';
import '../../../domain/formatting/hearts.dart';
import '../../../domain/formatting/scalars.dart';
import '../../bloc/shell/tab_definition.dart';
import '../../tabs_support/save_tab_scope.dart';
import '../../tabs_support/save_tab_source.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../../widgets/common/banner.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/parchment_panel.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/controls/control_icon_button.dart';
import '../../widgets/data/stat_tile.dart';
import 'placeholder_tab.dart';

/// Read-only session overview: saved slot identity, health, currency, raw MP,
/// scene banc, age, and outstanding changes.
///
/// This is deliberately a read-only dashboard. It renders exactly the values
/// the [SaveTabSource] reports and never constructs a field editor, calls
/// [SaveTabSource.edit], or invent a missing value: a field the save does not
/// contain shows "Not stored in this save". Editing lives in the Resources and
/// Player & World tabs.
class OverviewTab extends StatelessWidget {
  /// Creates the overview tab.
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final source = SaveTabScope.maybeOf(context);
    if (source == null || !source.isOpen) {
      return const TabPageFrame(
        child: EmptyState(
          title: 'Open a save to begin',
          message:
              'Open a save folder to see its player, world, and outstanding '
              'changes. This overview is read-only.',
        ),
      );
    }

    return AnimatedBuilder(
      animation: source.changes,
      builder: (context, _) => _OverviewDashboard(source: source),
    );
  }
}

class _OverviewDashboard extends StatelessWidget {
  const _OverviewDashboard({required this.source});

  final SaveTabSource source;

  @override
  Widget build(BuildContext context) {
    final definition = ShellTab.overview.definition;
    final palette = context.bombFlowerTheme;
    final views = source.viewsFor(EditorTabGroup.overview);
    final byLabel = <String, TabFieldView>{};
    for (final view in views) {
      byLabel.putIfAbsent(view.descriptor.label, () => view);
    }
    final issues = <String>[];
    for (final view in views) {
      final message = view.issueMessage;
      if (message != null && !issues.contains(message)) {
        issues.add(message);
      }
    }

    final activeSlot = source.activeSlot;
    final newestSlot = source.newestSlot;
    final slotMismatch =
        activeSlot != null && newestSlot != null && newestSlot != activeSlot;

    return TabPageFrame(
      child: ParchmentPanel(
        grainSeed: 2,
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
              titleStyle: BombFlowerTypography.h1,
              description: definition.purpose,
              isModified: source.isDirty,
            ),
            Text(
              'Read-only dashboard. Editing lives in Resources and Player & '
              'World.',
              style: BombFlowerTypography.caption.copyWith(
                color: palette.textMuted,
              ),
            ),
            if (slotMismatch) ...<Widget>[
              const SizedBox(height: BombFlowerSpacing.xl),
              Banner(
                title: 'Newer save on disk',
                message:
                    'Slot ${activeSlot.value} is open, but slot '
                    '${newestSlot.value} was modified more recently.',
                variant: BannerVariant.warning,
              ),
            ],
            for (final issue in issues) ...<Widget>[
              const SizedBox(height: BombFlowerSpacing.md),
              Banner(
                title: 'Field issue',
                message: issue,
                variant: BannerVariant.danger,
              ),
            ],
            const SizedBox(height: BombFlowerSpacing.xl),
            Wrap(
              spacing: BombFlowerSpacing.xl,
              runSpacing: BombFlowerSpacing.xl,
              children: _statTiles(byLabel, activeSlot),
            ),
            const SizedBox(height: BombFlowerSpacing.xl),
            _ChangesRow(source: source),
          ],
        ),
      ),
    );
  }

  List<Widget> _statTiles(
    Map<String, TabFieldView> byLabel,
    SaveSlotId? activeSlot,
  ) {
    final lifeView = byLabel['PlayerStatus.Life'];
    final maxLifeView = byLabel['PlayerStatus.MaxLife'];
    final life = _heartNumber(_asInt(lifeView?.value));
    final maxLife = _heartNumber(_asInt(maxLifeView?.value));

    final rupeeView = byLabel['PlayerStatus.CurrentRupee'];
    final rupees = _asInt(rupeeView?.value);

    final mpView = byLabel['PlayerStatus.MP'];
    final mp = _asInt(mpView?.value);

    final mpMaxView = byLabel['PlayerStatus.MPMax'];
    final mpMax = _asInt(mpMaxView?.value);

    final bancView = byLabel['Sequence_CurrentBanc'];
    final banc = _asString(bancView?.value);

    final ageView = byLabel['Sequence_IsChildhood'];
    final isChild = _asBool(ageView?.value);

    return <Widget>[
      if (life != null && maxLife != null)
        StatTile(
          key: const Key('overview-life'),
          label: 'Life',
          value: '$life / $maxLife',
          unit: 'hearts',
          icon: Icons.favorite_border,
          help:
              'Quarter hearts, four per heart. '
              '${_citationOf(lifeView)} ${_citationOf(maxLifeView)}',
        )
      else
        _unavailableTile(
          key: const Key('overview-life'),
          label: 'Life',
          help:
              'PlayerStatus.Life and PlayerStatus.MaxLife must both be stored '
              'as non-negative quarter-heart counts.',
        ),
      if (rupees != null)
        StatTile(
          key: const Key('overview-rupees'),
          label: 'Rupees',
          value: formatRupees(rupees),
          icon: Icons.paid_outlined,
          help: _citationOf(rupeeView),
        )
      else
        _unavailableTile(
          key: const Key('overview-rupees'),
          label: 'Rupees',
          help: 'PlayerStatus.CurrentRupee is not decoded in this save.',
        ),
      if (mp != null)
        StatTile(
          key: const Key('overview-mp'),
          label: 'MP',
          value: '$mp',
          unit: 'raw units',
          icon: Icons.water_drop_outlined,
          help:
              'Stored raw integer; no magic-power unit is inferred. '
              '${_citationOf(mpView)}',
        )
      else
        _unavailableTile(
          key: const Key('overview-mp'),
          label: 'MP',
          help: 'PlayerStatus.MP is not decoded in this save.',
        ),
      if (mpMax != null)
        StatTile(
          key: const Key('overview-mp-max'),
          label: 'MP max',
          value: '$mpMax',
          unit: 'raw units',
          icon: Icons.water_drop_outlined,
          help:
              'Stored raw integer; no magic-power unit is inferred. '
              '${_citationOf(mpMaxView)}',
        )
      else
        _unavailableTile(
          key: const Key('overview-mp-max'),
          label: 'MP max',
          help: 'PlayerStatus.MPMax is not decoded in this save.',
        ),
      if (banc != null && banc.isNotEmpty)
        StatTile(
          key: const Key('overview-banc'),
          label: 'Scene banc',
          value: banc,
          icon: Icons.map_outlined,
          help:
              'The stored Sequence_CurrentBanc map key, not a display scene '
              'name. ${_citationOf(bancView)}',
        )
      else
        _unavailableTile(
          key: const Key('overview-banc'),
          label: 'Scene banc',
          help: 'Sequence_CurrentBanc is empty or absent in this save.',
        ),
      if (isChild != null)
        StatTile(
          key: const Key('overview-age'),
          label: 'Age',
          value: isChild ? 'Child' : 'Adult',
          icon: Icons.person_outline,
          help:
              'Sequence_IsChildhood is the only stored age signal. '
              '${_citationOf(ageView)}',
        )
      else
        _unavailableTile(
          key: const Key('overview-age'),
          label: 'Age',
          help: 'Sequence_IsChildhood is not decoded in this save.',
        ),
      if (activeSlot != null)
        StatTile(
          key: const Key('overview-slot'),
          label: 'Slot',
          value: activeSlot.value,
          icon: Icons.save_outlined,
          help: 'Active save slot reported by the session.',
        )
      else
        _unavailableTile(
          key: const Key('overview-slot'),
          label: 'Slot',
          help: 'The session has not reported an active save slot.',
        ),
    ];
  }
}

class _ChangesRow extends StatelessWidget {
  const _ChangesRow({required this.source});

  final SaveTabSource source;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final count = source.changedFieldCount;
    final noun = count == 1 ? 'modified field' : 'modified fields';

    return Wrap(
      spacing: BombFlowerSpacing.xl,
      runSpacing: BombFlowerSpacing.lg,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        StatTile(
          key: const Key('overview-dirty'),
          label: 'Unsaved changes',
          value: '$count $noun',
          icon: Icons.edit_note,
          severity: source.isDirty
              ? StatSeverity.warning
              : StatSeverity.neutral,
          help: source.isDirty
              ? 'Fields whose bytes differ from the last saved file.'
              : 'No field differs from the last saved file.',
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ControlIconButton(
              key: const Key('overview-undo'),
              icon: Icons.undo,
              semanticLabel: 'Undo last edit',
              tooltip: 'Undo',
              onPressed: source.canUndo ? source.undo : null,
            ),
            const SizedBox(width: BombFlowerSpacing.md),
            ControlIconButton(
              key: const Key('overview-redo'),
              icon: Icons.redo,
              semanticLabel: 'Redo edit',
              tooltip: 'Redo',
              onPressed: source.canRedo ? source.redo : null,
            ),
            const SizedBox(width: BombFlowerSpacing.md),
            Text(
              source.canUndo || source.canRedo
                  ? 'History available'
                  : 'No history',
              style: BombFlowerTypography.caption.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

StatTile _unavailableTile({
  required Key key,
  required String label,
  String? help,
}) {
  return StatTile(
    key: key,
    label: label,
    value: '—',
    unit: 'Not stored in this save',
    icon: Icons.help_outline,
    severity: StatSeverity.warning,
    help: help ?? 'The save does not contain this field.',
  );
}

int? _asInt(FieldValue? value) => value is IntValue ? value.value : null;

String? _asString(FieldValue? value) =>
    value is StringValue ? value.value : null;

bool? _asBool(FieldValue? value) => value is BoolValue ? value.value : null;

/// Formats non-negative quarter hearts, or returns null when the value cannot
/// be displayed. A negative or absent field is unavailable, never an exception.
String? _heartNumber(int? quarterHearts) {
  if (quarterHearts == null || quarterHearts < 0) {
    return null;
  }
  try {
    final display = HeartsDisplay.fromQuarterHearts(quarterHearts);
    return formatQuarterHearts(display.quarterHearts);
  } on ArgumentError {
    return null;
  }
}

String _citationOf(TabFieldView? view) {
  if (view == null) {
    return 'Field not present in this save.';
  }
  return '${view.descriptor.label}: ${view.descriptor.source}.';
}
