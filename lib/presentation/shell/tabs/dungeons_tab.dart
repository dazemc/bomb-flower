import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart' hide Banner;

import '../../../domain/core/edit_command.dart';
import '../../../domain/core/identity.dart';
import '../../../domain/fields/field_groups.dart';
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
import '../../widgets/data/edit_table.dart';
import 'placeholder_tab.dart';

/// Per-dungeon item, key, boss, map, and heart-container fields.
///
/// Every catalogue field renders as one row. A row is editable only when the
/// save's own [FieldDescriptor.isEditable] says so; a missing, inferred, or
/// unverified field stays visible and read-only with its reason stated. Every
/// committed edit is an [EditCommand] passed to [SaveTabSource.edit], so undo,
/// redo, dirty tracking, validation, and backups stay in the save session.
class DungeonsTab extends StatelessWidget {
  /// Creates the dungeons tab.
  const DungeonsTab({super.key, this.catalogue, this.catalogueLoader});

  /// Optional injected field catalogue; when null the bundled asset is loaded.
  final FieldGroupsCatalogue? catalogue;

  /// Optional loader used instead of `rootBundle` when [catalogue] is null.
  ///
  /// It exists so the unavailable-catalogue state is testable without a broken
  /// asset bundle; production always uses the bundled `groups.json`.
  final Future<FieldGroupsCatalogue> Function()? catalogueLoader;

  /// Banner key shown when the field catalogue asset cannot be loaded.
  static const Key catalogueUnavailableKey = ValueKey<String>(
    'dungeons-catalogue-unavailable',
  );

  @override
  Widget build(BuildContext context) {
    final source = SaveTabScope.maybeOf(context);
    if (source == null || !source.isOpen) {
      return const TabPageFrame(
        child: EmptyState(
          title: 'Open a save to begin',
          message:
              'Open a save folder to read and edit the individual dungeon '
              'item, small-key, boss, map, and heart-container flags.',
        ),
      );
    }

    return AnimatedBuilder(
      animation: source.changes,
      builder: (context, _) => _DungeonsTable(
        source: source,
        catalogue: catalogue,
        catalogueLoader: catalogueLoader,
      ),
    );
  }
}

class _DungeonsTable extends StatefulWidget {
  const _DungeonsTable({
    required this.source,
    this.catalogue,
    this.catalogueLoader,
  });

  final SaveTabSource source;
  final FieldGroupsCatalogue? catalogue;
  final Future<FieldGroupsCatalogue> Function()? catalogueLoader;

  @override
  State<_DungeonsTable> createState() => _DungeonsTableState();
}

class _DungeonsTableState extends State<_DungeonsTable> {
  /// Vertical chrome that always frames the page at 1100x700 and 1280x720.
  ///
  /// `TabPageFrame` is a `SingleChildScrollView`, so the table has no intrinsic
  /// bound and must be given one. Subtracted from the window height: the page
  /// gutter (24-32 px top and bottom), the panel's 24 px bottom padding, the
  /// section header with eyebrow, title, purpose, and count line (about 180 px),
  /// the caveat paragraph (about 60 px), and the table's own toolbar, count
  /// readout, and column header (about 110 px). That is roughly 360 px; 320 px
  /// is the floor so a short window still shows several rows and the page
  /// scrolls instead of clipping.
  static const double _chromeAllowance = 360;
  static const double _minimumTableHeight = 320;

  Future<FieldGroupsCatalogue>? _catalogueFuture;

  @override
  void initState() {
    super.initState();
    _catalogueFuture = _loadCatalogue();
  }

  @override
  void didUpdateWidget(_DungeonsTable oldWidget) {
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
    final definition = ShellTab.dungeons.definition;
    final palette = context.bombFlowerTheme;
    final loading = catalogue == null && failure == null;

    // `viewsFor(EditorTabGroup.dungeons)` is empty in the production adapter,
    // so the rows resolve from `allViews`, scoped to the active slot. With no
    // active slot the whole list is used, unfiltered.
    final views = catalogue == null
        ? const <TabFieldView>[]
        : _scopedViews(widget.source);
    final viewsById = <String, TabFieldView>{
      for (final view in views) view.descriptor.id.value: view,
    };
    final rows = catalogue == null
        ? const <EditTableRow>[]
        : buildEditTableRows(
            catalogueFields: catalogue
                .forTab(EditorTabGroup.dungeons)
                .expand((FieldGroup group) => group.fields),
            views: views,
          );

    final named = rows.length;
    final editable = rows.where((EditTableRow row) => row.isEditable).length;
    final countLabel = catalogue == null
        ? null
        : '$named named fields · no hash-only fields · '
              '$editable of $named editable';

    return TabPageFrame(
      child: ParchmentPanel(
        grainSeed: 8,
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
              'Each row is one individual named flag. Only three dungeons have '
              'named DungeonInfo.* item flags, small keys are per-room flags '
              'rather than one inventory count, and only one heart-container '
              'flag is named.',
              style: BombFlowerTypography.caption.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.lg),
            if (failure != null) ...<Widget>[
              Banner(
                key: DungeonsTab.catalogueUnavailableKey,
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
            else
              EditTable(
                rows: rows,
                height: _tableHeight(context),
                searchHint: 'Search dungeon fields by name',
                emptyMessage:
                    'No dungeon fields are named in the field catalogue.',
                errorMessage: failure == null
                    ? null
                    : 'The field catalogue could not be loaded, so no dungeon '
                          'field can be edited here. $failure',
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
        ),
      ),
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
  // never re-scans the save's 11k descriptors.

  void _commitInteger(
    Map<String, TabFieldView> views,
    String id,
    int value,
  ) {
    if (!views.containsKey(id)) return;
    widget.source.edit(SetScalar(FieldId(id), value));
  }

  void _commitBoolean(
    Map<String, TabFieldView> views,
    String id,
    bool value,
  ) {
    if (!views.containsKey(id)) return;
    widget.source.edit(SetScalar(FieldId(id), value ? 1 : 0));
  }

  void _commitEnumeration(
    Map<String, TabFieldView> views,
    String id,
    String key,
  ) {
    if (!views.containsKey(id)) return;
    widget.source.edit(SetEnum(FieldId(id), key));
  }

  void _commitText(Map<String, TabFieldView> views, String id, String text) {
    final view = views[id];
    if (view == null) return;
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
