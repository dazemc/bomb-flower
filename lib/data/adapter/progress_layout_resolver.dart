/// Detection and repository wiring for the Switch 2 remake's save folder.
library;

import 'dart:io';
import 'dart:typed_data';

import '../../domain/core/identity.dart';
import '../../domain/core/layout.dart';
import '../../domain/engine/ports.dart';
import '../../domain/save/models/caption_save.dart';
import '../../domain/save/progress_layout.dart';
import '../codec/caption_codec.dart';
import '../codec/progress_codec.dart';
import 'progress_layout_builder.dart';

/// Builds a caption slot layout for [caption] without going through
/// [ProgressLayoutBuilder].
///
/// Tests and callers that supply their own caption layout can pass one to
/// [ProgressLayoutResolver] instead of relying on the builder.
typedef CaptionSlotLayoutBuilder = SaveSlotLayout Function(
  CaptionSave caption, {
  SaveSlotId? progressSlot,
});

/// What detection found at a root, including the reason it found nothing.
sealed class SaveDetection {
  /// Creates a detection result.
  const SaveDetection();
}

/// The root (or every `slot_NN` under it) is not a progress save.
final class SaveNotASave extends SaveDetection {
  /// Records [path] as not being a save, with the [magic] that was read.
  const SaveNotASave(this.path, {this.magic = 0, this.reason});

  /// The path that was inspected.
  final String path;

  /// The first four bytes read as a little-endian integer, when readable.
  final int magic;

  /// Why the path is not a save, when known.
  final String? reason;

  @override
  String toString() =>
      'SaveNotASave($path, magic: 0x${magic.toRadixString(16)}, '
      'reason: $reason)';
}

/// A save whose revision this resolver does not support.
final class SaveUnsupportedRevision extends SaveDetection {
  /// Records [path] and its [detected] revision.
  const SaveUnsupportedRevision(this.path, this.detected);

  /// The path that was inspected.
  final String path;

  /// The revision stored at [ProgressLayout.revisionOffset].
  final int detected;

  @override
  String toString() =>
      'SaveUnsupportedRevision($path, detected: $detected, '
      'supported: ${ProgressLayout.revision})';
}

/// A save-shaped file whose container could not be decoded.
final class SaveCorrupt extends SaveDetection {
  /// Records [path] and the failure [reason].
  const SaveCorrupt(this.path, this.reason);

  /// The path that was inspected.
  final String path;

  /// What is wrong with the bytes.
  final String reason;

  @override
  String toString() => 'SaveCorrupt($path, reason: $reason)';
}

/// A save this resolver understands.
final class SaveDetected extends SaveDetection {
  /// Records the detected [selection].
  const SaveDetected(this.selection);

  /// The layout and revision the save folder holds.
  final LayoutSelection selection;

  @override
  String toString() =>
      'SaveDetected(${selection.layout.id}, '
      'version: ${selection.detectedVersion})';
}

/// Detects the Switch 2 remake's progress layout for a save root.
///
/// Detection only reads. It never writes, caches, or creates temporary files,
/// and it never throws for user data: every failure is a [SaveDetection]
/// variant.
final class ProgressLayoutResolver {
  /// Creates a resolver backed by [builder].
  ///
  /// [captionBuilder] overrides how an existing `caption.sav` is turned into a
  /// slot layout; when omitted the builder's own caption method is used.
  ProgressLayoutResolver(this.builder, {this.captionBuilder});

  /// Builds progress and caption slot layouts from decoded files.
  final ProgressLayoutBuilder builder;

  /// Optional caption slot builder override.
  final CaptionSlotLayoutBuilder? captionBuilder;

  /// The layout id every detected save gets.
  static const String layoutId = 'oot-remake-progress';

  /// A slot directory name, for example `slot_03`.
  static final RegExp _slotDirectory = RegExp(r'^slot_\d+$');

