/// Point-in-time view of one slot's bytes.
library;

import 'dart:typed_data';

import 'byte_region.dart';
import 'field_metadata.dart';
import 'identity.dart';

/// A snapshot is a pointer to an immutable [ByteRegion] plus a revision.
///
/// Equality is deliberately state identity — slot, revision, and the same
/// region instance — not a byte comparison. Byte equality is explicit
/// ([ByteRegion.sameBytesAs] or `materialize`) so a 120 KB buffer never
/// participates in an implicit UI equality check.
final class const SaveSnapshot(
  final SaveSlotId slot,
  final int revision,
  final ByteRegion content,
) {
  /// Number of bytes in the slot.
  int get length => content.length;

  /// Content fingerprint hint; not integrity proof.
  int get fingerprint => content.fingerprint;

  /// A fresh buffer containing this snapshot's bytes.
  Uint8List materialize() => content.materialize();

  /// A snapshot of the same slot with [span] replaced and a new revision.
  ///
  /// The content region is rebuilt copy-on-write; the previous snapshot stays
  /// valid for history.
  SaveSnapshot replace(ByteSpan span, List<int> bytes) =>
      SaveSnapshot(slot, revision + 1, content.replace(span, bytes));

  @override
  bool operator ==(Object other) =>
      other is SaveSnapshot &&
      other.slot == slot &&
      other.revision == revision &&
      identical(other.content, content);

  @override
  int get hashCode => Object.hash(slot, revision, identityHashCode(content));

  @override
  String toString() => 'SaveSnapshot(${slot.value}, revision: $revision)';
}
