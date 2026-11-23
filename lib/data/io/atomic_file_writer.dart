/// Crash-safe single- and multi-file writes.
///
/// Protocol per file: temp in the same directory → flush/close → read-back
/// verify → optional `.bak` of the previous target → atomic rename → fsync the
/// parent directory → verify the final target. A failure cleans the temp and
/// leaves the previous target untouched; a final verification failure restores
/// the `.bak` (or removes a new target).
///
/// `dart:io` has no directory-fsync primitive; [AtomicFileWriter] attempts it
/// best-effort and documents the limitation rather than pretending otherwise.
library;

import 'dart:convert';
import 'dart:io';

import '../../domain/core/fingerprint.dart';
import '../../domain/core/validation.dart';

/// Injection points used by tests to simulate failures.
final class const AtomicWriteHooks({
  final void Function(String tempPath)? onAfterTempWritten,
  final void Function(String tempPath)? onBeforeRename,
  final void Function(String finalPath)? onBeforeFinalVerify,
});

/// A write failure with a stable code.
final class AtomicWriteException implements Exception {
  /// Creates a failure.
  const AtomicWriteException(this.code, this.message, {this.path});

  /// Stable code, normally from [ValidationCodes].
  final String code;

  /// Human-readable explanation.
  final String message;

  /// Path involved, when known.
  final String? path;

  @override
  String toString() => 'AtomicWriteException[$code] $path: $message';
}

/// The result of one verified atomic write.
final class const AtomicWriteResult(
  final String path,
  final int byteCount,
  final int fingerprint, {
  final String? backupPath,
});

/// One entry of a pending multi-file manifest.
final class const AtomicWriteEntry(
  final String targetPath,
  final String tempPath,
  final String? backupPath,
  final int length,
  final int fingerprint,
) {
  /// Serialises this entry.
  Map<String, Object?> toJson() => <String, Object?>{
    'targetPath': targetPath,
    'tempPath': tempPath,
    'backupPath': backupPath,
    'length': length,
    'fingerprint': fingerprint,
  };

  /// Parses one entry.
  static AtomicWriteEntry fromJson(Map<String, Object?> json) {
    final target = json['targetPath'];
    final temp = json['tempPath'];
    final length = json['length'];
    final fingerprint = json['fingerprint'];
    if (target is! String ||
        temp is! String ||
        length is! int ||
        fingerprint is! int) {
      throw const FormatException('Malformed atomic-write manifest entry');
    }
    final backup = json['backupPath'];
    return AtomicWriteEntry(
      target,
      temp,
      backup is String ? backup : null,
      length,
      fingerprint,
    );
  }
}

/// A pending or committed batch manifest.
final class const AtomicWriteManifest(
  final String state,
  final List<AtomicWriteEntry> entries,
) {
  /// A batch that may not have renamed every target yet.
  static const String pending = 'pending';

  /// A batch whose renames were all issued.
  static const String committed = 'committed';

  /// Serialises the manifest.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'state': state,
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };

  /// Parses a manifest.
  static AtomicWriteManifest fromJson(Map<String, Object?> json) {
    final version = json['version'];
    final state = json['state'];
    final rawEntries = json['entries'];
    if (version != 1 || state is! String || rawEntries is! List<Object?>) {
      throw const FormatException('Malformed atomic-write manifest');
    }
    return AtomicWriteManifest(state, <AtomicWriteEntry>[
      for (final raw in rawEntries)
        if (raw is Map<String, Object?>)
          AtomicWriteEntry.fromJson(raw)
        else
          throw const FormatException('Manifest entry is not an object'),
    ]);
  }
}

/// Recovery outcome for a leftover batch manifest.
final class const AtomicRecoveryReport(
  final String manifestPath,
  final bool recovered,
  final List<String> messages,
);

/// Performs atomic writes and crash recovery.
final class AtomicFileWriter {
  /// Creates a writer.
  AtomicFileWriter({
    this.hooks = const AtomicWriteHooks(),
    this.fsyncDirectory = true,
  });

  /// Test/diagnostic hooks.
  final AtomicWriteHooks hooks;

  /// Whether to attempt a parent-directory fsync (best effort).
  final bool fsyncDirectory;

  static int _counter = 0;

