import 'package:material_ui/material_ui.dart' hide Banner;

import '../../../domain/core/edit_command.dart';
import '../../../domain/core/field_metadata.dart';
import '../../../domain/core/field_value.dart';
import '../../../domain/fields/field_groups.dart';
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
import '../../widgets/common/rune_chip.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/controls/control_icon_button.dart';
import '../../widgets/controls/rune_checkbox.dart';
import '../../widgets/data/provenance_badge.dart';
import '../../widgets/selectors/item_grid.dart';
import 'placeholder_tab.dart';

/// Inventory tab: acquisition flags, bottles, and the one named item count.
///
/// Acquisition rows toggle exactly one `SetScalar` per click. Bottle contents
/// are edited through [FieldEditor], so an enumeration selection emits exactly
/// one `SetEnum`. The tab never invents an item: it only renders views the
/// [SaveTabSource] reports, and it says so when the source maps none.
class InventoryTab extends StatefulWidget {
  /// Creates the inventory tab.
  const InventoryTab({super.key});

  /// Caveat shown unconditionally: the save stores flags, not item counts.
  static const String stockCaveat =
      'Per-item stock and ammo counts are not stored in this save. '
      'Only PouchData.Item_Token_Gold.StockNum is a named count.';

  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab> {
  static const int _pageSize = 25;
  static const String _acquisitionPrefix = 'IsGet.';
  static const String _bottlePrefix = 'PlayerStatus.AssignableItem.BottleInfo.';
  static const String _stockLabel = 'PouchData.Item_Token_Gold.StockNum';

  String _query = '';
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final source = SaveTabScope.maybeOf(context);
    if (source == null || !source.isOpen) {
      return const TabPageFrame(
        child: EmptyState(
          title: 'Open a save to begin',
          message:
              'Open a save folder to view acquisition flags and edit bottle '
              'contents.',
        ),
      );
    }

    return AnimatedBuilder(
      animation: source.changes,
      builder: (context, _) => _buildBody(source),
    );
  }

