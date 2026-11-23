/// The open document view and the immutable project aggregate.
library;

import 'byte_region.dart';
import 'dirty_state.dart';
import 'edit_history.dart';
import 'edit_log.dart';
import 'field_metadata.dart';
import 'field_value.dart';
import 'identity.dart';
import 'layout.dart';
import 'save_snapshot.dart';

/// One slot's current snapshot plus its decoded field view.
final class const SaveDocument(
  final SaveSlotId slot,
  final SaveSlotLayout layout,
  final SaveSnapshot snapshot,
  final List<SaveField<FieldValue>> fields,
) {
  /// The field view for [id], if the codec exposed it.
  SaveField<FieldValue>? field(FieldId id) {
    for (final field in fields) {
      if (field.descriptor.id == id) {
        return field;
      }
    }
    return null;
  }
}

/// An open save project.
///
/// The byte state is immutable; [history] and [editLog] are explicit mutable
/// collaborators because undo/redo and the audit trail are session state, as
/// specified by the engine contract. Domain operations return a new project
/// rather than mutating documents or originals in place.
final class const SaveProject(
  final String projectId,
  final String rootPath,
  final String backupPath,
  final LayoutDescriptor layout,
  final int detectedVersion,
  final Map<SaveSlotId, SaveSnapshot> originals,
  final Map<SaveSlotId, SaveDocument> documents,
  final Map<SaveSlotId, int> savedFingerprints,
  final EditHistory history,
  final EditLog editLog, {
  final Map<SaveSlotId, SaveSnapshot> savedSnapshots =
      const <SaveSlotId, SaveSnapshot>{},
  final bool preserveUnknown = true,
}) {
  /// The current document for [slot], if open.
  SaveDocument? document(SaveSlotId slot) => documents[slot];

  /// The layout metadata for [slot], if present.
  SaveSlotLayout? slotLayout(SaveSlotId slot) => layout.slot(slot);

  /// Whether this project is allowed to export at all.
  ///
  /// A diagnostic open with `preserveUnknown: false` cannot reproduce untouched
  /// bytes and is therefore never exportable.
  bool get isExportable => preserveUnknown;

  /// The two dirty badges plus changed-field and changed-byte summaries.
  DirtyState get dirty {
    var unsaved = false;
    var differs = false;
    var byteCount = 0;
    final dirtySlots = <SaveSlotId>{};
    final changedFields = <FieldId>{};

    for (final entry in documents.entries) {
      final slot = entry.key;
      final document = entry.value;
      final current = document.snapshot;

      final savedSnapshot = savedSnapshots[slot];
      final savedFingerprint = savedFingerprints[slot];
      final savedDiffers = savedSnapshot != null
          ? !_sameSnapshotBytes(current, savedSnapshot)
          : savedFingerprint == null || savedFingerprint != current.fingerprint;
      if (savedDiffers) {
        unsaved = true;
        dirtySlots.add(slot);
      }

      final original = originals[slot];
      final originalDiffers =
          original == null || !_sameSnapshotBytes(current, original);
      if (originalDiffers) {
        differs = true;
      }

      final spans = changedSpans(slot);
      byteCount += spans.fold(0, (total, span) => total + span.length);

      final slotLayout = layout.slot(slot);
      if (slotLayout != null && original != null) {
        for (final descriptor in slotLayout.fields) {
          if (_spanDiffers(
            current.content,
            original.content,
            descriptor.span,
          )) {
            changedFields.add(descriptor.id);
          }
        }
      } else {
        for (final field in document.fields) {
          if (field.isDirty) {
            changedFields.add(field.descriptor.id);
          }
        }
      }
    }

    return DirtyState(
      unsaved,
      differs,
      changedFields.length,
      byteCount,
      dirtySlots,
      changedFields: changedFields,
    );
  }

  /// Coalesced current-vs-original changed byte runs for [slot].
  List<ByteSpan> changedSpans(SaveSlotId slot) {
    final document = documents[slot];
    final original = originals[slot];
    if (document == null || original == null) {
      return const <ByteSpan>[];
    }
    final currentBytes = document.snapshot.materialize();
    final originalBytes = original.materialize();
    if (currentBytes.length != originalBytes.length) {
      final length = currentBytes.length > originalBytes.length
          ? currentBytes.length
          : originalBytes.length;
      return <ByteSpan>[ByteSpan(0, length)];
    }

    final spans = <ByteSpan>[];
    int? runStart;
    for (var i = 0; i < currentBytes.length; i++) {
      final differs = currentBytes[i] != originalBytes[i];
      if (differs) {
        runStart ??= i;
      } else if (runStart != null) {
        spans.add(ByteSpan(runStart, i - runStart));
        runStart = null;
      }
    }
    if (runStart != null) {
      spans.add(ByteSpan(runStart, currentBytes.length - runStart));
    }
    return spans;
  }

  @override
  String toString() =>
      'SaveProject($projectId, ${documents.length} document(s), '
      '${dirty.hasUnsavedChanges ? 'dirty' : 'clean'})';
}

bool _sameSnapshotBytes(SaveSnapshot a, SaveSnapshot b) {
  if (identical(a.content, b.content)) {
    return true;
  }
  if (a.fingerprint != b.fingerprint) {
    return false;
  }
  // Fingerprint equality is only a hint; compare bytes before declaring clean.
  return a.content.sameBytesAs(b.content);
}

bool _spanDiffers(ByteRegion current, ByteRegion original, ByteSpan span) {
  if (!span.isValid ||
      span.end > current.length ||
      span.end > original.length) {
    return true;
  }
  for (var i = span.offset; i < span.end; i++) {
    if (current.readByte(i) != original.readByte(i)) {
      return true;
    }
  }
  return false;
}
