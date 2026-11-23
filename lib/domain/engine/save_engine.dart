/// Pure-Dart save engine: parse, edit, undo/redo, validate, plan, export.
///
/// The engine has no `dart:io`, Flutter, bloc, or game-specific constants. All
/// layout knowledge arrives through [LayoutDescriptor]; byte access and backup
/// storage arrive through ports implemented in `lib/data/io`.
library;

import 'dart:typed_data';

import '../core/core.dart';
import 'numeric_codec.dart';
import 'ports.dart';

/// Format-agnostic save engine.
final class SaveEngine {
  /// Creates an engine for [format].
  const SaveEngine(
    this.format, {
    this.valueCodec = const NumericFieldValueCodec(),
    this.integrityRecomputer,
    this.clock = DateTime.now,
  });

  /// The format family whose layouts this engine understands.
  final SaveFormat format;

  /// Decodes field display values; the default handles numeric kinds only.
  final FieldValueCodec valueCodec;

  /// Optional pluggable integrity codec. No algorithm is built in.
  final IntegrityRecomputer? integrityRecomputer;

  /// Injectable clock for deterministic audit timestamps and project ids.
  final DateTime Function() clock;

  /// Reads every slot from [source] and delegates to [parse].
  ///
  /// Never writes: only [SlotSource.read] is called, and no sidecar is touched.
  Future<ParseResult> open({
    required String rootPath,
    required SlotSource source,
    required LayoutDescriptor layout,
    required int detectedVersion,
    bool preserveUnknown = true,
    bool verifyIntegrity = true,
    String? backupPath,
    String? projectId,
  }) async {
    final files = <SaveSlotId, ByteRegion>{};
    for (final slot in layout.slots) {
      try {
        final bytes = await source.read(slot.id);
        if (bytes == null) {
          return ParseCorrupt('Missing ${slot.relativePath} in $rootPath');
        }
        files[slot.id] = ByteRegion.fromBytes(bytes);
      } catch (error) {
        return ParseCorrupt(
          'Could not read ${slot.relativePath} in $rootPath: $error',
        );
      }
    }
    return parse(
      rootPath: rootPath,
      files: files,
      layout: layout,
      detectedVersion: detectedVersion,
      preserveUnknown: preserveUnknown,
      verifyIntegrity: verifyIntegrity,
      backupPath: backupPath,
      projectId: projectId,
    );
  }

  /// Builds a project from already-read slot bytes.
  ///
  /// [layout] may be omitted when [format] has an exact layout for
  /// [detectedVersion]. Unsupported versions and malformed slots return typed
  /// failures without producing a project.
  ParseResult parse({
    required String rootPath,
    required Map<SaveSlotId, ByteRegion> files,
    required int detectedVersion,
    LayoutDescriptor? layout,
    bool preserveUnknown = true,
    bool verifyIntegrity = true,
    String? backupPath,
    String? projectId,
  }) {
    final resolved = layout ?? format.layoutFor(detectedVersion);
    if (resolved == null) {
      final newest = format.newestVersion;
      if (newest != null && detectedVersion > newest) {
        return ParseUnsupported(
          'layout $detectedVersion newer than supported $newest',
          detectedVersion: detectedVersion,
        );
      }
      int? minimum;
      for (final candidate in format.layouts) {
        if (minimum == null || candidate.minimumVersion < minimum) {
          minimum = candidate.minimumVersion;
        }
      }
      if (minimum != null && detectedVersion < minimum) {
        return ParseUnsupported(
          'layout $detectedVersion older than minimum $minimum',
          detectedVersion: detectedVersion,
        );
      }
      return ParseUnsupported(
        'layout $detectedVersion is not supported',
        detectedVersion: detectedVersion,
      );
    }
    if (detectedVersion > resolved.version) {
      return ParseUnsupported(
        'Layout version $detectedVersion is newer than supported '
        '${resolved.version}',
        detectedVersion: detectedVersion,
      );
    }
    if (detectedVersion < resolved.minimumVersion) {
      return ParseUnsupported(
        'Layout version $detectedVersion is older than minimum '
        '${resolved.minimumVersion}',
        detectedVersion: detectedVersion,
      );
    }
    if (detectedVersion != resolved.version) {
      return ParseUnsupported(
        'Layout version $detectedVersion does not exactly match '
        '${resolved.version}',
        detectedVersion: detectedVersion,
      );
    }

    final originals = <SaveSlotId, SaveSnapshot>{};
    final documents = <SaveSlotId, SaveDocument>{};
    final savedFingerprints = <SaveSlotId, int>{};
    final unverifiedFields = <FieldId>[];

    for (final slotLayout in resolved.slots) {
      final region = files[slotLayout.id];
      if (region == null) {
        return ParseCorrupt(
          'Slot ${slotLayout.id.value} (${slotLayout.relativePath}) is missing',
        );
      }
      final expected = slotLayout.expectedLength;
      if (expected != null && region.length != expected) {
        return ParseCorrupt(
          '${slotLayout.relativePath} is ${region.length} bytes; '
          'layout expects $expected',
          at: ByteSpan(0, region.length),
        );
      }
      final snapshot = SaveSnapshot(slotLayout.id, 0, region);
      originals[slotLayout.id] = snapshot;
      documents[slotLayout.id] = _documentFor(slotLayout, snapshot, snapshot);
      savedFingerprints[slotLayout.id] = snapshot.fingerprint;
      for (final descriptor in slotLayout.fields) {
        if (descriptor.confidence != FieldConfidence.verified) {
          unverifiedFields.add(descriptor.id);
        }
      }
    }

    if (verifyIntegrity) {
      final recomputer = integrityRecomputer;
      if (recomputer != null) {
        for (final slotLayout in resolved.slots) {
          final document = documents[slotLayout.id]!;
          for (final spec in slotLayout.integrity) {
            if (!spec.isConfirmed) {
              continue;
            }
            final verified = recomputer.verify(spec, document.snapshot.content);
            if (verified == false) {
              return ParseCorrupt(
                'Integrity scheme ${spec.schemeId} does not match '
                '${slotLayout.relativePath}',
                at: spec.region,
              );
            }
          }
        }
      }
    }

    final totalBytes = files.values.fold(
      0,
      (sum, region) => sum + region.length,
    );
    final firstSlot = resolved.slots.isEmpty
        ? SaveSlotId.account
        : resolved.slots.first.id;
    final log = EditLog(<EditRecord>[
      EditRecord(
        1,
        EditKind.open,
        clock(),
        firstSlot,
        0,
        0,
        null,
        'Opened $rootPath',
        totalBytes,
      ),
    ]);

    final project = SaveProject(
      projectId ?? '$rootPath#${clock().microsecondsSinceEpoch}',
      rootPath,
      backupPath ?? '$rootPath${BackupPolicy.standard.sidecarSuffix}',
      resolved,
      detectedVersion,
      Map<SaveSlotId, SaveSnapshot>.unmodifiable(originals),
      Map<SaveSlotId, SaveDocument>.unmodifiable(documents),
      Map<SaveSlotId, int>.unmodifiable(savedFingerprints),
      EditHistory(),
      log,
      savedSnapshots: Map<SaveSlotId, SaveSnapshot>.unmodifiable(originals),
      preserveUnknown: preserveUnknown,
    );

    return unverifiedFields.isEmpty
        ? ParseOk(project)
        : ParseUnverified(
            project,
            List<FieldId>.unmodifiable(unverifiedFields),
          );
  }