  Widget _buildBody(SaveTabSource source) {
    final definition = ShellTab.inventory.definition;
    final views = _inventoryViews(source);
    final acquisition = <TabFieldView>[
      for (final view in views)
        if (view.descriptor.label.startsWith(_acquisitionPrefix) &&
            view.value is BoolValue)
          view,
    ];

    return TabPageFrame(
      child: ParchmentPanel(
        grainSeed: 3,
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
            const Banner(
              title: 'Stock and ammo counts are not stored',
              message: InventoryTab.stockCaveat,
              variant: BannerVariant.info,
            ),
            if (views.isEmpty)
              _buildUnmapped()
            else ...<Widget>[
              _buildStock(views),
              _buildAcquisition(source, acquisition),
              _buildBottles(source, views),
              _buildAcquiredGrid(acquisition),
            ],
          ],
        ),
      ),
    );
  }

  /// Inventory views, falling back to the labels the acquisition and bottle
  /// sections own when the source reports no inventory grouping.
  List<TabFieldView> _inventoryViews(SaveTabSource source) {
    final grouped = source.viewsFor(EditorTabGroup.inventory);
    if (grouped.isNotEmpty) {
      return grouped;
    }
    return <TabFieldView>[
      for (final view in slotScopedViews(source, source.activeSlot))
        if (view.descriptor.label.startsWith(_acquisitionPrefix) ||
            view.descriptor.label.startsWith(_bottlePrefix))
          view,
    ];
  }

  Widget _buildUnmapped() {
    final palette = context.bombFlowerTheme;
    return Padding(
      key: const Key('inventory-unmapped'),
      padding: const EdgeInsets.only(top: BombFlowerSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Inventory fields are not mapped by this source',
            style: BombFlowerTypography.h3.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: BombFlowerSpacing.sm),
          Text(
            'No IsGet.* or PlayerStatus.AssignableItem.BottleInfo.* fields were '
            'reported, so there is nothing to toggle. No items are listed.',
            style: BombFlowerTypography.body.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildStock(List<TabFieldView> views) {
    final palette = context.bombFlowerTheme;
    TabFieldView? stock;
    for (final view in views) {
      if (view.descriptor.label == _stockLabel) {
        stock = view;
        break;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: BombFlowerSpacing.lg),
      child: stock == null
          ? Text(
              '$_stockLabel is not stored in this save.',
              key: const Key('inventory-stock-absent'),
              style: BombFlowerTypography.caption.copyWith(
                color: palette.textMuted,
              ),
            )
          : Column(
              key: const Key('inventory-stock'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Named item count',
                  style: BombFlowerTypography.label.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: BombFlowerSpacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        '$_stockLabel: ${formatFieldValue(stock.value)}',
                        style: BombFlowerTypography.mono.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: BombFlowerSpacing.md),
                    ProvenanceBadge(
                      level: _provenanceLevel(stock.descriptor.confidence),
                      source: stock.descriptor.source,
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildAcquisition(
    SaveTabSource source,
    List<TabFieldView> acquisition,
  ) {
    final palette = context.bombFlowerTheme;
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? acquisition
        : <TabFieldView>[
            for (final view in acquisition)
              if (view.descriptor.label.toLowerCase().contains(query)) view,
          ];
    final acquired = acquisition
        .where((TabFieldView view) => (view.value! as BoolValue).value)
        .length;
    final modified = acquisition
        .where((TabFieldView view) => view.isDirty)
        .length;

    final pageCount = filtered.isEmpty
        ? 1
        : ((filtered.length - 1) ~/ _pageSize) + 1;
    final page = _page.clamp(0, pageCount - 1);
    final visible = filtered
        .skip(page * _pageSize)
        .take(_pageSize)
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.only(top: BombFlowerSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Acquisition',
            style: BombFlowerTypography.h3.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: BombFlowerSpacing.xs),
          Text(
            'IsGet.* flags for items, weapons, armor, and pouch upgrades. '
            'Each is a yes/no acquisition flag, not a count.',
            style: BombFlowerTypography.caption.copyWith(
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: BombFlowerSpacing.md),
          Wrap(
            spacing: BombFlowerSpacing.md,
            runSpacing: BombFlowerSpacing.xs,
            children: <Widget>[
              RuneChip(
                variant: RuneChipVariant.neutral,
                label: 'Total ${acquisition.length}',
                semanticLabel: '${acquisition.length} acquisition flags',
              ),
              RuneChip(
                variant: RuneChipVariant.success,
                label: 'Acquired $acquired',
                semanticLabel: '$acquired acquisition flags are set',
              ),
              RuneChip(
                variant: RuneChipVariant.modified,
                label: 'Modified $modified',
                semanticLabel: '$modified acquisition flags are modified',
              ),
            ],
          ),
          const SizedBox(height: BombFlowerSpacing.md),
          TextField(
            key: const Key('inventory-acquisition-search'),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search acquisition flags',
              hintStyle: BombFlowerTypography.body.copyWith(
                color: palette.textMuted,
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 17,
                color: palette.textMuted,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
            onChanged: (String value) {
              setState(() {
                _query = value;
                _page = 0;
              });
            },
          ),
          const SizedBox(height: BombFlowerSpacing.sm),
          Text(
            '${filtered.length} of ${acquisition.length} acquisition flags',
            key: const Key('inventory-acquisition-count'),
            style: BombFlowerTypography.caption.copyWith(
              color: palette.textMuted,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: BombFlowerSpacing.md),
          if (acquisition.isEmpty)
            Text(
              'This save reports no IsGet.* acquisition flags.',
              style: BombFlowerTypography.body.copyWith(
                color: palette.textMuted,
              ),
            )
          else if (filtered.isEmpty)
            Text(
              'No acquisition flags match "$_query".',
              style: BombFlowerTypography.body.copyWith(
                color: palette.textMuted,
              ),
            )
          else
            for (final view in visible)
              _AcquisitionRow(key: _rowKey(view), source: source, view: view),
          if (pageCount > 1) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.md),
            Row(
              children: <Widget>[
                ControlIconButton(
                  key: const Key('inventory-page-previous'),
                  icon: Icons.chevron_left,
                  semanticLabel: 'Previous acquisition page',
                  tooltip: 'Previous page',
                  onPressed: page > 0
                      ? () => setState(() => _page = page - 1)
                      : null,
                ),
                const SizedBox(width: BombFlowerSpacing.md),
                Text(
                  'Page ${page + 1} of $pageCount',
                  key: const Key('inventory-page-label'),
                  style: BombFlowerTypography.caption.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(width: BombFlowerSpacing.md),
                ControlIconButton(
                  key: const Key('inventory-page-next'),
                  icon: Icons.chevron_right,
                  semanticLabel: 'Next acquisition page',
                  tooltip: 'Next page',
                  onPressed: page < pageCount - 1
                      ? () => setState(() => _page = page + 1)
                      : null,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottles(SaveTabSource source, List<TabFieldView> views) {
    final palette = context.bombFlowerTheme;
    final byLabel = <String, TabFieldView>{
      for (final view in views) view.descriptor.label: view,
    };
    const letters = <String>['A', 'B', 'C', 'D', 'E'];

    return Padding(
      padding: const EdgeInsets.only(top: BombFlowerSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Bottles',
            style: BombFlowerTypography.h3.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: BombFlowerSpacing.xs),
          Text(
            'Each bottle stores its contents and an IsValid flag. Contents use '
            'one shared enumeration, so the same choices apply to every bottle.',
            style: BombFlowerTypography.caption.copyWith(
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: BombFlowerSpacing.md),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              const gap = BombFlowerSpacing.md;
              final columns = constraints.maxWidth >= 900 ? 2 : 1;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: <Widget>[
                  for (var index = 0; index < letters.length; index++)
                    SizedBox(
                      width: width,
                      child: _BottleCard(
                        letter: letters[index],
                        grainSeed: 30 + index,
                        content:
                            byLabel['${_bottlePrefix}Bottle'
                                '${letters[index]}.BottleItem'],
                        isValid:
                            byLabel['${_bottlePrefix}Bottle'
                                '${letters[index]}.IsValid'],
                        source: source,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAcquiredGrid(List<TabFieldView> acquisition) {
    final palette = context.bombFlowerTheme;
    final acquired = <String>[
      for (final view in acquisition)
        if ((view.value! as BoolValue).value) view.descriptor.label,
    ];
    if (acquired.isEmpty) {
      return const SizedBox.shrink();
    }
    final shown = acquired.take(24).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.only(top: BombFlowerSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Acquired items',
            style: BombFlowerTypography.h3.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: BombFlowerSpacing.xs),
          Text(
            'Read-only summary of the first ${shown.length} acquired labels. '
            'Editing happens in the acquisition list above.',
            style: BombFlowerTypography.caption.copyWith(
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: BombFlowerSpacing.md),
          ItemGrid<String>(
            key: const Key('inventory-acquired-grid'),
            items: shown,
            itemLabel: (String label) => label,
            onSelected: null,
            emptySlotLabel: 'Empty slot',
          ),
        ],
      ),
    );
  }

  Key _rowKey(TabFieldView view) {
    return ValueKey<String>(
      'inventory-acquisition-${view.descriptor.id.value}',
    );
  }
}

class _AcquisitionRow extends StatelessWidget {
  const _AcquisitionRow({super.key, required this.source, required this.view});

  final SaveTabSource source;
  final TabFieldView view;

  @override
  Widget build(BuildContext context) {
    final descriptor = view.descriptor;
    final label = descriptor.label;
    final editable = descriptor.isEditable;

    return Padding(
      padding: const EdgeInsets.only(bottom: BombFlowerSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: RuneCheckbox(
              value: (view.value! as BoolValue).value,
              label: label,
              onChanged: editable
                  ? (bool? next) {
                      source.edit(SetScalar(descriptor.id, next! ? 1 : 0));
                    }
                  : null,
            ),
          ),
          if (view.isDirty) ...<Widget>[
            const SizedBox(width: BombFlowerSpacing.md),
            const RuneChip(
              variant: RuneChipVariant.modified,
              label: 'Modified',
              compact: true,
            ),
          ],
          const SizedBox(width: BombFlowerSpacing.md),
          ProvenanceBadge(
            level: _provenanceLevel(descriptor.confidence),
            source: descriptor.source,
          ),
        ],
      ),
    );
  }
}

class _BottleCard extends StatelessWidget {
  const _BottleCard({
    required this.letter,
    required this.grainSeed,
    required this.content,
    required this.isValid,
    required this.source,
  });

  final String letter;
  final int grainSeed;
  final TabFieldView? content;
  final TabFieldView? isValid;
  final SaveTabSource source;

  @override
  Widget build(BuildContext context) {
    final content = this.content;
    final isValid = this.isValid;

    return ParchmentPanel(
      key: Key('inventory-bottle-$letter'),
      title: 'Bottle $letter',
      grainSeed: grainSeed,
      padding: const EdgeInsets.all(BombFlowerSpacing.lg),
      child: content == null && isValid == null
          ? const _MissingField(
              key: Key('inventory-bottle-missing'),
              label: 'Bottle fields',
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (content == null)
                  const _MissingField(label: 'Contents')
                else
                  FieldEditor(view: content, source: source),
                const SizedBox(height: BombFlowerSpacing.md),
                if (isValid == null)
                  const _MissingField(label: 'Valid flag')
                else
                  FieldEditor(view: isValid, source: source),
              ],
            ),
    );
  }
}

class _MissingField extends StatelessWidget {
  const _MissingField({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: BombFlowerTypography.label.copyWith(
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: BombFlowerSpacing.xs),
        Text(
          'Not stored in this save',
          style: BombFlowerTypography.body.copyWith(color: palette.textMuted),
        ),
      ],
    );
  }
}

ProvenanceLevel _provenanceLevel(FieldConfidence confidence) {
  return switch (confidence) {
    FieldConfidence.verified => ProvenanceLevel.verified,
    FieldConfidence.inferred => ProvenanceLevel.inferred,
    FieldConfidence.unverified => ProvenanceLevel.unknown,
  };
}
