import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'byte_pattern.dart';
import 'hex_editor_controller.dart';

export 'hex_editor_controller.dart';

const Color _canopyDeep = Color(0xFF101A12);
const Color _canopyRaised = Color(0xFF16241B);
const Color _canopyHigh = Color(0xFF1E2F23);
const Color _parchment = Color(0xFFEFE3C8);
const Color _parchmentMuted = Color(0xFFE3D3B0);
const Color _stone = Color(0xFF6E6A5C);
const Color _brass = Color(0xFFC9A227);
const Color _ink = Color(0xFF241C12);
const Color _inkMuted = Color(0xFF5C4F3A);
const Color _danger = Color(0xFFA63A2E);
const Color _selection = Color(0xFFE8CD7A);

/// The danger tone lifted for dark surfaces.
///
/// [_danger] is tuned for parchment; on the canopy it measures about 2.2:1 and
/// cannot carry text or a border. This is the same hue at light-text weight
/// (`BombFlowerColors.dangerLight`).
const Color _dangerLight = Color(0xFFE88B7D);

/// A derived sage tone for the "verified" mark. The palette above has no
/// success colour, and verified should not share the brass used for edits.
const Color _verified = Color(0xFF7FA37A);

/// Visual tokens for [HexEditor].
///
/// This is deliberately a standalone data class rather than an app theme
/// dependency: the editor can be previewed and tested without the rest of the
/// presentation layer. Every default is a plain [Color] constant defined in
/// this file.
class HexEditorThemeData {
  const HexEditorThemeData({
    this.canopyDeep = _canopyDeep,
    this.canopyRaised = _canopyRaised,
    this.canopyHigh = _canopyHigh,
    this.parchment = _parchment,
    this.parchmentMuted = _parchmentMuted,
    this.stone = _stone,
    this.brass = _brass,
    this.ink = _ink,
    this.inkMuted = _inkMuted,
    this.danger = _danger,
    this.dangerLight = _dangerLight,
    this.selection = _selection,
    this.verified = _verified,
    this.monoFontFamily = 'monospace',
    this.monoFontSize = 13,
    this.monoLineHeight = 20,
    this.radius = 6,
  });

  final Color canopyDeep;
  final Color canopyRaised;
  final Color canopyHigh;
  final Color parchment;
  final Color parchmentMuted;
  final Color stone;
  final Color brass;
  final Color ink;
  final Color inkMuted;
  final Color danger;

  /// The danger tone lifted for the dark canopy.
  ///
  /// [danger] is tuned for parchment and only reaches about 2.2:1 on the
  /// canopy, so text and borders painted on the editor's own dark surface use
  /// this lighter tone instead.
  final Color dangerLight;

  final Color selection;
  final Color verified;

  /// Font family for the address, byte, ASCII, and bit columns.
  final String monoFontFamily;

  /// Font size of the monospace grid. The default 13 matches the editor spec.
  final double monoFontSize;

  /// Row height of the monospace grid. The default 20 matches the editor spec.
  final double monoLineHeight;

  /// Corner radius for panels and controls.
  final double radius;

  /// The grid text style, with a line height that exactly fills a row.
  TextStyle get monoStyle => TextStyle(
    fontFamily: monoFontFamily,
    fontSize: monoFontSize,
    height: monoLineHeight / monoFontSize,
    color: parchment,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// The tint used for [kind] in the grid and legend.
  ///
  /// The grid and legend are painted on the canopy, so [ByteMarkKind.invalid]
  /// uses [dangerLight] rather than the parchment-tuned [danger].
  Color markColor(ByteMarkKind kind) => switch (kind) {
    ByteMarkKind.modified => brass,
    ByteMarkKind.invalid => dangerLight,
    ByteMarkKind.unknown => stone,
    ByteMarkKind.verified => verified,
  };
}

/// A reusable, presentation-only hex and bit editor.
///
/// [controller] owns the bytes, selection, marks, editability, and read-only
/// state. The widget adds a virtualised grid, keyboard editing, a bit
/// inspector, search, jump-to-address, and empty/loading/error states. It
/// imports no app theme: inject a [HexEditorThemeData] instead.
///
/// Keyboard and pointer edits always call
/// [HexEditorController.writeByte] or [HexEditorController.toggleBit], which
/// throw rather than clamp outside the buffer or [HexEditableRange].
///
/// The widget does not dispose [controller]; the host owns its lifetime.
class HexEditor extends StatefulWidget {
  const HexEditor({
    super.key,
    required this.controller,
    this.theme = const HexEditorThemeData(),
    this.bitLabelProvider,
    this.marks = const <int, ByteMarkKind>{},
    this.modifiedOffsets = const <int>{},
    this.title,
    this.emptyMessage = 'Empty buffer',
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    this.showLegend = true,
  });

