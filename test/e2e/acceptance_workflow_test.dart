/// End-to-end acceptance workflow over the production save stack.
///
/// Every byte used here comes from a copied scrubbed sample under
/// `.tmp/e2e/a2/`; the fixtures in `.local-fixtures/` are never edited.
///
/// 1. open a sample, edit one verified field in three different tabs, Save As,
///    reopen the export, and prove that only the edited value words differ (no
///    checksum was invented).
/// 2. an in-place save keeps the pre-save bytes in `progress.sav.bak` and in
///    `<root>.bombflower-original/` before replacing the target.
/// 3. a truncated file and a wrong-revision file are rejected. The exact
///    resolver reason and the cubit's user-facing message are reported
///    separately; `SaveSessionCubit.openPath` carries the typed resolver reason
///    into the error details.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/adapter/progress_layout_builder.dart';
import 'package:bomb_flower/data/adapter/progress_layout_resolver.dart';
import 'package:bomb_flower/data/io/file_save_repository.dart';
import 'package:bomb_flower/data/io/sidecar_backup.dart';
import 'package:bomb_flower/domain/core/core.dart' hide ByteRegion;
import 'package:bomb_flower/domain/engine/save_engine.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/domain/save/progress_layout.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration/support/progress_chain.dart';
import '../support/byte_assert.dart';
import '../support/fixture_loader.dart';

/// The scrubbed sample used for every case.
const String fixtureName = 'kokiri-start';

/// Scratch space for this file, under the gitignored `.tmp/` tree.
const String scratchRootPath = '.tmp/e2e/a2';

/// Header plus reserved bytes, `[0x00, 0x28)`.
const int headerLength = 0x28;

