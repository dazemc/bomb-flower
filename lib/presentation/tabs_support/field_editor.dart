import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../domain/core/edit_command.dart';
import '../../domain/core/field_metadata.dart';
import '../../domain/core/field_value.dart';
import '../../domain/formatting/scalars.dart';
import '../theme/bomb_flower_spacing.dart';
import '../theme/bomb_flower_theme.dart';
import '../theme/bomb_flower_typography.dart';
import '../widgets/common/field_row.dart';
import '../widgets/common/rune_chip.dart';
import '../widgets/controls/brass_toggle.dart';
import '../widgets/controls/numeric_field.dart';
import '../widgets/data/provenance_badge.dart';
import '../widgets/selectors/searchable_select.dart';
import 'save_tab_source.dart';

/// Renders one [TabFieldView] and turns committed input into an [EditCommand].
///
/// The editor never invents or clamps a value. A control only calls
/// [SaveTabSource.edit] when the user's input is fully valid; read-only,
/// inferred, unverified, opaque, and undecoded fields render disabled text and
/// emit nothing.
class FieldEditor extends StatelessWidget {
  const FieldEditor({super.key, required this.view, required this.source});

  /// Field to render.
  final TabFieldView view;

  /// Port that receives the committed edit.
  final SaveTabSource source;

  /// Text entry key for string fields.
  static const Key stringFieldKey = ValueKey<String>('field-editor-string');

  /// Disabled value key for fields with no editable control.
  static const Key disabledValueKey = ValueKey<String>('field-editor-disabled');

  /// Numeric entry keys for the three vector/position components.
  static const List<Key> vectorComponentKeys = <Key>[
    ValueKey<String>('field-editor-vector-0'),
    ValueKey<String>('field-editor-vector-1'),
    ValueKey<String>('field-editor-vector-2'),
  ];

