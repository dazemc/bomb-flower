/// Decoded field values and the immutable field view used by a document.
library;

import 'field_metadata.dart';

/// A decoded field value.
///
/// Values are only produced by a codec; the engine itself never invents field
/// semantics. Every variant is immutable and compares by value.
sealed class FieldValue {
  const FieldValue();
}

/// An unsigned integer.
final class const IntValue(final int value) extends FieldValue {
  @override
  bool operator ==(Object other) => other is IntValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'IntValue($value)';
}

/// An enumeration key and, when known, its raw wire value.
///
/// [key] may be empty when the raw value is not in the layout's choices map;
/// [rawValue] still carries what the bytes say so the UI can show it.
final class const EnumValue({required final String key, final int? rawValue})
    extends FieldValue {
  @override
  bool operator ==(Object other) =>
      other is EnumValue && other.key == key && other.rawValue == rawValue;

  @override
  int get hashCode => Object.hash(key, rawValue);

  @override
  String toString() => 'EnumValue($key, raw: $rawValue)';
}

/// A boolean.
final class const BoolValue(final bool value) extends FieldValue {
  @override
  bool operator ==(Object other) => other is BoolValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'BoolValue($value)';
}

/// A packed integer of flag bits.
final class const BitfieldValue(final int bits) extends FieldValue {
  @override
  bool operator ==(Object other) =>
      other is BitfieldValue && other.bits == bits;

  @override
  int get hashCode => bits.hashCode;

  @override
  String toString() => 'BitfieldValue(0x${bits.toRadixString(16)})';
}

/// Text decoded by a layout-specific codec.
final class const StringValue(final String value) extends FieldValue {
  @override
  bool operator ==(Object other) =>
      other is StringValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'StringValue(${value.length} code units)';
}

/// A semantic 3D position.
final class const PositionValue({
  required final double x,
  required final double y,
  required final double z,
}) extends FieldValue {
  @override
  bool operator ==(Object other) =>
      other is PositionValue && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'PositionValue($x, $y, $z)';
}

/// A fixed-length numeric tuple.
final class VectorValue extends FieldValue {
  /// Copies [components] into an unmodifiable list.
  VectorValue(List<double> components)
    : components = List<double>.unmodifiable(components);

  /// The tuple components.
  final List<double> components;

  @override
  bool operator ==(Object other) =>
      other is VectorValue && _doubleListsEqual(other.components, components);

  @override
  int get hashCode => Object.hashAll(components);

  @override
  String toString() => 'VectorValue($components)';
}

/// A variable-length list of values.
final class ListValue extends FieldValue {
  /// Copies [items] into an unmodifiable list.
  ListValue(List<FieldValue> items)
    : items = List<FieldValue>.unmodifiable(items);

  /// The list items.
  final List<FieldValue> items;

  @override
  bool operator ==(Object other) =>
      other is ListValue && _valueListsEqual(other.items, items);

  @override
  int get hashCode => Object.hashAll(items);

  @override
  String toString() => 'ListValue(${items.length} items)';
}

/// One field's current and original values plus byte-derived dirty flag.
///
/// [isDirty] is computed by the engine from bytes, never from value equality,
/// so float/NaN and unknown-raw-value quirks cannot mislabel a field.
final class const SaveField<T extends FieldValue>(
  final FieldDescriptor descriptor,
  final T value,
  final T originalValue, {
  required final bool isDirty,
}) {
  /// Whether the field is editable according to its descriptor.
  bool get isEditable => descriptor.isEditable;

  @override
  bool operator ==(Object other) =>
      other is SaveField<T> &&
      other.descriptor == descriptor &&
      other.value == value &&
      other.originalValue == originalValue &&
      other.isDirty == isDirty;

  @override
  int get hashCode => Object.hash(descriptor, value, originalValue, isDirty);

  @override
  String toString() => 'SaveField(${descriptor.id.value}, dirty: $isDirty)';
}

bool _doubleListsEqual(List<double> a, List<double> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _valueListsEqual(List<FieldValue> a, List<FieldValue> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
