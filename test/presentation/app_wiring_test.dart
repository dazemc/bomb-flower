import 'dart:io';

import 'package:bomb_flower/app.dart';
import 'package:bomb_flower/data/system/directory_picker.dart';
import 'package:bomb_flower/data/system/startup_open.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/engine/ports.dart';
import 'package:bomb_flower/domain/engine/save_engine.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_ui_state.dart';
import 'package:bomb_flower/presentation/bloc/shell/shell_cubit.dart';
import 'package:bomb_flower/presentation/bloc/shell/shell_state.dart';
import 'package:bomb_flower/presentation/dialogs/open_save_dialog.dart';
import 'package:bomb_flower/presentation/shell/app_shell.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_scope.dart';
import 'package:bomb_flower/presentation/tabs_support/session_save_tab_source.dart';
import 'package:bomb_flower/presentation/widgets/common/empty_state.dart';
import 'package:flutter/services.dart'
    show MethodCall, StandardMethodCodec, rootBundle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Minimal layout and project so an open can reach [SaveSessionReady] without
/// any real file or real save bytes.
const LayoutDescriptor _layout = LayoutDescriptor(
  'wiring-layout',
  1,
  <SaveSlotLayout>[],
);

const SaveSlotId _slot = SaveSlotId('slot_00');

/// Byte length of the synthetic slot used by the validation-footer cases.
const int _syntheticSlotLength = 64;

/// A project whose single slot declares [fields], so the real [SaveEngine]
/// classifies them; no codec, file, or save bytes are involved.
SaveProject _projectWithFields(
  List<FieldDescriptor> fields, {
  List<int>? bytes,
}) {
  final layout = LayoutDescriptor('wiring-layout', 1, <SaveSlotLayout>[
    SaveSlotLayout(
      _slot,
      'slot_00/progress.sav',
      fields,
      expectedLength: _syntheticSlotLength,
    ),
  ]);
  final snapshot = SaveSnapshot(
    _slot,
    1,
    ByteRegion.fromBytes(bytes ?? List<int>.filled(_syntheticSlotLength, 0)),
  );
  return SaveProject(
    'wiring-project',
    '/wiring/save',
    '/wiring/save.bombflower',
    layout,
    1,
    <SaveSlotId, SaveSnapshot>{_slot: snapshot},
    <SaveSlotId, SaveDocument>{
      _slot: SaveDocument(_slot, layout.slots.single, snapshot, const []),
    },
    <SaveSlotId, int>{_slot: snapshot.fingerprint},
    EditHistory(),
    EditLog.empty(),
  );
}

/// One field the engine reports as `field.unverified` and read-only.
FieldDescriptor _unverifiedField(int offset) => FieldDescriptor(
  FieldId('progress.unverified_$offset'),
  _slot,
  'Unverified $offset',
  FieldKind.integer,
  ByteSpan(offset, 4),
  FieldConfidence.unverified,
  '',
);

/// A session that opens [project] through the real engine's validation.
({SaveSessionCubit cubit, _FakeRepository repository}) _sessionFor(
  SaveProject project,
) {
  final repository = _FakeRepository(project);
  final cubit = SaveSessionCubit(
    engine: const SaveEngine(
      SaveFormat('test-format', 'Test format', <LayoutDescriptor>[]),
    ),
    repository: repository,
    resolveLayout: (_) async => const LayoutSelection(_layout, 1),
  );
  return (cubit: cubit, repository: repository);
}

ShellState _shellState(WidgetTester tester) =>
    BlocProvider.of<ShellCubit>(tester.element(find.byType(AppShell))).state;

SaveProject _project() => SaveProject(
  'wiring-project',
  '/wiring/save',
  '/wiring/save.bombflower',
  _layout,
  1,
  const <SaveSlotId, SaveSnapshot>{},
  const <SaveSlotId, SaveDocument>{},
  const <SaveSlotId, int>{},
  EditHistory(),
  EditLog.empty(),
);

/// A repository that opens a minimal project when given one, and otherwise
/// rejects the folder; it never touches the filesystem.
final class _FakeRepository implements SaveRepository {
  _FakeRepository([this.project]);

  final SaveProject? project;
  int openCalls = 0;