  /// Applies one command atomically.
  ///
  /// Validation and encoding happen before any snapshot, revision, history, or
  /// audit mutation. A no-op edit returns the same project instance.
  SaveProject apply(SaveProject project, EditCommand command) {
    final descriptor = project.layout.descriptor(command.field);
    if (descriptor == null) {
      throw FieldWriteException(
        FieldWriteCodes.unknown,
        'Field ${command.field.value} is not in layout ${project.layout.id}',
        field: command.field,
        value: null,
      );
    }
    final document = project.documents[descriptor.slot];
    final slotLayout = project.layout.slot(descriptor.slot);
    if (document == null || slotLayout == null) {
      throw FieldWriteException(
        FieldWriteCodes.mismatch,
        'Slot ${descriptor.slot.value} is not open',
        field: command.field,
      );
    }

    final before = document.snapshot;

    // Validation and encoding are pure; nothing below runs on failure.
    final patch = command.encodePatch(descriptor, before.content);
    if (_rangeEquals(before.content, patch.span, patch.bytes)) {
      return project;
    }
    var after = before.replace(patch.span, patch.bytes);
    after = _recomputeIntegrity(slotLayout, after, patch.span);

    // Build the decoded view before committing history/log, so a codec failure
    // cannot leave history ahead of the project.
    final documents = Map<SaveSlotId, SaveDocument>.of(project.documents);
    documents[descriptor.slot] = _documentFor(
      slotLayout,
      after,
      project.originals[descriptor.slot] ?? after,
    );

    project.history.record(command, before, after);
    final log = project.editLog.append(
      EditRecord(
        project.editLog.nextSequence,
        EditKind.apply,
        clock(),
        descriptor.slot,
        before.revision,
        after.revision,
        command,
        command.description,
        _changedByteCount(before, after),
      ),
    );

    return _copyProject(project, documents: documents, editLog: log);
  }

  /// Undoes the newest history entry by reinstalling its prior bytes.
  ///
  /// The installed snapshot gets a fresh, higher revision; bytes are identical
  /// to the pre-edit snapshot.
  SaveProject undo(SaveProject project) {
    final entry = project.history.undo();
    if (entry == null) {
      return project;
    }
    return _installHistorySnapshot(project, entry, useBefore: true);
  }

  /// Redoes the newest undone entry by reinstalling its edited bytes.
  SaveProject redo(SaveProject project) {
    final entry = project.history.redo();
    if (entry == null) {
      return project;
    }
    return _installHistorySnapshot(project, entry, useBefore: false);
  }

  /// Installs [snapshot]'s bytes with a fresh revision, without history.
  ///
  /// Intended for transaction rollback, where the caller has already discarded
  /// the group and does not want a new undo entry.
  SaveProject restoreSnapshot(SaveProject project, SaveSnapshot snapshot) {
    final document = project.documents[snapshot.slot];
    final slotLayout = project.layout.slot(snapshot.slot);
    if (document == null || slotLayout == null) {
      throw StateError('Slot ${snapshot.slot.value} is not open');
    }
    final installed = SaveSnapshot(
      snapshot.slot,
      document.snapshot.revision + 1,
      snapshot.content,
    );
    final documents = Map<SaveSlotId, SaveDocument>.of(project.documents);
    documents[snapshot.slot] = _documentFor(
      slotLayout,
      installed,
      project.originals[snapshot.slot] ?? installed,
    );
    return _copyProject(project, documents: documents);
  }