  /// Source of bytes, selection, marks, and editability rules.
  final HexEditorController controller;

  /// Injected visual tokens.
  final HexEditorThemeData theme;

  /// Optional per-bit meaning labels for the bit inspector.
  final BitLabelProvider? bitLabelProvider;

  /// Extra display marks, merged over the controller's marks.
  final Map<int, ByteMarkKind> marks;

  /// Extra offsets to highlight as edited, merged with the controller's set.
  final Set<int> modifiedOffsets;

  /// Optional toolbar title.
  final String? title;

  /// Message shown for a zero-length buffer.
  final String emptyMessage;

  /// Whether to show skeleton rows instead of the grid.
  final bool isLoading;

  /// When non-null, replaces the body with an error message and optional retry.
  final String? errorMessage;

  /// Retry callback for the error state.
  final VoidCallback? onRetry;

  /// Whether to show the mark colour legend.
  final bool showLegend;

  /// Key for the jump-to-address field.
  static const Key jumpFieldKey = ValueKey<String>('hex-jump-field');

  /// Key for the byte-sequence search field.
  static const Key searchFieldKey = ValueKey<String>('hex-search-field');

  /// Key for the ASCII search toggle.
  static const Key searchAsciiKey = ValueKey<String>('hex-search-ascii');

  /// Key for the previous-match button.
  static const Key searchPreviousKey = ValueKey<String>('hex-search-prev');

  /// Key for the next-match button.
  static const Key searchNextKey = ValueKey<String>('hex-search-next');

  /// Key for the selected-bytes hex field.
  static const Key selectionFieldKey = ValueKey<String>('hex-selection-field');

  /// Key for the apply-selection-bytes button.
  static const Key applySelectionKey = ValueKey<String>('hex-selection-apply');

  /// Key for the error-state retry button.
  static const Key retryKey = ValueKey<String>('hex-retry');

  /// Key for one byte cell.
  static ValueKey<String> cellKey(int offset) =>
      ValueKey<String>('hex-cell-$offset');

  /// Key for one bit toggle.
  static ValueKey<String> bitKey(int offset, int bitIndex) =>
      ValueKey<String>('hex-bit-$offset-$bitIndex');

  @override
  State<HexEditor> createState() => _HexEditorState();
}

class _HexEditorState extends State<HexEditor> {
  static const double _cellWidth = 32;
  static const double _addressWidth = 76;
  static const double _asciiWidth = 132;
  static const int _pageRows = 8;

  final FocusNode _gridFocus = FocusNode(debugLabel: 'HexEditorGrid');
  final FocusNode _selectionFieldFocus = FocusNode(
    debugLabel: 'HexEditorSelectionField',
  );
  final ScrollController _gridScroll = ScrollController();
  final ScrollController _horizontalScroll = ScrollController();
  late final TextEditingController _jumpController;
  late final TextEditingController _searchController;
  late final TextEditingController _selectionHexController;

  int? _pendingNibble;
  int? _lastActiveOffset;
  int _lastRevision = 0;
  int _bytesPerRow = 16;
  bool _gridFocused = false;

  String? _jumpError;
  String? _selectionError;
  String? _searchError;
  bool _searchAscii = false;
  BytePattern? _pattern;
  List<int> _matches = const <int>[];
  Set<int> _matchOffsets = const <int>{};
  Set<int> _currentMatchOffsets = const <int>{};
  int _matchIndex = -1;

  @override
  void initState() {
    super.initState();
    _jumpController = TextEditingController();
    _searchController = TextEditingController();
    _selectionHexController = TextEditingController();
    _lastRevision = widget.controller.revision;
    _lastActiveOffset = widget.controller.activeOffset;
    _syncSelectionText(force: true);
    widget.controller.addListener(_onControllerChanged);
    _gridFocus.addListener(_onGridFocusChanged);
    _selectionFieldFocus.addListener(_onSelectionFieldFocusChanged);
  }