  @override
  Future<ParseResult> open(
    String rootPath, {
    bool preserveUnknown = true,
    bool verifyIntegrity = true,
  }) async {
    openCalls++;
    final resolved = project;
    if (resolved == null) {
      return const ParseUnsupported('The wiring test repository has no save.');
    }
    return ParseOk(resolved);
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
  }) => throw UnimplementedError();

  @override
  Future<SaveProject> reset(
    SaveProject project,
    SaveSlotId slot, {
    bool clearHistory = false,
  }) => throw UnimplementedError();

  @override
  Future<ExportResult> duplicate(
    SaveProject project,
    SaveSlotId slot, {
    required String destinationRoot,
    BackupPolicy policy = BackupPolicy.standard,
    bool allowOverwrite = false,
  }) => throw UnimplementedError();
}

({SaveSessionCubit cubit, _FakeRepository repository}) _openingSession() {
  final repository = _FakeRepository(_project());
  final cubit = SaveSessionCubit(
    engine: const SaveEngine(
      SaveFormat('test-format', 'Test format', <LayoutDescriptor>[]),
    ),
    repository: repository,
    resolveLayout: (_) async => const LayoutSelection(_layout, 1),
  );
  return (cubit: cubit, repository: repository);
}

/// A session whose repository rejects every folder: nothing is ever open.
({SaveSessionCubit cubit, _FakeRepository repository}) _failingSession() {
  final repository = _FakeRepository();
  final cubit = SaveSessionCubit(
    engine: const SaveEngine(
      SaveFormat('test-format', 'Test format', <LayoutDescriptor>[]),
    ),
    repository: repository,
    resolveLayout: (_) async => const LayoutSelection(_layout, 1),
  );
  return (cubit: cubit, repository: repository);
}

/// An inspector that never touches the filesystem.
final class _FakeProbe implements SaveFolderProbe {
  @override
  Future<SaveFolderInfo> inspect(String path) async =>
      SaveFolderInfo(path: path, exists: false, isDirectory: false);
}

/// An inspector that reports a `slot_NN` folder holding `progress.sav`.
final class _SlotFolderProbe implements SaveFolderProbe {
  const _SlotFolderProbe();

  @override
  Future<SaveFolderInfo> inspect(String path) async => SaveFolderInfo(
    path: path,
    exists: true,
    isDirectory: true,
    parentExists: true,
    progressSavePresent: true,
  );
}

/// An in-memory recent-folder port.
final class _FakeRecentPaths implements RecentPathsStore {
  @override
  Future<List<String>> read() async => const <String>[];

  @override
  Future<void> add(String path) async {}

  @override
  Future<void> clear() async {}
}

void _closeOnTeardown(SaveSessionCubit cubit) {
  addTearDown(() async {
    if (!cubit.isClosed) {
      await cubit.close(force: true);
    }
  });
}

