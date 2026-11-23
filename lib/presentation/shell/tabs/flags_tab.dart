import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart' hide Banner;

import '../../../domain/core/edit_command.dart';
import '../../../domain/core/field_metadata.dart';
import '../../../domain/core/identity.dart';
import '../../../domain/fields/field_groups.dart';
import '../../../domain/formatting/scalars.dart';
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
import '../../widgets/controls/brass_toggle.dart';
import '../../widgets/data/edit_table.dart';
import '../../widgets/data/provenance_badge.dart';
import 'placeholder_tab.dart';

/// Every Bool flag on disk, in two separate sections.
///
/// The named half is one row per catalogue field. A row is editable only when
/// the save's own [FieldDescriptor.isEditable] says so; a missing, inferred, or
/// unverified field stays visible and read-only with its reason stated. The
/// hash-only half is the other 6,769 on-disk Bools whose hash the schema does
/// not name: they keep the engine's `Unnamed 0x…` label, stay read-only, and
/// are reachable by hash in Advanced Data.
///
/// Both halves live in one bounded [EditTable], shown one at a time, so the
/// page keeps the primitive's virtualisation instead of building 10,212 rows.
/// Every committed edit is an [EditCommand] passed to [SaveTabSource.edit], so
/// undo, redo, dirty tracking, validation, and backups stay in the save
/// session.
class FlagsTab extends StatelessWidget {
  /// Creates the flags tab.
  const FlagsTab({super.key, this.catalogue, this.catalogueLoader});

  /// Optional injected field catalogue; when null the bundled asset is loaded.
  final FieldGroupsCatalogue? catalogue;

  /// Optional loader used instead of `rootBundle` when [catalogue] is null.
  ///
  /// It exists so the unavailable-catalogue state is testable without a broken
  /// asset bundle; production always uses the bundled `groups.json`.
  final Future<FieldGroupsCatalogue> Function()? catalogueLoader;

  /// Banner key shown when the field catalogue asset cannot be loaded.
  static const Key catalogueUnavailableKey = ValueKey<String>(
    'flags-catalogue-unavailable',
  );

  /// Toggle that swaps the table between the named and hash-only sections.
  static const Key hashOnlyToggleKey = ValueKey<String>(
    'flags-hash-only-toggle',
  );

  /// Label above the table naming the section currently shown.
  static const Key sectionLabelKey = ValueKey<String>('flags-section-label');

  /// Why a hash-only row cannot be edited.
  ///
  /// The record is real and on disk, but the schema never recovered a name for
  /// its hash, so no meaning is verified and no editor can be offered.
  static const String hashOnlyReadOnlyReason =
      'Hash-only record: no verified name. Read-only; reachable by hash in '
      'Advanced Data';

  @override
  Widget build(BuildContext context) {
    final source = SaveTabScope.maybeOf(context);
    if (source == null || !source.isOpen) {
      return const TabPageFrame(
        child: EmptyState(
          title: 'Open a save to begin',
          message:
              'Open a save folder to read and edit the individual event, '
              'quest, cutscene, and room Bool flags, including the on-disk '
              'records that have no verified name.',
        ),
      );
    }

    return AnimatedBuilder(
      animation: source.changes,
      builder: (context, _) => _FlagsTable(
        source: source,
        catalogue: catalogue,
        catalogueLoader: catalogueLoader,
      ),
    );
  }
}

class _FlagsTable extends StatefulWidget {
  const _FlagsTable({
    required this.source,
    this.catalogue,
    this.catalogueLoader,
  });

  final SaveTabSource source;
  final FieldGroupsCatalogue? catalogue;
  final Future<FieldGroupsCatalogue> Function()? catalogueLoader;

  @override
  State<_FlagsTable> createState() => _FlagsTableState();
}

class _FlagsTableState extends State<_FlagsTable> {
  /// Vertical chrome that always frames the page at 1100x700 and 1280x720.
  ///
  /// `TabPageFrame` is a `SingleChildScrollView`, so the table has no intrinsic
  /// bound and must be given one. Subtracted from the window height: the page
  /// gutter (24-32 px top and bottom), the panel's 24 px bottom padding, the
  /// section header with eyebrow, title, purpose, and count line (about 180 px),
  /// the caveat paragraph (about 60 px), the section label and toggle row, and
  /// the table's own toolbar, count readout, and column header (about 110 px).
  /// That is roughly 360 px; 320 px is the floor so a short window still shows
  /// several rows and the page scrolls instead of clipping.
  static const double _chromeAllowance = 360;
  static const double _minimumTableHeight = 320;

  static const String _namedSectionLabel =
      'Named Bool fields — editable only where this save verifies the name '
      'and the value decodes.';

  static const String _hashOnlySectionLabel =
      'Hash-only Bool records — no verified name. Read-only; each row is '
      'identified by its on-disk hash.';

  Future<FieldGroupsCatalogue>? _catalogueFuture;

  bool _showHashOnly = false;

  @override
  void initState() {
    super.initState();
    _catalogueFuture = _loadCatalogue();
  }

