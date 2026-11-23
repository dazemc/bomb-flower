import 'package:bomb_flower/data/system/directory_lister.dart';
import 'package:bomb_flower/data/system/directory_picker.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/engine/engine.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/dialogs/open_save_dialog.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/chrome/app_title_bar.dart';
import 'package:bomb_flower/presentation/widgets/controls/control_icon_button.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/core/fixtures.dart';
import '../dialogs/dialog_test_support.dart';

/// Every action key, in title-bar order.
const List<String> actionKeys = <String>[
  'shell-action-open',
  'shell-action-save',
  'shell-action-save-as',
  'shell-action-duplicate',
  'shell-action-reset',
  'shell-action-undo',
  'shell-action-redo',
];

final class FakeSaveRepository implements SaveRepository {
  FakeSaveRepository(this.project);

  SaveProject project;

  @override
  Future<ParseResult> open(
    String rootPath, {
    bool preserveUnknown = true,
    bool verifyIntegrity = true,
  }) async {
    return ParseOk(project);
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
    return ExportResult(
      succeeded: true,
      project: plan.project,
      writtenPaths: <SaveSlotId, String>{
        for (final entry in plan.writes.entries)
          entry.key:
              '${plan.destinationRoot}/'
              '${plan.project.layout.slot(entry.key)!.relativePath}',
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
  }) async {
    return project;
  }

  @override
  Future<ExportResult> duplicate(
    SaveProject project,
    SaveSlotId slot, {
    required String destinationRoot,
    BackupPolicy policy = BackupPolicy.standard,
    bool allowOverwrite = false,
  }) async {
    return ExportResult(
      succeeded: true,
      writtenPaths: <SaveSlotId, String>{
        slot: '$destinationRoot/slot_00/progress.sav',
      },
      fingerprints: <SaveSlotId, int>{slot: 7},
      project: project,
    );
  }
}

/// A live cubit over the shared synthetic layout.
({SaveSessionCubit cubit, FakeSaveRepository repository}) buildCubit() {
  final layout = testLayout(includeUnverified: false);
  final engine = SaveEngine(testFormat(includeUnverified: false));
  final result = engine.parse(
    rootPath: '/save',
    files: testFiles(layout: layout),
    layout: layout,
    detectedVersion: 7,
  );
  final project = switch (result) {
    ParseOk(:final project) => project,
    _ => throw StateError('Fixture did not open'),
  };
  final repository = FakeSaveRepository(project);
  final cubit = SaveSessionCubit(
    engine: engine,
    repository: repository,
    resolveLayout: (path) async => LayoutSelection(project.layout, 7),
  );
  return (cubit: cubit, repository: repository);
}

void disposeCubit(SaveSessionCubit cubit) {
  addTearDown(() async {
    if (!cubit.isClosed) {
      await cubit.close(force: true);
    }
  });
}

/// Pumps the bar in a themed app at [size], with the cubit provided from above
/// exactly as `AppShell` sees it in production.
Future<void> pumpTitleBar(
  WidgetTester tester, {
  SaveSessionCubit? cubit,
  Size size = const Size(1360, 880),
  SaveFolderProbe? probe,
  RecentPathsStore? recentPaths,
  DirectoryLister? directoryLister,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  Widget bar = AppTitleBar(
    interactive: false,
    saveName: 'slot_00',
    saveFolderProbe: probe ?? FakeSaveFolderProbe(),
    recentPaths: recentPaths ?? FakeRecentPathsStore(),
    directoryLister: directoryLister ?? FakeDirectoryLister(),
  );
  if (cubit != null) {
    bar = BlocProvider<SaveSessionCubit>.value(value: cubit, child: bar);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      home: Scaffold(
        body: Column(children: <Widget>[bar]),
      ),
    ),
  );
  await tester.pump();
}

/// Taps [finder] and lets the title bar's ancestor double-tap recognizer lose
/// the gesture arena before settling.
Future<void> tapAction(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// The icon button behind one action key.
ControlIconButton buttonFor(WidgetTester tester, String key) {
  return tester.widget<ControlIconButton>(
    find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(ControlIconButton),
    ),
  );
}

void main() {
  testWidgets('exposes all seven actions with a project open', (tester) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');

    await pumpTitleBar(tester, cubit: harness.cubit);

    for (final key in actionKeys) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(find.byKey(const Key('file-action-bar')), findsOneWidget);
    expect(find.byKey(const Key('shell-action-overflow')), findsNothing);
  });

  testWidgets('no session disables every action with the open reason', (
    tester,
  ) async {
    await pumpTitleBar(tester);

    for (final key in actionKeys) {
      final button = buttonFor(tester, key);
      expect(button.onPressed, isNull, reason: key);
      expect(button.tooltip, contains('Open a save first'), reason: key);
    }
  });

  testWidgets('a closed session keeps Open reachable and disables the rest', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);

    await pumpTitleBar(tester, cubit: harness.cubit);

    expect(buttonFor(tester, 'shell-action-open').onPressed, isNotNull);
    for (final key in actionKeys.skip(1)) {
      expect(buttonFor(tester, key).onPressed, isNull, reason: key);
    }
  });

  testWidgets('Save is disabled while clean and enabled after an edit', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');

    await pumpTitleBar(tester, cubit: harness.cubit);

    expect(buttonFor(tester, 'shell-action-save').onPressed, isNull);
    expect(buttonFor(tester, 'shell-action-save').tooltip, 'Save');

    harness.cubit.edit(const SetScalar(healthId, 42));
    await tester.pumpAndSettle();

    expect(buttonFor(tester, 'shell-action-save').onPressed, isNotNull);
  });

  testWidgets('Undo and Redo follow the edit history', (tester) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');
    harness.cubit.edit(const SetScalar(healthId, 42));

    await pumpTitleBar(tester, cubit: harness.cubit);

    expect(buttonFor(tester, 'shell-action-undo').onPressed, isNotNull);
    expect(buttonFor(tester, 'shell-action-redo').onPressed, isNull);

    await tapAction(tester, find.byKey(const Key('shell-action-undo')));

    expect(buttonFor(tester, 'shell-action-undo').onPressed, isNull);
    expect(buttonFor(tester, 'shell-action-redo').onPressed, isNotNull);
  });

  testWidgets('Open shows the open-save dialog and cancels cleanly', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');
    final probe = FakeSaveFolderProbe();
    final recentPaths = FakeRecentPathsStore();
    final lister = FakeDirectoryLister();

    await pumpTitleBar(
      tester,
      cubit: harness.cubit,
      probe: probe,
      recentPaths: recentPaths,
      directoryLister: lister,
    );

    await tapAction(tester, find.byKey(const Key('shell-action-open')));

    expect(find.byType(OpenSaveDialog), findsOneWidget);
    expect(lister.calls, isNotEmpty);

    await tapAction(tester, find.byKey(const Key('open-save-cancel')));

    expect(find.byType(OpenSaveDialog), findsNothing);
  });

  testWidgets('collapses into one overflow trigger below the breakpoint', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');

    await pumpTitleBar(
      tester,
      cubit: harness.cubit,
      size: const Size(1100, 700),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('file-action-bar')), findsOneWidget);
    expect(find.byKey(const Key('shell-action-overflow')), findsOneWidget);

    await tapAction(tester, find.byKey(const Key('shell-action-overflow')));

    expect(tester.takeException(), isNull);
    for (final key in actionKeys) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
  });
}