  /// Resets one slot to its in-memory original.
  ///
  /// With [clearHistory] the undo stacks are emptied and the reset cannot be
  /// undone; otherwise a synthetic entry is recorded. No files are written.
  SaveProject resetSlotInMemory(
    SaveProject project,
    SaveSlotId slot, {
    bool clearHistory = false,
  }) {
    final original = project.originals[slot];
    final document = project.documents[slot];
    final slotLayout = project.layout.slot(slot);
    if (original == null || document == null || slotLayout == null) {
      throw StateError('Slot ${slot.value} is not open');
    }

    final installed = SaveSnapshot(
      slot,
      document.snapshot.revision + 1,
      original.content,
    );
    final documents = Map<SaveSlotId, SaveDocument>.of(project.documents);
    documents[slot] = _documentFor(slotLayout, installed, original);

    if (clearHistory) {
      project.history.clear();
    } else {
      project.history.recordSynthetic(
        'Reset ${slot.value} to original',
        document.snapshot,
        installed,
      );
    }

    final log = project.editLog.append(
      EditRecord(
        project.editLog.nextSequence,
        EditKind.reset,
        clock(),
        slot,
        document.snapshot.revision,
        installed.revision,
        null,
        'Reset ${slot.value} to original',
        _changedByteCount(document.snapshot, installed),
      ),
    );
    return _copyProject(project, documents: documents, editLog: log);
  }

  /// Resets every open slot to its open-time original.
  SaveProject resetToOriginal(
    SaveProject project, {
    bool clearHistory = false,
  }) {
    var result = project;
    if (clearHistory) {
      result.history.clear();
    }
    for (final slotLayout in result.layout.slots) {
      if (result.documents.containsKey(slotLayout.id)) {
        result = resetSlotInMemory(
          result,
          slotLayout.id,
          clearHistory: clearHistory,
        );
      }
    }
    return result;
  }

  /// Validation issues for [project].
  List<ValidationIssue> validate(SaveProject project) =>
      validateResult(project).issues;

