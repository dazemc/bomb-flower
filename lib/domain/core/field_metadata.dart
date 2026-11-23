/// Half-open byte ranges and field metadata shared by layouts and edits.
library;

import 'dart:typed_data';

import 'identity.dart';

/// A half-open byte range `[offset, end)`.
///
/// A span is declarative metadata: layouts supply it, edits never infer it.
/// The constructor is `const` and therefore cannot reject invalid values;
/// consumers that index bytes must validate with [isValid] first and throw a
/// `RangeError` or `FieldWriteException` rather than clamping.
final class const ByteSpan(final int offset, final int length) {
  /// First byte after the span (exclusive).
  int get end => offset + length;

  /// Whether this span is well formed and non-negative.
  bool get isValid => offset >= 0 && length >= 0;

  /// Whether [other] is fully inside this span.
  bool contains(ByteSpan other) => other.offset >= offset && other.end <= end;

  /// Whether the two half-open spans share at least one byte.
  bool overlaps(ByteSpan other) => offset < other.end && other.offset < end;

  @override
  bool operator ==(Object other) =>
      other is ByteSpan && other.offset == offset && other.length == length;

  @override
  int get hashCode => Object.hash(offset, length);

  @override
  String toString() => 'ByteSpan(offset: $offset, length: $length)';
}

/// How a field's bytes are interpreted.
enum FieldKind {
  /// An unsigned integer of `span.length` bytes.
  integer,

  /// An unsigned integer interpreted through [FieldDescriptor.choices].
  enumeration,

  /// A boolean value, usually one byte.
  boolean,

  /// A packed set of flags; individual bits are edited with `SetBit`.
  bitfield,

  /// Text bytes; layout research defines the encoding.
  string,

  /// A fixed-length numeric tuple.
  vector,

  /// A semantic 3D position.
  position,

  /// A variable-length list; edited through `SetBytes`.
  list,
}

/// How strongly a field's meaning has been established by research.
enum FieldConfidence {
  /// Confirmed by at least one cited source and the bytes agree.
  verified,

  /// Plausible but not confirmed; never editable.
  inferred,

  /// Not established; never editable.
  unverified,
}

/// The confidence a layout has in an integrity scheme.
///
/// No checksum algorithm is part of this task. `IntegritySpec` is opaque and
/// can only be acted on by a pluggable recomputer supplied by a codec.
final class const IntegritySpec(
  final String schemeId,
  final ByteSpan region,
  final List<ByteSpan> coverage,
  final FieldConfidence confidence,
) {
  /// Whether research has confirmed this scheme.
  bool get isConfirmed => confidence == FieldConfidence.verified;

  /// Whether [changed] intersects any covered byte.
  bool coversChange(ByteSpan changed) =>
      coverage.any((span) => span.overlaps(changed));

  @override
  bool operator ==(Object other) =>
      other is IntegritySpec &&
      other.schemeId == schemeId &&
      other.region == region &&
      other.confidence == confidence &&
      _spanListsEqual(other.coverage, coverage);

  @override
  int get hashCode =>
      Object.hash(schemeId, region, confidence, Object.hashAll(coverage));
}

/// Metadata for one editable field.
///
/// [span] is absolute within the slot's file and owns exactly `span.length`
/// bytes. [source] is a mandatory citation and is shown to the user. Bounds
/// [min] and [max] are inclusive; a `null` bound is unknown and must not be
/// invented by the engine.
final class const FieldDescriptor(
  final FieldId id,
  final SaveSlotId slot,
  final String label,
  final FieldKind kind,
  final ByteSpan span,
  final FieldConfidence confidence,
  final String source, {
  final Endian endianness = Endian.big,
  final num? min,
  final num? max,
  final Map<String, int> choices = const <String, int>{},
  final bool readOnly = false,
}) {
  /// Whether the field may be edited.
  ///
  /// This is the single source of truth for UI enablement and engine checks.
  bool get isEditable => confidence == FieldConfidence.verified && !readOnly;

  /// Whether the field span and citation metadata are internally consistent.
  bool get isLayoutValid =>
      span.isValid &&
      span.length > 0 &&
      (isEditable ? source.isNotEmpty : true);

  @override
  bool operator ==(Object other) =>
      other is FieldDescriptor &&
      other.id == id &&
      other.slot == slot &&
      other.label == label &&
      other.kind == kind &&
      other.span == span &&
      other.confidence == confidence &&
      other.source == source &&
      other.endianness == endianness &&
      other.min == min &&
      other.max == max &&
      other.readOnly == readOnly &&
      _intMapsEqual(other.choices, choices);

  @override
  int get hashCode => Object.hash(
    id,
    slot,
    label,
    kind,
    span,
    confidence,
    source,
    endianness,
    min,
    max,
    readOnly,
    Object.hashAll(choices.entries.map((e) => Object.hash(e.key, e.value))),
  );

  @override
  String toString() => 'FieldDescriptor(${id.value} @ $span)';
}

bool _spanListsEqual(List<ByteSpan> a, List<ByteSpan> b) {
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

bool _intMapsEqual(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
