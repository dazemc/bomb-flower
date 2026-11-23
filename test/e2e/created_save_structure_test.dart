/// End-to-end proof of a created save's bytes and structure.
///
/// Three proofs, in declaration order, all on fresh unique `.tmp/` roots that
/// are removed in `addTearDown`:
///
/// 1. The production CLI (`dart run tool/create_save.dart --out <root>`) writes
///    the documented 120,572-byte `progress.sav` and 2,029-byte `caption.sav`
///    (and the 1,400-byte `--no-screenshot` variant), and each file is
///    byte-identical to the in-memory `NewSaveBuilder` output for the same
///    inputs. Printed lengths are never trusted: the bytes are read and
///    compared.
/// 2. The production in-app dialog (`NewSaveDialog`) creates the same pair
///    with **no dependency injected**: its own `_create` runs
///    `NewSaveBuilder.build` + the dialog's default `NewSaveWriter().write`
///    (`AtomicFileWriter.writeAll`), and its own default `rootBundle` schema
///    loader. The one honest caveat is recorded in the test output: the widget
///    is pumped by `flutter_test`, so no native window or human click exists;
///    the button is tapped through `WidgetTester`. Nothing about the create
///    chain itself is faked.
/// 3. `SaveSessionCubit.openPath` — wired exactly as `lib/main.dart` wires
///    `SaveEngine` + `FileSaveRepository` + `ProgressLayoutResolver` — accepts
///    the CLI-created folder. `ParseUnverified` is the acceptance shape here:
///    8,328 hash-only fields are unverified and read-only, which is a
///    provenance note, not a parse failure. Nothing blocks.
///
/// Every step prints one `[e2e] ...` line carrying the measured values, and
/// asserts the same values.
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/adapter/progress_layout_builder.dart';
import 'package:bomb_flower/data/adapter/progress_layout_resolver.dart';
import 'package:bomb_flower/data/codec/caption_codec.dart';
import 'package:bomb_flower/data/codec/progress_codec.dart';
import 'package:bomb_flower/data/io/file_save_repository.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/newsave/new_save_builder.dart';
import 'package:bomb_flower/domain/newsave/new_save_spec.dart';
import 'package:bomb_flower/domain/save/caption_layout.dart';
import 'package:bomb_flower/domain/save/progress_layout.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_ui_state.dart';
import 'package:bomb_flower/presentation/dialogs/new_save_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../integration/support/progress_chain.dart';
import '../presentation/dialogs/dialog_test_support.dart';
import '../support/temp_roots.dart';

/// Progress length documented in `docs/NEW-SAVE.md`.
const int _progressLength = 120572;

/// Caption length with the builder's 633-byte JPEG.
const int _captionLength = 2029;

/// Caption length with `--no-screenshot` (1,396-byte header + `FF D8 FF D9`).
const int _captionLengthNoScreenshot = 1400;

/// The 32 section sentinels are `{0, typeId}` for these ids, in order.
const int _sentinelCount = 32;

/// Fields plus sentinels plus the footer.
const int _recordCount = 11958;

/// Field records only.
const int _fieldCount = 11925;

/// `field.unverified` provenance notes the engine reports for this file:
/// 8,317 hash-only schema fields plus 11 named fields without a verified
/// source, all read-only. They are informational, never blocking.
const int _informationalNoteCount = 8328;

/// Field records the value codec can decode into the UI document (11,925
/// descriptors minus 225 opaque/uninterpretable ones).
const int _decodableFieldCount = 11700;

/// Field descriptors with no decoded value; they stay read-only.
const int _opaqueFieldCount = 225;

/// Caption slot descriptors: five container fields plus six date entries and
/// the JPEG length row.
const int _captionFieldCount = 12;

/// Schema used by both create paths and by the cubit wiring.
late GameDataSchema _schema;

/// Fresh CLI destination (screenshot enabled) for this run.
late Directory _cliRoot;

/// Fresh CLI destination for the `--no-screenshot` variant.
late Directory _noScreenshotRoot;