  /// Validation issues plus aggregate helpers.
  ValidationResult validateResult(SaveProject project) {
    final issues = <ValidationIssue>[];
    final fallbackSlot = _firstSlot(project);

    if (project.detectedVersion != project.layout.version) {
      issues.add(
        ValidationIssue(
          Severity.error,
          ValidationCodes.layoutUnsupported,
          'Detected version ${project.detectedVersion} does not match layout '
          '${project.layout.version}',
          fallbackSlot,
        ),
      );
    }
    if (!project.preserveUnknown) {
      issues.add(
        ValidationIssue(
          Severity.error,
          ValidationCodes.layoutUnsupported,
          'Project was opened with preserveUnknown=false; exporting would '
          'discard untouched bytes',
          fallbackSlot,
          remedy: 'Reopen with preserveUnknown=true',
        ),
      );
    }
    if (_normalizePath(project.rootPath) ==
        _normalizePath(project.backupPath)) {
      issues.add(
        ValidationIssue(
          Severity.error,
          ValidationCodes.pathConflict,
          'Backup path and save root are the same directory',
          fallbackSlot,
        ),
      );
    }

    for (final slotLayout in project.layout.slots) {
      final document = project.documents[slotLayout.id];
      if (document == null) {
        issues.add(
          ValidationIssue(
            Severity.error,
            ValidationCodes.fileSizeMismatch,
            'Slot ${slotLayout.relativePath} is not open',
            slotLayout.id,
          ),
        );
        continue;
      }
      final expected = slotLayout.expectedLength;
      if (expected != null && document.snapshot.length != expected) {
        issues.add(
          ValidationIssue(
            Severity.error,
            ValidationCodes.fileSizeMismatch,
            '${slotLayout.relativePath} is ${document.snapshot.length} bytes; '
            'layout expects $expected',
            slotLayout.id,
          ),
        );
      }

      final changed = project.changedSpans(slotLayout.id);
      for (final descriptor in slotLayout.fields) {
        if (!descriptor.span.isValid ||
            descriptor.span.length == 0 ||
            descriptor.span.end > document.snapshot.length) {
          issues.add(
            ValidationIssue(
              Severity.error,
              ValidationCodes.fieldSpanInvalid,
              'Field ${descriptor.id.value} span ${descriptor.span} is '
              'outside ${document.snapshot.length} bytes',
              slotLayout.id,
              field: descriptor.id,
            ),
          );
          continue;
        }
        if (descriptor.confidence != FieldConfidence.verified) {
          issues.add(
            ValidationIssue(
              Severity.warning,
              ValidationCodes.fieldUnverified,
              'Field ${descriptor.id.value} is '
              '${descriptor.confidence.name} and read-only',
              slotLayout.id,
              field: descriptor.id,
              remedy: 'Verify the field against research before editing',
            ),
          );
        } else if (descriptor.source.isEmpty) {
          issues.add(
            ValidationIssue(
              Severity.error,
              ValidationCodes.fieldUnverified,
              'Verified field ${descriptor.id.value} has no source citation',
              slotLayout.id,
              field: descriptor.id,
            ),
          );
        }
        final raw = readUnsigned(
          document.snapshot.content,
          descriptor.span,
          descriptor.endianness,
        );
        if (raw != null) {
          final min = descriptor.min;
          final max = descriptor.max;
          // A descriptor whose declared minimum is negative describes a signed
          // field: the layout builder maps the schema's `Int` to signed 32-bit
          // bounds while the bytes are stored in two's complement. Reading
          // them unsigned would turn the documented `-1` default into
          // 4294967295 and flag every retail save.
          final value = min != null && min < 0
              ? raw.toSigned(descriptor.span.length * 8)
              : raw;
          if ((min != null && value < min) || (max != null && value > max)) {
            issues.add(
              ValidationIssue(
                Severity.warning,
                ValidationCodes.fieldOutOfRange,
                'Field ${descriptor.id.value} is $value, outside the declared '
                'range ${min ?? '−∞'}..${max ?? '∞'}',
                slotLayout.id,
                field: descriptor.id,
              ),
            );
          }
        }
      }

      for (final spec in slotLayout.integrity) {
        final regionValid =
            spec.region.isValid &&
            spec.region.length > 0 &&
            spec.region.end <= document.snapshot.length;
        if (!regionValid) {
          issues.add(
            ValidationIssue(
              Severity.error,
              ValidationCodes.fieldSpanInvalid,
              'Integrity region ${spec.region} for ${spec.schemeId} is '
              'outside the slot',
              slotLayout.id,
            ),
          );
        }
        for (final span in spec.coverage) {
          if (!span.isValid || span.end > document.snapshot.length) {
            issues.add(
              ValidationIssue(
                Severity.error,
                ValidationCodes.fieldSpanInvalid,
                'Integrity coverage $span for ${spec.schemeId} is outside '
                'the slot',
                slotLayout.id,
              ),
            );
          }
        }
        if (!spec.isConfirmed) {
          issues.add(
            ValidationIssue(
              Severity.warning,
              ValidationCodes.integrityUnconfirmed,
              'Integrity scheme ${spec.schemeId} is '
              '${spec.confidence.name}; it cannot be verified or '
              'recomputed',
              slotLayout.id,
              remedy: 'Research must confirm the scheme before exporting edits',
            ),
          );
        }
        final touched = changed.any(spec.coversChange);
        if (!touched) {
          continue;
        }
        if (!spec.isConfirmed) {
          issues.add(
            ValidationIssue(
              Severity.error,
              ValidationCodes.integrityUnconfirmed,
              'Edit touches unconfirmed integrity scheme ${spec.schemeId}; '
              'the output would not be safe to claim as valid',
              slotLayout.id,
              remedy: 'Revert the edit or supply a verified integrity scheme',
            ),
          );
        } else if (integrityRecomputer == null) {
          issues.add(
            ValidationIssue(
              Severity.error,
              ValidationCodes.integrityUnconfirmed,
              'Edit touches confirmed integrity scheme ${spec.schemeId}, but '
              'no recomputer is registered',
              slotLayout.id,
              remedy: 'Register the layout codec before exporting',
            ),
          );
        } else {
          final recomputer = integrityRecomputer!;
          Uint8List? replacement;
          bool? verified;
          try {
            replacement = recomputer.recompute(spec, document.snapshot.content);
            verified = recomputer.verify(spec, document.snapshot.content);
          } catch (error) {
            issues.add(
              ValidationIssue(
                Severity.error,
                ValidationCodes.integrityUnconfirmed,
                'Integrity recomputer failed for ${spec.schemeId}: $error',
                slotLayout.id,
              ),
            );
            continue;
          }
          if (replacement == null || replacement.length != spec.region.length) {
            issues.add(
              ValidationIssue(
                Severity.error,
                ValidationCodes.integrityUnconfirmed,
                'Recomputer cannot produce ${spec.region.length} bytes for '
                '${spec.schemeId}',
                slotLayout.id,
              ),
            );
          } else if (!_rangeEquals(
            document.snapshot.content,
            spec.region,
            replacement,
          )) {
            issues.add(
              ValidationIssue(
                Severity.error,
                ValidationCodes.checksumMismatch,
                'Integrity bytes for ${spec.schemeId} are stale after the edit',
                slotLayout.id,
              ),
            );
          } else if (verified == false) {
            issues.add(
              ValidationIssue(
                Severity.error,
                ValidationCodes.checksumMismatch,
                'Integrity scheme ${spec.schemeId} does not match the current '
                'bytes',
                slotLayout.id,
              ),
            );
          }
        }
      }
    }

    return ValidationResult(issues);
  }