void main() {
  late GameDataSchema schema;
  late FieldGroupsCatalogue catalogue;

  final fixturePath =
      '${fixturesDirectory.path}/$fixtureName/slot_00/progress.sav';
  final skipReason = File(fixturePath).existsSync()
      ? null
      : 'SKIPPED, NOT PASSED: $fixturePath is missing, so this test did not '
            'run. Run `dart run tool/make_fixtures.dart` from the repository '
            'root, then re-run. A green suite that reports ~N > 0 is not full '
            'e2e coverage.';

  setUpAll(() async {
    schema = await loadGameDataSchema();
    catalogue = FieldGroupsCatalogue.load(
      await File('assets/fields/groups.json').readAsString(),
    );
    final scratch = Directory(scratchRootPath);
    if (!scratch.existsSync()) {
      await scratch.create(recursive: true);
    }
  });

  group('acceptance workflow', () {
    test('edit three tabs, export to a new path, reopen: only value words differ', () async {
      final root = await _prepareCase('item3-source');
      final sourceProgress = File('${root.path}/slot_00/progress.sav');
      final original = Uint8List.fromList(await sourceProgress.readAsBytes());

      final session = _createSession(schema);
      final cubit = session.cubit;
      await cubit.openPath(root.path);
      expect(
        cubit.state,
        isA<SaveSessionReady>(),
        reason: 'open must succeed: ${cubit.state}',
      );
      final project = cubit.openProject!;
      expect(project.preserveUnknown, isTrue);

      final chosen = _chooseFields(catalogue, project);
      expect(chosen, hasLength(3), reason: 'three fields are required');
      expect(
        chosen.map((pick) => pick.tab).toSet(),
        hasLength(3),
        reason: 'the three fields must belong to three different tabs',
      );
      expect(
        chosen.map((pick) => pick.ref.hash).toSet(),
        hasLength(3),
        reason: 'the three fields must be distinct records',
      );
      for (final pick in chosen) {
        stdout.writeln(
          '[e2e] field=${pick.ref.name} tab=${pick.tab.title} '
          'before=${pick.beforeLabel} after=${pick.afterLabel} '
          'offset=0x${pick.spanOffset.toRadixString(16)}',
        );
      }

      for (final pick in chosen) {
        cubit.edit(SetScalar(pick.id, pick.after));
        expect(
          cubit.state,
          isNot(isA<SaveSessionError>()),
          reason: 'editing ${pick.ref.name} must not fail: ${cubit.state}',
        );
        expect(_numericValue(cubit.openProject!, pick.id), pick.after);
      }
      expect(cubit.state, isA<SaveSessionReady>());

      final exportRoot = _resetDirectory('item3-export');
      final plan = session.engine.planExport(
        cubit.openProject!,
        destinationRoot: exportRoot.path,
        mode: ExportMode.saveAs,
      );
      expect(
        plan.isSafe,
        isTrue,
        reason: plan.blockingIssues
            .map((issue) => '${issue.code}: ${issue.message}')
            .join('; '),
      );

      await cubit.saveAs(exportRoot.path);
      expect(
        cubit.state,
        isA<SaveSessionSaved>(),
        reason: 'Save As must succeed: ${cubit.state}',
      );
      final saved = cubit.state as SaveSessionSaved;
      expect(saved.mode, ExportMode.saveAs);
      expect(saved.path, exportRoot.path);
      expect(saved.written, isNotEmpty);
      await cubit.close(force: true);

      final exported = Uint8List.fromList(
        await File('${exportRoot.path}/slot_00/progress.sav').readAsBytes(),
      );

      // The source root must be untouched by Save As.
      expectByteIdentical(
        original,
        Uint8List.fromList(await sourceProgress.readAsBytes()),
        reason: 'Save As must not rewrite the source progress.sav',
      );
      expect(
        Directory('${root.path}.bombflower-original').existsSync(),
        isFalse,
        reason: 'Save As must not create a sidecar beside the source',
      );

      expect(exported, hasLength(original.length));
      expectByteIdentical(
        Uint8List.sublistView(original, 0, headerLength),
        Uint8List.sublistView(exported, 0, headerLength),
        reason: 'magic, revision, tail and reserved bytes must not change',
      );
      expect(
        progressRecordCount(exported),
        11958,
        reason: 'the record stream must keep its 11,958 records',
      );
      final originalSentinels = progressSentinels(original);
      final exportedSentinels = progressSentinels(exported);
      expect(exportedSentinels, hasLength(32));
      expect(exportedSentinels, orderedEquals(originalSentinels));

      final footer = progressFooter(exported);
      expect(footer, progressFooter(original));
      expect(footer.key, ProgressLayout.footerKey);
      expect(footer.value, exported.length - 8);
      stdout.writeln(
        '[e2e] footer=key=0x${footer.key.toRadixString(16)} '
        'value=${footer.value} filesize-8=${exported.length - 8}',
      );

      final expectedOffsets = <int>{};
      for (final pick in chosen) {
        for (var i = 0; i < pick.spanLength; i++) {
          final shift = pick.littleEndian
              ? i * 8
              : (pick.spanLength - 1 - i) * 8;
          final newByte = (pick.after >> shift) & 0xff;
          if (original[pick.spanOffset + i] != newByte) {
            expectedOffsets.add(pick.spanOffset + i);
          }
        }
        expect(
          expectedOffsets.any(
            (offset) =>
                offset >= pick.spanOffset &&
                offset < pick.spanOffset + pick.spanLength,
          ),
          isTrue,
          reason: '${pick.ref.name} must actually change at least one byte',
        );
      }
      final actualOffsets = <int>{
        for (var i = 0; i < original.length; i++)
          if (original[i] != exported[i]) i,
      };
      expect(
        actualOffsets,
        equals(expectedOffsets),
        reason:
            'the only differing bytes must be the edited value words; '
            'actual=${_formatOffsets(actualOffsets)} '
            'expected=${_formatOffsets(expectedOffsets)}',
      );
      stdout.writeln(
        '[e2e] diff offsets=${_formatOffsets(actualOffsets)} '
        'count=${actualOffsets.length}',
      );

      // Reopen the export with a fresh cubit (fresh engine, repository and
      // resolver) and prove the values survived the round trip.
      final reopenedSession = _createSession(schema);
      final reopenedCubit = reopenedSession.cubit;
      await reopenedCubit.openPath(exportRoot.path);
      expect(
        reopenedCubit.state,
        isA<SaveSessionReady>(),
        reason: 'the export must reopen: ${reopenedCubit.state}',
      );
      final reopened = reopenedCubit.openProject!;
      expect(reopened.preserveUnknown, isTrue);
      for (final pick in chosen) {
        expect(
          _numericValue(reopened, pick.id),
          pick.after,
          reason: '${pick.ref.name} must survive the export',
        );
      }
      stdout.writeln(
        '[e2e] reopen values='
        '${chosen.map((pick) => '${pick.ref.name}=${pick.afterLabel}').join(', ')}',
      );
      await reopenedCubit.close(force: true);
    }, skip: skipReason);

    test('in-place save keeps .bak and the sidecar original before replacing', () async {
      final root = await _prepareCase('item4-in-place');
      final progressFile = File('${root.path}/slot_00/progress.sav');
      final original = Uint8List.fromList(await progressFile.readAsBytes());

      final session = _createSession(schema);
      final cubit = session.cubit;
      await cubit.openPath(root.path);
      expect(
        cubit.state,
        isA<SaveSessionReady>(),
        reason: 'open must succeed: ${cubit.state}',
      );
      final layout = cubit.openProject!.layout;
      expect(fieldInt(cubit.openProject!, lifeFieldId), 12);

      cubit.edit(const SetScalar(lifeFieldId, 20));
      expect(
        cubit.state,
        isNot(isA<SaveSessionError>()),
        reason: 'editing Life must not fail: ${cubit.state}',
      );
      expect(fieldInt(cubit.openProject!, lifeFieldId), 20);

      await cubit.save();
      expect(
        cubit.state,
        isA<SaveSessionSaved>(),
        reason: 'in-place save must succeed: ${cubit.state}',
      );
      final saved = cubit.state as SaveSessionSaved;
      expect(saved.mode, ExportMode.saveInPlace);

      final replaced = Uint8List.fromList(await progressFile.readAsBytes());
      expect(
        ByteRegionDiff.diff(original, replaced).hasChanges,
        isTrue,
        reason: 'the in-place save must rewrite progress.sav',
      );
      expect(fieldInt(cubit.openProject!, lifeFieldId), 20);

      final bak = File('${progressFile.path}.bak');
      expect(bak.existsSync(), isTrue, reason: 'a .bak must exist');
      final bakBytes = Uint8List.fromList(await bak.readAsBytes());
      expectByteIdentical(
        original,
        bakBytes,
        reason: 'progress.sav.bak must hold the pre-save original',
      );

      final sidecar = SidecarBackup(saveRoot: root.path, layout: layout);
      expect(sidecar.inspect(), SidecarStatus.ready);
      final stored = await sidecar.read(progressSlotId);
      expect(stored, isNotNull, reason: 'the sidecar must hold slot_00');
      expectByteIdentical(
        original,
        stored!,
        reason:
            '<root>.bombflower-original/slot_00/progress.sav must hold the '
            'pre-save original',
      );
      expect(
        File('${root.path}/.bombflower-pending.json').existsSync(),
        isFalse,
        reason: 'the batch manifest must be gone after a successful save',
      );
      stdout.writeln(
        '[e2e] in-place target=${replaced.length}B '
        'bak=${bakBytes.length}B sidecar=${stored.length}B '
        'sidecarStatus=${sidecar.inspect().name} '
        'pending=${File('${root.path}/.bombflower-pending.json').existsSync()}',
      );
      await cubit.close(force: true);
    }, skip: skipReason);

    test(
      'truncated progress.sav is rejected by detect() and by the cubit',
      () async {
        final source = Uint8List.fromList(
          await File(
            '${fixturesDirectory.path}/$fixtureName/slot_00/progress.sav',
          ).readAsBytes(),
        );
        final root = await _emptyCase('item5-truncated');
        final truncated = Uint8List.sublistView(source, 0, 100);
        await File('${root.path}/slot_00/progress.sav').writeAsBytes(truncated);

        final resolver = ProgressLayoutResolver(ProgressLayoutBuilder(schema));
        final detection = await resolver.detect(root.path);
        expect(
          detection,
          isA<SaveCorrupt>(),
          reason: 'a 100-byte file must be detected as corrupt: $detection',
        );
        final corrupt = detection as SaveCorrupt;
        expect(
          corrupt.reason,
          'the data offset 95704 points past the end of the 100-byte buffer',
        );
        stdout.writeln(
          '[e2e] truncated detection=${detection.runtimeType} '
          'toString=$detection',
        );

        final session = _createSession(schema);
        final cubit = session.cubit;
        await cubit.openPath(root.path);
        final state = cubit.state;
        expect(state, isA<SaveSessionError>());
        final error = state as SaveSessionError;
        expect(error.project, isNull);
        expect(error.kind, SaveSessionErrorKind.corruptSave);
        expect(
          error.message,
          'This save folder is damaged or incomplete.',
        );
        expect(
          error.details,
          contains(
            'the data offset 95704 points past the end of the 100-byte buffer',
          ),
        );
        expect(
          cubit.lastOpenResult,
          isNull,
          reason:
              'the resolver rejected before the repository was reached; the '
              'typed reason lives in the error details instead',
        );
        stdout.writeln(
          '[e2e] truncated cubit message="${error.message}" '
          'details="${error.details}" kind=${error.kind.name} '
          'lastOpenResult=${cubit.lastOpenResult}',
        );
        await cubit.close(force: true);
      },
      skip: skipReason,
    );

    test(
      'wrong-revision progress.sav is rejected by detect() and by the cubit',
      () async {
        final source = Uint8List.fromList(
          await File(
            '${fixturesDirectory.path}/$fixtureName/slot_00/progress.sav',
          ).readAsBytes(),
        );
        final wrongRevision = Uint8List.fromList(source);
        const detectedRevision = 2982124;
        _writeU32(
          wrongRevision,
          ProgressLayout.revisionOffset,
          detectedRevision,
        );
        expect(ProgressLayout.revision, 2982123);
        final root = await _emptyCase('item5-revision');
        await File('${root.path}/slot_00/progress.sav')
            .writeAsBytes(wrongRevision);

        final resolver = ProgressLayoutResolver(ProgressLayoutBuilder(schema));
        final detection = await resolver.detect(root.path);
        expect(
          detection,
          isA<SaveUnsupportedRevision>(),
          reason: 'a wrong revision must be unsupported: $detection',
        );
        final unsupported = detection as SaveUnsupportedRevision;
        expect(unsupported.detected, detectedRevision);
        expect(
          detection.toString(),
          contains('detected: 2982124, supported: 2982123'),
        );
        stdout.writeln(
          '[e2e] revision detection=${detection.runtimeType} '
          'toString=$detection',
        );

        final session = _createSession(schema);
        final cubit = session.cubit;
        await cubit.openPath(root.path);
        final state = cubit.state;
        expect(state, isA<SaveSessionError>());
        final error = state as SaveSessionError;
        expect(error.project, isNull);
        expect(error.kind, SaveSessionErrorKind.unsupportedLayout);
        expect(
          error.message,
          'This save uses a game version this build does not support.',
        );
        expect(error.details, contains('layout revision 2982124'));
        expect(error.details, contains('2982123'));
        expect(cubit.lastOpenResult, isNull);
        stdout.writeln(
          '[e2e] revision cubit message="${error.message}" '
          'details="${error.details}" kind=${error.kind.name} '
          'lastOpenResult=${cubit.lastOpenResult}',
        );
        await cubit.close(force: true);
      },
      skip: skipReason,
    );
  });
}