  @override
  void didUpdateWidget(HexEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _lastRevision = widget.controller.revision;
      _lastActiveOffset = widget.controller.activeOffset;
      _clearSearch();
      _selectionHexController.clear();
      _selectionError = null;
      _syncSelectionText(force: true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _gridFocus.dispose();
    _selectionFieldFocus.dispose();
    _gridScroll.dispose();
    _horizontalScroll.dispose();
    _jumpController.dispose();
    _searchController.dispose();
    _selectionHexController.dispose();
    super.dispose();
  }

  void _onGridFocusChanged() {
    final focused = _gridFocus.hasFocus;
    if (focused == _gridFocused || !mounted) return;
    setState(() => _gridFocused = focused);
  }

  void _onSelectionFieldFocusChanged() {
    if (!_selectionFieldFocus.hasFocus) {
      _syncSelectionText(force: true);
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final controller = widget.controller;

    if (controller.revision != _lastRevision) {
      _lastRevision = controller.revision;
      if (_searchController.text.isNotEmpty) {
        _executeSearch();
      }
    }

    final active = controller.activeOffset;
    if (active != _lastActiveOffset) {
      _lastActiveOffset = active;
      _pendingNibble = null;
      _selectionError = null;
    }

    _syncSelectionText();
  }

  void _syncSelectionText({bool force = false}) {
    if (_selectionFieldFocus.hasFocus && !force) return;
    final text = widget.controller.selectionHex;
    if (_selectionHexController.text == text) return;
    _selectionHexController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Material(
      color: theme.canopyDeep,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              _bytesPerRow = wide ? 16 : 8;
              final normal =
                  widget.errorMessage == null &&
                  !widget.isLoading &&
                  !widget.controller.isEmpty;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (normal) _buildToolbar(),
                  if (normal && widget.showLegend) _buildLegend(),
                  Expanded(child: _buildBody(wide)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildToolbar() {
    final theme = widget.theme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          if (widget.title != null)
            Text(
              widget.title!,
              style: TextStyle(
                color: theme.parchment,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          SizedBox(
            width: 152,
            child: TextField(
              key: HexEditor.jumpFieldKey,
              controller: _jumpController,
              style: _inputStyle(),
              cursorColor: theme.brass,
              textInputAction: TextInputAction.go,
              decoration: _inputDecoration(
                'Jump to address',
                hintText: '00000000',
                errorText: _jumpError,
              ),
              onChanged: (_) {
                if (_jumpError != null) {
                  setState(() => _jumpError = null);
                }
              },
              onSubmitted: _submitJump,
            ),
          ),
          SizedBox(
            width: 210,
            child: TextField(
              key: HexEditor.searchFieldKey,
              controller: _searchController,
              style: _inputStyle(),
              cursorColor: theme.brass,
              textInputAction: TextInputAction.search,
              decoration: _inputDecoration(
                'Search bytes',
                hintText: _searchAscii ? 'text' : 'DE AD BE EF',
                errorText: _searchError,
              ),
              onChanged: (_) => _executeSearch(reset: true),
              onSubmitted: (_) => _nextMatch(),
            ),
          ),
          Tooltip(
            message: 'Interpret the search query as ASCII text',
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: FilterChip(
                key: HexEditor.searchAsciiKey,
                label: const Text('ASCII'),
                selected: _searchAscii,
                onSelected: _toggleAsciiSearch,
                backgroundColor: theme.canopyHigh,
                selectedColor: theme.brass,
                checkmarkColor: theme.ink,
                labelStyle: TextStyle(
                  color: _searchAscii ? theme.ink : theme.parchment,
                  fontSize: 11,
                ),
                side: BorderSide(color: theme.stone.withValues(alpha: 0.4)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          if (_pattern != null)
            Text(
              '${_matches.length} '
              '${_matches.length == 1 ? 'match' : 'matches'}',
              style: TextStyle(color: theme.parchmentMuted, fontSize: 11),
            ),
          if (_matches.isNotEmpty)
            Text(
              '${_matchIndex + 1} / ${_matches.length}',
              style: theme.monoStyle.copyWith(fontSize: 11, color: theme.brass),
            ),
          _toolbarButton(
            key: HexEditor.searchPreviousKey,
            icon: Icons.keyboard_arrow_up,
            tooltip: 'Previous match',
            onPressed: _matches.isEmpty ? null : _previousMatch,
          ),
          _toolbarButton(
            key: HexEditor.searchNextKey,
            icon: Icons.keyboard_arrow_down,
            tooltip: 'Next match',
            onPressed: _matches.isEmpty ? null : _nextMatch,
          ),
          if (widget.controller.readOnly) _buildReadOnlyBadge(),
        ],
      ),
    );
  }

  Widget _toolbarButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final theme = widget.theme;
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      style: IconButton.styleFrom(
        foregroundColor: theme.parchment,
        backgroundColor: theme.canopyHigh,
        disabledForegroundColor: theme.stone.withValues(alpha: 0.55),
        side: BorderSide(color: theme.stone.withValues(alpha: 0.35)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  Widget _buildReadOnlyBadge() {
    final theme = widget.theme;
    return Tooltip(
      message: 'Editing is disabled for this buffer',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: theme.dangerLight.withValues(alpha: 0.16),
          border: Border.all(color: theme.dangerLight),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'READ-ONLY',
          style: TextStyle(
            color: theme.dangerLight,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    final theme = widget.theme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          for (final kind in ByteMarkKind.values)
            Semantics(
              label: '${_markName(kind)} bytes',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: theme.markColor(kind).withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _markName(kind),
                    style: TextStyle(color: theme.parchmentMuted, fontSize: 10),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(bool wide) {
    if (widget.errorMessage != null) return _buildError();
    if (widget.isLoading) return _buildLoading();
    if (widget.controller.isEmpty) return _buildEmpty();

    final bitLength = _bitSelectionLength;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: _buildGrid(wide)),
        if (widget.controller.selectionLength > 0) _buildSelectionBar(),
        if (bitLength != null) _buildBitPanel(),
      ],
    );
  }

  Widget _buildGrid(bool wide) {
    final theme = widget.theme;
    final rows = (widget.controller.length + _bytesPerRow - 1) ~/ _bytesPerRow;
    final contentWidth =
        _addressWidth +
        _bytesPerRow * _cellWidth +
        (_bytesPerRow == 16 ? 8 : 0) +
        (wide ? _asciiWidth + 16 : 0) +
        12;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: theme.canopyRaised,
          borderRadius: BorderRadius.circular(theme.radius),
          border: Border.all(
            color: _gridFocused ? theme.brass : theme.canopyHigh,
            width: _gridFocused ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(theme.radius),
          child: Focus(
            focusNode: _gridFocus,
            autofocus: true,
            onKeyEvent: _handleKeyEvent,
            child: Semantics(
              container: true,
              label: 'Hex byte grid, $_bytesPerRow bytes per row',
              child: Scrollbar(
                controller: _gridScroll,
                child: SingleChildScrollView(
                  controller: _horizontalScroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentWidth,
                    child: ListView.builder(
                      key: ValueKey<String>('hex-grid-$_bytesPerRow'),
                      controller: _gridScroll,
                      itemExtent: theme.monoLineHeight,
                      itemCount: rows,
                      itemBuilder: (context, row) => _buildRow(row, wide),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(int row, bool wide) {
    final controller = widget.controller;
    final start = row * _bytesPerRow;
    final end = math.min(start + _bytesPerRow, controller.length);
    final children = <Widget>[
      SizedBox(
        width: _addressWidth,
        child: Text(
          _hex8(controller.baseOffset + start),
          style: widget.theme.monoStyle.copyWith(color: widget.theme.stone),
        ),
      ),
    ];

    for (var column = 0; column < _bytesPerRow; column++) {
      if (_bytesPerRow == 16 && column == 8) {
        children.add(const SizedBox(width: 8));
      }
      final offset = start + column;
      if (offset < end) {
        children.add(_buildCell(offset));
      } else {
        children.add(const SizedBox(width: _cellWidth));
      }
    }

    if (wide) {
      children.add(const SizedBox(width: 16));
      children.add(
        SizedBox(
          width: _asciiWidth,
          child: Text(
            _asciiFor(controller.bytes, start, end),
            key: const ValueKey<String>('hex-ascii-gutter'),
            style: widget.theme.monoStyle.copyWith(
              color: widget.theme.parchmentMuted,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: widget.theme.monoLineHeight,
      child: Row(children: children),
    );
  }

  Widget _buildCell(int offset) {
    final controller = widget.controller;
    final offsetMark = widget.marks[offset] ?? controller.marks[offset];
    final modified =
        widget.modifiedOffsets.contains(offset) ||
        controller.modifiedOffsets.contains(offset);
    return HexByteCell(
      key: HexEditor.cellKey(offset),
      address: controller.baseOffset + offset,
      value: controller.bytes[offset],
      theme: widget.theme,
      selected: controller.isSelected(offset),
      editable: controller.isEditable(offset),
      isSearchMatch: _matchOffsets.contains(offset),
      isCurrentMatch: _currentMatchOffsets.contains(offset),
      mark: offsetMark,
      modified: modified,
      onTap: () => _onCellTap(offset),
    );
  }

  Widget _buildSelectionBar() {
    final controller = widget.controller;
    final theme = widget.theme;
    final start = controller.selectionStart!;
    final end = controller.selectionEnd!;
    final count = end - start;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            '0x${_hex8(controller.baseOffset + start)}-'
            '0x${_hex8(controller.baseOffset + end - 1)}',
            style: theme.monoStyle.copyWith(
              fontSize: 11,
              color: theme.parchmentMuted,
            ),
          ),
          Text(
            '$count ${count == 1 ? 'byte' : 'bytes'} selected',
            style: TextStyle(color: theme.stone, fontSize: 11),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              key: HexEditor.selectionFieldKey,
              focusNode: _selectionFieldFocus,
              controller: _selectionHexController,
              enabled: !controller.readOnly,
              style: _inputStyle(),
              cursorColor: theme.brass,
              textInputAction: TextInputAction.done,
              decoration: _inputDecoration(
                'Selected bytes (hex)',
                hintText: 'AA BB CC',
                errorText: _selectionError,
              ),
              onSubmitted: (_) => _applySelectionHex(),
            ),
          ),
          _toolbarButton(
            key: HexEditor.applySelectionKey,
            icon: Icons.check,
            tooltip: 'Apply selection bytes',
            onPressed: controller.readOnly ? null : _applySelectionHex,
          ),
        ],
      ),
    );
  }

  Widget _buildBitPanel() {
    final controller = widget.controller;
    final theme = widget.theme;
    final start = controller.selectionStart!;
    final length = controller.selectionLength;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 224),
        decoration: BoxDecoration(
          color: theme.canopyRaised,
          borderRadius: BorderRadius.circular(theme.radius),
          border: Border.all(color: theme.canopyHigh),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.memory, size: 14, color: theme.brass),
                  const SizedBox(width: 6),
                  Text(
                    'Bit inspector',
                    style: TextStyle(
                      color: theme.parchment,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    length == 1
                        ? '0x${_hex8(controller.baseOffset + start)}'
                        : '0x${_hex8(controller.baseOffset + start)}-'
                              '0x${_hex8(controller.baseOffset + start + length - 1)}',
                    style: theme.monoStyle.copyWith(
                      fontSize: 11,
                      color: theme.stone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildValueSummary(controller, start, length),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (var index = 0; index < length; index++)
                      _buildBitRow(start + index),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildValueSummary(
    HexEditorController controller,
    int start,
    int length,
  ) {
    final data = controller.bytes.sublist(start, start + length);
    final facts = <Widget>[_fact('Hex', data.map(_hex2).join(' '))];

    if (length == 1) {
      final value = data.first;
      facts
        ..add(_fact('Dec', '$value'))
        ..add(_fact('Bin', _groupBits(value.toRadixString(2).padLeft(8, '0'))));
    } else {
      final big = _readBigEndian(data);
      final little = _readLittleEndian(data);
      facts
        ..add(
          _fact('Big endian', '0x${_hexBig(big, length)} (${big.toString()})'),
        )
        ..add(
          _fact(
            'Little endian',
            '0x${_hexBig(little, length)} (${little.toString()})',
          ),
        );
      if (length <= 4) {
        facts.add(
          _fact(
            'Bin (BE)',
            _groupBits(big.toRadixString(2).padLeft(length * 8, '0')),
          ),
        );
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: facts,
    );
  }

  Widget _fact(String label, String value) {
    final theme = widget.theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.canopyHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: theme.stone,
              fontSize: 9,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: theme.monoStyle.copyWith(
              fontSize: 11,
              height: 1.2,
              color: theme.parchment,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBitRow(int offset) {
    final theme = widget.theme;
    final editable = widget.controller.isEditable(offset);
    final value = widget.controller.bytes[offset];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 78,
          child: Text(
            '0x${_hex8(widget.controller.baseOffset + offset)}',
            style: theme.monoStyle.copyWith(
              fontSize: 10,
              color: theme.parchmentMuted,
            ),
          ),
        ),
        for (var bit = 7; bit >= 0; bit--)
          _buildBitCell(offset, bit, value, editable),
      ],
    );
  }

  Widget _buildBitCell(int offset, int bit, int value, bool editable) {
    final theme = widget.theme;
    final set = (value >> bit) & 1 == 1;
    final label = widget.bitLabelProvider?.call(offset, bit);
    final background = set
        ? (editable ? theme.brass : theme.stone)
        : theme.canopyHigh;
    final foreground = set
        ? (editable ? theme.ink : theme.canopyDeep)
        : (editable ? theme.parchmentMuted : theme.stone);
    final description = label ?? 'Bit $bit';

    return SizedBox(
      width: 40,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '$bit',
            style: TextStyle(color: theme.stone, fontSize: 9, height: 1),
          ),
          const SizedBox(height: 1),
          Tooltip(
            message: editable ? description : '$description (read-only)',
            excludeFromSemantics: true,
            waitDuration: const Duration(milliseconds: 500),
            child: Semantics(
              button: editable,
              enabled: editable,
              label:
                  'Bit $bit, ${set ? 'set' : 'clear'}'
                  '${label == null ? '' : ', $label'}',
              child: InkWell(
                key: HexEditor.bitKey(offset, bit),
                onTap: editable
                    ? () {
                        widget.controller.toggleBit(offset, bit);
                        _gridFocus.requestFocus();
                      }
                    : null,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: set
                          ? theme.brass
                          : theme.stone.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    set ? '1' : '0',
                    style: theme.monoStyle.copyWith(
                      fontSize: 12,
                      height: 1,
                      color: foreground,
                      fontWeight: set ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 12,
            child: label == null
                ? null
                : Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.parchmentMuted,
                      fontSize: 8,
                      height: 1.2,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final theme = widget.theme;
    return Center(
      child: Semantics(
        label: 'Empty buffer. 0 bytes.',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.data_array, size: 28, color: theme.stone),
            const SizedBox(height: 8),
            Text(
              widget.emptyMessage,
              style: TextStyle(
                color: theme.parchment,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'This buffer contains 0 bytes.',
              style: TextStyle(color: theme.stone, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    final theme = widget.theme;
    return Semantics(
      label: 'Loading byte data',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var row = 0; row < 10; row++)
              SizedBox(
                height: theme.monoLineHeight,
                child: Row(
                  children: <Widget>[
                    _skeletonBar(64, theme.stone.withValues(alpha: 0.18)),
                    const SizedBox(width: 14),
                    for (var column = 0; column < 8; column++) ...<Widget>[
                      _skeletonBar(
                        12,
                        theme.stone.withValues(alpha: row.isEven ? 0.16 : 0.11),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _skeletonBar(double width, Color color) {
    return Container(
      width: width,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildError() {
    final theme = widget.theme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.warning_amber_rounded,
              size: 30,
              color: theme.dangerLight,
            ),
            const SizedBox(height: 10),
            Text(
              widget.errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.parchment, fontSize: 13),
            ),
            if (widget.onRetry != null) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: HexEditor.retryKey,
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.brass,
                  foregroundColor: theme.ink,
                  minimumSize: const Size(88, 36),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String label, {
    String? hintText,
    String? errorText,
  }) {
    final theme = widget.theme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: theme.stone.withValues(alpha: 0.55)),
    );
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      errorText: errorText,
      isDense: true,
      filled: true,
      fillColor: theme.canopyHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      labelStyle: TextStyle(color: theme.parchmentMuted, fontSize: 11),
      floatingLabelStyle: TextStyle(color: theme.brass, fontSize: 11),
      hintStyle: TextStyle(
        color: theme.stone,
        fontSize: 11,
        fontFamily: theme.monoFontFamily,
      ),
      errorStyle: TextStyle(color: theme.dangerLight, fontSize: 10),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: theme.brass, width: 1.5),
      ),
      errorBorder: border.copyWith(
        borderSide: BorderSide(color: theme.dangerLight),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: BorderSide(color: theme.dangerLight, width: 1.5),
      ),
    );
  }

  TextStyle _inputStyle() => widget.theme.monoStyle.copyWith(
    fontSize: 12,
    height: 1.2,
    color: widget.theme.parchment,
  );

  void _onCellTap(int offset) {
    _gridFocus.requestFocus();
    widget.controller.selectByte(
      offset,
      extend: HardwareKeyboard.instance.isShiftPressed,
    );
    _scrollToOffset(offset);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final controller = widget.controller;
    if (controller.isEmpty) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final extend = HardwareKeyboard.instance.isShiftPressed;

    if (key == LogicalKeyboardKey.arrowLeft) {
      _move(-1, extend);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _move(1, extend);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-_bytesPerRow, extend);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(_bytesPerRow, extend);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      controller.selectByte(0, extend: extend);
      _scrollToOffset(controller.activeOffset!);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      controller.selectByte(controller.length - 1, extend: extend);
      _scrollToOffset(controller.activeOffset!);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _move(-_bytesPerRow * _pageRows, extend);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      _move(_bytesPerRow * _pageRows, extend);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.escape) {
      _pendingNibble = null;
      controller.clearSelection();
      return KeyEventResult.handled;
    }

    final nibble = _nibbleFor(event);
    if (nibble != null) {
      _handleHexDigit(nibble);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _move(int delta, bool extend) {
    widget.controller.moveSelection(delta, extend: extend);
    final active = widget.controller.activeOffset;
    if (active != null) _scrollToOffset(active);
  }

  void _handleHexDigit(int nibble) {
    final controller = widget.controller;
    if (controller.readOnly) return;
    final active = controller.activeOffset;
    if (active == null || !controller.isEditable(active)) return;

    final pending = _pendingNibble;
    if (pending == null) {
      setState(() => _pendingNibble = nibble);
      return;
    }

    setState(() => _pendingNibble = null);
    controller.writeByte(active, (pending << 4) | nibble);
    controller.moveSelection(1);
    final next = controller.activeOffset;
    if (next != null) _scrollToOffset(next);
  }

  int? _nibbleFor(KeyEvent event) {
    final character = event.character;
    if (character != null && character.length == 1) {
      final code = character.codeUnitAt(0);
      if (code >= 0x30 && code <= 0x39) return code - 0x30;
      if (code >= 0x41 && code <= 0x46) return code - 0x41 + 10;
      if (code >= 0x61 && code <= 0x66) return code - 0x61 + 10;
    }
    return _nibbleForKey(event.logicalKey);
  }

  void _scrollToOffset(int offset) {
    if (!_gridScroll.hasClients) return;
    final row = offset ~/ _bytesPerRow;
    final rowHeight = widget.theme.monoLineHeight;
    final target = row * rowHeight;
    final position = _gridScroll.position;
    final viewport = position.viewportDimension;
    final current = position.pixels;

    double? destination;
    if (target < current) {
      destination = target;
    } else if (target + rowHeight > current + viewport) {
      destination = target + rowHeight - viewport;
    }
    if (destination == null) return;
    _gridScroll.jumpTo(destination.clamp(0.0, position.maxScrollExtent));
  }

  void _submitJump(String raw) {
    final controller = widget.controller;
    final trimmed = raw.trim();
    final cleaned = trimmed.toLowerCase().startsWith('0x')
        ? trimmed.substring(2)
        : trimmed;
    if (cleaned.isEmpty || !RegExp(r'^[0-9a-fA-F]{1,8}$').hasMatch(cleaned)) {
      setState(() => _jumpError = 'Use 1-8 hex digits (0-9, A-F).');
      return;
    }

    final address = int.tryParse(cleaned, radix: 16);
    final index = address == null ? null : address - controller.baseOffset;
    if (address == null ||
        index == null ||
        index < 0 ||
        index >= controller.length) {
      final first = _hex8(controller.baseOffset);
      final last = _hex8(controller.baseOffset + controller.length - 1);
      setState(() => _jumpError = 'Address must be within 0x$first-0x$last.');
      return;
    }

    setState(() => _jumpError = null);
    controller.selectByte(index);
    _scrollToOffset(index);
    _gridFocus.requestFocus();
  }

  void _toggleAsciiSearch(bool selected) {
    setState(() => _searchAscii = selected);
    if (_searchController.text.isNotEmpty) {
      _executeSearch(reset: true);
    }
  }

  void _executeSearch({bool reset = false}) {
    final query = _searchController.text;
    if (query.isEmpty) {
      setState(_clearSearchState);
      return;
    }

    final pattern = BytePattern.tryParse(query, ascii: _searchAscii);
    if (pattern == null) {
      setState(() {
        _clearSearchState();
        _searchError = _searchAscii
            ? 'Enter at least one ASCII character.'
            : 'Enter an even number of hex digits, e.g. DE AD BE EF.';
      });
      return;
    }

    final matches = pattern.findAll(widget.controller.bytes);
    final matchOffsets = <int>{};
    for (final match in matches) {
      for (var index = 0; index < pattern.length; index++) {
        matchOffsets.add(match + index);
      }
    }

    final index = matches.isEmpty
        ? -1
        : (reset || _matchIndex < 0 || _matchIndex >= matches.length
              ? 0
              : _matchIndex);
    final currentOffsets = index < 0
        ? const <int>{}
        : <int>{
            for (var offset = 0; offset < pattern.length; offset++)
              matches[index] + offset,
          };

    setState(() {
      _pattern = pattern;
      _matches = matches;
      _matchOffsets = matchOffsets;
      _currentMatchOffsets = currentOffsets;
      _matchIndex = index;
      _searchError = null;
    });

    if (index >= 0) _scrollToOffset(matches[index]);
  }

  void _clearSearch() {
    setState(_clearSearchState);
  }

  void _clearSearchState() {
    _pattern = null;
    _matches = const <int>[];
    _matchOffsets = const <int>{};
    _currentMatchOffsets = const <int>{};
    _matchIndex = -1;
    _searchError = null;
  }

  void _nextMatch() {
    if (_matches.isEmpty) return;
    setState(() {
      _matchIndex = (_matchIndex + 1) % _matches.length;
      _currentMatchOffsets = _offsetsForMatch(_matches[_matchIndex]);
    });
    _scrollToOffset(_matches[_matchIndex]);
  }

  void _previousMatch() {
    if (_matches.isEmpty) return;
    setState(() {
      _matchIndex = (_matchIndex - 1 + _matches.length) % _matches.length;
      _currentMatchOffsets = _offsetsForMatch(_matches[_matchIndex]);
    });
    _scrollToOffset(_matches[_matchIndex]);
  }

  Set<int> _offsetsForMatch(int start) {
    final length = _pattern?.length ?? 0;
    return <int>{
      for (var offset = 0; offset < length; offset++) start + offset,
    };
  }

  void _applySelectionHex() {
    final controller = widget.controller;
    final start = controller.selectionStart;
    final end = controller.selectionEnd;
    if (start == null || end == null) return;

    final raw = _selectionHexController.text.replaceAll(RegExp(r'[\s,]+'), '');
    final expectedDigits = (end - start) * 2;
    if (raw.isEmpty ||
        raw.length != expectedDigits ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(raw)) {
      setState(() {
        _selectionError =
            'Enter exactly ${end - start} bytes '
            '($expectedDigits hex digits).';
      });
      return;
    }

    for (var offset = start; offset < end; offset++) {
      if (!controller.isEditable(offset)) {
        setState(
          () => _selectionError =
              'Selection includes bytes outside the editable range.',
        );
        return;
      }
    }

    setState(() => _selectionError = null);
    for (var index = 0; index < end - start; index++) {
      final value = int.parse(
        raw.substring(index * 2, index * 2 + 2),
        radix: 16,
      );
      controller.writeByte(start + index, value);
    }
    _syncSelectionText(force: true);
  }

  int? get _bitSelectionLength {
    final length = widget.controller.selectionLength;
    return length == 1 || length == 2 || length == 4 || length == 8
        ? length
        : null;
  }
}

/// One byte cell in the hex grid.
///
/// Public so hosts (and tests) can count built cells, which is the simplest
/// proof that [HexEditor] is virtualised.
class HexByteCell extends StatelessWidget {
  const HexByteCell({
    super.key,
    required this.address,
    required this.value,
    required this.theme,
    required this.selected,
    required this.editable,
    required this.isSearchMatch,
    required this.isCurrentMatch,
    required this.mark,
    required this.modified,
    required this.onTap,
  });

  final int address;
  final int value;
  final HexEditorThemeData theme;
  final bool selected;
  final bool editable;
  final bool isSearchMatch;
  final bool isCurrentMatch;
  final ByteMarkKind? mark;
  final bool modified;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final markColor = mark == null ? null : theme.markColor(mark!);
    Color background = Colors.transparent;
    if (selected) {
      background = theme.selection;
    } else if (isCurrentMatch) {
      background = theme.brass.withValues(alpha: 0.48);
    } else if (isSearchMatch) {
      background = theme.brass.withValues(alpha: 0.22);
    } else if (markColor != null) {
      // The wash stays on the unlifted [HexEditorThemeData.danger]: at 28%
      // opacity over `canopyRaised` the lifted tone would lighten the cell to
      // #514136 and drop the glyph below 4.5:1.
      background = (mark == ByteMarkKind.invalid ? theme.danger : markColor)
          .withValues(alpha: 0.28);
    } else if (modified) {
      background = theme.brass.withValues(alpha: 0.14);
    }

    var foreground = editable ? theme.parchment : theme.stone;
    if (selected) {
      foreground = theme.ink;
    } else if (mark == ByteMarkKind.invalid) {
      foreground = theme.dangerLight;
    }

    final cell = Container(
      width: 32,
      height: theme.monoLineHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        _hex2(value),
        style: theme.monoStyle.copyWith(
          color: foreground,
          fontWeight: modified ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );

    Widget result = Semantics(
      button: true,
      selected: selected,
      label:
          'Address 0x${_hex8(address)}, value 0x${_hex2(value)}'
          '${editable ? '' : ', read-only'}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(cursor: SystemMouseCursors.click, child: cell),
      ),
    );

    if (!editable) {
      result = Tooltip(
        message: 'Read-only byte',
        excludeFromSemantics: true,
        waitDuration: const Duration(milliseconds: 500),
        child: result,
      );
    }
    return result;
  }
}

int? _nibbleForKey(LogicalKeyboardKey key) {
  final label = key.keyLabel.toLowerCase();
  if (label.length != 1) return null;
  final code = label.codeUnitAt(0);
  if (code >= 0x30 && code <= 0x39) return code - 0x30;
  if (code >= 0x61 && code <= 0x66) return code - 0x61 + 10;
  return null;
}

String _markName(ByteMarkKind kind) => switch (kind) {
  ByteMarkKind.modified => 'Modified',
  ByteMarkKind.invalid => 'Invalid',
  ByteMarkKind.unknown => 'Unknown',
  ByteMarkKind.verified => 'Verified',
};

String _hex2(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();

String _hex8(int value) =>
    value.toRadixString(16).padLeft(8, '0').toUpperCase();

String _hexBig(BigInt value, int byteCount) =>
    value.toRadixString(16).padLeft(byteCount * 2, '0').toUpperCase();

String _groupBits(String bits) {
  final buffer = StringBuffer();
  for (var index = 0; index < bits.length; index++) {
    if (index > 0 && index % 4 == 0) buffer.write(' ');
    buffer.write(bits[index]);
  }
  return buffer.toString();
}

String _asciiFor(List<int> bytes, int start, int end) {
  final buffer = StringBuffer();
  for (var offset = start; offset < end; offset++) {
    final value = bytes[offset];
    buffer.write(
      value >= 0x20 && value <= 0x7E ? String.fromCharCode(value) : '.',
    );
  }
  return buffer.toString();
}

BigInt _readBigEndian(List<int> data) {
  var value = BigInt.zero;
  for (final byte in data) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

BigInt _readLittleEndian(List<int> data) {
  var value = BigInt.zero;
  for (var index = data.length - 1; index >= 0; index--) {
    value = (value << 8) | BigInt.from(data[index]);
  }
  return value;
}
