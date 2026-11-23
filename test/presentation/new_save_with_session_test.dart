import 'dart:io';

import 'package:bomb_flower/data/newsave/new_save_writer.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/engine/ports.dart';
import 'package:bomb_flower/domain/engine/save_engine.dart';
import 'package:bomb_flower/domain/newsave/new_save_builder.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_ui_state.dart';
import 'package:bomb_flower/presentation/bloc/shell/shell_cubit.dart';
import 'package:bomb_flower/presentation/dialogs/new_save_dialog.dart';
import 'package:bomb_flower/presentation/shell/app_shell.dart';
// The repository port uses the domain BackupPolicy; the settings store has its
// own enum of the same name and is only imported for InMemorySettingsStore.
import 'package:bomb_flower/presentation/shell/tabs/settings_tab.dart'
    hide BackupPolicy;
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/core/fixtures.dart';
import '../integration/support/progress_chain.dart';
import '../support/temp_roots.dart';
import 'dialogs/dialog_test_support.dart';

/// The folder the first project is "opened" from; never touches disk.
const String _openRoot = '/save';

/// Writes a marker pair into the destination, like the real writer, and records
/// every attempt. No save bytes are involved: this test is about the flow.
final class _FakePersist {
  _FakePersist({Set<int> failCalls = const <int>{}})
    : failCalls = <int>{...failCalls};

  /// 1-based call numbers that fail as a non-empty destination. Mutable so a
  /// test can arm it after construction.
  final Set<int> failCalls;
  final List<String> calls = <String>[];

  Future<NewSaveWriteResult> call({
    required String rootDirectory,
    required NewSaveBuild build,
    bool allowOverwrite = false,
  }) async {
    calls.add(rootDirectory);
    if (failCalls.contains(calls.length)) {
      throw const NewSaveWriteException(
        NewSaveWriteException.destinationNotEmpty,
        'non-empty',
      );
    }
    final slot = Directory('$rootDirectory/slot_00')
      ..createSync(recursive: true);
    File('${slot.path}/progress.sav').writeAsBytesSync(<int>[1, 2, 3, 4]);
    File('${slot.path}/caption.sav').writeAsBytesSync(<int>[5, 6]);
    return NewSaveWriteResult(
      rootDirectory: rootDirectory,
      progressPath: '${slot.path}/progress.sav',
      captionPath: '${slot.path}/caption.sav',
      progressLength: 4,
      captionLength: 2,
      progressFingerprint: Fnv1a.hash32(<int>[1, 2, 3, 4]),
      captionFingerprint: Fnv1a.hash32(<int>[5, 6]),
    );
  }
}

/// The project as the real repository returns it after a successful write:
/// the current bytes become the new saved baseline, so it is no longer dirty.
SaveProject _markSaved(SaveProject project) {
  return SaveProject(
    project.projectId,
    project.rootPath,
    project.backupPath,
    project.layout,
    project.detectedVersion,
    project.originals,
    project.documents,
    <SaveSlotId, int>{
      for (final entry in project.documents.entries)
        entry.key: entry.value.snapshot.fingerprint,
    },
    project.history,
    project.editLog,
    savedSnapshots: <SaveSlotId, SaveSnapshot>{
      for (final entry in project.documents.entries)
        entry.key: entry.value.snapshot,
    },
    preserveUnknown: project.preserveUnknown,
  );
}

/// Serves one parsed project per root path, so a real open swaps the project.
final class _PerPathRepository implements SaveRepository {
  _PerPathRepository(this._engine, this._layout);

  final SaveEngine _engine;
  final LayoutDescriptor _layout;
  final List<String> openedAt = <String>[];
  int writeExportCalls = 0;
  bool failExport = false;

  @override
  Future<ParseResult> open(
    String rootPath, {
    bool preserveUnknown = true,
    bool verifyIntegrity = true,
  }) async {
    openedAt.add(rootPath);
    return _engine.parse(
      rootPath: rootPath,
      files: testFiles(layout: _layout),
      layout: _layout,
      detectedVersion: 7,
    );
  }

