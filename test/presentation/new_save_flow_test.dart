import 'dart:io';

import 'package:bomb_flower/data/newsave/new_save_writer.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/newsave/new_save_builder.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:bomb_flower/presentation/bloc/shell/shell_cubit.dart';
import 'package:bomb_flower/presentation/dialogs/new_save_dialog.dart';
import 'package:bomb_flower/presentation/shell/app_shell.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../integration/support/progress_chain.dart';
import 'dialogs/dialog_test_support.dart';

final class _PersistCall {
  const _PersistCall(this.rootDirectory, this.build, this.allowOverwrite);

  final String rootDirectory;
  final NewSaveBuild build;
  final bool allowOverwrite;
}

/// Records every persist attempt; selected call numbers fail as non-empty.
final class _FakeNewSavePersist {
  _FakeNewSavePersist({this.failCalls = const <int>{}});

  final Set<int> failCalls;
  final List<_PersistCall> calls = <_PersistCall>[];

  Future<NewSaveWriteResult> call({
    required String rootDirectory,
    required NewSaveBuild build,
    bool allowOverwrite = false,
  }) async {
    calls.add(_PersistCall(rootDirectory, build, allowOverwrite));
    if (failCalls.contains(calls.length)) {
      throw const NewSaveWriteException(
        NewSaveWriteException.destinationNotEmpty,
        'non-empty',
      );
    }
    return NewSaveWriteResult(
      rootDirectory: rootDirectory,
      progressPath: '$rootDirectory/slot_00/progress.sav',
      captionPath: '$rootDirectory/slot_00/caption.sav',
      progressLength: build.progressBytes.length,
      captionLength: build.captionBytes.length,
      progressFingerprint: Fnv1a.hash32(build.progressBytes),
      captionFingerprint: Fnv1a.hash32(build.captionBytes),
    );
  }
}

String _tempTarget(String label) =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'bomb_flower_newsave_flow_${label}_'
    '${DateTime.now().microsecondsSinceEpoch}';

void _deleteTempTree(Directory directory) {
  if (!directory.existsSync()) {
    return;
  }
  final prefix =
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'bomb_flower_newsave_flow_';
  if (!directory.path.startsWith(prefix)) {
    fail('refusing to delete non-temp path ${directory.path}');
  }
  directory.deleteSync(recursive: true);
}

