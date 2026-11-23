import 'dart:io';

import 'package:bomb_flower/app.dart';
import 'package:bomb_flower/data/system/startup_open.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/engine/ports.dart';
import 'package:bomb_flower/domain/engine/save_engine.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_ui_state.dart';
import 'package:bomb_flower/presentation/shell/app_shell.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_scope.dart';
import 'package:bomb_flower/presentation/tabs_support/session_save_tab_source.dart';
import 'package:bomb_flower/presentation/widgets/common/empty_state.dart';
import 'package:flutter/services.dart' show rootBundle;
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

void _prepareView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1360, 880);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _join(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';

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
}