/// The production wiring exactly as `lib/main.dart` builds it: one engine
/// shared by the repository and the cubit, one resolver, one `FileSaveRepository`.
({SaveEngine engine, ProgressLayoutResolver resolver, SaveSessionCubit cubit})
_createSession(GameDataSchema schema) {
  final engine = createProgressEngine();
  final resolver = ProgressLayoutResolver(ProgressLayoutBuilder(schema));
  final repository = FileSaveRepository(
    engine: engine,
    resolveLayout: resolver.call,
  );
  final cubit = SaveSessionCubit(
    engine: engine,
    repository: repository,
    resolveLayout: resolver.call,
  );
  return (engine: engine, resolver: resolver, cubit: cubit);
}

/// Copies the fixture pair for [fixtureName] into a fresh case directory.
Future<Directory> _prepareCase(String name) async {
  final root = await _emptyCase(name);
  for (final file in sampleSaveFiles) {
    final source = File('${fixturesDirectory.path}/$fixtureName/slot_00/$file');
    if (!source.existsSync()) {
      fail('fixture file is missing: ${source.path}');
    }
    await source.copy('${root.path}/slot_00/$file');
  }
  return root;
}

/// Deletes [name], its sidecar and its contents, then creates an empty slot.
Future<Directory> _emptyCase(String name) async {
  final root = Directory('$scratchRootPath/$name');
  _deleteTree(root.path);
  await Directory('${root.path}/slot_00').create(recursive: true);
  return root;
}