  /// Inspects [rootPath] without writing.
  ///
  /// A `slot_NN` directory that itself holds `progress.sav` is treated as one
  /// slot. Otherwise only the immediate `slot_NN` children that hold a
  /// `progress.sav` are considered, in name order.
  Future<SaveDetection> detect(String rootPath) async {
    final root = Directory(rootPath);
    if (!root.existsSync()) {
      return SaveNotASave(rootPath, reason: 'no slot_NN/progress.sav');
    }

    final candidates = <_SlotDirectory>[];
    final rootName = _baseName(rootPath);
    if (_slotDirectory.hasMatch(rootName) &&
        File(_join(rootPath, 'progress.sav')).existsSync()) {
      candidates.add(_SlotDirectory(rootPath, rootName));
    } else {
      final List<FileSystemEntity> entries;
      try {
        entries = root.listSync(followLinks: false);
      } on FileSystemException catch (error) {
        return SaveCorrupt(
          rootPath,
          'could not list the save root: ${error.message}',
        );
      }
      for (final entry in entries) {
        if (entry is! Directory) {
          continue;
        }
        final name = _baseName(entry.path);
        if (!_slotDirectory.hasMatch(name)) {
          continue;
        }
        if (!File(_join(entry.path, 'progress.sav')).existsSync()) {
          continue;
        }
        candidates.add(_SlotDirectory(entry.path, name));
      }
      candidates.sort((a, b) => a.name.compareTo(b.name));
    }

    if (candidates.isEmpty) {
      return SaveNotASave(rootPath, reason: 'no slot_NN/progress.sav');
    }

    final slots = <SaveSlotLayout>[];
    for (final candidate in candidates) {
      final detection = await _detectSlot(candidate, slots);
      if (detection != null) {
        return detection;
      }
    }

    return SaveDetected(
      LayoutSelection(
        LayoutDescriptor(layoutId, ProgressLayout.revision, slots),
        ProgressLayout.revision,
      ),
    );
  }

  /// Detects one slot, appending its layouts to [slots].
  ///
  /// Returns a failure, or `null` when the slot decoded and its layouts were
  /// added. The first failure wins.
  Future<SaveDetection?> _detectSlot(
    _SlotDirectory candidate,
    List<SaveSlotLayout> slots,
  ) async {
    final progressPath = _join(candidate.path, 'progress.sav');
    final Uint8List bytes;
    try {
      bytes = await File(progressPath).readAsBytes();
    } on FileSystemException catch (error) {
      return SaveCorrupt(
        progressPath,
        'could not read progress.sav: ${error.message}',
      );
    }

    if (bytes.length < ProgressLayout.valueWordSize) {
      return SaveCorrupt(
        progressPath,
        'the file is ${bytes.length} bytes; a progress.sav needs at least '
        '${ProgressLayout.valueWordSize} bytes for the magic',
      );
    }
    final magic = _readU32(bytes, ProgressLayout.magicOffset);
    if (magic != ProgressLayout.magicValue) {
      return SaveNotASave(
        progressPath,
        magic: magic,
        reason:
            'the magic at 0x0 is ${ProgressLayout.keyHex(magic)}; '
            'expected ${ProgressLayout.keyHex(ProgressLayout.magicValue)}',
      );
    }
    if (bytes.length < ProgressLayout.revisionOffset + 4) {
      return SaveCorrupt(
        progressPath,
        'the magic is present but the revision is not',
      );
    }
    final revision = _readU32(bytes, ProgressLayout.revisionOffset);
    if (revision != ProgressLayout.revision) {
      return SaveUnsupportedRevision(progressPath, revision);
    }

    final decoded = ProgressCodec.decode(bytes);
    switch (decoded) {
      case ProgressDecodeOk(:final save):
        final index = int.tryParse(candidate.name.substring('slot_'.length));
        if (index == null) {
          return SaveNotASave(
            progressPath,
            magic: magic,
            reason: 'the slot index in ${candidate.name} is too large',
          );
        }
        final slot = SaveSlotId.progress(index);
        slots.add(builder.buildProgressSlotLayout(save, slot: slot));

        final captionPath = _join(candidate.path, 'caption.sav');
        if (File(captionPath).existsSync()) {
          final caption = await _detectCaption(captionPath, slot);
          if (caption.detection != null) {
            return caption.detection;
          }
          slots.add(caption.layout!);
        }
        return null;

      case ProgressDecodeUnsupported():
        return switch (decoded) {
          ProgressBadMagic(:final magic, :final message) => SaveNotASave(
            progressPath,
            magic: magic,
            reason: message,
          ),
          ProgressRevisionMismatch(:final revision) => SaveUnsupportedRevision(
            progressPath,
            revision,
          ),
        };

      case ProgressDecodeCorrupt(:final reason):
        return SaveCorrupt(progressPath, reason);

      case ProgressDecodeTruncated(:final reason):
        return SaveCorrupt(progressPath, reason);
    }
  }

