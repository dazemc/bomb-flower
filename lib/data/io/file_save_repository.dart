/// File-backed slot source and repository.
library;

import 'dart:io';
import 'dart:typed_data';

import '../../domain/core/core.dart';
import '../../domain/engine/ports.dart';
import '../../domain/engine/save_engine.dart';
import 'atomic_file_writer.dart';
import 'io_paths.dart';
import 'sidecar_backup.dart';

/// Manifest name used for crash-recoverable multi-file exports.
const String pendingManifestName = '.bombflower-pending.json';

/// Reads and writes slot files under one root using a layout's relative paths.
final class FileSlotSource implements SlotSource {
  /// Creates a source for [rootPath].
  FileSlotSource({
    required this.rootPath,
    required this.layout,
    AtomicFileWriter? writer,
  }) : writer = writer ?? AtomicFileWriter();

  /// Save folder root.
  final String rootPath;

  /// Layout supplying each slot's relative path.
  final LayoutDescriptor layout;

  /// Atomic writer used for every mutation.
  final AtomicFileWriter writer;

  /// Manifest path for batch recovery.
  String get manifestPath =>
      '$rootPath${Platform.pathSeparator}$pendingManifestName';

  @override
  String pathFor(SaveSlotId slot) {
    final slotLayout = layout.slot(slot);
    if (slotLayout == null) {
      throw ArgumentError.value(slot.value, 'slot', 'is not in the layout');
    }
    return resolveUnderRoot(rootPath, slotLayout.relativePath);
  }

  @override
  Future<Uint8List?> read(SaveSlotId slot) async {
    final file = File(pathFor(slot));
    return file.existsSync() ? file.readAsBytes() : null;
  }

  @override
  Future<void> write(
    SaveSlotId slot,
    Uint8List bytes, {
    bool keepPreviousVersion = true,
  }) async {
    await writer.write(
      pathFor(slot),
      bytes,
      keepPreviousVersion: keepPreviousVersion,
    );
  }

  @override
  Future<void> writeAll(
    Map<SaveSlotId, Uint8List> writes, {
    bool keepPreviousVersion = true,
  }) async {
    if (writes.isEmpty) {
      return;
    }
    final files = <String, List<int>>{
      for (final entry in writes.entries) pathFor(entry.key): entry.value,
    };
    await writer.writeAll(
      files,
      keepPreviousVersion: keepPreviousVersion,
      manifestPath: manifestPath,
    );
  }

  /// Finishes or rolls back a crash-left batch manifest, if one exists.
  Future<AtomicRecoveryReport> recover() => writer.recover(manifestPath);
}

/// File-system implementation of [SaveRepository].
final class FileSaveRepository implements SaveRepository {
  /// Creates a repository around [engine] and a layout detector.
  FileSaveRepository({
    required this.engine,
    required this.resolveLayout,
    this.policy = BackupPolicy.standard,
    AtomicFileWriter? writer,
  }) : writer = writer ?? AtomicFileWriter();

  /// Domain engine.
  final SaveEngine engine;

  /// Detects a layout for a root without writing.
  final LayoutResolver resolveLayout;

  /// Default backup policy.
  final BackupPolicy policy;

  /// Atomic writer shared by all sources.
  final AtomicFileWriter writer;

  @override
  Future<ParseResult> open(
    String rootPath, {
    bool preserveUnknown = true,
    bool verifyIntegrity = true,
  }) async {
    final resolution = await resolveLayout(rootPath);
    final LayoutSelection detected;
    switch (resolution) {
      case LayoutResolved(:final selection):
        detected = selection;
      case LayoutRejected(:final reason, :final detectedVersion, :final path):
        return ParseUnsupported(
          path == null ? reason : '$reason (at $path)',
          detectedVersion: detectedVersion,
        );
    }
    final source = FileSlotSource(
      rootPath: rootPath,
      layout: detected.layout,
      writer: writer,
    );
    try {
      final recovery = await source.recover();
      if (!recovery.recovered && recovery.messages.isNotEmpty) {
        return ParseCorrupt(
          'Incomplete export in $rootPath: ${recovery.messages.join('; ')}',
        );
      }
    } catch (error) {
      return ParseCorrupt('Could not recover an interrupted export: $error');
    }
    return engine.open(
      rootPath: rootPath,
      source: source,
      layout: detected.layout,
      detectedVersion: detected.detectedVersion,
      preserveUnknown: preserveUnknown,
      verifyIntegrity: verifyIntegrity,
      backupPath: sidecarPathFor(rootPath, policy.sidecarSuffix),
    );
  }

  @override
  Future<void> ensureOriginalBackup(
    SaveProject project,
    BackupPolicy policy,
  ) async {
    await _sidecarFor(
      project,
      project.rootPath,
      policy,
    ).ensure(_regions(project.originals), policy);
  }

  @override
  Future<ExportResult> writeExport(
    ExportPlan plan, {
    bool allowOverwrite = false,
  }) {
    final root = plan.mode == ExportMode.saveInPlace
        ? plan.project.rootPath
        : plan.destinationRoot;
    final source = FileSlotSource(
      rootPath: root,
      layout: plan.project.layout,
      writer: writer,
    );
    final sidecar = _sidecarFor(plan.project, root, plan.backupPolicy);
    return engine.export(
      plan,
      source: source,
      originals: sidecar,
      allowOverwrite: allowOverwrite,
    );
  }

  @override
  Future<SaveProject> reset(
    SaveProject project,
    SaveSlotId slot, {
    bool clearHistory = false,
  }) {
    final source = FileSlotSource(
      rootPath: project.rootPath,
      layout: project.layout,
      writer: writer,
    );
    final sidecar = _sidecarFor(project, project.rootPath, policy);
    return engine.reset(
      project,
      slot,
      source: source,
      originals: sidecar,
      policy: policy,
      clearHistory: clearHistory,
    );
  }

  @override
  Future<ExportResult> duplicate(
    SaveProject project,
    SaveSlotId slot, {
    required String destinationRoot,
    BackupPolicy policy = BackupPolicy.standard,
    bool allowOverwrite = false,
  }) {
    final source = FileSlotSource(
      rootPath: destinationRoot,
      layout: project.layout,
      writer: writer,
    );
    final sidecar = _sidecarFor(project, destinationRoot, policy);
    return engine.duplicate(
      project,
      slot,
      destinationRoot: destinationRoot,
      destination: source,
      originals: sidecar,
      policy: policy,
      allowOverwrite: allowOverwrite,
    );
  }

  SidecarBackup _sidecarFor(
    SaveProject project,
    String root,
    BackupPolicy policy,
  ) => SidecarBackup(
    saveRoot: root,
    layout: project.layout,
    suffix: policy.sidecarSuffix,
    projectId: project.projectId,
    formatId: engine.format.id,
  );

  static Map<SaveSlotId, ByteRegion> _regions(
    Map<SaveSlotId, SaveSnapshot> snapshots,
  ) => <SaveSlotId, ByteRegion>{
    for (final entry in snapshots.entries) entry.key: entry.value.content,
  };
}