  /// Writes [bytes] to [path] atomically and verifies the result.
  Future<AtomicWriteResult> write(
    String path,
    List<int> bytes, {
    bool keepPreviousVersion = true,
    bool verify = true,
  }) async {
    _ensureWritableTarget(path);
    final parent = Directory(File(path).parent.path);
    parent.createSync(recursive: true);

    final tempPath = _nextTempPath(path);
    String? backupPath;
    String? safetyPath;
    var renamed = false;
    try {
      _writeTemp(tempPath, bytes, verify: verify);
      hooks.onAfterTempWritten?.call(tempPath);
      hooks.onBeforeRename?.call(tempPath);

      if (File(path).existsSync()) {
        if (keepPreviousVersion) {
          backupPath = _createBackup(path);
          safetyPath = backupPath;
        } else {
          // Keep an unretained rollback copy so a failed verification can
          // restore the previous target even when .bak retention is off.
          safetyPath = _createSafetyCopy(path);
        }
      }

      File(tempPath).renameSync(path);
      renamed = true;
      _fsyncDirectory(parent.path);

      hooks.onBeforeFinalVerify?.call(path);
      if (verify) {
        _verifyBytes(path, bytes);
      }
      if (!keepPreviousVersion) {
        _deleteIfExists(safetyPath);
      }
      return AtomicWriteResult(
        path,
        bytes.length,
        Fnv1a.hash32(bytes),
        backupPath: backupPath,
      );
    } catch (error) {
      if (renamed) {
        _restoreOrRemove(path, safetyPath);
      }
      if (error is AtomicWriteException) {
        rethrow;
      }
      throw AtomicWriteException(
        ValidationCodes.writeVerifyFailed,
        '$error',
        path: path,
      );
    } finally {
      _deleteIfExists(tempPath);
      if (!keepPreviousVersion) {
        _deleteIfExists(safetyPath);
      }
    }
  }

  /// Stages every file, then renames all of them.
  ///
  /// A staging failure touches no target. A rename or final-verify failure
  /// restores every already-renamed target from its `.bak`, or removes a target
  /// that had no previous version.
  Future<List<AtomicWriteResult>> writeAll(
    Map<String, List<int>> files, {
    bool keepPreviousVersion = true,
    bool verify = true,
    String? manifestPath,
  }) async {
    final staged = <_StagedFile>[];
    try {
      for (final entry in files.entries) {
        _ensureWritableTarget(entry.key);
        Directory(File(entry.key).parent.path).createSync(recursive: true);
        final tempPath = _nextTempPath(entry.key);
        final item = _StagedFile(entry.key, tempPath, entry.value);
        staged.add(item);
        _writeTemp(tempPath, entry.value, verify: verify);
        hooks.onAfterTempWritten?.call(tempPath);
        hooks.onBeforeRename?.call(tempPath);
      }

      for (final item in staged) {
        if (File(item.path).existsSync()) {
          if (keepPreviousVersion) {
            item.backupPath = _createBackup(item.path);
            item.safetyPath = item.backupPath;
          } else {
            item.safetyPath = _createSafetyCopy(item.path);
          }
        }
      }

      if (manifestPath != null) {
        _writeManifest(
          manifestPath,
          AtomicWriteManifest(AtomicWriteManifest.pending, <AtomicWriteEntry>[
            for (final item in staged)
              AtomicWriteEntry(
                item.path,
                item.tempPath,
                item.safetyPath,
                item.bytes.length,
                Fnv1a.hash32(item.bytes),
              ),
          ]),
        );
      }

      for (final item in staged) {
        File(item.tempPath).renameSync(item.path);
        item.renamed = true;
        _fsyncDirectory(File(item.path).parent.path);
      }
      if (manifestPath != null) {
        _writeManifest(
          manifestPath,
          AtomicWriteManifest(AtomicWriteManifest.committed, <AtomicWriteEntry>[
            for (final item in staged)
              AtomicWriteEntry(
                item.path,
                item.tempPath,
                item.safetyPath,
                item.bytes.length,
                Fnv1a.hash32(item.bytes),
              ),
          ]),
        );
      }

      if (verify) {
        for (final item in staged) {
          hooks.onBeforeFinalVerify?.call(item.path);
          _verifyBytes(item.path, item.bytes);
        }
      }
      if (manifestPath != null) {
        _deleteIfExists(manifestPath);
      }
      if (!keepPreviousVersion) {
        for (final item in staged) {
          _deleteIfExists(item.safetyPath);
        }
      }
      return <AtomicWriteResult>[
        for (final item in staged)
          AtomicWriteResult(
            item.path,
            item.bytes.length,
            Fnv1a.hash32(item.bytes),
            backupPath: item.backupPath,
          ),
      ];
    } catch (error) {
      for (final item in staged.reversed) {
        if (item.renamed) {
          _restoreOrRemove(item.path, item.safetyPath);
        }
        _deleteIfExists(item.tempPath);
      }
      if (manifestPath != null) {
        _deleteIfExists(manifestPath);
      }
      if (error is AtomicWriteException) {
        rethrow;
      }
      throw AtomicWriteException(ValidationCodes.writeVerifyFailed, '$error');
    } finally {
      if (!keepPreviousVersion) {
        for (final item in staged) {
          _deleteIfExists(item.safetyPath);
        }
      }
    }
  }