void _prepareView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1360, 880);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _join(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';

/// Delivers one native drop message exactly as the Linux runner will: the
/// `folderDropped` method with the dropped absolute path as its only argument.
///
/// The channel itself replies before any filesystem work, but the resolver it
/// starts is real async `dart:io`, and the widget binding's fake clock never
/// completes real I/O. The dispatch therefore runs on the real event loop
/// inside [WidgetTester.runAsync] and waits on [until] — the observable effect
/// of the drop — instead of a fixed delay.
Future<void> _dispatchDrop(
  WidgetTester tester,
  String path, {
  bool Function()? until,
}) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  await tester.runAsync(() async {
    await messenger.handlePlatformMessage(
      'bomb_flower/drop',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('folderDropped', path),
      ),
      (_) {},
    );
    // A valid drop prints its one log line after the open completes; a refusal
    // schedules the frame that shows the failure panel. Either way the effect
    // arrives within a few event-loop turns.
    final ready = until ?? (() => tester.binding.hasScheduledFrame);
    for (var attempt = 0; attempt < 500; attempt++) {
      if (ready()) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A plain test, not testWidgets: the test binding's fake async never pumps
  // the platform reply that rootBundle awaits, so a widget test would hang.
  test('the bundled GameData schema is declared and readable', () async {
    final json = await rootBundle.loadString('assets/schema/gamedata_110.json');

    expect(json, isNotEmpty);
    expect(json, contains('"schemaRevision"'));
  });

  testWidgets('a session-less app is hermetic and shows the empty state', (
    tester,
  ) async {
    _prepareView(tester);
    await tester.pumpWidget(const BombFlowerApp(enableWindowChrome: false));
    await tester.pumpAndSettle();

    final cubit = BlocProvider.of<SaveSessionCubit>(
      tester.element(find.byType(AppShell)),
    );
    expect(cubit.isEnabled, isFalse);
    expect(cubit.state, isA<SaveSessionClosed>());
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Open a save to begin'), findsOneWidget);
    expect(find.text('No save file open'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an injected session opens onto the overview surface', (
    tester,
  ) async {
    _prepareView(tester);
    final session = _openingSession();
    final cubit = session.cubit;
    addTearDown(() async {
      if (!cubit.isClosed) {
        await cubit.close(force: true);
      }
    });

    await tester.pumpWidget(
      BombFlowerApp(enableWindowChrome: false, session: cubit),
    );
    await tester.pumpAndSettle();

    expect(
      BlocProvider.of<SaveSessionCubit>(tester.element(find.byType(AppShell))),
      same(cubit),
    );
    expect(find.byType(EmptyState), findsOneWidget);

    await cubit.openPath('/wiring/save');
    await tester.pumpAndSettle();

    expect(session.repository.openCalls, 1);
    expect(cubit.state, isA<SaveSessionReady>());

    final source = SaveTabScope.maybeOf(tester.element(find.byType(AppShell)));
    expect(source, isA<SessionSaveTabSource>());
    expect(source!.isOpen, isTrue);
    expect(source.rootPath, '/wiring/save');

    expect(find.byType(EmptyState), findsNothing);
    expect(find.textContaining('Read-only dashboard'), findsOneWidget);
    expect(find.byKey(const Key('overview-dirty')), findsOneWidget);
    expect(find.text('0 modified fields'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'startup open classification never throws or mutates the environment',
    () {
      expect(resolveStartupOpenFor(null), isA<StartupOpenAbsent>());
      expect(resolveStartupOpenFor(''), isA<StartupOpenAbsent>());
      expect(resolveStartupOpenFor('   '), isA<StartupOpenAbsent>());
      expect(
        resolveStartupOpen(environment: const <String, String>{}),
        isA<StartupOpenAbsent>(),
      );

      final root = Directory.systemTemp.createTempSync('bomb_flower_startup_');
      addTearDown(() {
        if (root.existsSync()) {
          root.deleteSync(recursive: true);
        }
      });
      final slot = Directory(_join(root.path, 'slot_00'))..createSync();
      File(_join(slot.path, 'progress.sav')).writeAsStringSync('save');

      final requested = resolveStartupOpenFor(root.path);
      expect(requested, isA<StartupOpenRequested>());
      expect((requested as StartupOpenRequested).path, root.path);
      expect(
        resolveStartupOpen(
          environment: <String, String>{startupOpenEnvVar: root.path},
        ),
        isA<StartupOpenRequested>(),
      );

      final direct = Directory.systemTemp.createTempSync('bomb_flower_direct_');
      addTearDown(() {
        if (direct.existsSync()) {
          direct.deleteSync(recursive: true);
        }
      });
      File(_join(direct.path, 'progress.sav')).writeAsStringSync('save');
      expect(resolveStartupOpenFor(direct.path), isA<StartupOpenRequested>());

      final empty = Directory.systemTemp.createTempSync('bomb_flower_empty_');
      addTearDown(() {
        if (empty.existsSync()) {
          empty.deleteSync(recursive: true);
        }
      });
      final invalid = resolveStartupOpenFor(empty.path);
      expect(invalid, isA<StartupOpenInvalid>());
      expect((invalid as StartupOpenInvalid).reason, isNotEmpty);

      expect(
        resolveStartupOpenFor(_join(root.path, 'missing')),
        isA<StartupOpenInvalid>(),
      );
    },
  );

  testWidgets(
    'a failed open shows the open-failure panel with its path and both actions',
    (tester) async {
      _prepareView(tester);
      final session = _failingSession();
      final cubit = session.cubit;
      _closeOnTeardown(cubit);

      await tester.pumpWidget(
        BombFlowerApp(enableWindowChrome: false, session: cubit),
      );
      await tester.pumpAndSettle();

      await cubit.openPath('/wiring/missing');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('open-failure-panel')), findsOneWidget);
      expect(find.text('Could not open save'), findsOneWidget);
      expect(
        find.text('This save folder is not supported by this version.'),
        findsOneWidget,
      );
      expect(find.text('/wiring/missing'), findsOneWidget);
      expect(find.text('Open another save…'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.text('Open a save to begin'), findsNothing);
    },
  );

  testWidgets(
    'a closed session still shows the empty state and no failure text',
    (tester) async {
      _prepareView(tester);
      final session = _openingSession();
      final cubit = session.cubit;
      _closeOnTeardown(cubit);

      await tester.pumpWidget(
        BombFlowerApp(enableWindowChrome: false, session: cubit),
      );
      await tester.pumpAndSettle();

      expect(cubit.state, isA<SaveSessionClosed>());
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Open a save to begin'), findsOneWidget);
      expect(find.byKey(const Key('open-failure-panel')), findsNothing);
      expect(find.text('Could not open save'), findsNothing);
    },
  );

  testWidgets('a successful open never shows the failure panel', (
    tester,
  ) async {
    _prepareView(tester);
    final session = _openingSession();
    final cubit = session.cubit;
    _closeOnTeardown(cubit);

    await tester.pumpWidget(
      BombFlowerApp(enableWindowChrome: false, session: cubit),
    );
    await tester.pumpAndSettle();

    await cubit.openPath('/wiring/save');
    await tester.pumpAndSettle();

    expect(cubit.state, isA<SaveSessionReady>());
    expect(find.byKey(const Key('open-failure-panel')), findsNothing);
    expect(find.text('Could not open save'), findsNothing);
    expect(find.textContaining('Read-only dashboard'), findsOneWidget);
  });

  testWidgets('the failure actions retry the open and open the save dialog', (
    tester,
  ) async {
    _prepareView(tester);
    final session = _failingSession();
    final cubit = session.cubit;
    _closeOnTeardown(cubit);

    await tester.pumpWidget(
      BombFlowerApp(
        enableWindowChrome: false,
        session: cubit,
        saveFolderProbe: _FakeProbe(),
        recentPaths: _FakeRecentPaths(),
      ),
    );
    await tester.pumpAndSettle();

    await cubit.openPath('/wiring/missing');
    await tester.pumpAndSettle();
    expect(session.repository.openCalls, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(session.repository.openCalls, 2);
    expect(find.byKey(const Key('open-failure-panel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-failure-open-another')));
    await tester.pumpAndSettle();

    expect(find.byType(OpenSaveDialog), findsOneWidget);
    expect(find.text('Open save folder'), findsOneWidget);
  });

  testWidgets(
    'an unsupported folder reports its attempted path from the failure details',
    (tester) async {
      _prepareView(tester);
      final repository = _FakeRepository();
      final cubit = SaveSessionCubit(
        engine: const SaveEngine(
          SaveFormat('test-format', 'Test format', <LayoutDescriptor>[]),
        ),
        repository: repository,
        resolveLayout: (_) async => null,
      );
      _closeOnTeardown(cubit);

      await tester.pumpWidget(
        BombFlowerApp(enableWindowChrome: false, session: cubit),
      );
      await tester.pumpAndSettle();

      await cubit.openPath('/nope/folder');
      await tester.pumpAndSettle();

      expect(find.text('Could not open save'), findsOneWidget);
      expect(
        find.text('No supported save layout was found in this folder.'),
        findsOneWidget,
      );
      expect(find.text('/nope/folder'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets('the chrome reflects the open project, not the placeholders', (
    tester,
  ) async {
    _prepareView(tester);
    final session = _openingSession();
    final cubit = session.cubit;
    _closeOnTeardown(cubit);

    await tester.pumpWidget(
      BombFlowerApp(enableWindowChrome: false, session: cubit),
    );
    await tester.pumpAndSettle();

    // Nothing is open yet, so the empty wording is unchanged.
    expect(find.text('No save open'), findsOneWidget);
    expect(find.textContaining('No save file open'), findsWidgets);

    await cubit.openPath('/wiring/save');
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(
      find.byKey(const Key('title-bar-save-name')),
    );
    expect(title.data, 'save');
    expect(find.text('/wiring/save'), findsWidgets);
    expect(find.text('rev 1'), findsOneWidget);
    expect(find.text('No validation issues'), findsOneWidget);
    expect(find.text('Validation: engine pending'), findsNothing);
    expect(find.text('No save open'), findsNothing);
    expect(find.textContaining('No save file open'), findsNothing);
    expect(find.textContaining('engine pending'), findsNothing);
  });

  testWidgets(
    'an informational-only save says so and keeps the footer dot healthy',
    (tester) async {
      _prepareView(tester);
      final session = _sessionFor(
        _projectWithFields(<FieldDescriptor>[
          _unverifiedField(0),
          _unverifiedField(4),
          _unverifiedField(8),
        ]),
      );
      final cubit = session.cubit;
      _closeOnTeardown(cubit);

      await tester.pumpWidget(
        BombFlowerApp(enableWindowChrome: false, session: cubit),
      );
      await tester.pumpAndSettle();

      await cubit.openPath('/wiring/save');
      await tester.pumpAndSettle();

      expect(
        find.text('No blocking issues · 3 informational notes'),
        findsOneWidget,
      );
      expect(find.textContaining('warnings'), findsNothing);
      expect(_shellState(tester).validationHealth, ShellValidationHealth.ok);
    },
  );

  testWidgets(
    'one blocking issue is reported as blocking and turns the dot red',
    (tester) async {
      _prepareView(tester);
      final session = _sessionFor(
        _projectWithFields(<FieldDescriptor>[
          FieldDescriptor(
            FieldId('progress.out_of_slot'),
            _slot,
            'Outside the slot',
            FieldKind.integer,
            const ByteSpan(60, 8),
            FieldConfidence.unverified,
            '',
          ),
        ]),
      );
      final cubit = session.cubit;
      _closeOnTeardown(cubit);

      await tester.pumpWidget(
        BombFlowerApp(enableWindowChrome: false, session: cubit),
      );
      await tester.pumpAndSettle();

      await cubit.openPath('/wiring/save');
      await tester.pumpAndSettle();

      expect(find.text('1 blocking issue'), findsOneWidget);
      expect(
        _shellState(tester).validationHealth,
        ShellValidationHealth.errors,
      );
    },
  );

  testWidgets(
    'actionable warnings lead and provenance notices are counted separately',
    (tester) async {
      _prepareView(tester);
      // One verified field holds 200 against a declared 0..10 bound, and one
      // unverified field is a provenance notice.
      final bytes = List<int>.filled(_syntheticSlotLength, 0)..[0] = 200;
      final session = _sessionFor(
        _projectWithFields(<FieldDescriptor>[
          const FieldDescriptor(
            FieldId('progress.max_life'),
            _slot,
            'Max life',
            FieldKind.integer,
            ByteSpan(0, 1),
            FieldConfidence.verified,
            'test citation',
            min: 0,
            max: 10,
          ),
          _unverifiedField(8),
        ], bytes: bytes),
      );
      final cubit = session.cubit;
      _closeOnTeardown(cubit);

      await tester.pumpWidget(
        BombFlowerApp(enableWindowChrome: false, session: cubit),
      );
      await tester.pumpAndSettle();

      await cubit.openPath('/wiring/save');
      await tester.pumpAndSettle();

      expect(find.text('1 warning · 1 informational note'), findsOneWidget);
      expect(
        _shellState(tester).validationHealth,
        ShellValidationHealth.warnings,
      );
    },
  );

  testWidgets('a closed session keeps the engine-pending footer default', (
    tester,
  ) async {
    _prepareView(tester);
    final session = _openingSession();
    final cubit = session.cubit;
    _closeOnTeardown(cubit);

    await tester.pumpWidget(
      BombFlowerApp(enableWindowChrome: false, session: cubit),
    );
    await tester.pumpAndSettle();

    expect(find.text('Validation: engine pending'), findsOneWidget);
    expect(_shellState(tester).validationHealth, ShellValidationHealth.unknown);
  });

  testWidgets(
    'a slot folder root names its parent and never blames the save data',
    (tester) async {
      _prepareView(tester);

      final logged = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          logged.add(message);
        }
      };
      addTearDown(() => debugPrint = previousDebugPrint);

      final session = _failingSession();
      final cubit = session.cubit;
      _closeOnTeardown(cubit);

      await tester.pumpWidget(
        BombFlowerApp(
          enableWindowChrome: false,
          session: cubit,
          saveFolderProbe: const _SlotFolderProbe(),
          initialOpenPath: '/saves/kokiri-start/slot_00',
        ),
      );
      await tester.pumpAndSettle();

      // The engine never saw the folder: the shape was classified first.
      expect(session.repository.openCalls, 0);
      expect(find.byKey(const Key('open-failure-panel')), findsOneWidget);
      expect(
        find.text(
          'That is a slot folder. Choose the folder that contains it '
          '(/saves/kokiri-start).',
        ),
        findsOneWidget,
      );
      expect(
        find.text('This save folder is damaged or incomplete.'),
        findsNothing,
      );

      // Exactly one line per attempt, with the reason and no save values.
      expect(logged, hasLength(1));
      expect(
        logged.single,
        startsWith('open /saves/kokiri-start/slot_00 -> ParseUnsupported: '),
      );
      expect(logged.single, contains('That is a slot folder.'));
    },
  );

  testWidgets('a dropped save folder opens it once and logs exactly one line', (
    tester,
  ) async {
    _prepareView(tester);
    final root = Directory.systemTemp.createTempSync('bomb_flower_drop_open_');
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });
    final slot = Directory(_join(root.path, 'slot_00'))..createSync();
    File(_join(slot.path, 'progress.sav')).writeAsStringSync('save');

    final logged = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        logged.add(message);
      }
    };
    addTearDown(() => debugPrint = previousDebugPrint);

    final session = _openingSession();
    final cubit = session.cubit;
    _closeOnTeardown(cubit);

    await tester.pumpWidget(
      BombFlowerApp(
        enableWindowChrome: false,
        session: cubit,
        saveFolderProbe: _FakeProbe(),
        recentPaths: _FakeRecentPaths(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);

    await _dispatchDrop(tester, root.path, until: () => logged.isNotEmpty);
    await tester.pumpAndSettle();

    expect(session.repository.openCalls, 1);
    expect(cubit.state, isA<SaveSessionReady>());
    expect(find.byKey(const Key('open-failure-panel')), findsNothing);
    expect(find.byType(EmptyState), findsNothing);
    expect(logged, hasLength(1));
    expect(logged.single, startsWith('open ${root.path} -> ParseOk'));
  });

  testWidgets(
    'a dropped file is refused, named, and cleared by the next open',
    (tester) async {
      _prepareView(tester);
      final folder = Directory.systemTemp.createTempSync(
        'bomb_flower_drop_file_',
      );
      addTearDown(() {
        if (folder.existsSync()) {
          folder.deleteSync(recursive: true);
        }
      });
      final file = File(_join(folder.path, 'notes.txt'))
        ..writeAsStringSync('not a save');

      final logged = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          logged.add(message);
        }
      };
      addTearDown(() => debugPrint = previousDebugPrint);

      final session = _openingSession();
      final cubit = session.cubit;
      _closeOnTeardown(cubit);

      await tester.pumpWidget(
        BombFlowerApp(
          enableWindowChrome: false,
          session: cubit,
          saveFolderProbe: _FakeProbe(),
          recentPaths: _FakeRecentPaths(),
        ),
      );
      await tester.pumpAndSettle();

      await _dispatchDrop(tester, file.path);
      await tester.pumpAndSettle();

      // Nothing reached the engine and nothing was logged: the drop was
      // refused before an open was attempted.
      expect(session.repository.openCalls, 0);
      expect(logged, isEmpty);
      expect(find.byKey(const Key('open-failure-panel')), findsOneWidget);
      expect(find.text('Could not open save'), findsOneWidget);
      expect(
        find.text('Drop the profile folder that contains slot_00, not a file.'),
        findsOneWidget,
      );
      expect(find.text(file.path), findsOneWidget);

      // The existing open path clears the refusal on the next attempt.
      await cubit.openPath('/wiring/save');
      await tester.pumpAndSettle();

      expect(cubit.state, isA<SaveSessionReady>());
      expect(find.byKey(const Key('open-failure-panel')), findsNothing);
      expect(find.textContaining('Read-only dashboard'), findsOneWidget);
    },
  );
}
