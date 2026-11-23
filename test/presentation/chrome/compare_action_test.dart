import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/engine/engine.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/dialogs/compare_save_dialog.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/chrome/file_action_bar.dart';
import 'package:bomb_flower/presentation/widgets/controls/control_icon_button.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/core/fixtures.dart';

/// Mirrors the repository fake used by the title-bar action tests.
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
    resolveLayout: (path) async =>
        LayoutResolved(LayoutSelection(project.layout, 7)),
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

/// Pumps the action group alone, with a session only when one is supplied.
Future<void> pumpFileBar(
  WidgetTester tester, {
  SaveSessionCubit? cubit,
  Size size = const Size(1360, 880),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  Widget bar = const FileActionBar(
    onOpen: null,
    onSave: null,
    onSaveAs: null,
    onDuplicate: null,
    onReset: null,
    onUndo: null,
    onRedo: null,
  );
  if (cubit != null) {
    bar = BlocProvider<SaveSessionCubit>.value(value: cubit, child: bar);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      home: Scaffold(body: Center(child: bar)),
    ),
  );
  await tester.pump();
}

/// The icon button behind the comparison action key.
ControlIconButton compareButton(WidgetTester tester) {
  return tester.widget<ControlIconButton>(
    find.descendant(
      of: find.byKey(const Key('shell-action-compare')),
      matching: find.byType(ControlIconButton),
    ),
  );
}

void main() {
  testWidgets('no session renders the compare action disabled', (tester) async {
    await pumpFileBar(tester);

    expect(find.byKey(const Key('shell-action-compare')), findsOneWidget);
    final button = compareButton(tester);
    expect(button.onPressed, isNull);
    expect(button.tooltip, 'Compare original and edited save');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a clean open project leaves compare disabled', (tester) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');

    await pumpFileBar(tester, cubit: harness.cubit);

    expect(compareButton(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dirty project enables compare and opens the dialog', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');
    harness.cubit.edit(const SetScalar(healthId, 42));

    await pumpFileBar(tester, cubit: harness.cubit);

    expect(compareButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('shell-action-compare')));
    await tester.pumpAndSettle();

    expect(find.byType(CompareSaveDialog), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('compare-close')));
    await tester.pumpAndSettle();
  });

  testWidgets('the collapsed overflow menu carries compare too', (
    tester,
  ) async {
    final harness = buildCubit();
    disposeCubit(harness.cubit);
    await harness.cubit.openPath('/save');
    harness.cubit.edit(const SetScalar(healthId, 42));

    await pumpFileBar(
      tester,
      cubit: harness.cubit,
      size: const Size(1100, 700),
    );

    expect(find.byKey(const Key('shell-action-overflow')), findsOneWidget);
    expect(find.byKey(const Key('shell-action-compare')), findsNothing);

    await tester.tap(find.byKey(const Key('shell-action-overflow')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('shell-action-compare')), findsOneWidget);
  });
}
