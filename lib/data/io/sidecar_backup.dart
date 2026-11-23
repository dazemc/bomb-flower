/// Adjacent sidecar originals: create, verify, and restore.
///
/// Layout:
/// ```
/// <root>.bombflower-original/
///   READY              // written last, only after every file is durable
///   manifest.json      // project/format/version/fingerprint metadata
///   files/<mirror of the source tree>
/// ```
///
/// Collision policy: an existing sidecar is never silently overwritten.
/// A sidecar is reusable only when `READY` exists, the manifest parses, the
/// recorded source-tree fingerprint matches the open originals, and every file
/// byte still matches. Anything else raises `backup.conflict`; the caller must
/// choose a different backup location or explicitly archive the sidecar.
///
/// No directory or file is created by [inspect], [read], or [verify].
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/core/byte_region.dart';
import '../../domain/core/export_plan.dart';
import '../../domain/core/fingerprint.dart';
import '../../domain/core/identity.dart';
import '../../domain/core/layout.dart';
import '../../domain/core/validation.dart';
import '../../domain/engine/ports.dart';
import 'io_paths.dart';

/// The state of an adjacent sidecar directory.
enum SidecarStatus {
  /// The sidecar directory does not exist.
  absent,

  /// The directory exists but `READY` (or a parseable manifest) is missing.
  incomplete,

  /// `READY` and a parseable manifest are present.
  ready,
}

/// Metadata recorded in `manifest.json`.
final class const SidecarManifest(
  final String projectId,
  final String formatId,
  final int layoutVersion,
  final String sourceTreeFingerprint,
  final String createdAt,
  final String engineVersion,
) {
  /// Serialises the manifest.
  Map<String, Object?> toJson() => <String, Object?>{
    'projectId': projectId,
    'formatId': formatId,
    'layoutVersion': layoutVersion,
    'sourceTreeFingerprint': sourceTreeFingerprint,
    'createdAt': createdAt,
    'engineVersion': engineVersion,
  };

  /// Parses a manifest produced by [toJson].
  static SidecarManifest fromJson(Map<String, Object?> json) {
    final projectId = json['projectId'];
    final formatId = json['formatId'];
    final layoutVersion = json['layoutVersion'];
    final fingerprint = json['sourceTreeFingerprint'];
    final createdAt = json['createdAt'];
    final engineVersion = json['engineVersion'];
    if (projectId is! String ||
        formatId is! String ||
        layoutVersion is! int ||
        fingerprint is! String ||
        createdAt is! String ||
        engineVersion is! String) {
      throw const FormatException('Malformed sidecar manifest');
    }
    return SidecarManifest(
      projectId,
      formatId,
      layoutVersion,
      fingerprint,
      createdAt,
      engineVersion,
    );
  }
}