  @override
  void didUpdateWidget(_FlagsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalogue != widget.catalogue ||
        oldWidget.catalogueLoader != widget.catalogueLoader) {
      _catalogueFuture = _loadCatalogue();
    }
  }

  Future<FieldGroupsCatalogue>? _loadCatalogue() {
    if (widget.catalogue != null) {
      return null;
    }
    final loader = widget.catalogueLoader;
    if (loader != null) {
      return loader();
    }
    return rootBundle
        .loadString('assets/fields/groups.json')
        .then(FieldGroupsCatalogue.load);
  }

  @override
  Widget build(BuildContext context) {
    final injected = widget.catalogue;
    if (injected != null) {
      return _page(context, injected);
    }

    return FutureBuilder<FieldGroupsCatalogue>(
      future: _catalogueFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _page(
            context,
            null,
            failure: _failureText(snapshot.error),
          );
        }
        final loaded = snapshot.data;
        if (loaded == null) {
          return _page(context, null);
        }
        return _page(context, loaded);
      },
    );
  }

  String _failureText(Object? error) {
    final text = error?.toString().trim() ?? '';
    return text.isEmpty ? 'unknown error' : text;
  }

  Widget _page(
    BuildContext context,
    FieldGroupsCatalogue? catalogue, {
    String? failure,
  }) {
    final definition = ShellTab.flags.definition;
    final palette = context.bombFlowerTheme;
    final loading = catalogue == null && failure == null;

    // `viewsFor(EditorTabGroup.flags)` is empty in the production adapter, so
    // the rows resolve from `allViews`, scoped to the active slot. With no
    // active slot the whole list is used, unfiltered.
    final views = catalogue == null
        ? const <TabFieldView>[]
        : _scopedViews(widget.source);
    final viewsById = <String, TabFieldView>{
      for (final view in views) view.descriptor.id.value: view,
    };
    final stats = catalogue?.stats.forTab(EditorTabGroup.flags);
    final namedRows = catalogue == null
        ? const <EditTableRow>[]
        : buildEditTableRows(
            catalogueFields: catalogue
                .forTab(EditorTabGroup.flags)
                .expand((FieldGroup group) => group.fields),
            views: views,
          );
    // The hash-only rows come from the save, not the catalogue: they are the
    // engine's `Unnamed 0x…` Bool records, which no schema name covers.
    final hashOnlyRows = catalogue == null
        ? const <EditTableRow>[]
        : _hashOnlyRows(views);

    final named = namedRows.length;
    final editable = namedRows.where((EditTableRow row) => row.isEditable).length;
    final hashOnly = hashOnlyRows.length;
    final hashOnlyEditable = hashOnlyRows
        .where((EditTableRow row) => row.isEditable)
        .length;

    final rows = _showHashOnly ? hashOnlyRows : namedRows;
    // `formatRupees` is the app's comma-thousands formatter; a field count is
    // just an integer that needs grouping.
    final countLabel = stats == null
        ? null
        : _showHashOnly
        ? '${formatRupees(stats.named)} named fields · '
              '${formatRupees(stats.unnamed)} hash-only · '
              '${formatRupees(hashOnlyEditable)} of '
              '${formatRupees(hashOnly)} hash-only editable'
        : '${formatRupees(stats.named)} named fields · '
              '${formatRupees(stats.unnamed)} hash-only · '
              '${formatRupees(editable)} of ${formatRupees(named)} '
              'named editable';

    return TabPageFrame(
      child: ParchmentPanel(
        grainSeed: 10,
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
              countLabel: countLabel,
              isModified: widget.source.isDirty,
            ),
            Text(
              _caption(catalogue, hashOnly),
              style: BombFlowerTypography.caption.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.lg),
            if (failure != null) ...<Widget>[
              Banner(
                key: FlagsTab.catalogueUnavailableKey,
                title: 'Field catalogue unavailable',
                message:
                    'The bundled field catalogue could not be loaded, so no '
                    'field rows are shown and no editor is offered. Nothing is '
                    'fabricated. ($failure)',
                variant: BannerVariant.warning,
              ),
              const SizedBox(height: BombFlowerSpacing.lg),
            ],
            if (loading)
              Text(
                'Loading field catalogue…',
                style: BombFlowerTypography.body.copyWith(
                  color: palette.textMuted,
                ),
              )
            else ...<Widget>[
              if (catalogue != null) ...<Widget>[
                _sectionRow(palette),
                const SizedBox(height: BombFlowerSpacing.md),
              ],
              EditTable(
                rows: rows,
                height: _tableHeight(context),
                searchHint: _showHashOnly
                    ? 'Search hash-only records by hash'
                    : 'Search named flags by name',
                emptyMessage: _showHashOnly
                    ? 'No hash-only Bool records are present in this save.'
                    : 'No named Bool flags are in the field catalogue.',
                errorMessage: failure == null
                    ? null
                    : 'The field catalogue could not be loaded, so no flag '
                          'can be listed or edited here. $failure',
                onInteger: (String id, int value) =>
                    _commitInteger(viewsById, id, value),
                onBoolean: (String id, bool value) =>
                    _commitBoolean(viewsById, id, value),
                onEnumeration: (String id, String key) =>
                    _commitEnumeration(viewsById, id, key),
                onText: (String id, String text) =>
                    _commitText(viewsById, id, text),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The honest two-halves statement, with measured numbers.
  String _caption(FieldGroupsCatalogue? catalogue, int hashOnlyPresent) {
    if (catalogue == null) {
      return 'No field rows are listed here: the bundled field catalogue could '
          'not be loaded, so neither the named flags nor the hash-only records '
          'can be identified. Advanced Data can still inspect the raw bytes.';
    }
    final stats = catalogue.stats.forTab(EditorTabGroup.flags);
    final present = hashOnlyPresent == stats.unnamed
        ? ''
        : ' ${formatRupees(hashOnlyPresent)} present in this save.';
    return 'Each row is one individual Bool flag; there is no medallion '
        'bitmask and no single event mask. '
        '${formatRupees(stats.named)} named Bool fields. '
        '${formatRupees(stats.unnamed)} on-disk Bools have no verified name and '
        'appear by hash only, read-only.$present';
  }

  /// Section label plus the toggle that swaps the two halves.
  Widget _sectionRow(BombFlowerTheme palette) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            _showHashOnly ? _hashOnlySectionLabel : _namedSectionLabel,
            key: FlagsTab.sectionLabelKey,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: BombFlowerTypography.caption.copyWith(
              color: palette.textMuted,
            ),
          ),
        ),
        const SizedBox(width: BombFlowerSpacing.lg),
        BrassToggle(
          key: FlagsTab.hashOnlyToggleKey,
          value: _showHashOnly,
          label: 'Show hash-only records',
          description: 'Hash-only Bools have no verified name and are '
              'read-only',
          onChanged: (bool next) => setState(() => _showHashOnly = next),
        ),
      ],
    );
  }

  /// The engine's unverified Bool records, as read-only rows.
  ///
  /// A hash-only record never carries an [EditTableRow.kind], so no editor can
  /// exist for it: the table renders its value as plain text.
  List<EditTableRow> _hashOnlyRows(List<TabFieldView> views) {
    return <EditTableRow>[
      for (final view in views)
        if (view.descriptor.confidence == FieldConfidence.unverified &&
            view.descriptor.kind == FieldKind.boolean)
          _hashOnlyRow(view),
    ];
  }

  EditTableRow _hashOnlyRow(TabFieldView view) {
    final descriptor = view.descriptor;
    final formatted = formatFieldValue(view.value);
    return EditTableRow(
      id: descriptor.id.value,
      // The label is the engine's, so it carries the hash and search matches it.
      label: descriptor.label,
      typeLabel: 'Bool',
      valueLabel: formatted.isEmpty ? editTableEmptyValue : formatted,
      level: ProvenanceLevel.unknown,
      source: descriptor.source,
      isModified: view.isDirty,
      readOnlyReason: FlagsTab.hashOnlyReadOnlyReason,
      issueMessage: view.issueMessage,
    );
  }

  /// Every view whose descriptor belongs to the active slot.
  List<TabFieldView> _scopedViews(SaveTabSource source) {
    final slot = source.activeSlot;
    final all = source.allViews;
    if (slot == null) {
      return all.toList(growable: false);
    }
    return <TabFieldView>[
      for (final view in all)
        if (view.descriptor.slot == slot) view,
    ];
  }

  double _tableHeight(BuildContext context) {
    final available = MediaQuery.sizeOf(context).height - _chromeAllowance;
    return available < _minimumTableHeight ? _minimumTableHeight : available;
  }

  // The view map is built once per frame, not per callback, so a keystroke
  // never re-scans the save's 10k descriptors. Each helper also refuses a view
  // the save itself marks not editable, so editability can only narrow.

  void _commitInteger(
    Map<String, TabFieldView> views,
    String id,
    int value,
  ) {
    final view = views[id];
    if (view == null || !view.descriptor.isEditable) return;
    widget.source.edit(SetScalar(FieldId(id), value));
  }

  void _commitBoolean(
    Map<String, TabFieldView> views,
    String id,
    bool value,
  ) {
    final view = views[id];
    if (view == null || !view.descriptor.isEditable) return;
    widget.source.edit(SetScalar(FieldId(id), value ? 1 : 0));
  }

  void _commitEnumeration(
    Map<String, TabFieldView> views,
    String id,
    String key,
  ) {
    final view = views[id];
    if (view == null || !view.descriptor.isEditable) return;
    widget.source.edit(SetEnum(FieldId(id), key));
  }

  void _commitText(Map<String, TabFieldView> views, String id, String text) {
    final view = views[id];
    if (view == null || !view.descriptor.isEditable) return;
    final span = view.descriptor.span;
    // Length-preserving by construction: the payload is exactly the field's
    // declared span, zero-filled after the text. The engine refuses a resize.
    final bytes = Uint8List(span.length);
    final units = text.codeUnits;
    for (var index = 0; index < units.length && index < bytes.length; index++) {
      bytes[index] = units[index];
    }
    widget.source.edit(SetBytes(FieldId(id), target: span, bytes: bytes));
  }
}