  /// Describes an export without writing anything.
  ExportPlan planExport(
    SaveProject project, {
    required String destinationRoot,
    required ExportMode mode,
    BackupPolicy policy = BackupPolicy.standard,
  }) {
    final issues = validateResult(project).issues.toList();
    final fallbackSlot = _firstSlot(project);

    final destination = _normalizePath(destinationRoot);
    final root = _normalizePath(project.rootPath);
    final backup = _normalizePath(project.backupPath);

    if (destination.isEmpty) {
      issues.add(
        ValidationIssue(
          Severity.error,
          ValidationCodes.pathConflict,
          'Destination root is empty',
          fallbackSlot,
        ),
      );
    } else if (mode == ExportMode.saveInPlace) {
      if (destination != root) {
        issues.add(
          ValidationIssue(
            Severity.error,
            ValidationCodes.pathConflict,
            'Save-in-place destination "$destinationRoot" is not the open root '
            '"${project.rootPath}"',
            fallbackSlot,
          ),
        );
      }
    } else {
      if (destination == root) {
        issues.add(
          ValidationIssue(
            Severity.error,
            ValidationCodes.pathConflict,
            '${mode.name} requires a destination distinct from the open root',
            fallbackSlot,
          ),
        );
      }
      if (destination == backup ||
          _isWithin(destination, backup) ||
          _isWithin(backup, destination)) {
        issues.add(
          ValidationIssue(
            Severity.error,
            ValidationCodes.pathConflict,
            'Destination overlaps the backup sidecar',
            fallbackSlot,
          ),
        );
      }
      if (_isWithin(destination, root) || _isWithin(root, destination)) {
        issues.add(
          ValidationIssue(
            Severity.error,
            ValidationCodes.pathConflict,
            'Destination and source root contain one another',
            fallbackSlot,
          ),
        );
      }
    }
    if (root.endsWith(policy.sidecarSuffix)) {
      issues.add(
        ValidationIssue(
          Severity.error,
          ValidationCodes.pathConflict,
          'Source root ends with the sidecar suffix ${policy.sidecarSuffix}',
          fallbackSlot,
        ),
      );
    }
    if (destination.endsWith(policy.sidecarSuffix)) {
      issues.add(
        ValidationIssue(
          Severity.error,
          ValidationCodes.pathConflict,
          'Destination ends with the sidecar suffix ${policy.sidecarSuffix}',
          fallbackSlot,
        ),
      );
    }

    final writes = <SaveSlotId, SaveSnapshot>{};
    if (mode == ExportMode.duplicate) {
      writes.addAll(project.originals);
    } else {
      for (final entry in project.documents.entries) {
        writes[entry.key] = entry.value.snapshot;
      }
    }

    return ExportPlan(
      project,
      mode,
      destinationRoot,
      Map<SaveSlotId, SaveSnapshot>.unmodifiable(writes),
      List<ValidationIssue>.unmodifiable(
        issues.where((issue) => issue.isBlocking),
      ),
      policy,
      _requiresIntegrityRecompute(project),
    );
  }

  /// Writes [plan] atomically and verifies every written slot.
  ///
  /// Refuses before any write when validation has a blocking issue, when a
  /// sidecar conflicts, or when a non-in-place destination already exists and
  /// [allowOverwrite] is false. A transaction must be committed or rolled back
  /// first.
  Future<ExportResult> export(
    ExportPlan plan, {
    required SlotSource source,
    required OriginalStore originals,
    bool allowOverwrite = false,
  }) async {
    final issues = <ValidationIssue>[];
    for (final issue in validateResult(plan.project).issues) {
      _addUnique(issues, issue);
    }
    for (final issue in plan.blockingIssues) {
      _addUnique(issues, issue);
    }
    if (issues.any((issue) => issue.isBlocking)) {
      return ExportResult.blocked(List<ValidationIssue>.unmodifiable(issues));
    }
    if (plan.project.history.inTransaction) {
      throw StateError(
        'Commit or roll back the open transaction before export',
      );
    }

    final payload = <SaveSlotId, Uint8List>{
      for (final entry in plan.writes.entries)
        entry.key: entry.value.materialize(),
    };
    final payloadRegions = <SaveSlotId, ByteRegion>{
      for (final entry in payload.entries)
        entry.key: ByteRegion.fromBytes(entry.value),
    };

    if (plan.mode != ExportMode.saveInPlace && !allowOverwrite) {
      final conflicts = <SaveSlotId>[];
      for (final slot in payload.keys) {
        if (await source.read(slot) != null) {
          conflicts.add(slot);
        }
      }
      if (conflicts.isNotEmpty) {
        return ExportResult.blocked(<ValidationIssue>[
          ...issues,
          ValidationIssue(
            Severity.error,
            ValidationCodes.pathConflict,
            'Destination already contains slot(s): '
            '${conflicts.map((slot) => slot.value).join(', ')}',
            conflicts.first,
            remedy: 'Pass allowOverwrite with explicit user confirmation',
          ),
        ]);
      }
    }

    final originalsToKeep = plan.mode == ExportMode.saveInPlace
        ? <SaveSlotId, ByteRegion>{
            for (final entry in plan.project.originals.entries)
              entry.key: entry.value.content,
          }
        : payloadRegions;
    try {
      await originals.ensure(originalsToKeep, plan.backupPolicy);
    } on OriginalBackupException catch (error) {
      return ExportResult(
        succeeded: false,
        issues: <ValidationIssue>[
          ...issues,
          ValidationIssue(
            Severity.error,
            error.code,
            error.message,
            _firstSlot(plan.project),
          ),
        ],
      );
    } catch (error) {
      return ExportResult(
        succeeded: false,
        issues: issues,
        error: 'Could not prepare the sidecar original: $error',
      );
    }

    try {
      await source.writeAll(
        payload,
        keepPreviousVersion: plan.backupPolicy.keepPreviousVersion,
      );
    } catch (error) {
      return ExportResult(
        succeeded: false,
        issues: <ValidationIssue>[
          ...issues,
          ValidationIssue(
            Severity.error,
            ValidationCodes.writeVerifyFailed,
            'Atomic write failed: $error',
            _firstSlot(plan.project),
          ),
        ],
        error: '$error',
      );
    }

    // Verify by re-reading every slot; the atomic writer verifies its temp and
    // final target too, so this is a second, independent check.
    final writtenPaths = <SaveSlotId, String>{};
    final fingerprints = <SaveSlotId, int>{};
    for (final entry in payload.entries) {
      final slot = entry.key;
      final expected = entry.value;
      Uint8List? actual;
      try {
        actual = await source.read(slot);
      } catch (error) {
        return ExportResult(
          succeeded: false,
          writtenPaths: writtenPaths,
          fingerprints: fingerprints,
          issues: <ValidationIssue>[
            ...issues,
            ValidationIssue(
              Severity.error,
              ValidationCodes.writeVerifyFailed,
              'Could not re-read ${slot.value}: $error',
              slot,
            ),
          ],
        );
      }
      if (actual == null || !_bytesEqual(actual, expected)) {
        return ExportResult(
          succeeded: false,
          writtenPaths: writtenPaths,
          fingerprints: fingerprints,
          issues: <ValidationIssue>[
            ...issues,
            ValidationIssue(
              Severity.error,
              ValidationCodes.writeVerifyFailed,
              'Post-write verification failed for ${slot.value}',
              slot,
            ),
          ],
        );
      }
      writtenPaths[slot] = source.pathFor(slot);
      fingerprints[slot] = Fnv1a.hash32(expected);
    }

    final updatedProject = _projectAfterExport(
      plan,
      payloadRegions,
      fingerprints,
    );
    return ExportResult(
      succeeded: true,
      writtenPaths: Map<SaveSlotId, String>.unmodifiable(writtenPaths),
      fingerprints: Map<SaveSlotId, int>.unmodifiable(fingerprints),
      project: updatedProject,
      issues: List<ValidationIssue>.unmodifiable(issues),
    );
  }