  @override
  Future<void> ensureOriginalBackup(
    SaveProject project,
    BackupPolicy policy,
  ) async {}

  @override
  Future<ExportResult> writeExport(
    ExportPlan plan, {
    bool allowOverwrite = false,
  }) async {
    writeExportCalls++;
    if (failExport) {
      throw StateError('injected export failure');
    }
    return ExportResult(
      succeeded: true,
      project: _markSaved(plan.project),
      writtenPaths: <SaveSlotId, String>{
        for (final entry in plan.writes.entries)
          entry.key: '${plan.destinationRoot}/${entry.key.value}',
      },
      fingerprints: <SaveSlotId, int>{
        for (final entry in plan.writes.entries)
          entry.key: entry.value.fingerprint,
      },
    );
  }

  @override
  Future<SaveProject> reset(
    SaveProject project,
    SaveSlotId slot, {
    bool clearHistory = false,
  }) async => project;

  @override
  Future<ExportResult> duplicate(
    SaveProject project,
    SaveSlotId slot, {
    required String destinationRoot,
    BackupPolicy policy = BackupPolicy.standard,
    bool allowOverwrite = false,
  }) async {
    throw UnimplementedError();
  }
}

/// One open session plus the seams the shell needs.
final class _Harness {
  _Harness(this.cubit, this.repository, this.persist);

  final SaveSessionCubit cubit;
  final _PerPathRepository repository;
  final _FakePersist persist;

  /// Paths the shell asked to open through the ordinary open path.
  final List<String> opened = <String>[];

  /// Paths it asked to open through the discard-aware path.
  final List<String> openedDiscarding = <String>[];

  String? get openRoot => cubit.openProject?.rootPath;

  bool get isDirty => cubit.openProject?.dirty.hasUnsavedChanges ?? false;
}

Future<_Harness> _openSession(
  WidgetTester tester,
  GameDataSchema schema,
) async {
  final layout = testLayout(includeUnverified: false);
  final engine = SaveEngine(testFormat(includeUnverified: false));
  final repository = _PerPathRepository(engine, layout);
  final cubit = SaveSessionCubit(
    engine: engine,
    repository: repository,
    resolveLayout: (path) async => LayoutResolved(LayoutSelection(layout, 7)),
  );
  addTearDown(() async {
    if (!cubit.isClosed) {
      await cubit.close(force: true);
    }
  });
  await cubit.openPath(_openRoot);
  expect(cubit.openProject, isNotNull, reason: 'fixture must open');
  final persist = _FakePersist();
  final harness = _Harness(cubit, repository, persist);

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1360, 880);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ShellCubit>(
            create: (_) => ShellCubit(windowChromeEnabled: false),
          ),
          BlocProvider<SaveSessionCubit>.value(value: cubit),
        ],
        child: AppShell(
          settingsStore: InMemorySettingsStore(),
          newSaveSchemaLoader: () async => schema,
          newSavePersist: persist.call,
          newSaveDirectoryPicker: FakeDirectoryPicker(),
          onOpenPath: (String path) async {
            harness.opened.add(path);
            await cubit.openPath(path);
          },
          onOpenPathDiscardingUnsavedChanges: (String path) async {
            harness.openedDiscarding.add(path);
            await cubit.openPath(path, discardUnsavedChanges: true);
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

/// Drives the real shell: title-bar action, destination, Create, then the
/// success panel's own "Open this save" action.
Future<void> _createAt(WidgetTester tester, String root) async {
  await tester.tap(find.byKey(const Key('shell-action-new-save')));
  await tester.pumpAndSettle();
  // Defect 1: the destination must never start as the save already open.
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('new-save-root')))
        .controller!
        .text,
    isEmpty,
    reason: 'the open save folder must not be pre-filled',
  );
  await tester.enterText(find.byKey(const Key('new-save-root')), root);
  await tester.tap(find.byKey(const Key('new-save-create')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('new-save-success')), findsOneWidget);
  await tester.tap(find.byKey(const Key('new-save-open')));
  await tester.pumpAndSettle();
}