/// Fresh destination the production dialog writes into.
late Directory _dialogRoot;

/// Captured CLI runs, asserted rather than assumed.
late ProcessResult _cliRun;
late ProcessResult _noScreenshotRun;

/// The CLI's bytes, read from disk by the test.
late Uint8List _cliProgress;
late Uint8List _cliCaption;

void main() {
  setUpAll(() async {
    _schema = await loadGameDataSchema();
    _cliRoot = createTempRoot('e2e/created-save-structure/cli');
    _noScreenshotRoot = createTempRoot('e2e/created-save-structure/cli-noshot');
    _dialogRoot = createTempRoot('e2e/created-save-structure/dialog');
    addTearDown(() {
      removeTempRoot(_cliRoot);
      removeTempRoot(_noScreenshotRoot);
      removeTempRoot(_dialogRoot);
    });

    _cliRun = await _runCli(_cliRoot.path);
    _noScreenshotRun = await _runCli(_noScreenshotRoot.path, <String>[
      '--no-screenshot',
    ]);

    _cliProgress = _readIfPresent('${_cliRoot.path}/slot_00/progress.sav');
    _cliCaption = _readIfPresent('${_cliRoot.path}/slot_00/caption.sav');
  });

  test('the CLI writes the documented pair, byte-identical to the builder', () {
    expect(
      _cliRun.exitCode,
      0,
      reason:
          'CLI failed\nstdout:\n${_cliRun.stdout}\nstderr:\n${_cliRun.stderr}',
    );
    final cliStdout = '${_cliRun.stdout}';
    expect(cliStdout, contains('progress.sav $_progressLength bytes'));
    expect(cliStdout, contains('caption.sav $_captionLength bytes'));
    expect(cliStdout, contains('records=$_recordCount fields=$_fieldCount'));
    expect(cliStdout, contains('dataOffset=0x000175d8'));
    expect(cliStdout, contains('progress decode=ok fields=$_fieldCount'));
    expect(cliStdout, contains('caption decode=ok scene=KokiriForest'));
    expect(cliStdout, contains('corrupt=0 unsupported=0'));
    stdout.writeln(
      '[e2e] CLI exit=0 root=${_cliRoot.path} '
      'progress=${_cliProgress.length}B caption=${_cliCaption.length}B',
    );

    // Measured, not printed: real file lengths.
    expect(
      File('${_cliRoot.path}/slot_00/progress.sav').lengthSync(),
      _progressLength,
    );
    expect(
      File('${_cliRoot.path}/slot_00/caption.sav').lengthSync(),
      _captionLength,
    );
    expect(_cliProgress.length, _progressLength);
    expect(_cliCaption.length, _captionLength);

    // Same input through the same production builder: the CLI's files are the
    // builder's bytes, so the printed lengths cannot be hiding a mismatch.
    final build = NewSaveBuilder.build(
      schema: _schema,
      spec: NewSaveSpec.preset(NewSavePreset.schemaDefaults),
    );
    expect(build.progressBytes, orderedEquals(_cliProgress));
    expect(build.captionBytes, orderedEquals(_cliCaption));
    expect(build.recordCount, _recordCount);
    expect(build.fieldCount, _fieldCount);
    expect(build.sentinelCount, _sentinelCount);
    expect(build.dataOffset, ProgressLayout.sampleDataOffset);
    stdout.writeln(
      '[e2e] builder bytes == CLI bytes (progress + caption); '
      'fnv1a32 progress=${Fnv1a.hex32(Fnv1a.hash32(_cliProgress))} '
      'caption=${Fnv1a.hex32(Fnv1a.hash32(_cliCaption))} '
      'fnv1a64 progress=${_fnv1a64(_cliProgress)} '
      'caption=${_fnv1a64(_cliCaption)}',
    );

    _expectProgressStructure(_cliProgress, label: 'CLI progress.sav');
    _expectCaptionStructure(
      _cliCaption,
      jpegLength: 633,
      label: 'CLI caption.sav',
    );

    // The `--no-screenshot` variant: a separate run, a 1,400-byte caption and
    // an unchanged progress file.
    expect(
      _noScreenshotRun.exitCode,
      0,
      reason:
          'CLI --no-screenshot failed\n'
          'stdout:\n${_noScreenshotRun.stdout}\n'
          'stderr:\n${_noScreenshotRun.stderr}',
    );
    final noScreenshotCaption = _readIfPresent(
      '${_noScreenshotRoot.path}/slot_00/caption.sav',
    );
    final noScreenshotProgress = _readIfPresent(
      '${_noScreenshotRoot.path}/slot_00/progress.sav',
    );
    expect(noScreenshotCaption.length, _captionLengthNoScreenshot);
    expect(
      File('${_noScreenshotRoot.path}/slot_00/caption.sav').lengthSync(),
      _captionLengthNoScreenshot,
    );
    expect(noScreenshotProgress, orderedEquals(_cliProgress));
    final preset = NewSaveSpec.preset(NewSavePreset.schemaDefaults);
    final noScreenshotBuild = NewSaveBuilder.build(
      schema: _schema,
      spec: NewSaveSpec(
        scene: preset.scene,
        mapPath: preset.mapPath,
        createCaptionScreenshot: false,
      ),
    );
    expect(noScreenshotBuild.captionBytes, orderedEquals(noScreenshotCaption));
    _expectCaptionStructure(
      noScreenshotCaption,
      jpegLength: 4,
      label: 'CLI caption.sav (--no-screenshot)',
    );
    stdout.writeln(
      '[e2e] CLI --no-screenshot caption=${noScreenshotCaption.length}B '
      'jpeg=4B progress identical to screenshot run',
    );
  });

  testWidgets('the production dialog writes the same bytes as the CLI', (
    tester,
  ) async {
    // No `persist` and no `schemaLoader` are passed: the dialog uses its own
    // default `NewSaveWriter().write` and its own bundled-schema loader, which
    // is the chain lib/main.dart gets. `initialRoot` only pre-fills the field a
    // human would type into.
    await launchDialog<NewSaveOutcome>(
      tester,
      (context) => NewSaveDialog.show(context, initialRoot: _dialogRoot.path),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NewSaveDialog), findsOneWidget);
    expect(find.byKey(const Key('new-save-never-loaded')), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-save-create')));

    // The create chain does real file IO and loads the bundled 7.2 MB schema;
    // both need real event-loop turns, which runAsync supplies while pump()
    // drives the dialog's frames.
    for (var attempt = 0; attempt < 400; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
      if (find.byKey(const Key('new-save-success')).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('new-save-success')),
      findsOneWidget,
      reason:
          'the dialog did not reach its success panel; error panel: '
          '${_dialogErrorText(tester)}',
    );
    expect(find.text('Created slot_00'), findsOneWidget);
    expect(
      find.text('${_dialogRoot.path}/slot_00/progress.sav'),
      findsOneWidget,
    );
    expect(
      find.text('${_dialogRoot.path}/slot_00/caption.sav'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    stdout.writeln(
      '[e2e] dialog create: real NewSaveDialog -> NewSaveBuilder -> default '
      'NewSaveWriter().write -> AtomicFileWriter.writeAll (no seams injected)',
    );

    final dialogProgress = _readIfPresent(
      '${_dialogRoot.path}/slot_00/progress.sav',
    );
    final dialogCaption = _readIfPresent(
      '${_dialogRoot.path}/slot_00/caption.sav',
    );
    expect(
      File('${_dialogRoot.path}/slot_00/progress.sav').lengthSync(),
      _progressLength,
    );
    expect(
      File('${_dialogRoot.path}/slot_00/caption.sav').lengthSync(),
      _captionLength,
    );
    expect(dialogProgress.length, _progressLength);
    expect(dialogCaption.length, _captionLength);

    // Byte identity, not merely equal lengths.
    expect(dialogProgress, orderedEquals(_cliProgress));
    expect(dialogCaption, orderedEquals(_cliCaption));
    expect(
      Fnv1a.hash32(dialogProgress),
      Fnv1a.hash32(_cliProgress),
      reason: 'fnv1a32 progress.sav must match the CLI',
    );
    expect(
      Fnv1a.hash32(dialogCaption),
      Fnv1a.hash32(_cliCaption),
      reason: 'fnv1a32 caption.sav must match the CLI',
    );
    expect(_fnv1a64(dialogProgress), _fnv1a64(_cliProgress));
    expect(_fnv1a64(dialogCaption), _fnv1a64(_cliCaption));
    stdout.writeln(
      '[e2e] CLI vs dialog byte identity: progress=${dialogProgress.length}B '
      'caption=${dialogCaption.length}B '
      'fnv1a32=${Fnv1a.hex32(Fnv1a.hash32(dialogProgress))}/'
      '${Fnv1a.hex32(Fnv1a.hash32(dialogCaption))} '
      'fnv1a64=${_fnv1a64(dialogProgress)}/${_fnv1a64(dialogCaption)}',
    );

    // The dialog's success panel reports the same lengths it wrote.
    expect(
      tester.widget<Text>(find.byKey(const Key('new-save-written-size'))).data,
      contains('120,572 B'),
    );
  });

  test('SaveSessionCubit.openPath accepts the created save and keeps it intact', () async {
    final cubit = _buildCubit(_schema);
    addTearDown(() => cubit.close(force: true));

    await cubit.openPath(_cliRoot.path);
    expect(
      cubit.state,
      isA<SaveSessionReady>(),
      reason: 'openPath(${_cliRoot.path}) left ${cubit.state}',
    );

    // `ParseUnverified` is the acceptance shape: the 8,328 unverified
    // (hash-only / uncited) fields are read-only provenance notes, not a
    // parse failure. A failure would be ParseCorrupt or ParseUnsupported.
    final result = cubit.lastOpenResult;
    expect(result, isA<ParseUnverified>(), reason: 'got $result');
    expect(result, isNot(isA<ParseCorrupt>()));
    expect(result, isNot(isA<ParseUnsupported>()));
    final unverifiedFields = (result! as ParseUnverified).unverifiedFields;
    expect(
      unverifiedFields.length,
      _informationalNoteCount,
      reason: 'one read-only note per unverified field',
    );
    stdout.writeln(
      '[e2e] lastOpenResult=ParseUnverified (acceptance; ${unverifiedFields.length} '
      'hash-only/uncited fields are read-only notes, not fatal) '
      'state=SaveSessionReady',
    );

    final ui = (cubit.state as SaveSessionReady).project;
    expect(ui.hasBlockingErrors, isFalse);
    expect(ui.blockingIssueCount, 0);
    expect(ui.actionableWarningCount, 0);
    expect(ui.informationalIssueCount, _informationalNoteCount);
    expect(ui.issues.length, _informationalNoteCount);
    expect(ui.issues.every((issue) => issue.isInformational), isTrue);
    expect(
      ui.issues.every(
        (issue) =>
            issue.code == ValidationCodes.fieldUnverified &&
            issue.severity == Severity.warning,
      ),
      isTrue,
      reason: 'every issue is a field.unverified provenance note',
    );
    final progressNotes = ui.issues
        .where((issue) => issue.slot == progressSlotId)
        .length;
    final captionNotes = ui.issues
        .where((issue) => issue.slot.value == 'slot_00.caption')
        .length;
    expect(progressNotes + captionNotes, _informationalNoteCount);
    expect(progressNotes, greaterThan(0));
    stdout.writeln(
      '[e2e] validation: total=${ui.issues.length} blocking=0 actionable=0 '
      'informational=${ui.informationalIssueCount} '
      'progressNotes=$progressNotes captionNotes=$captionNotes',
    );

    // Slot rows: both files open. The layout declares 11,925 progress field
    // descriptors; the UI row counts the 11,700 the value codec can decode, so
    // both numbers are asserted rather than conflated.
    final progressSlot = ui.slots.firstWhere(
      (slot) => slot.id == progressSlotId,
    );
    expect(progressSlot.isOpen, isTrue);
    expect(progressSlot.relativePath, 'slot_00/progress.sav');
    expect(progressSlot.fieldCount, _decodableFieldCount);
    expect(progressSlot.expectedLength, _progressLength);
    final captionSlot = ui.slots.firstWhere(
      (slot) => slot.id.value == 'slot_00.caption',
    );
    expect(captionSlot.isOpen, isTrue);
    expect(captionSlot.relativePath, 'slot_00/caption.sav');
    expect(captionSlot.expectedLength, _captionLength);
    expect(ui.activeSlot, progressSlotId);
    expect(ui.hasUnsavedChanges, isFalse);
    expect(ui.differsFromOriginal, isFalse);

    // The opened project reproduces the bytes on disk exactly: opening did not
    // alter them.
    final project = cubit.openProject;
    expect(project, isNotNull);

    // The layout carries every field descriptor; the UI row above counts only
    // the ones the value codec can decode.
    final progressLayout = project!.layout.slot(progressSlotId);
    expect(progressLayout, isNotNull);
    expect(progressLayout!.fields, hasLength(_fieldCount));
    expect(
      progressLayout.fields.length - progressSlot.fieldCount,
      _opaqueFieldCount,
      reason: 'fields with no decoded value stay read-only',
    );
    final captionLayout = project.layout.slot(SaveSlotId('slot_00.caption'));
    expect(captionLayout, isNotNull);
    expect(captionLayout!.fields, hasLength(_captionFieldCount));
    stdout.writeln(
      '[e2e] cubit slots: ${ui.slots.length} '
      '(progress layout fields=${progressLayout.fields.length} '
      'decodable=${progressSlot.fieldCount} expected=${progressSlot.expectedLength}; '
      'caption layout fields=${captionLayout.fields.length} '
      'expected=${captionSlot.expectedLength})',
    );

    final progressDocument = project.document(progressSlotId);
    expect(progressDocument, isNotNull);
    final materialized = progressDocument!.snapshot.materialize();
    expect(materialized, orderedEquals(_cliProgress));
    _expectProgressStructure(materialized, label: 'cubit progress snapshot');
    _expectProgressStructure(
      File('${_cliRoot.path}/slot_00/progress.sav').readAsBytesSync(),
      label: 'on-disk progress.sav',
    );
    stdout.writeln(
      '[e2e] cubit snapshot == CLI progress.sav (${materialized.length}B, '
      'fnv1a32=${Fnv1a.hex32(Fnv1a.hash32(materialized))})',
    );

    final captionDocument = project.document(SaveSlotId('slot_00.caption'));
    expect(captionDocument, isNotNull);
    final captionBytes = captionDocument!.snapshot.materialize();
    expect(captionBytes, orderedEquals(_cliCaption));
    _expectCaptionStructure(
      captionBytes,
      jpegLength: 633,
      label: 'cubit caption snapshot',
    );
    stdout.writeln(
      '[e2e] cubit caption == CLI caption.sav (${captionBytes.length}B) '
      'scene=KokiriForest map=KokiriForest/KokiriForest_Child',
    );
  });
}

/// Runs the production CLI against [outRoot] from the repository root.
Future<ProcessResult> _runCli(
  String outRoot, [
  List<String> extra = const <String>[],
]) {
  return Process.run('dart', <String>[
    'run',
    'tool/create_save.dart',
    '--out',
    outRoot,
    ...extra,
  ], workingDirectory: Directory.current.path);
}

/// Builds the cubit exactly as `lib/main.dart` does.
SaveSessionCubit _buildCubit(GameDataSchema schema) {
  final engine = createProgressEngine();
  final resolver = ProgressLayoutResolver(ProgressLayoutBuilder(schema));
  return SaveSessionCubit(
    engine: engine,
    repository: FileSaveRepository(
      engine: engine,
      resolveLayout: resolver.call,
    ),
    resolveLayout: resolver.call,
  );
}

/// Reads [path], or returns an empty buffer so the caller's assertions fail
/// with a measured value instead of a read error.
Uint8List _readIfPresent(String path) {
  final file = File(path);
  return file.existsSync() ? file.readAsBytesSync() : Uint8List(0);
}

/// The dialog's visible error text, or `(none)`.
String _dialogErrorText(WidgetTester tester) {
  final finder = find.byKey(const Key('new-save-error'));
  if (finder.evaluate().isEmpty) {
    return '(no new-save-error panel)';
  }
  return tester
      .widgetList<Text>(
        find.descendant(of: finder, matching: find.byType(Text)),
      )
      .map((text) => text.data ?? '')
      .join(' | ');
}

/// Asserts the `progress.sav` container: header, record table, tail and trailer.
void _expectProgressStructure(Uint8List bytes, {required String label}) {
  expect(bytes.length, _progressLength, reason: '$label length');
  expect(
    bytes.sublist(0, 4),
    ProgressLayout.magicBytes,
    reason: '$label magic 04 03 02 01',
  );
  expect(_u32(bytes, ProgressLayout.magicOffset), 0x01020304);
  expect(
    _u32(bytes, ProgressLayout.revisionOffset),
    2982123,
    reason: '$label revision',
  );
  final dataOffset = _u32(bytes, ProgressLayout.dataOffsetFieldOffset);
  expect(dataOffset, 0x175D8, reason: '$label tail/data offset');
  expect(
    bytes.sublist(
      ProgressLayout.reservedOffset,
      ProgressLayout.reservedOffset + ProgressLayout.reservedLength,
    ),
    List<int>.filled(ProgressLayout.reservedLength, 0),
    reason: '$label reserved 0x0C..0x27 must be zero',
  );

  // Record table measured from raw bytes, independently of the codec.
  final recordCount =
      (dataOffset - ProgressLayout.recordStart) ~/ ProgressLayout.recordSize;
  expect(recordCount, _recordCount);
  var fieldRecords = 0;
  final sentinelIds = <int>[];
  var footerKey = -1;
  var footerValue = -1;
  for (var index = 0; index < recordCount; index++) {
    final offset =
        ProgressLayout.recordStart + index * ProgressLayout.recordSize;
    final key = _u32(bytes, offset);
    final value = _u32(bytes, offset + ProgressLayout.valueWordSize);
    if (index == recordCount - 1) {
      footerKey = key;
      footerValue = value;
    } else if (key == 0 && value >= 1 && value <= _sentinelCount) {
      sentinelIds.add(value);
    } else {
      fieldRecords++;
    }
  }
  expect(sentinelIds, List<int>.generate(_sentinelCount, (index) => index + 1));
  expect(fieldRecords, _fieldCount);
  expect(footerKey, 0xA3DB7114);
  expect(footerValue, 0x01D6F4);
  expect(
    footerValue,
    bytes.length - 8,
    reason: '$label footer value must be length - 8',
  );
  expect(
    bytes.sublist(bytes.length - 8),
    List<int>.filled(8, 0),
    reason: '$label final 8 bytes must be zero',
  );

  // The codec agrees with the raw measurement.
  final decoded = ProgressCodec.decode(bytes);
  expect(decoded, isA<ProgressDecodeOk>(), reason: '$label decode: $decoded');
  final save = (decoded as ProgressDecodeOk).save;
  expect(save.length, _progressLength);
  expect(save.revision, 2982123);
  expect(save.dataOffset, 0x175D8);
  expect(save.recordCount, _recordCount);
  expect(save.fieldCount, _fieldCount);
  expect(save.sentinels, hasLength(_sentinelCount));
  expect(
    save.sentinels.map((sentinel) => sentinel.rawValue).toList(),
    List<int>.generate(_sentinelCount, (index) => index + 1),
  );
  expect(
    save.sentinels.every((sentinel) => sentinel.key == 0),
    isTrue,
    reason: '$label every sentinel key is 0',
  );
  expect(save.footer.key, 0xA3DB7114);
  expect(save.footer.rawValue, 0x01D6F4);
  expect(save.sections, hasLength(_sentinelCount));

  // The tail tiles [dataOffset, EOF) with no gap or overlap. The final inferred
  // span runs to EOF, so the 8-byte zero trailer checked above lies inside it.
  final spans = <({int start, int end})>[
    for (final record in save.records)
      if (record.dataOffset != null)
        (
          start: record.dataOffset!,
          end: record.dataOffset! + record.dataLength,
        ),
  ]..sort((a, b) => a.start.compareTo(b.start));
  expect(spans, isNotEmpty);
  expect(spans.first.start, dataOffset);
  var cursor = dataOffset;
  for (final span in spans) {
    expect(
      span.start,
      cursor,
      reason:
          '$label tail gap/overlap at 0x'
          '${cursor.toRadixString(16)} -> 0x${span.start.toRadixString(16)}',
    );
    cursor = span.end;
  }
  expect(
    cursor,
    bytes.length,
    reason: '$label tail must run contiguously from 0x175D8 to EOF',
  );

  stdout.writeln(
    '[e2e] $label: magic=04030201 revision=2982123 dataOffset=0x175d8 '
    'reservedZero=yes records=$recordCount fields=$fieldRecords '
    'sentinels=$_sentinelCount/1..32 footer=0xa3db7114/120564 '
    'tailSpans=${spans.length} tail=0x175d8..0x${cursor.toRadixString(16)} '
    'trailerZero=yes',
  );
}

/// Asserts the `caption.sav` container and its decoded scene/map.
void _expectCaptionStructure(
  Uint8List bytes, {
  required int jpegLength,
  required String label,
}) {
  expect(
    bytes.length,
    CaptionLayout.jpegOffset + jpegLength,
    reason: '$label length',
  );
  expect(_u32(bytes, CaptionLayout.magicOffset), CaptionLayout.magicValue);
  expect(
    _u32(bytes, CaptionLayout.layoutCheckOffset),
    CaptionLayout.layoutCheckValue,
  );
  expect(
    bytes.sublist(
      CaptionLayout.sceneNameOffset,
      CaptionLayout.sceneNameOffset + 12,
    ),
    'KokiriForest'.codeUnits,
  );
  expect(bytes[CaptionLayout.sceneNameOffset + 12], 0);

  final decoded = CaptionCodec.decode(bytes);
  expect(decoded, isA<CaptionDecodeOk>(), reason: '$label decode: $decoded');
  final save = (decoded as CaptionDecodeOk).save;
  expect(save.sceneName, 'KokiriForest');
  expect(save.mapPath, 'KokiriForest/KokiriForest_Child');
  expect(save.jpegLength, jpegLength);
  expect(save.savedAt.year, 2026);
  expect(save.savedAt.month, 1);
  expect(save.savedAt.day, 1);
  stdout.writeln(
    '[e2e] $label: scene=${save.sceneName} map=${save.mapPath} '
    'jpeg=${save.jpegLength}B savedAt=${save.savedAt.year}-'
    '${save.savedAt.month}-${save.savedAt.day}',
  );
}

/// The little-endian `u32` at [offset].
int _u32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

/// FNV-1a 64, a second fingerprint beside the production FNV-1a 32.
///
/// Dart's 64-bit `int` is signed, so the digest is rendered nibble by nibble
/// instead of with `toRadixString`, which would print a minus sign.
String _fnv1a64(Uint8List bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash *= 0x100000001b3;
  }
  final buffer = StringBuffer('0x');
  for (var shift = 60; shift >= 0; shift -= 4) {
    buffer.write(((hash >> shift) & 0xf).toRadixString(16));
  }
  return buffer.toString();
}