  /// Recovers or rolls back a leftover batch manifest.
  Future<AtomicRecoveryReport> recover(String manifestPath) async {
    final file = File(manifestPath);
    if (!file.existsSync()) {
      return AtomicRecoveryReport(manifestPath, false, const <String>[]);
    }
    final messages = <String>[];
    late final AtomicWriteManifest manifest;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Manifest root must be an object');
      }
      manifest = AtomicWriteManifest.fromJson(decoded);
    } catch (error) {
      messages.add('Unreadable manifest: $error');
      _deleteIfExists(manifestPath);
      return AtomicRecoveryReport(manifestPath, false, messages);
    }

    final tempsUsable = manifest.entries.every(_entryTempMatches);
    if (tempsUsable && manifest.state == AtomicWriteManifest.pending) {
      for (final entry in manifest.entries) {
        File(entry.tempPath).renameSync(entry.targetPath);
        _fsyncDirectory(File(entry.targetPath).parent.path);
        _discardTransientBackup(entry);
      }
      messages.add('Completed ${manifest.entries.length} pending rename(s)');
      _deleteIfExists(manifestPath);
      return AtomicRecoveryReport(manifestPath, true, messages);
    }

    if (manifest.state == AtomicWriteManifest.committed &&
        manifest.entries.every(_entryTargetMatches)) {
      for (final entry in manifest.entries) {
        _deleteIfExists(entry.tempPath);
        _discardTransientBackup(entry);
      }
      _deleteIfExists(manifestPath);
      messages.add('Previous batch was already committed and verified');
      return AtomicRecoveryReport(manifestPath, true, messages);
    }

    for (final entry in manifest.entries) {
      _deleteIfExists(entry.tempPath);
      final backup = entry.backupPath;
      if (backup != null && File(backup).existsSync()) {
        File(backup).copySync(entry.targetPath);
        messages.add('Restored ${entry.targetPath} from $backup');
      }
      _discardTransientBackup(entry);
    }
    _deleteIfExists(manifestPath);
    messages.add('Rolled back an incomplete batch');
    return AtomicRecoveryReport(manifestPath, false, messages);
  }

  void _discardTransientBackup(AtomicWriteEntry entry) {
    final backup = entry.backupPath;
    if (backup != null && backup.contains('bombflower-tmp')) {
      _deleteIfExists(backup);
    }
  }

  bool _entryTempMatches(AtomicWriteEntry entry) {
    final file = File(entry.tempPath);
    if (!file.existsSync()) {
      return false;
    }
    final bytes = file.readAsBytesSync();
    return bytes.length == entry.length &&
        Fnv1a.hash32(bytes) == entry.fingerprint;
  }

  bool _entryTargetMatches(AtomicWriteEntry entry) {
    final file = File(entry.targetPath);
    if (!file.existsSync()) {
      return false;
    }
    final bytes = file.readAsBytesSync();
    return bytes.length == entry.length &&
        Fnv1a.hash32(bytes) == entry.fingerprint;
  }

  void _writeTemp(String tempPath, List<int> bytes, {required bool verify}) {
    final file = File(tempPath);
    file.createSync(exclusive: true);
    final raf = file.openSync(mode: FileMode.writeOnly);
    try {
      raf.writeFromSync(bytes);
      raf.flushSync();
    } finally {
      raf.closeSync();
    }
    if (verify) {
      _verifyBytes(tempPath, bytes);
    }
  }

  void _verifyBytes(String path, List<int> expected) {
    final file = File(path);
    if (!file.existsSync()) {
      throw AtomicWriteException(
        ValidationCodes.writeVerifyFailed,
        'Target disappeared after write',
        path: path,
      );
    }
    final actual = file.readAsBytesSync();
    if (actual.length != expected.length) {
      throw AtomicWriteException(
        ValidationCodes.writeVerifyFailed,
        'Expected ${expected.length} bytes, found ${actual.length}',
        path: path,
      );
    }
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) {
        throw AtomicWriteException(
          ValidationCodes.writeVerifyFailed,
          'Byte $i differs after write (expected ${expected[i]}, '
          'found ${actual[i]})',
          path: path,
        );
      }
    }
  }

  String _createBackup(String path) {
    final backupPath = '$path.bak';
    _ensureWritableTarget(backupPath);
    final backupTemp = _nextTempPath(backupPath);
    try {
      File(backupTemp)
        ..createSync(exclusive: true)
        ..writeAsBytesSync(File(path).readAsBytesSync(), flush: true);
      File(backupTemp).renameSync(backupPath);
      return backupPath;
    } finally {
      _deleteIfExists(backupTemp);
    }
  }

  String _createSafetyCopy(String path) {
    final safetyPath = _nextTempPath(path);
    final file = File(safetyPath);
    file.createSync(exclusive: true);
    file.writeAsBytesSync(File(path).readAsBytesSync(), flush: true);
    return safetyPath;
  }

  void _restoreOrRemove(String path, String? backupPath) {
    try {
      if (backupPath != null && File(backupPath).existsSync()) {
        File(backupPath).copySync(path);
      } else {
        _deleteIfExists(path);
      }
    } on FileSystemException {
      // Best effort: a failed restore is reported by the caller's exception.
    }
  }

  void _writeManifest(String manifestPath, AtomicWriteManifest manifest) {
    Directory(File(manifestPath).parent.path).createSync(recursive: true);
    final tempPath = _nextTempPath(manifestPath);
    try {
      File(tempPath)
        ..createSync(exclusive: true)
        ..writeAsStringSync(jsonEncode(manifest.toJson()), flush: true);
      File(tempPath).renameSync(manifestPath);
    } finally {
      _deleteIfExists(tempPath);
    }
  }

  void _ensureWritableTarget(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw AtomicWriteException(
        ValidationCodes.pathConflict,
        'Refusing to write through a symlink',
        path: path,
      );
    }
    if (type == FileSystemEntityType.directory) {
      throw AtomicWriteException(
        ValidationCodes.pathConflict,
        'Target is a directory',
        path: path,
      );
    }
  }

  void _fsyncDirectory(String path) {
    if (!fsyncDirectory) {
      return;
    }
    // Dart exposes no portable directory fsync. Opening a directory often
    // fails on Linux; this is intentionally best effort.
    RandomAccessFile? raf;
    try {
      raf = File(path).openSync(mode: FileMode.read);
      raf.flushSync();
    } catch (_) {
      // Directory fsync is unavailable through dart:io.
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {
        // Ignore close failures on a best-effort directory handle.
      }
    }
  }

  static String _nextTempPath(String path) {
    final file = File(path);
    final directory = file.parent.path;
    final segments = file.path.split(Platform.pathSeparator);
    final base = segments.isEmpty ? 'file' : segments.last;
    final token =
        '${pid}_${DateTime.now().microsecondsSinceEpoch}_'
        '${_counter++}';
    return '$directory${Platform.pathSeparator}'
        '.$base.bombflower-tmp-$token';
  }

  static void _deleteIfExists(String? path) {
    if (path == null) {
      return;
    }
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } on FileSystemException {
      // A temp that cannot be deleted is reported by the process that owns it;
      // never treat it as a successful save.
    }
  }
}

final class _StagedFile {
  _StagedFile(this.path, this.tempPath, this.bytes);

  final String path;
  final String tempPath;
  final List<int> bytes;
  String? backupPath;
  String? safetyPath;
  bool renamed = false;
}