  /// Decodes `caption.sav` at [path] and builds its layout.
  Future<_CaptionSlot> _detectCaption(String path, SaveSlotId slot) async {
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException catch (error) {
      return _CaptionSlot.failure(
        SaveCorrupt(path, 'could not read caption.sav: ${error.message}'),
      );
    }

    final decoded = CaptionCodec.decode(bytes);
    switch (decoded) {
      case CaptionDecodeOk(:final save):
        final build = captionBuilder;
        final layout = build != null
            ? build(save, progressSlot: slot)
            : builder.buildCaptionSlotLayout(save, progressSlot: slot);
        return _CaptionSlot.layout(layout);

      case CaptionDecodeUnsupported(:final message):
        return _CaptionSlot.failure(SaveCorrupt(path, message));

      case CaptionDecodeCorrupt(:final reason):
        return _CaptionSlot.failure(SaveCorrupt(path, reason));

      case CaptionDecodeTruncated(:final reason):
        return _CaptionSlot.failure(SaveCorrupt(path, reason));
    }
  }

  /// Resolves [rootPath] to a layout, or to the typed reason it cannot.
  ///
  /// Never throws for user data: detection failures become [LayoutRejected].
  Future<LayoutResolution> call(String rootPath) async {
    final detection = await detect(rootPath);
    return switch (detection) {
      SaveDetected(:final selection) => LayoutResolved(selection),
      SaveNotASave(:final path, :final reason) => LayoutRejected(
        LayoutRejectionKind.notASave,
        reason ?? 'no slot_NN/progress.sav was found',
        path: path,
      ),
      SaveUnsupportedRevision(:final path, :final detected) => LayoutRejected(
        LayoutRejectionKind.unsupportedRevision,
        'layout revision $detected is not supported; this build reads '
        '${ProgressLayout.revision}',
        detectedVersion: detected,
        path: path,
      ),
      SaveCorrupt(:final path, :final reason) => LayoutRejected(
        LayoutRejectionKind.corrupt,
        reason,
        path: path,
      ),
    };
  }
}

/// One candidate slot directory and its directory name.
final class _SlotDirectory {
  const _SlotDirectory(this.path, this.name);

  final String path;
  final String name;
}

/// The caption layout or the failure that stopped detection.
final class _CaptionSlot {
  const _CaptionSlot.layout(this.layout) : detection = null;
  const _CaptionSlot.failure(this.detection) : layout = null;

  final SaveSlotLayout? layout;
  final SaveDetection? detection;
}

int _readU32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

String _join(String parent, String child) {
  if (parent.endsWith('/') || parent.endsWith('\\')) {
    return '$parent$child';
  }
  return '$parent${Platform.pathSeparator}$child';
}

String _baseName(String path) {
  var normalized = path.replaceAll('\\', '/');
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  final separator = normalized.lastIndexOf('/');
  return separator < 0 ? normalized : normalized.substring(separator + 1);
}
