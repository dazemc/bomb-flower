import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import 'control_icon_button.dart';

/// Validated numeric text entry with explicit -/+ steppers.
///
/// The field never clamps: an out-of-range or malformed entry keeps the typed
/// text visible, shows an inline error, and leaves [onChanged] uncalled. Valid
/// values commit on Enter or when focus leaves the field, so a half-typed value
/// never reaches the save model. Steppers are honest too: stepping past a bound
/// shows the same inline error rather than silently stopping at the edge.
class NumericField extends StatefulWidget {
  const NumericField({
    super.key,
    required this.value,
    required this.onChanged,
    this.min,
    this.max,
    this.step = 1,
    this.label,
    this.unit,
    this.allowNegative = true,
    this.validator,
    this.autofocus = false,
  }) : assert(step > 0, 'step must be positive'),
       assert(
         min == null || max == null || min <= max,
         'min must not exceed max',
       );

  final num value;
  final ValueChanged<num>? onChanged;
  final num? min;
  final num? max;
  final num step;
  final String? label;
  final String? unit;
  final bool allowNegative;

  /// Receives the parsed candidate before commit. Return an error message or
  /// null. It is never called for a value that failed parsing or bounds.
  final String? Function(num? value)? validator;

  final bool autofocus;

  static const Key fieldKey = ValueKey<String>('numeric-field-input');
  static const Key decrementKey = ValueKey<String>('numeric-field-decrement');
  static const Key incrementKey = ValueKey<String>('numeric-field-increment');
  static const Key errorKey = ValueKey<String>('numeric-field-error');

  @override
  State<NumericField> createState() => _NumericFieldState();
}

class _NumericFieldState extends State<NumericField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _error;
  num? _lastCommitted;

  bool get _enabled => widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode(debugLabel: 'NumericField');
    _focusNode.addListener(_handleFocusChange);
    _error = _parse(_controller.text).error;
    _lastCommitted = widget.value;
  }

  @override
  void didUpdateWidget(NumericField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onChanged != null && widget.onChanged == null) {
      _focusNode.unfocus();
    }
    if (oldWidget.value != widget.value) {
      _lastCommitted = widget.value;
      final parsed = _parse(_controller.text);
      if (!_focusNode.hasFocus || parsed.value != widget.value) {
        final text = _format(widget.value);
        _controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        _error = _parse(text).error;
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
    if (result.error != _error) {
      setState(() => _error = result.error);
    }
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
    if (normalize) {
      final text = _format(parsed);
      if (text != _controller.text) {
        _controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
    if (_error != null) setState(() => _error = null);
    if (parsed != widget.value && parsed != _lastCommitted) {
      _lastCommitted = parsed;
      widget.onChanged!(parsed);
    }
  }

  void _step(int direction) {
    if (!_enabled) return;
    final parsed = _parse(_controller.text);
    final base = parsed.value ?? widget.value;
    final candidate = _clean(base + widget.step * direction);
    _setText(_format(candidate));
    final result = _parse(_controller.text);
    setState(() => _error = result.error);
    if (result.value != null &&
        result.value != widget.value &&
        result.value != _lastCommitted) {
      _lastCommitted = result.value;
      widget.onChanged!(result.value!);
    }
  }

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  _NumericParse _parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const _NumericParse.failure('Enter a number.');
    }
    final parsed = num.tryParse(text);
    if (parsed == null || !parsed.isFinite) {
      return const _NumericParse.failure('Enter a valid number.');
    }
    if (!widget.allowNegative && parsed < 0) {
      return const _NumericParse.failure('Negative values are not allowed.');
    }
    if (widget.min != null && parsed < widget.min!) {
      return _NumericParse.failure('Must be at least ${_format(widget.min!)}.');
    }
    if (widget.max != null && parsed > widget.max!) {
      return _NumericParse.failure('Must be at most ${_format(widget.max!)}.');
    }
    final custom = widget.validator?.call(parsed);
    if (custom != null && custom.trim().isNotEmpty) {
      return _NumericParse.failure(custom);
    }
    return _NumericParse.success(_clean(parsed));
  }

  num _clean(num value) {
    if (value is int) return value;
    final cleaned = double.parse(value.toStringAsFixed(6));
    if (cleaned == cleaned.roundToDouble()) return cleaned.toInt();
    return cleaned;
  }

  String _format(num value) {
    if (value is int) return value.toString();
    final cleaned = _clean(value);
    if (cleaned is int) return cleaned.toString();
    return cleaned.toString();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final labelColor = _enabled ? palette.textPrimary : palette.disabledText;
    final error = _error;
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: NumericField.fieldKey,
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: _enabled,
                  autofocus: widget.autofocus,
                  style: BombFlowerTypography.mono.copyWith(
                    color: _enabled
                        ? palette.textPrimary
                        : palette.disabledText,
                  ),
                  textAlignVertical: TextAlignVertical.center,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: true,
                    signed: widget.allowNegative,
                  ),
                  textInputAction: TextInputAction.done,
                  enableSuggestions: false,
                  autocorrect: false,
                  onChanged: _handleTextChanged,
                  onSubmitted: (_) => _commit(normalize: true),
                  onTapOutside: (_) => _focusNode.unfocus(),
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: widget.unit,
                    suffixStyle: BombFlowerTypography.body.copyWith(
                      color: palette.textMuted,
                    ),
                    hintText: '0',
                    hintStyle: BombFlowerTypography.mono.copyWith(
                      color: palette.textMuted,
                    ),
                    enabledBorder: fieldBorder,
                    focusedBorder: fieldBorder,
                    disabledBorder: _border(BombFlowerColors.stone),
                  ),
                ),
              ),
              const SizedBox(width: BombFlowerSpacing.xs),
              ControlIconButton(
                key: NumericField.decrementKey,
                icon: Icons.remove,
                semanticLabel: 'Decrease ${widget.label ?? 'value'}',
                tooltip: widget.unit == null
                    ? 'Decrease by ${_format(widget.step)}'
                    : 'Decrease by ${_format(widget.step)} ${widget.unit}',
                onPressed: _enabled ? () => _step(-1) : null,
              ),
              const SizedBox(width: BombFlowerSpacing.xs),
              ControlIconButton(
                key: NumericField.incrementKey,
                icon: Icons.add,
                semanticLabel: 'Increase ${widget.label ?? 'value'}',
                tooltip: widget.unit == null
                    ? 'Increase by ${_format(widget.step)}'
                    : 'Increase by ${_format(widget.step)} ${widget.unit}',
                onPressed: _enabled ? () => _step(1) : null,
              ),
            ],
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.xs),
            Row(
              key: NumericField.errorKey,
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

class _NumericParse {
  const _NumericParse.success(this.value) : error = null;
  const _NumericParse.failure(this.error) : value = null;

  final num? value;
  final String? error;
}