  /// Restores one slot from the sidecar original, then resets it in memory.
  ///
  /// Refuses when the sidecar is missing and cannot be created, or when it does
  /// not byte-match the open-time original.
  Future<SaveProject> reset(
    SaveProject project,
    SaveSlotId slot, {
    required SlotSource source,
    required OriginalStore originals,
    BackupPolicy policy = BackupPolicy.standard,
    bool clearHistory = false,
  }) async {
    final original = project.originals[slot];
    if (original == null) {
      throw StateError('Slot ${slot.value} has no open-time original');
    }
    var sidecarBytes = await originals.read(slot);
    if (sidecarBytes == null) {
      await originals.ensure(<SaveSlotId, ByteRegion>{
        for (final entry in project.originals.entries)
          entry.key: entry.value.content,
      }, policy);
      sidecarBytes = await originals.read(slot);
    }
    if (sidecarBytes == null) {
      throw const OriginalBackupException(
        ValidationCodes.backupConflict,
        'Sidecar original is missing and could not be created',
      );
    }
    if (!_bytesEqual(sidecarBytes, original.materialize())) {
      throw const OriginalBackupException(
        ValidationCodes.backupConflict,
        'Sidecar original does not match the open-time bytes; refusing reset',
      );
    }

    final expected = original.materialize();
    await source.write(slot, expected, keepPreviousVersion: true);
    final actual = await source.read(slot);
    if (actual == null || !_bytesEqual(actual, expected)) {
      throw StateError('Post-write verification failed for ${slot.value}');
    }
    return resetSlotInMemory(project, slot, clearHistory: clearHistory);
  }

  /// Copies one slot's open-time original bytes to [destinationRoot].
  Future<ExportResult> duplicate(
    SaveProject project,
    SaveSlotId slot, {
    required String destinationRoot,
    required SlotSource destination,
    required OriginalStore originals,
    BackupPolicy policy = BackupPolicy.standard,
    bool allowOverwrite = false,
  }) async {
    final original = project.originals[slot];
    if (original == null) {
      return ExportResult(
        succeeded: false,
        error: 'Slot ${slot.value} has no open-time original',
      );
    }
    final issues = _destinationIssues(project, destinationRoot, policy);
    if (issues.isNotEmpty) {
      return ExportResult.blocked(issues);
    }
    if (!allowOverwrite && await destination.read(slot) != null) {
      return ExportResult.blocked(<ValidationIssue>[
        ValidationIssue(
          Severity.error,
          ValidationCodes.pathConflict,
          'Destination already contains ${slot.value}',
          slot,
          remedy: 'Pass allowOverwrite with explicit user confirmation',
        ),
      ]);
    }

    final bytes = original.materialize();
    final region = ByteRegion.fromBytes(bytes);
    try {
      await originals.ensure(<SaveSlotId, ByteRegion>{slot: region}, policy);
    } on OriginalBackupException catch (error) {
      return ExportResult(
        succeeded: false,
        issues: <ValidationIssue>[
          ValidationIssue(Severity.error, error.code, error.message, slot),
        ],
      );
    }

    try {
      await destination.write(
        slot,
        bytes,
        keepPreviousVersion: policy.keepPreviousVersion,
      );
      final actual = await destination.read(slot);
      if (actual == null || !_bytesEqual(actual, bytes)) {
        return ExportResult(
          succeeded: false,
          issues: <ValidationIssue>[
            ValidationIssue(
              Severity.error,
              ValidationCodes.writeVerifyFailed,
              'Post-write verification failed for ${slot.value}',
              slot,
            ),
          ],
        );
      }
    } catch (error) {
      return ExportResult(
        succeeded: false,
        issues: <ValidationIssue>[
          ValidationIssue(
            Severity.error,
            ValidationCodes.writeVerifyFailed,
            'Atomic copy failed: $error',
            slot,
          ),
        ],
        error: '$error',
      );
    }

    final log = project.editLog.append(
      EditRecord(
        project.editLog.nextSequence,
        EditKind.duplicate,
        clock(),
        slot,
        0,
        0,
        null,
        'Duplicated ${slot.value} to $destinationRoot',
        bytes.length,
      ),
    );
    return ExportResult(
      succeeded: true,
      writtenPaths: <SaveSlotId, String>{slot: destination.pathFor(slot)},
      fingerprints: <SaveSlotId, int>{slot: Fnv1a.hash32(bytes)},
      project: _copyProject(project, editLog: log),
    );
  }