/// Deletes [path] and its `<path>.bombflower-original` sidecar.
void _deleteTree(String path) {
  for (final suffix in const <String>['', '.bombflower-original']) {
    final directory = Directory('$path$suffix');
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}

/// Deletes [name] and its sidecar, then creates an empty directory.
Directory _resetDirectory(String name) {
  final root = Directory('$scratchRootPath/$name');
  _deleteTree(root.path);
  root.createSync(recursive: true);
  return root;
}

/// Picks the first editable verified Int/Bool field of each of three tabs.
///
/// The scan is data-driven: it walks `EditorTabGroup.values`, one field per
/// tab, and accepts a field only when the opened project's descriptor says it
/// is editable and its decoded value can be changed without clamping.
List<_ChosenField> _chooseFields(
  FieldGroupsCatalogue catalogue,
  SaveProject project,
) {
  final chosen = <_ChosenField>[];
  final usedHashes = <int>{};
  for (final tab in EditorTabGroup.values) {
    if (chosen.length == 3) {
      break;
    }
    _ChosenField? pick;
    for (final group in catalogue.forTab(tab)) {
      for (final ref in group.fields) {
        if (usedHashes.contains(ref.hash)) {
          continue;
        }
        final candidate = _pickField(tab, ref, project);
        if (candidate != null) {
          pick = candidate;
          break;
        }
      }
      if (pick != null) {
        break;
      }
    }
    if (pick != null) {
      chosen.add(pick);
      usedHashes.add(pick.ref.hash);
    }
  }
  return chosen;
}

/// Returns the increment for [ref], or `null` when it is not a safe candidate.
_ChosenField? _pickField(
  EditorTabGroup tab,
  FieldRef ref,
  SaveProject project,
) {
  if (ref.provenance != FieldProvenance.verified) {
    return null;
  }
  if (ref.type != 'Int' && ref.type != 'Bool') {
    return null;
  }
  final id = FieldId('progress.${ref.hash.toRadixString(16).padLeft(8, '0')}');
  final descriptor = project.layout.descriptor(id);
  if (descriptor == null || !descriptor.isEditable) {
    return null;
  }
  if (descriptor.kind != FieldKind.integer &&
      descriptor.kind != FieldKind.boolean) {
    return null;
  }

  final int before;
  final int after;
  final String beforeLabel;
  final String afterLabel;
  switch (project.document(progressSlotId)?.field(id)?.value) {
    case IntValue(value: final value):
      before = value;
      after = value + 1;
      beforeLabel = '$value';
      afterLabel = '$after';
    case BoolValue(value: final value):
      before = value ? 1 : 0;
      after = value ? 0 : 1;
      beforeLabel = '$value';
      afterLabel = '$value' == 'true' ? 'false' : 'true';
    default:
      return null;
  }

  if (after == before) {
    return null;
  }
  final min = descriptor.min;
  if (min != null && after < min) {
    return null;
  }
  final max = descriptor.max;
  if (max != null && after > max) {
    return null;
  }
  final width = descriptor.span.length;
  if (width < 8 && after >= (1 << (width * 8))) {
    return null;
  }

  return _ChosenField(
    tab: tab,
    ref: ref,
    id: id,
    before: before,
    after: after,
    beforeLabel: beforeLabel,
    afterLabel: afterLabel,
    spanOffset: descriptor.span.offset,
    spanLength: width,
    littleEndian: descriptor.endianness == Endian.little,
  );
}

/// The decoded numeric value of [id], with a boolean mapped to 0/1.
int _numericValue(SaveProject project, FieldId id) {
  return switch (project.document(progressSlotId)?.field(id)?.value) {
    IntValue(value: final value) => value,
    BoolValue(value: final value) => value ? 1 : 0,
    final other => throw StateError('$id is not numeric: $other'),
  };
}

/// Writes [value] as a little-endian u32 at [offset].
void _writeU32(Uint8List bytes, int offset, int value) {
  for (var index = 0; index < 4; index++) {
    bytes[offset + index] = (value >> (index * 8)) & 0xff;
  }
}

/// Formats [offsets] as ascending `0x...` values.
String _formatOffsets(Set<int> offsets) {
  final sorted = offsets.toList()..sort();
  return sorted.map((offset) => '0x${offset.toRadixString(16)}').join(',');
}

/// One field chosen for the multi-tab edit.
final class _ChosenField {
  const _ChosenField({
    required this.tab,
    required this.ref,
    required this.id,
    required this.before,
    required this.after,
    required this.beforeLabel,
    required this.afterLabel,
    required this.spanOffset,
    required this.spanLength,
    required this.littleEndian,
  });

  final EditorTabGroup tab;
  final FieldRef ref;
  final FieldId id;
  final int before;
  final int after;
  final String beforeLabel;
  final String afterLabel;
  final int spanOffset;
  final int spanLength;
  final bool littleEndian;
}
