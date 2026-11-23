import 'package:flutter/services.dart'
    show KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import 'search_index.dart';

export 'search_index.dart';

class _OpenSelectIntent extends Intent {
  const _OpenSelectIntent();
}

/// Compact parchment field that opens an anchored, searchable option panel.
///
/// The field is one Tab stop; Enter, Space, or Arrow Down opens it. Inside the
/// panel the search box keeps focus and Arrow Up/Down move the highlight,
/// Enter selects, and Escape closes and returns focus. Options can be grouped,
/// the current value is checked, and the result count is always printed.
class SearchableSelect<T> extends StatefulWidget {
  const SearchableSelect({
    super.key,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.itemSubtitle,
    this.search,
    this.value,
    this.label,
    this.emptyMessage = 'No options available',
    this.groupBy,
    this.hintText = 'Select an option',
    this.autofocus = false,
    this.maxOverlayHeight = 360,
  });

  final List<T> items;
  final String Function(T item) itemLabel;
  final String? Function(T item)? itemSubtitle;
  final String Function(T item)? search;
  final T? value;
  final ValueChanged<T>? onChanged;
  final String? label;
  final String emptyMessage;
  final String Function(T item)? groupBy;
  final String hintText;
  final bool autofocus;
  final double maxOverlayHeight;

  static const Key fieldKey = ValueKey<String>('searchable-select-field');
  static const Key searchFieldKey = ValueKey<String>(
    'searchable-select-search',
  );
  static const Key panelKey = ValueKey<String>('searchable-select-panel');
  static const Key countKey = ValueKey<String>('searchable-select-count');
  static const Key emptyKey = ValueKey<String>('searchable-select-empty');

  @override
  State<SearchableSelect<T>> createState() => _SearchableSelectState<T>();
}