  SaveDocument _documentFor(
    SaveSlotLayout slotLayout,
    SaveSnapshot snapshot,
    SaveSnapshot original,
  ) {
    final fields = <SaveField<FieldValue>>[];
    for (final descriptor in slotLayout.fields) {
      final value = valueCodec.decode(descriptor, snapshot.content);
      final originalValue = valueCodec.decode(descriptor, original.content);
      if (value == null || originalValue == null) {
        continue;
      }
      fields.add(
        SaveField<FieldValue>(
          descriptor,
          value,
          originalValue,
          isDirty: _spanDiffers(
            snapshot.content,
            original.content,
            descriptor.span,
          ),
        ),
      );
    }
    return SaveDocument(
      slotLayout.id,
      slotLayout,
      snapshot,
      List<SaveField<FieldValue>>.unmodifiable(fields),
    );
  }

  SaveProject _installHistorySnapshot(
    SaveProject project,
    HistoryEntry entry, {
    required bool useBefore,
  }) {
    final target = useBefore ? entry.before : entry.after;
    final document = project.documents[target.slot];
    final slotLayout = project.layout.slot(target.slot);
    if (document == null || slotLayout == null) {
      return project;
    }
    final installed = SaveSnapshot(
      target.slot,
      document.snapshot.revision + 1,
      target.content,
    );
    final documents = Map<SaveSlotId, SaveDocument>.of(project.documents);
    documents[target.slot] = _documentFor(
      slotLayout,
      installed,
      project.originals[target.slot] ?? installed,
    );
    final log = project.editLog.append(
      EditRecord(
        project.editLog.nextSequence,
        useBefore ? EditKind.undo : EditKind.redo,
        clock(),
        target.slot,
        document.snapshot.revision,
        installed.revision,
        entry.command,
        '${useBefore ? 'Undo' : 'Redo'}: ${entry.label}',
        _changedByteCount(document.snapshot, installed),
      ),
    );
    return _copyProject(project, documents: documents, editLog: log);
  }

  SaveSnapshot _recomputeIntegrity(
    SaveSlotLayout slotLayout,
    SaveSnapshot snapshot,
    ByteSpan changed,
  ) {
    final recomputer = integrityRecomputer;
    if (recomputer == null) {
      return snapshot;
    }
    var result = snapshot;
    for (final spec in slotLayout.integrity) {
      if (!spec.isConfirmed || !spec.coversChange(changed)) {
        continue;
      }
      if (!spec.region.isValid ||
          spec.region.length == 0 ||
          spec.region.end > result.length) {
        continue;
      }
      Uint8List? replacement;
      try {
        replacement = recomputer.recompute(spec, result.content);
      } catch (_) {
        // A codec failure leaves the edit in place; validation blocks export
        // until a working recomputer exists.
        continue;
      }
      if (replacement != null && replacement.length == spec.region.length) {
        result = result.replace(spec.region, replacement);
      }
    }
    return result;
  }