/// File-backed sidecar original store for one save root.
final class SidecarBackup implements OriginalStore {
  /// Creates a sidecar for [saveRoot].
  SidecarBackup({
    required this.saveRoot,
    required this.layout,
    this.suffix = '.bombflower-original',
    this.projectId = '',
    this.formatId = '',
    this.engineVersion = '0.1.0',
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Root of the working save folder.
  final String saveRoot;

  /// Layout used to mirror slot relative paths.
  final LayoutDescriptor layout;

  /// Sidecar suffix, normally from [BackupPolicy.sidecarSuffix].
  final String suffix;

  /// Project id recorded in a newly created manifest.
  final String projectId;

  /// Format id recorded in a newly created manifest.
  final String formatId;

  /// Engine version recorded in a newly created manifest.
  final String engineVersion;

  final DateTime Function() _clock;

  @override
  String get rootPath => sidecarPathFor(saveRoot, suffix);

  /// Absolute path of `manifest.json`.
  String get manifestPath => _join(rootPath, 'manifest.json');

  /// Absolute path of the `READY` marker.
  String get readyPath => _join(rootPath, 'READY');

  /// Absolute path of the mirrored `files` directory.
  String get filesPath => _join(rootPath, 'files');

  /// Inspects the sidecar without creating or modifying anything.
  SidecarStatus inspect() {
    final directory = Directory(rootPath);
    if (!directory.existsSync()) {
      return SidecarStatus.absent;
    }
    if (!File(readyPath).existsSync()) {
      return SidecarStatus.incomplete;
    }
    try {
      _readManifest();
      return SidecarStatus.ready;
    } catch (_) {
      return SidecarStatus.incomplete;
    }
  }

  @override
  Future<void> ensure(
    Map<SaveSlotId, ByteRegion> originals,
    BackupPolicy policy,
  ) async {
    final status = inspect();
    if (status == SidecarStatus.ready) {
      if (!await verify(originals)) {
        throw const OriginalBackupException(
          ValidationCodes.backupConflict,
          'An existing sidecar has READY but does not match the open '
          'originals; refusing to overwrite it',
        );
      }
      return;
    }
    if (status == SidecarStatus.incomplete) {
      throw const OriginalBackupException(
        ValidationCodes.backupConflict,
        'An incomplete sidecar exists (READY is missing or the manifest is '
        'unreadable); refusing to overwrite it',
      );
    }

    final expected = _treeFingerprint(originals);
    try {
      Directory(rootPath).createSync(recursive: true);
      Directory(filesPath).createSync(recursive: true);
      for (final entry in _sortedEntries(originals)) {
        final slotLayout = layout.slot(entry.key);
        if (slotLayout == null) {
          throw OriginalBackupException(
            ValidationCodes.backupConflict,
            'Slot ${entry.key.value} has no layout path to mirror',
          );
        }
        final target = resolveUnderRoot(filesPath, slotLayout.relativePath);
        _writeDurable(target, entry.value.materialize());
        _makeReadOnly(target);
      }
      final manifest = SidecarManifest(
        projectId.isEmpty
            ? '$saveRoot#${_clock().microsecondsSinceEpoch}'
            : projectId,
        formatId,
        layout.version,
        Fnv1a.hex32(expected),
        _clock().toIso8601String(),
        engineVersion,
      );
      _writeDurable(manifestPath, utf8.encode(jsonEncode(manifest.toJson())));
      // READY is written last: its presence is the only trusted marker.
      _writeDurable(readyPath, utf8.encode(Fnv1a.hex32(expected)));
    } catch (error) {
      if (error is OriginalBackupException) {
        rethrow;
      }
      throw OriginalBackupException(
        ValidationCodes.backupConflict,
        'Sidecar creation failed and was left incomplete: $error',
      );
    }

    if (!await verify(originals)) {
      // READY was written before the final read-back. Remove it so a corrupt
      // sidecar is reported as incomplete and never trusted by a later open.
      _deleteIfExists(readyPath);
      throw const OriginalBackupException(
        ValidationCodes.backupConflict,
        'Sidecar verification failed after creation; READY was not trusted',
      );
    }
  }

  @override
  Future<Uint8List?> read(SaveSlotId slot) async {
    if (inspect() != SidecarStatus.ready) {
      return null;
    }
    final slotLayout = layout.slot(slot);
    if (slotLayout == null) {
      return null;
    }
    final file = File(resolveUnderRoot(filesPath, slotLayout.relativePath));
    return file.existsSync() ? file.readAsBytes() : null;
  }

  /// Reads a sidecar original, throwing when the sidecar is absent/conflicted.
  Future<Uint8List> restore(SaveSlotId slot) async {
    final bytes = await read(slot);
    if (bytes == null) {
      throw OriginalBackupException(
        ValidationCodes.backupConflict,
        'No READY sidecar original exists for ${slot.value}',
      );
    }
    return bytes;
  }

  @override
  Future<bool> verify(Map<SaveSlotId, ByteRegion> originals) async {
    if (inspect() != SidecarStatus.ready) {
      return false;
    }
    late final SidecarManifest manifest;
    try {
      manifest = _readManifest();
    } catch (_) {
      return false;
    }
    if (manifest.sourceTreeFingerprint !=
        Fnv1a.hex32(_treeFingerprint(originals))) {
      return false;
    }
    for (final entry in originals.entries) {
      final slotLayout = layout.slot(entry.key);
      if (slotLayout == null) {
        return false;
      }
      final file = File(resolveUnderRoot(filesPath, slotLayout.relativePath));
      if (!file.existsSync()) {
        return false;
      }
      final stored = file.readAsBytesSync();
      final expected = entry.value.materialize();
      if (!_bytesEqual(stored, expected)) {
        return false;
      }
    }
    return true;
  }

  SidecarManifest _readManifest() {
    final file = File(manifestPath);
    if (!file.existsSync()) {
      throw const FormatException('manifest.json is missing');
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Manifest root must be an object');
    }
    return SidecarManifest.fromJson(decoded);
  }

  static List<MapEntry<SaveSlotId, ByteRegion>> _sortedEntries(
    Map<SaveSlotId, ByteRegion> originals,
  ) {
    final entries = originals.entries.toList()
      ..sort((a, b) => a.key.value.compareTo(b.key.value));
    return entries;
  }

  static int _treeFingerprint(Map<SaveSlotId, ByteRegion> originals) {
    final buffer = <int>[];
    for (final entry in _sortedEntries(originals)) {
      buffer.addAll(utf8.encode(entry.key.value));
      buffer.add(0);
      buffer.addAll(entry.value.materialize());
      buffer.add(0);
    }
    return Fnv1a.hash32(buffer);
  }

  static void _writeDurable(String path, List<int> bytes) {
    Directory(File(path).parent.path).createSync(recursive: true);
    final temp =
        '$path.bombflower-tmp-${pid}_${DateTime.now().microsecondsSinceEpoch}';
    final file = File(temp);
    try {
      file.createSync(exclusive: true);
      final raf = file.openSync(mode: FileMode.writeOnly);
      try {
        raf.writeFromSync(bytes);
        raf.flushSync();
      } finally {
        raf.closeSync();
      }
      file.renameSync(path);
    } finally {
      _deleteIfExists(temp);
    }
  }

  static void _deleteIfExists(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } on FileSystemException {
      // A leftover temp is never trusted as a completed sidecar.
    }
  }

  static void _makeReadOnly(String path) {
    if (!Platform.isLinux && !Platform.isMacOS) {
      return;
    }
    try {
      Process.runSync('chmod', <String>['0444', path]);
    } catch (_) {
      // Permissions are best effort; READY still validates byte identity.
    }
  }

  static String _join(String root, String child) =>
      '$root${Platform.pathSeparator}$child';

  static bool _bytesEqual(List<int> a, List<int> b) {
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
}