/// Mounts the real shell directly (not through [BombFlowerApp]) with the
/// new-save seams injected. No save session is provided, so the shell reads no
/// project; the fake writer means no test touches disk.
Future<void> _pumpShell(
  WidgetTester tester, {
  required GameDataSchema schema,
  required _FakeNewSavePersist persist,
  Future<void> Function(String path)? onOpenPath,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1360, 880);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      home: BlocProvider<ShellCubit>(
        create: (_) => ShellCubit(windowChromeEnabled: false),
        child: AppShell(
          newSaveSchemaLoader: () async => schema,
          newSavePersist: persist.call,
          newSaveDirectoryPicker: FakeDirectoryPicker(),
          onOpenPath: onOpenPath,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late GameDataSchema schema;

  setUpAll(() async {
    schema = await loadGameDataSchema();
  });

  testWidgets('creates the schema-default save and the produced bytes reopen', (
    tester,
  ) async {
    final root = _tempTarget('create');
    final persist = _FakeNewSavePersist();
    final launch = await launchDialog<NewSaveOutcome>(
      tester,
      (context) => NewSaveDialog.show(
        context,
        schemaLoader: () async => schema,
        persist: persist.call,
        directoryPicker: FakeDirectoryPicker(),
        initialRoot: root,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-save-never-loaded')), findsOneWidget);
    expect(
      find.text('A created save has never been loaded by the game'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('new-save-slot')), findsOneWidget);
    expect(
      find.textContaining('slot_00 (fixed by the format builder)'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('new-save-size')), findsOneWidget);
    expect(find.textContaining('120,572'), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-save-create')));
    await tester.pumpAndSettle();

    expect(persist.calls, hasLength(1));
    final call = persist.calls.single;
    expect(call.rootDirectory, root);
    expect(call.allowOverwrite, isFalse);
    expect(call.build.progressBytes.length, 120572);

    expect(find.byKey(const Key('new-save-success')), findsOneWidget);
    expect(find.text('Created slot_00'), findsOneWidget);
    expect(find.text('$root/slot_00/progress.sav'), findsOneWidget);
    expect(find.text('$root/slot_00/caption.sav'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('new-save-written-size'))).data,
      contains('120,572 B'),
    );
    expect(tester.takeException(), isNull);

    final captured = call.build;
    await tester.runAsync(() async {
      final realRoot = Directory.systemTemp.createTempSync(
        'bomb_flower_newsave_flow_',
      );
      addTearDown(() => _deleteTempTree(realRoot));

      final written = await NewSaveWriter().write(
        rootDirectory: realRoot.path,
        build: captured,
      );
      expect(File(written.progressPath).lengthSync(), 120572);
      expect(
        File(written.captionPath).lengthSync(),
        captured.captionBytes.length,
      );

      final repository = createProgressRepository(schema);
      final open = await repository.open(realRoot.path);
      expect(open, anyOf(isA<ParseOk>(), isA<ParseUnverified>()));
      final project = switch (open) {
        ParseOk(:final project) => project,
        ParseUnverified(:final project) => project,
        _ => fail('expected an openable save, got $open'),
      };
      final bytes = project.document(progressSlotId)!.snapshot.materialize();
      expect(bytes, orderedEquals(captured.progressBytes));
    });

    await tester.tap(find.byKey(const Key('new-save-open')));
    await tester.pumpAndSettle();

    final outcome = await launch.future;
    expect(outcome, isNotNull);
    expect(outcome!.rootDirectory, root);
    expect(outcome.progressPath, '$root/slot_00/progress.sav');
    expect(outcome.captionPath, '$root/slot_00/caption.sav');
    expect(outcome.progressLength, 120572);
    expect(outcome.captionLength, captured.captionBytes.length);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('asks before replacing a non-empty destination', (tester) async {
    final root = _tempTarget('overwrite');
    final persist = _FakeNewSavePersist(failCalls: <int>{1, 2});
    await launchDialog<NewSaveOutcome>(
      tester,
      (context) => NewSaveDialog.show(
        context,
        schemaLoader: () async => schema,
        persist: persist.call,
        directoryPicker: FakeDirectoryPicker(),
        initialRoot: root,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('new-save-create')));
    await tester.pumpAndSettle();

    expect(persist.calls, hasLength(1));
    expect(persist.calls.single.allowOverwrite, isFalse);
    expect(find.text('Replace the existing slot_00?'), findsOneWidget);
    expect(find.textContaining('.bak'), findsOneWidget);
    expect(find.text('Replace slot_00'), findsOneWidget);
    expect(find.text('Keep existing files'), findsOneWidget);
    expect(find.byKey(const Key('new-save-success')), findsNothing);

    await tester.tap(find.text('Keep existing files'));
    await tester.pumpAndSettle();

    expect(persist.calls, hasLength(1));
    expect(find.text('Replace the existing slot_00?'), findsNothing);
    expect(find.byKey(const Key('new-save-success')), findsNothing);
    expect(find.byKey(const Key('new-save-info')), findsOneWidget);
    expect(find.byKey(const Key('new-save-create')), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-save-create')));
    await tester.pumpAndSettle();

    expect(persist.calls, hasLength(2));
    expect(find.text('Replace the existing slot_00?'), findsOneWidget);

    await tester.tap(find.text('Replace slot_00'));
    await tester.pumpAndSettle();

    expect(persist.calls, hasLength(3));
    expect(persist.calls[2].allowOverwrite, isTrue);
    expect(find.byKey(const Key('new-save-success')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a blank destination is rejected without persisting', (
    tester,
  ) async {
    final persist = _FakeNewSavePersist();
    await launchDialog<NewSaveOutcome>(
      tester,
      (context) => NewSaveDialog.show(
        context,
        schemaLoader: () async => schema,
        persist: persist.call,
        directoryPicker: FakeDirectoryPicker(),
        initialRoot: '   ',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('new-save-create')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-save-error')), findsOneWidget);
    expect(find.text('Enter a destination folder.'), findsOneWidget);
    expect(persist.calls, isEmpty);
    expect(find.byKey(const Key('new-save-success')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('title-bar New save opens the dialog and cancel closes it', (
    tester,
  ) async {
    final persist = _FakeNewSavePersist();
    await _pumpShell(tester, schema: schema, persist: persist);

    await tester.tap(find.byKey(const Key('shell-action-new-save')));
    await tester.pumpAndSettle();

    expect(find.byType(NewSaveDialog), findsOneWidget);
    expect(find.byKey(const Key('new-save-never-loaded')), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-save-cancel')));
    await tester.pumpAndSettle();

    expect(find.byType(NewSaveDialog), findsNothing);
    expect(persist.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the empty-state Create new save link opens the same dialog', (
    tester,
  ) async {
    final persist = _FakeNewSavePersist();
    await _pumpShell(tester, schema: schema, persist: persist);

    expect(find.byKey(const Key('empty-state-new-save')), findsOneWidget);
    await tester.tap(find.byKey(const Key('empty-state-new-save')));
    await tester.pumpAndSettle();

    expect(find.byType(NewSaveDialog), findsOneWidget);
    expect(find.byKey(const Key('new-save-never-loaded')), findsOneWidget);
    expect(persist.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shell reopens the created save through onOpenPath', (
    tester,
  ) async {
    final root = _tempTarget('shell');
    final persist = _FakeNewSavePersist();
    final opened = <String>[];
    await _pumpShell(
      tester,
      schema: schema,
      persist: persist,
      onOpenPath: (path) async => opened.add(path),
    );

    await tester.tap(find.byKey(const Key('shell-action-new-save')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('new-save-root')), root);
    await tester.tap(find.byKey(const Key('new-save-create')));
    await tester.pumpAndSettle();

    expect(persist.calls, hasLength(1));
    expect(persist.calls.single.rootDirectory, root);
    expect(find.byKey(const Key('new-save-success')), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-save-open')));
    await tester.pumpAndSettle();

    expect(find.byType(NewSaveDialog), findsNothing);
    expect(opened, <String>[root]);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