  SaveProject _projectAfterExport(
    ExportPlan plan,
    Map<SaveSlotId, ByteRegion> payloadRegions,
    Map<SaveSlotId, int> fingerprints,
  ) {
    final project = plan.project;
    final writtenSnapshots = <SaveSlotId, SaveSnapshot>{
      for (final entry in payloadRegions.entries)
        entry.key: SaveSnapshot(
          entry.key,
          project.documents[entry.key]?.snapshot.revision ?? 0,
          entry.value,
        ),
    };
    final totalBytes = payloadRegions.values.fold(
      0,
      (sum, region) => sum + region.length,
    );
    final slot = payloadRegions.keys.isEmpty
        ? _firstSlot(project)
        : payloadRegions.keys.first;
    final saveRecord = EditRecord(
      project.editLog.nextSequence,
      EditKind.save,
      clock(),
      slot,
      0,
      0,
      null,
      'Exported ${payloadRegions.length} slot(s) to ${plan.destinationRoot}',
      totalBytes,
    );

    if (plan.mode == ExportMode.saveInPlace) {
      final savedSnapshots = Map<SaveSlotId, SaveSnapshot>.of(
        project.savedSnapshots,
      );
      for (final entry in writtenSnapshots.entries) {
        savedSnapshots[entry.key] =
            project.documents[entry.key]?.snapshot ?? entry.value;
      }
      return _copyProject(
        project,
        savedFingerprints: fingerprints,
        savedSnapshots: savedSnapshots,
        editLog: project.editLog.append(saveRecord),
      );
    }

    final documents = <SaveSlotId, SaveDocument>{};
    for (final entry in writtenSnapshots.entries) {
      final slotLayout = project.layout.slot(entry.key);
      if (slotLayout != null) {
        documents[entry.key] = _documentFor(
          slotLayout,
          entry.value,
          entry.value,
        );
      }
    }
    return SaveProject(
      '${plan.destinationRoot}#${clock().microsecondsSinceEpoch}',
      plan.destinationRoot,
      _backupPathFor(plan.destinationRoot, plan.backupPolicy),
      project.layout,
      project.detectedVersion,
      Map<SaveSlotId, SaveSnapshot>.unmodifiable(writtenSnapshots),
      Map<SaveSlotId, SaveDocument>.unmodifiable(documents),
      Map<SaveSlotId, int>.unmodifiable(fingerprints),
      plan.mode == ExportMode.duplicate ? EditHistory() : project.history,
      EditLog(<EditRecord>[saveRecord]),
      savedSnapshots: Map<SaveSlotId, SaveSnapshot>.unmodifiable(
        writtenSnapshots,
      ),
      preserveUnknown: project.preserveUnknown,
    );
  }

  bool _requiresIntegrityRecompute(SaveProject project) {
    for (final slotLayout in project.layout.slots) {
      final changed = project.changedSpans(slotLayout.id);
      if (changed.isEmpty) {
        continue;
      }
      for (final spec in slotLayout.integrity) {
        if (spec.isConfirmed && changed.any(spec.coversChange)) {
          return true;
        }
      }
    }
    return false;
  }

  List<ValidationIssue> _destinationIssues(
    SaveProject project,
    String destinationRoot,
    BackupPolicy policy,
  ) {
    final destination = _normalizePath(destinationRoot);
    final root = _normalizePath(project.rootPath);
    final backup = _normalizePath(project.backupPath);
    final slot = _firstSlot(project);
    final issues = <ValidationIssue>[];
    if (destination.isEmpty || destination == root) {
      issues.add(
        ValidationIssue(
          Severity.error,
          ValidationCodes.pathConflict,
          'Duplicate destination must be a distinct non-empty root',
          slot,
        ),
      );
    }
    if (destination == backup ||
        _isWithin(destination, backup) ||
        _isWithin(backup, destination)) {
      issues.add(
        ValidationIssue(
          Severity.error,
          ValidationCodes.pathConflict,
          'Duplicate destination overlaps the backup sidecar',
          slot,
        ),
      );
    }
    if (_isWithin(destination, root) || _isWithin(root, destination)) {
      issues.add(
        ValidationIssue(
          Severity.error,
          ValidationCodes.pathConflict,
          'Duplicate destination and source contain one another',
          slot,
        ),
      );
    }
    if (destination.endsWith(policy.sidecarSuffix)) {
      issues.add(
        ValidationIssue(
          Severity.error,
          ValidationCodes.pathConflict,
          'Duplicate destination ends with the sidecar suffix',
          slot,
        ),
      );
    }
    return issues;
  }

  SaveProject _copyProject(
    SaveProject project, {
    Map<SaveSlotId, SaveDocument>? documents,
    Map<SaveSlotId, int>? savedFingerprints,
    Map<SaveSlotId, SaveSnapshot>? savedSnapshots,
    EditLog? editLog,
  }) => SaveProject(
    project.projectId,
    project.rootPath,
    project.backupPath,
    project.layout,
    project.detectedVersion,
    project.originals,
    documents ?? project.documents,
    savedFingerprints ?? project.savedFingerprints,
    project.history,
    editLog ?? project.editLog,
    savedSnapshots: savedSnapshots ?? project.savedSnapshots,
    preserveUnknown: project.preserveUnknown,
  );

  SaveSlotId _firstSlot(SaveProject project) => project.layout.slots.isEmpty
      ? SaveSlotId.account
      : project.layout.slots.first.id;
}

String _backupPathFor(String rootPath, BackupPolicy policy) =>
    '$rootPath${policy.sidecarSuffix}';

String _normalizePath(String path) {
  var normalized = path.trim().replaceAll('\\', '/');
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool _isWithin(String child, String parent) =>
    child != parent && child.startsWith('$parent/');

bool _rangeEquals(ByteRegion region, ByteSpan span, List<int> bytes) {
  if (bytes.length != span.length) {
    return false;
  }
  for (var i = 0; i < span.length; i++) {
    if (region.readByte(span.offset + i) != bytes[i]) {
      return false;
    }
  }
  return true;
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

bool _bytesEqual(List<int> a, List<int> b) {
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

int _changedByteCount(SaveSnapshot before, SaveSnapshot after) {
  final a = before.materialize();
  final b = after.materialize();
  if (a.length != b.length) {
    return a.length > b.length ? a.length : b.length;
  }
  var count = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      count++;
    }
  }
  return count;
}

void _addUnique(List<ValidationIssue> issues, ValidationIssue issue) {
  if (!issues.contains(issue)) {
    issues.add(issue);
  }
}