class _SearchableSelectState<T> extends State<SearchableSelect<T>> {
  late SearchIndex<T> _index;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocus;
  late final FocusNode _fieldFocus;
  final LayerLink _link = LayerLink();
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};

  OverlayEntry? _overlayEntry;
  List<SearchHit<T>> _hits = <SearchHit<T>>[];
  String _query = '';
  int _highlighted = -1;
  double _fieldWidth = 320;
  bool _openUp = false;
  bool _fieldFocused = false;
  bool _fieldHovered = false;

  bool get _enabled => widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    _index = SearchIndex<T>(
      items: widget.items,
      label: widget.itemLabel,
      search: widget.search,
    );
    _searchController = TextEditingController();
    _searchFocus = FocusNode(debugLabel: 'SearchableSelect.search');
    _fieldFocus = FocusNode(debugLabel: 'SearchableSelect.field');
  }

  @override
  void didUpdateWidget(SearchableSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final dataChanged =
        oldWidget.items != widget.items ||
        oldWidget.itemLabel != widget.itemLabel ||
        oldWidget.search != widget.search;
    if (dataChanged) {
      _index = SearchIndex<T>(
        items: widget.items,
        label: widget.itemLabel,
        search: widget.search,
      );
      _refreshResults();
    }
    if (oldWidget.onChanged != null && widget.onChanged == null) {
      final entry = _overlayEntry;
      _overlayEntry = null;
      entry?.remove();
    }
    if (_overlayEntry != null &&
        (dataChanged || oldWidget.value != widget.value)) {
      _overlayEntry!.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _searchController.dispose();
    _searchFocus.dispose();
    _fieldFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _refreshResults() {
    _hits = _index.rank(_query);
    if (_hits.isEmpty) {
      _highlighted = -1;
    } else if (_highlighted < 0 || _highlighted >= _hits.length) {
      _highlighted = 0;
    }
  }

  void _open() {
    if (!_enabled || _overlayEntry != null) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    _query = '';
    _searchController.clear();
    _refreshResults();
    final selected = widget.value;
    if (selected != null) {
      final at = _hits.indexWhere((hit) => hit.item == selected);
      if (at >= 0) _highlighted = at;
    }

    final origin = renderBox.localToGlobal(Offset.zero);
    _fieldWidth = renderBox.size.width;
    final screen = MediaQuery.sizeOf(context);
    final bottomSpace = screen.height - (origin.dy + renderBox.size.height);
    _openUp = bottomSpace < 280 && origin.dy > bottomSpace;

    _overlayEntry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _overlayEntry != null) _searchFocus.requestFocus();
    });
  }

  void _close({bool restoreFocus = true}) {
    final entry = _overlayEntry;
    if (entry == null) return;
    _overlayEntry = null;
    entry.remove();
    if (restoreFocus && mounted) _fieldFocus.requestFocus();
    if (mounted) setState(() {});
  }

  void _select(T item) {
    widget.onChanged?.call(item);
    _close();
  }

  void _selectHighlighted() {
    if (_highlighted < 0 || _highlighted >= _hits.length) return;
    _select(_hits[_highlighted].item);
  }

  void _moveHighlight(int delta) {
    if (_hits.isEmpty) return;
    final next = (_highlighted + delta).clamp(0, _hits.length - 1).toInt();
    if (next == _highlighted) return;
    _highlighted = next;
    _overlayEntry?.markNeedsBuild();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final hit = _hits[_highlighted];
      final rowContext = _rowKeys[hit.index]?.currentContext;
      if (rowContext != null) {
        Scrollable.ensureVisible(
          rowContext,
          alignment: 0.5,
          duration: Duration.zero,
        );
      }
    });
  }

  void _handleQueryChanged(String query) {
    _query = query;
    _highlighted = -1;
    _refreshResults();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _overlayEntry?.markNeedsBuild();
  }

  KeyEventResult _handleSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      _moveHighlight(5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _moveHighlight(-5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _selectHighlighted();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final selected = widget.value;
    final selectedLabel = selected == null ? null : widget.itemLabel(selected);
    final fieldBorder = _fieldFocused
        ? palette.focusOnLight
        : _fieldHovered && _enabled
        ? palette.borderStrong
        : palette.border;
    final fieldBackground = !_enabled
        ? palette.disabledSurface
        : _fieldHovered
        ? BombFlowerColors.parchmentRaised
        : palette.surfaceRaised;

    final field = Semantics(
      container: true,
      button: true,
      enabled: _enabled,
      focusable: _enabled,
      focused: _fieldFocused,
      label: widget.label,
      value: selectedLabel ?? widget.hintText,
      hint: 'Opens a searchable list of ${widget.items.length} options.',
      onTap: _enabled ? _open : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: _enabled,
        autofocus: widget.autofocus,
        focusNode: _fieldFocus,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.arrowDown): _OpenSelectIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _open();
              return null;
            },
          ),
          _OpenSelectIntent: CallbackAction<_OpenSelectIntent>(
            onInvoke: (_) {
              _open();
              return null;
            },
          ),
        },
        onShowHoverHighlight: (value) {
          if (_fieldHovered != value) setState(() => _fieldHovered = value);
        },
        onShowFocusHighlight: (value) {
          if (_fieldFocused != value) setState(() => _fieldFocused = value);
        },
        child: MouseRegion(
          cursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _enabled ? _open : null,
            child: AnimatedContainer(
              key: SearchableSelect.fieldKey,
              duration: BombFlowerMotion.adaptive(
                context,
                BombFlowerMotion.hover,
              ),
              curve: BombFlowerMotion.hoverCurve,
              constraints: const BoxConstraints(
                minHeight: BombFlowerSpacing.fieldHeight,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: BombFlowerSpacing.lg,
                vertical: BombFlowerSpacing.md,
              ),
              decoration: BoxDecoration(
                color: fieldBackground,
                borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
                border: Border.all(
                  color: fieldBorder,
                  width: _fieldFocused ? 2 : 1,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      selectedLabel ?? widget.hintText,
                      style: BombFlowerTypography.body.copyWith(
                        color: selectedLabel == null || !_enabled
                            ? palette.textMuted
                            : palette.textPrimary,
                        fontWeight: selectedLabel == null
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: BombFlowerSpacing.md),
                  Icon(
                    _overlayEntry == null
                        ? Icons.expand_more
                        : Icons.expand_less,
                    size: 18,
                    color: _enabled ? palette.textSecondary : palette.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return CompositedTransformTarget(
      link: _link,
      child: widget.label == null
          ? field
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.label!,
                  style: BombFlowerTypography.label.copyWith(
                    color: _enabled
                        ? palette.textPrimary
                        : palette.disabledText,
                  ),
                ),
                const SizedBox(height: BombFlowerSpacing.xs),
                field,
              ],
            ),
    );
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final palette = overlayContext.bombFlowerTheme;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _close(),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: _openUp ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor: _openUp ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(0, _openUp ? -4 : 4),
          child: SizedBox(
            width: _fieldWidth,
            child: Material(
              key: SearchableSelect.panelKey,
              color: palette.surfaceRaised,
              elevation: BombFlowerElevation.popover.toDouble(),
              shadowColor: BombFlowerColors.shadow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BombFlowerRadii.md),
                side: BorderSide(color: palette.borderStrong),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: widget.maxOverlayHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.all(BombFlowerSpacing.md),
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: _handleSearchKey,
                        child: TextField(
                          key: SearchableSelect.searchFieldKey,
                          controller: _searchController,
                          focusNode: _searchFocus,
                          style: BombFlowerTypography.body.copyWith(
                            color: palette.textPrimary,
                          ),
                          textInputAction: TextInputAction.done,
                          onChanged: _handleQueryChanged,
                          onSubmitted: (_) => _selectHighlighted(),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Search…',
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
                        ),
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BombFlowerSpacing.lg,
                        vertical: BombFlowerSpacing.xs,
                      ),
                      child: Text(
                        '${_hits.length} '
                        '${_hits.length == 1 ? 'result' : 'results'}',
                        key: SearchableSelect.countKey,
                        style: BombFlowerTypography.caption.copyWith(
                          color: palette.textMuted,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                    Flexible(
                      child: _hits.isEmpty
                          ? _buildEmpty(palette)
                          : Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: true,
                              child: ListView(
                                controller: _scrollController,
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                children: _buildRows(palette),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BombFlowerTheme palette) {
    final noMatch = _query.trim().isNotEmpty;
    return Padding(
      key: SearchableSelect.emptyKey,
      padding: const EdgeInsets.all(BombFlowerSpacing.xxxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.search_off, size: 24, color: palette.textMuted),
          const SizedBox(height: BombFlowerSpacing.md),
          Text(
            noMatch ? 'No matches for "$_query"' : widget.emptyMessage,
            textAlign: TextAlign.center,
            style: BombFlowerTypography.bodyStrong.copyWith(
              color: palette.textPrimary,
            ),
          ),
          if (noMatch) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.xs),
            Text(
              widget.emptyMessage,
              textAlign: TextAlign.center,
              style: BombFlowerTypography.caption.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildRows(BombFlowerTheme palette) {
    final rows = <Widget>[];
    String? currentGroup;
    var groupStarted = false;
    for (var index = 0; index < _hits.length; index++) {
      final hit = _hits[index];
      final group = widget.groupBy?.call(hit.item);
      if (widget.groupBy != null && (!groupStarted || group != currentGroup)) {
        currentGroup = group;
        groupStarted = true;
        if (group != null) rows.add(_GroupHeader(label: group));
      }
      rows.add(_buildRow(hit, index, palette));
    }
    return rows;
  }

  Widget _buildRow(SearchHit<T> hit, int resultIndex, BombFlowerTheme palette) {
    final item = hit.item;
    final selected = widget.value == item;
    final highlighted = resultIndex == _highlighted;
    final label = widget.itemLabel(item);
    final subtitle = widget.itemSubtitle?.call(item);
    final semanticsLabel = subtitle == null ? label : '$label, $subtitle';
    final rowKey = _rowKeys.putIfAbsent(hit.index, () => GlobalKey());

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: semanticsLabel,
      onTap: () => _select(item),
      excludeSemantics: true,
      child: InkWell(
        canRequestFocus: false,
        onTap: () => _select(item),
        child: Container(
          key: rowKey,
          constraints: const BoxConstraints(
            minHeight: BombFlowerSpacing.tableRowHeight,
          ),
          decoration: BoxDecoration(
            color: highlighted
                ? palette.selection
                : selected
                ? palette.surfaceSunken
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: highlighted ? palette.accentInk : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: BombFlowerSpacing.lg,
            vertical: BombFlowerSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: BombFlowerTypography.body.copyWith(
                        color: palette.textPrimary,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: BombFlowerTypography.caption.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected) ...<Widget>[
                const SizedBox(width: BombFlowerSpacing.md),
                Icon(Icons.check, size: 16, color: palette.accentInk),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      padding: const EdgeInsets.fromLTRB(
        BombFlowerSpacing.lg,
        BombFlowerSpacing.sm,
        BombFlowerSpacing.lg,
        BombFlowerSpacing.xs,
      ),
      color: palette.surfaceSunken,
      alignment: Alignment.centerLeft,
      child: Text(
        label.toUpperCase(),
        style: BombFlowerTypography.overline.copyWith(color: palette.textMuted),
      ),
    );
  }
}