void _makeDirty(_Harness harness) {
  harness.cubit.edit(SetScalar(healthId, 42));
  expect(harness.isDirty, isTrue, reason: 'the fixture edit must dirty it');
}

void main() {
  late GameDataSchema schema;

  setUpAll(() async {
    schema = await loadGameDataSchema();
  });

  testWidgets('a clean session creates into a fresh folder and opens it', (
    tester,
  ) async {
    final root = createTempRoot('new_save_session');
    addTearDown(() => removeTempRoot(root));
    final harness = await _openSession(tester, schema);
    expect(harness.isDirty, isFalse);

    await _createAt(tester, root.path);

    expect(harness.persist.calls, <String>[root.path]);
    expect(harness.opened, <String>[root.path]);
    expect(harness.openedDiscarding, isEmpty);
    expect(harness.openRoot, root.path);
    expect(
      File('${root.path}/slot_00/progress.sav').existsSync(),
      isTrue,
      reason: 'the created save is a real artifact',
    );
    expect(find.byType(NewSaveDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel keeps the dirty project and says where the save went', (
    tester,
  ) async {
    final root = createTempRoot('new_save_session');
    addTearDown(() => removeTempRoot(root));
    final harness = await _openSession(tester, schema);
    _makeDirty(harness);

    await _createAt(tester, root.path);
    // The shell asks before losing the edits; Cancel is the safe default.
    expect(find.byKey(const Key('unsaved-cancel')), findsOneWidget);
    await tester.tap(find.byKey(const Key('unsaved-cancel')));
    await tester.pumpAndSettle();

    expect(harness.opened, isEmpty);
    expect(harness.openedDiscarding, isEmpty);
    expect(harness.openRoot, _openRoot, reason: 'the old save stays open');
    expect(harness.isDirty, isTrue, reason: 'no edit may be lost');
    expect(
      File('${root.path}/slot_00/progress.sav').existsSync(),
      isTrue,
      reason: 'the created save is a real artifact even when open is cancelled',
    );
    expect(
      find.textContaining('New save written to ${root.path}'),
      findsOneWidget,
      reason: 'the user must be told where the files are',
    );
    expect(find.textContaining('is unchanged'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Let the toast timer fire so nothing is left pending.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('discard opens the new save and drops the old project', (
    tester,
  ) async {
    final root = createTempRoot('new_save_session');
    addTearDown(() => removeTempRoot(root));
    final harness = await _openSession(tester, schema);
    _makeDirty(harness);

    await _createAt(tester, root.path);
    await tester.tap(find.byKey(const Key('unsaved-discard')));
    await tester.pumpAndSettle();

    expect(harness.openedDiscarding, <String>[root.path]);
    expect(harness.opened, isEmpty);
    expect(
      harness.openRoot,
      root.path,
      reason: 'discarding must actually open the created save',
    );
    expect(harness.isDirty, isFalse);
    expect(harness.repository.openedAt, contains(root.path));
    expect(tester.takeException(), isNull);
  });

  testWidgets('save writes the current project, then opens the new save', (
    tester,
  ) async {
    final root = createTempRoot('new_save_session');
    addTearDown(() => removeTempRoot(root));
    final harness = await _openSession(tester, schema);
    _makeDirty(harness);

    await _createAt(tester, root.path);
    await tester.tap(find.byKey(const Key('unsaved-save')));
    await tester.pumpAndSettle();

    expect(harness.repository.writeExportCalls, 1);
    expect(harness.opened, <String>[root.path]);
    expect(harness.openedDiscarding, isEmpty);
    expect(harness.openRoot, root.path);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed save refuses to open and says the new path', (
    tester,
  ) async {
    final root = createTempRoot('new_save_session');
    addTearDown(() => removeTempRoot(root));
    final harness = await _openSession(tester, schema);
    _makeDirty(harness);
    harness.repository.failExport = true;

    await _createAt(tester, root.path);
    await tester.tap(find.byKey(const Key('unsaved-save')));
    await tester.pumpAndSettle();

    expect(harness.repository.writeExportCalls, 1);
    expect(
      harness.opened,
      isEmpty,
      reason: 'a save that failed must not be followed by an open',
    );
    expect(harness.openRoot, _openRoot);
    expect(harness.isDirty, isTrue);
    expect(
      find.textContaining('could not be saved'),
      findsOneWidget,
      reason: 'the failure must be surfaced, not swallowed',
    );
    expect(
      find.textContaining('The new save is at ${root.path}'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('the open save folder is refused before anything is written', (
    tester,
  ) async {
    final harness = await _openSession(tester, schema);

    for (final destination in <String>[
      _openRoot,
      '$_openRoot/',
      '/tmp/../save',
    ]) {
      await tester.tap(find.byKey(const Key('shell-action-new-save')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('new-save-root')),
        destination,
      );
      await tester.tap(find.byKey(const Key('new-save-create')));
      await tester.pumpAndSettle();

      expect(
        find.text(NewSaveDialog.reservedRootError),
        findsOneWidget,
        reason:
            'destination $destination must be refused with the specific text',
      );
      expect(find.byKey(const Key('new-save-success')), findsNothing);
      expect(
        harness.persist.calls,
        isEmpty,
        reason: 'nothing may be written for $destination',
      );

      await tester.tap(find.byKey(const Key('new-save-cancel')));
      await tester.pumpAndSettle();
    }
    expect(harness.opened, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('openPath refuses a dirty project unless the caller opts in', () async {
    final layout = testLayout(includeUnverified: false);
    final engine = SaveEngine(testFormat(includeUnverified: false));
    final repository = _PerPathRepository(engine, layout);
    final cubit = SaveSessionCubit(
      engine: engine,
      repository: repository,
      resolveLayout: (path) async => LayoutResolved(LayoutSelection(layout, 7)),
    );
    addTearDown(() async {
      if (!cubit.isClosed) {
        await cubit.close(force: true);
      }
    });
    await cubit.openPath(_openRoot);
    cubit.edit(SetScalar(healthId, 42));
    expect(cubit.openProject!.dirty.hasUnsavedChanges, isTrue);

    // The default every other caller uses: refused, nothing opened.
    await cubit.openPath('/somewhere-else');
    expect(cubit.state, isA<SaveSessionError>());
    expect(cubit.openProject!.rootPath, _openRoot);
    expect(repository.openedAt, <String>[_openRoot]);

    // The one opt-in the new-save discard branch passes: opens.
    await cubit.openPath('/somewhere-else', discardUnsavedChanges: true);
    expect(cubit.openProject!.rootPath, '/somewhere-else');
    expect(repository.openedAt, <String>[_openRoot, '/somewhere-else']);
  });

  testWidgets('a non-empty destination still asks before replacing', (
    tester,
  ) async {
    final root = createTempRoot('new_save_session');
    addTearDown(() => removeTempRoot(root));
    final harness = await _openSession(tester, schema);
    harness.persist.failCalls.add(1);

    await tester.tap(find.byKey(const Key('shell-action-new-save')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-save-root')), root.path);
    await tester.tap(find.byKey(const Key('new-save-create')));
    await tester.pumpAndSettle();

    expect(find.text('Replace the existing slot_00?'), findsOneWidget);
    expect(harness.persist.calls, hasLength(1));

    // Keeping the existing files writes nothing: no retry with overwrite.
    await tester.tap(find.text('Keep existing files'));
    await tester.pumpAndSettle();

    expect(harness.persist.calls, hasLength(1));
    expect(find.byKey(const Key('new-save-info')), findsOneWidget);
    expect(find.byKey(const Key('new-save-success')), findsNothing);
    expect(harness.opened, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
