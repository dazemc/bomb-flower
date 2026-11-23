/// Writes a generated new save into a `slot_00` folder.
///
/// The builder owns the bytes; this writer owns the filesystem rules. It
/// refuses a non-empty destination by default, writes both files through one
/// [AtomicFileWriter.writeAll] call so a failure touches neither target, and
/// never deletes a directory or an unrelated file.
library;

import 'dart:io';

import '../../domain/core/fingerprint.dart';
import '../../domain/newsave/new_save_builder.dart';
import '../io/atomic_file_writer.dart';

/// A new-save write failure with a stable code.
final class NewSaveWriteException implements Exception {
  /// Creates a failure.
  const NewSaveWriteException(this.code, this.message);

  /// The destination already contains at least one entry.
  static const String destinationNotEmpty = 'destination_not_empty';

  /// The filesystem rejected part of the write.
  static const String writeFailed = 'write_failed';

  /// Stable code; one of [destinationNotEmpty] or [writeFailed].
  final String code;

  /// Human-readable explanation.
  final String message;

  @override
  String toString() => 'NewSaveWriteException[$code] $message';
}

/// The files written by a successful [NewSaveWriter.write].
final class NewSaveWriteResult {
  /// Creates a result.
  const NewSaveWriteResult({
    required this.rootDirectory,
    required this.progressPath,
    required this.captionPath,
    required this.progressLength,
    required this.captionLength,
    required this.progressFingerprint,
    required this.captionFingerprint,
  });

  /// The destination root, as given to [NewSaveWriter.write].
  final String rootDirectory;

  /// Absolute or relative path of `slot_00/progress.sav`.
  final String progressPath;

  /// Absolute or relative path of `slot_00/caption.sav`.
  final String captionPath;

  /// Length of `progress.sav` in bytes.
  final int progressLength;

  /// Length of `caption.sav` in bytes.
  final int captionLength;

  /// FNV-1a 32 fingerprint of `progress.sav`.
  final int progressFingerprint;

  /// FNV-1a 32 fingerprint of `caption.sav`.
  final int captionFingerprint;
}

/// Writes one [NewSaveBuild] as `slot_00/progress.sav` and `slot_00/caption.sav`.
final class NewSaveWriter {
  /// Creates a writer, optionally around an injected [AtomicFileWriter].
  NewSaveWriter({AtomicFileWriter? writer})
    : writer = writer ?? AtomicFileWriter();

  /// Atomic writer used for the batch.
  final AtomicFileWriter writer;

  /// The one slot folder a new save occupies.
  static const String slotDirectoryName = 'slot_00';

  /// The progress file's name.
  static const String progressFileName = 'progress.sav';

  /// The caption file's name.
  static const String captionFileName = 'caption.sav';

  /// Writes [build] under [rootDirectory].
  ///
  /// When [allowOverwrite] is false, a [rootDirectory] that exists and contains
  /// any entry at all is refused with [NewSaveWriteException.destinationNotEmpty]
  /// before anything is created or written. When it is true, the write proceeds
  /// and [AtomicFileWriter] keeps `.bak` copies of the previous files.
  Future<NewSaveWriteResult> write({
    required String rootDirectory,
    required NewSaveBuild build,
    bool allowOverwrite = false,
  }) async {
    if (rootDirectory.trim().isEmpty) {
      throw ArgumentError.value(
        rootDirectory,
        'rootDirectory',
        'must not be empty',
      );
    }

    final root = Directory(rootDirectory);
    if (!allowOverwrite && root.existsSync()) {
      final List<FileSystemEntity> entries;
      try {
        entries = root.listSync(followLinks: false);
      } on FileSystemException catch (error) {
        throw NewSaveWriteException(
          NewSaveWriteException.writeFailed,
          'Could not inspect ${root.path}: ${error.message}',
        );
      }
      if (entries.isNotEmpty) {
        final noun = entries.length == 1 ? 'entry' : 'entries';
        throw NewSaveWriteException(
          NewSaveWriteException.destinationNotEmpty,
          'Refusing to write into ${root.path}: it already contains '
          '${entries.length} $noun; pass allowOverwrite to replace '
          'slot_00 and keep .bak copies.',
        );
      }
    }

    final slotDirectory = _join(root.path, slotDirectoryName);
    final progressPath = _join(slotDirectory, progressFileName);
    final captionPath = _join(slotDirectory, captionFileName);

    try {
      final results = await writer.writeAll(<String, List<int>>{
        progressPath: build.progressBytes,
        captionPath: build.captionBytes,
      }, keepPreviousVersion: true);
      final byPath = <String, AtomicWriteResult>{
        for (final result in results) result.path: result,
      };
      if (!byPath.containsKey(progressPath) ||
          !byPath.containsKey(captionPath)) {
        throw const NewSaveWriteException(
          NewSaveWriteException.writeFailed,
          'The atomic writer did not report both new-save targets.',
        );
      }
    } on NewSaveWriteException {
      rethrow;
    } on AtomicWriteException catch (error) {
      throw NewSaveWriteException(
        NewSaveWriteException.writeFailed,
        'Could not write ${error.path ?? slotDirectory}: ${error.message}',
      );
    } on FileSystemException catch (error) {
      throw NewSaveWriteException(
        NewSaveWriteException.writeFailed,
        'Could not write under ${root.path}: ${error.message}',
      );
    }

    return NewSaveWriteResult(
      rootDirectory: root.path,
      progressPath: progressPath,
      captionPath: captionPath,
      progressLength: build.progressBytes.length,
      captionLength: build.captionBytes.length,
      progressFingerprint: Fnv1a.hash32(build.progressBytes),
      captionFingerprint: Fnv1a.hash32(build.captionBytes),
    );
  }

  static String _join(String directory, String name) {
    final hasSeparator =
        directory.endsWith(Platform.pathSeparator) || directory.endsWith('/');
    return hasSeparator
        ? '$directory$name'
        : '$directory${Platform.pathSeparator}$name';
  }
}
