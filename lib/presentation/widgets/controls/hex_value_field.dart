import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';

/// Hexadecimal text entry with width, range, and character validation.
///
/// Accepts `0x1F`, `0X1F`, and bare `1F`. While the text is valid the decimal
/// equivalent is printed beneath the field. Invalid text is never clamped or
/// rewritten: it stays visible with an inline error and [onChanged] is not
/// called. Valid values commit on Enter or blur and are then normalised to the
/// canonical zero-padded `0x` form.
class HexValueField extends StatefulWidget {
  const HexValueField({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 4,
    this.label,
    this.maxValue,
    this.autofocus = false,
  }) : assert(width > 0 && width <= 15, 'width must be between 1 and 15'),
       assert(maxValue == null || maxValue >= 0, 'maxValue must be >= 0');

  final int value;
  final ValueChanged<int>? onChanged;

  /// Maximum number of hex digits accepted (4 for a 16-bit field).
  final int width;

  final String? label;

  /// Optional tighter upper bound. The width mask is always enforced too.
  final int? maxValue;

  final bool autofocus;

  static const Key fieldKey = ValueKey<String>('hex-value-field-input');
  static const Key errorKey = ValueKey<String>('hex-value-field-error');
  static const Key decimalKey = ValueKey<String>('hex-value-field-decimal');

  @override
  State<HexValueField> createState() => _HexValueFieldState();
}

class _HexValueFieldState extends State<HexValueField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _error;
  int? _lastCommitted;

  bool get _enabled => widget.onChanged != null;

  int get _mask => (1 << (widget.width * 4)) - 1;

  int get _effectiveMax {
    final maxValue = widget.maxValue;
    if (maxValue == null) return _mask;
    return maxValue < _mask ? maxValue : _mask;
  }

  String get _canonical => _formatValue(widget.value);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _canonical);
    _focusNode = FocusNode(debugLabel: 'HexValueField');
    _focusNode.addListener(_handleFocusChange);
    _error = _parse(_controller.text).error;
    _lastCommitted = widget.value;
  }

  @override
  void didUpdateWidget(HexValueField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onChanged != null && widget.onChanged == null) {
      _focusNode.unfocus();
    }
    if (oldWidget.value != widget.value) {
      _lastCommitted = widget.value;
      final parsed = _parse(_controller.text);
      if (!_focusNode.hasFocus || parsed.value != widget.value) {
        _setText(_canonical);
        _error = _parse(_controller.text).error;
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus && mounted) {
      _commit(normalize: true);
    }
  }

  void _handleTextChanged(String _) {
    final result = _parse(_controller.text);
    setState(() => _error = result.error);
  }

  void _commit({bool normalize = false}) {
    if (!_enabled) return;
    final result = _parse(_controller.text);
    if (result.error != null) {
      if (result.error != _error) {
        setState(() => _error = result.error);
      }
      return;
    }
    final parsed = result.value!;
    if (normalize) _setText(_formatValue(parsed));
    if (_error != null) {
      setState(() => _error = null);
    } else {
      setState(() {});
    }
    if (parsed != widget.value && parsed != _lastCommitted) {
      _lastCommitted = parsed;
      widget.onChanged!(parsed);
    }
  }

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  String _formatValue(int value) {
    final digits = value
        .toRadixString(16)
        .toUpperCase()
        .padLeft(widget.width, '0');
    return '0x$digits';
  }

  String _groupDecimal(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  _HexParse _parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const _HexParse.failure('Enter a hexadecimal value.');
    }
    var body = text;
    if (body.length >= 2 && body.substring(0, 2).toLowerCase() == '0x') {
      body = body.substring(2);
    }
    if (body.isEmpty) {
      return const _HexParse.failure('Enter hex digits after 0x.');
    }
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(body)) {
      return const _HexParse.failure('Use only hex digits 0-9 and A-F.');
    }
    if (body.length > widget.width) {
      return _HexParse.failure(
        'Use at most ${widget.width} hex '
        '${widget.width == 1 ? 'digit' : 'digits'} '
        '(${widget.width * 4} bits).',
      );
    }
    final parsed = int.parse(body, radix: 16);
    if (parsed > _effectiveMax) {
      return _HexParse.failure(
        'Must be at most ${_groupDecimal(_effectiveMax)} '
        '(${_formatValue(_effectiveMax)}).',
      );
    }
    return _HexParse.success(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final labelColor = _enabled ? palette.textPrimary : palette.disabledText;
    final error = _error;
    final parsed = _parse(_controller.text);
    final valid = parsed.value;
    final fieldBorder = error != null
        ? _border(BombFlowerColors.danger, 2)
        : null;

    return Semantics(
      container: true,
      label: widget.label,
      hint: error,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.label != null) ...<Widget>[
            Text(
              widget.label!,
              style: BombFlowerTypography.label.copyWith(color: labelColor),
            ),
            const SizedBox(height: BombFlowerSpacing.xs),
          ],
          TextField(
            key: HexValueField.fieldKey,
            controller: _controller,
            focusNode: _focusNode,
            enabled: _enabled,
            autofocus: widget.autofocus,
            style: BombFlowerTypography.mono.copyWith(
              color: _enabled ? palette.textPrimary : palette.disabledText,
              letterSpacing: 0.8,
            ),
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            enableSuggestions: false,
            autocorrect: false,
            onChanged: _handleTextChanged,
            onSubmitted: (_) => _commit(normalize: true),
            onTapOutside: (_) => _focusNode.unfocus(),
            decoration: InputDecoration(
              isDense: true,
              hintText: '0x${'0' * widget.width}',
              hintStyle: BombFlowerTypography.mono.copyWith(
                color: palette.textMuted,
              ),
              enabledBorder: fieldBorder,
              focusedBorder: fieldBorder,
              disabledBorder: _border(BombFlowerColors.stone),
            ),
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.xs),
            Row(
              key: HexValueField.errorKey,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.error_outline,
                    size: 14,
                    color: BombFlowerColors.danger,
                  ),
                ),
                const SizedBox(width: BombFlowerSpacing.xs),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    label: error,
                    excludeSemantics: true,
                    child: Text(
                      error,
                      style: BombFlowerTypography.caption.copyWith(
                        color: palette.danger,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (valid != null) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.xs),
            Row(
              key: HexValueField.decimalKey,
              children: <Widget>[
                Icon(Icons.tag, size: 13, color: palette.textMuted),
                const SizedBox(width: BombFlowerSpacing.xs),
                Flexible(
                  child: Text(
                    'Decimal ${_groupDecimal(valid)}',
                    style: BombFlowerTypography.caption.copyWith(
                      color: palette.textMuted,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  OutlineInputBorder _border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

class _HexParse {
  const _HexParse.success(this.value) : error = null;
  const _HexParse.failure(this.error) : value = null;

  final int? value;
  final String? error;
}