  @override
  Widget build(BuildContext context) {
    final descriptor = view.descriptor;
    final reason = _disabledReason(view);
    final helper = reason ?? _enumUnknownNote(view);
    final body = reason == null
        ? _buildControl()
        : _DisabledFieldValue(value: view.value);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FieldRow(
          label: fieldDisplayLabel(view),
          isReadOnly: descriptor.readOnly,
          helper: helper,
          error: view.issueMessage,
          semanticValue: reason == null ? null : formatFieldValue(view.value),
          child: body,
        ),
        const SizedBox(height: BombFlowerSpacing.xs),
        Wrap(
          spacing: BombFlowerSpacing.sm,
          runSpacing: BombFlowerSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            ProvenanceBadge(
              level: _provenanceLevel(descriptor.confidence),
              source: descriptor.source,
            ),
            if (view.isDirty)
              const RuneChip(
                variant: RuneChipVariant.modified,
                label: 'Modified',
                compact: true,
              ),
            if (view.issueMessage != null)
              const RuneChip(
                variant: RuneChipVariant.invalid,
                label: 'Invalid',
                compact: true,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildControl() {
    final descriptor = view.descriptor;
    final value = view.value;

    return switch (descriptor.kind) {
      FieldKind.integer => NumericField(
        value: (value! as IntValue).value,
        min: descriptor.min,
        max: descriptor.max,
        allowNegative: (descriptor.min ?? 0) < 0,
        validator: _wholeNumberError,
        onChanged: (num next) {
          source.edit(SetScalar(descriptor.id, next.toInt()));
        },
      ),
      FieldKind.boolean => BrassToggle(
        value: (value! as BoolValue).value,
        onChanged: (bool next) {
          source.edit(SetScalar(descriptor.id, next ? 1 : 0));
        },
      ),
      FieldKind.enumeration => SearchableSelect<String>(
        items: descriptor.choices.keys.toList(growable: false),
        itemLabel: (String key) => key,
        value: _selectedEnumKey(value! as EnumValue),
        onChanged: (String key) {
          source.edit(SetEnum(descriptor.id, key));
        },
      ),
      FieldKind.string => _StringFieldEditor(view: view, source: source),
      FieldKind.vector ||
      FieldKind.position => _VectorFieldEditor(view: view, source: source),
      // `_disabledReason` never lets these kinds reach a control.
      FieldKind.bitfield || FieldKind.list => const SizedBox.shrink(),
    };
  }
}

/// Human text for a decoded field value, or the honest absence of one.
String formatFieldValue(FieldValue? value) {
  return switch (value) {
    null => 'No decoded value',
    IntValue(:final value) => value.toString(),
    EnumValue(:final key, :final rawValue) => _formatEnumValue(key, rawValue),
    BoolValue(:final value) => value ? 'On' : 'Off',
    BitfieldValue(:final bits) => '0x${bits.toRadixString(16)}',
    StringValue(:final value) => value,
    PositionValue(:final x, :final y, :final z) => formatVector3(x, y, z),
    VectorValue(:final components) => _formatVector(components),
    ListValue(:final items) => _formatList(items),
  };
}

/// Label the field row shows for [view].
String fieldDisplayLabel(TabFieldView view) => view.descriptor.label;

String _formatEnumValue(String key, int? rawValue) {
  if (key.isNotEmpty) {
    return key;
  }
  return rawValue == null ? 'Unknown value' : 'Unknown value $rawValue';
}

String _formatVector(List<double> components) {
  final text = components
      .map((double component) => formatFloat32(component))
      .join(', ');
  return '($text)';
}

String _formatList(List<FieldValue> items) {
  if (items.isEmpty) {
    return '[]';
  }
  return '[${items.map(formatFieldValue).join(', ')}]';
}

String? _wholeNumberError(num? value) {
  if (value == null) {
    return 'Enter a whole number.';
  }
  if (value is! int && value != value.roundToDouble()) {
    return 'Enter a whole number.';
  }
  return null;
}

String? _selectedEnumKey(EnumValue value) {
  return value.key.isEmpty ? null : value.key;
}

ProvenanceLevel _provenanceLevel(FieldConfidence confidence) {
  return switch (confidence) {
    FieldConfidence.verified => ProvenanceLevel.verified,
    FieldConfidence.inferred => ProvenanceLevel.inferred,
    FieldConfidence.unverified => ProvenanceLevel.unknown,
  };
}

String? _disabledReason(TabFieldView view) {
  final descriptor = view.descriptor;
  if (descriptor.readOnly) {
    return 'Read-only field';
  }
  if (descriptor.confidence != FieldConfidence.verified) {
    return '${descriptor.confidence.name} fields cannot be edited';
  }
  final value = view.value;
  if (value == null) {
    return 'No decoded value';
  }

  return switch (descriptor.kind) {
    FieldKind.integer => _scalarShapeReason(
      descriptor,
      value is IntValue,
      'integer',
    ),
    FieldKind.boolean => _scalarShapeReason(
      descriptor,
      value is BoolValue,
      'boolean',
    ),
    FieldKind.enumeration => _enumShapeReason(descriptor, value),
    FieldKind.string =>
      descriptor.span.length < 2
          ? 'String fields need a NUL terminator byte'
          : value is StringValue
          ? null
          : 'Value does not match the string field kind',
    FieldKind.vector ||
    FieldKind.position => _vectorShapeReason(descriptor, value),
    FieldKind.bitfield => 'Bitfield fields have no dedicated editor',
    FieldKind.list => 'List fields have no dedicated editor',
  };
}

String? _scalarShapeReason(
  FieldDescriptor descriptor,
  bool matchesKind,
  String kindName,
) {
  if (descriptor.span.length == 0 || descriptor.span.length > 8) {
    return 'A $kindName scalar needs 1 to 8 bytes';
  }
  if (!matchesKind) {
    return 'Value does not match the $kindName field kind';
  }
  return null;
}

String? _enumShapeReason(FieldDescriptor descriptor, FieldValue value) {
  if (descriptor.span.length == 0 || descriptor.span.length > 8) {
    return 'An enumeration scalar needs 1 to 8 bytes';
  }
  if (value is! EnumValue) {
    return 'Value does not match the enumeration field kind';
  }
  if (descriptor.choices.isEmpty) {
    return 'No enumeration choices are available';
  }
  return null;
}

String? _vectorShapeReason(FieldDescriptor descriptor, FieldValue value) {
  if (descriptor.span.length != 12) {
    return 'Vector and position fields need a 12-byte span';
  }
  if (value is PositionValue) {
    return null;
  }
  if (value is! VectorValue) {
    return 'Value does not match the vector field kind';
  }
  if (value.components.length != 3) {
    return 'Only three-component vectors can be edited';
  }
  return null;
}

String? _enumUnknownNote(TabFieldView view) {
  final descriptor = view.descriptor;
  final value = view.value;
  if (descriptor.kind != FieldKind.enumeration ||
      value is! EnumValue ||
      descriptor.choices.containsKey(value.key)) {
    return null;
  }
  final raw = value.rawValue;
  return raw == null ? 'Unknown value' : 'Unknown value $raw';
}

class _DisabledFieldValue extends StatelessWidget {
  const _DisabledFieldValue({required this.value});

  final FieldValue? value;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;

    return Container(
      key: FieldEditor.disabledValueKey,
      constraints: const BoxConstraints(
        minHeight: BombFlowerSpacing.fieldHeight,
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(
        horizontal: BombFlowerSpacing.lg,
        vertical: BombFlowerSpacing.md,
      ),
      decoration: BoxDecoration(
        color: palette.disabledSurface,
        borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        formatFieldValue(value),
        style: BombFlowerTypography.body.copyWith(color: palette.disabledText),
      ),
    );
  }
}

class _StringFieldEditor extends StatefulWidget {
  const _StringFieldEditor({required this.view, required this.source});

  final TabFieldView view;
  final SaveTabSource source;

  @override
  State<_StringFieldEditor> createState() => _StringFieldEditorState();
}

class _StringFieldEditorState extends State<_StringFieldEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _error;
  late String _lastCommitted;

  @override
  void initState() {
    super.initState();
    final text = (widget.view.value! as StringValue).value;
    _lastCommitted = text;
    _controller = TextEditingController(text: text);
    _focusNode = FocusNode(debugLabel: 'FieldEditor.string');
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(_StringFieldEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.view.value;
    if (oldWidget.view.value != next && next is StringValue) {
      _lastCommitted = next.value;
      if (!_focusNode.hasFocus) {
        _controller.value = TextEditingValue(
          text: next.value,
          selection: TextSelection.collapsed(offset: next.value.length),
        );
        _error = null;
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
      _commit();
    }
  }

  void _commit() {
    final descriptor = widget.view.descriptor;
    final text = _controller.text;
    final cap = descriptor.span.length - 1;
    final String? error;
    if (text.length > cap) {
      error = 'Text must be at most $cap characters.';
    } else if (text.codeUnits.any((int unit) => unit < 0x20 || unit > 0x7e)) {
      error = 'Use printable ASCII characters only.';
    } else {
      error = null;
    }

    if (error != null) {
      if (error != _error) {
        setState(() => _error = error);
      }
      return;
    }

    if (_error != null) {
      setState(() => _error = null);
    }
    if (text == _lastCommitted) {
      return;
    }

    final bytes = Uint8List(descriptor.span.length);
    for (var index = 0; index < text.length; index++) {
      bytes[index] = text.codeUnitAt(index);
    }
    _lastCommitted = text;
    widget.source.edit(
      SetBytes(descriptor.id, target: descriptor.span, bytes: bytes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          key: FieldEditor.stringFieldKey,
          controller: _controller,
          focusNode: _focusNode,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          style: BombFlowerTypography.mono.copyWith(color: palette.textPrimary),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _focusNode.unfocus(),
          decoration: const InputDecoration(isDense: true),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: BombFlowerSpacing.xs),
          Text(
            _error!,
            style: BombFlowerTypography.caption.copyWith(color: palette.danger),
          ),
        ],
      ],
    );
  }
}

class _VectorFieldEditor extends StatefulWidget {
  const _VectorFieldEditor({required this.view, required this.source});

  final TabFieldView view;
  final SaveTabSource source;

  @override
  State<_VectorFieldEditor> createState() => _VectorFieldEditorState();
}

class _VectorFieldEditorState extends State<_VectorFieldEditor> {
  late double _x;
  late double _y;
  late double _z;

  @override
  void initState() {
    super.initState();
    _readComponents();
  }

  @override
  void didUpdateWidget(_VectorFieldEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.value != widget.view.value) {
      _readComponents();
    }
  }

  void _readComponents() {
    final value = widget.view.value;
    if (value is PositionValue) {
      _x = value.x;
      _y = value.y;
      _z = value.z;
    } else if (value is VectorValue && value.components.length == 3) {
      _x = value.components[0];
      _y = value.components[1];
      _z = value.components[2];
    }
  }

  void _commit() {
    final descriptor = widget.view.descriptor;
    if (descriptor.span.length != 12) {
      return;
    }
    final data = ByteData(12)
      ..setFloat32(0, _x, Endian.little)
      ..setFloat32(4, _y, Endian.little)
      ..setFloat32(8, _z, Endian.little);
    widget.source.edit(
      SetBytes(
        descriptor.id,
        target: descriptor.span,
        bytes: data.buffer.asUint8List(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NumericField(
          key: FieldEditor.vectorComponentKeys[0],
          value: _x,
          onChanged: (num next) {
            setState(() => _x = next.toDouble());
            _commit();
          },
        ),
        const SizedBox(height: BombFlowerSpacing.xs),
        NumericField(
          key: FieldEditor.vectorComponentKeys[1],
          value: _y,
          onChanged: (num next) {
            setState(() => _y = next.toDouble());
            _commit();
          },
        ),
        const SizedBox(height: BombFlowerSpacing.xs),
        NumericField(
          key: FieldEditor.vectorComponentKeys[2],
          value: _z,
          onChanged: (num next) {
            setState(() => _z = next.toDouble());
            _commit();
          },
        ),
      ],
    );
  }
}
