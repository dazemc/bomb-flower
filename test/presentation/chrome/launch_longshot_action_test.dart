import 'dart:io';

import 'package:bomb_flower/data/system/longshot_launcher.dart';
import 'package:bomb_flower/data/system/longshot_launcher_resolver.dart';
import 'package:bomb_flower/presentation/shell/tabs/settings_tab.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/chrome/app_title_bar.dart';
import 'package:bomb_flower/presentation/widgets/controls/control_icon_button.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Records every launch call and answers with [result].
final class FakeLongshotLauncher implements LongshotLauncher {
  FakeLongshotLauncher(this.result);

  /// Maps the requested path to the reported outcome.
  final LaunchResult Function(String path) result;

  /// Paths the title bar asked to launch, in order.
  final List<String> calls = <String>[];

  @override
  Future<LaunchResult> launch(String path) async {
    calls.add(path);
    return result(path);
  }
}

/// Answers every resolve call with one scripted path and counts the calls.
final class FakeLongshotLauncherResolver implements LongshotLauncherResolver {
  FakeLongshotLauncherResolver(this.path);

  /// What resolution reports; `''` means nothing was found.
  final String path;

  /// Number of times the title bar asked.
  int calls = 0;

  @override
  String resolve() {
    calls++;
    return path;
  }
}

/// Pumps the title bar with its launch seams injected, exactly as `AppShell`
/// wires them in production.
Future<void> pumpTitleBar(
  WidgetTester tester, {
  SettingsStore? store,
  LongshotLauncher? launcher,
  LongshotLauncherResolver? resolver,
  Size size = const Size(1360, 880),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      home: Scaffold(
        body: Column(
          children: <Widget>[
            AppTitleBar(
              interactive: false,
              saveName: 'slot_00',
              settingsStore: store ?? InMemorySettingsStore(),
              launcher: launcher ?? const IoLongshotLauncher(),
              launcherResolver: resolver,
            ),
          ],
        ),
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

Finder get errorBanner => find.byKey(const Key('title-bar-action-error'));

void main() {
  testWidgets('Launch is present and enabled with no session at all', (
    tester,
  ) async {
    await pumpTitleBar(tester);

    expect(find.byKey(const Key('shell-action-launch')), findsOneWidget);
    final button = buttonFor(tester, 'shell-action-launch');
    expect(button.onPressed, isNotNull);
    expect(button.tooltip, 'Launch Longshot');
    expect(button.semanticLabel, 'Launch Longshot');
    // Launching does not need an open save, so the reason does not apply.
    expect(button.tooltip, isNot(contains('Open a save first')));
  });

  testWidgets('a missing launcher path surfaces the path in the banner', (
    tester,
  ) async {
    const path = '/tmp/opencode/longshot-launcher-does-not-exist';
    // [IoLongshotLauncher] stats the real filesystem, and widget tests run
    // inside a fake-async zone where real IO completions never arrive on their
    // own. The real-IO classification itself is covered by
    // `test/data/system/longshot_launcher_test.dart`; here the seam reports the
    // verdict so this test can assert the action surfaces it.
    final launcher = FakeLongshotLauncher(
      (requested) =>
          LaunchResult(status: LaunchStatus.missing, path: requested),
    );
    await pumpTitleBar(
      tester,
      store: InMemorySettingsStore(const EditorPreferences(launcherPath: path)),
      launcher: launcher,
      // The test font is a square 13 px/char, so this 79-character message needs
      // a wider centre slot than 1360 px to stay on one line inside the fixed
      // 44 px title bar. Real fonts fit at 1360; the banner assertions below are
      // unchanged.
      size: const Size(2000, 880),
    );

    await tapAction(tester, find.byKey(const Key('shell-action-launch')));

    expect(launcher.calls, <String>[path]);
    expect(errorBanner, findsOneWidget);
    expect(
      find.descendant(of: errorBanner, matching: find.textContaining(path)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unset preference reports the shared no-launcher message', (
    tester,
  ) async {
    final launcher = FakeLongshotLauncher(
      (path) => LaunchResult(status: LaunchStatus.started, path: path),
    );
    final resolver = FakeLongshotLauncherResolver('');
    final store = InMemorySettingsStore(const EditorPreferences());
    await pumpTitleBar(
      tester,
      store: store,
      launcher: launcher,
      resolver: resolver,
      size: const Size(2000, 880),
    );

    await tapAction(tester, find.byKey(const Key('shell-action-launch')));

    expect(resolver.calls, 1);
    // Nothing is fabricated and no process is attempted.
    expect(launcher.calls, isEmpty);
    expect(errorBanner, findsOneWidget);
    expect(
      find.descendant(
        of: errorBanner,
        matching: find.text(kNoLongshotLauncherConfigured),
      ),
      findsOneWidget,
    );
    expect(store.preferences.launcherPath, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unset preference launches the use-time resolution as-is', (
    tester,
  ) async {
    const resolved = '/opt/longshot/LongshotLauncher-x86_64.AppImage';
    final launcher = FakeLongshotLauncher(
      (path) => LaunchResult(status: LaunchStatus.started, path: path),
    );
    final store = InMemorySettingsStore(const EditorPreferences());
    await pumpTitleBar(
      tester,
      store: store,
      launcher: launcher,
      resolver: FakeLongshotLauncherResolver(resolved),
    );

    await tapAction(tester, find.byKey(const Key('shell-action-launch')));

    expect(launcher.calls, <String>[resolved]);
    // Resolution must not be written back as a preference.
    expect(store.preferences.launcherPath, '');
    expect(errorBanner, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an executable path is launched once through the seam', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('bf-launch-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final script = File('${temp.path}/longshot-launcher')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');
    final chmod = Process.runSync('chmod', <String>['755', script.path]);
    expect(
      chmod.exitCode,
      0,
      reason: 'test setup could not mark it executable',
    );

    final launcher = FakeLongshotLauncher(
      (path) => LaunchResult(status: LaunchStatus.started, path: path),
    );
    await pumpTitleBar(
      tester,
      store: InMemorySettingsStore(
        EditorPreferences(launcherPath: script.path),
      ),
      launcher: launcher,
    );

    await tapAction(tester, find.byKey(const Key('shell-action-launch')));

    expect(launcher.calls, hasLength(1));
    expect(launcher.calls.single, script.path);
    expect(errorBanner, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the collapsed overflow menu carries Launch too', (tester) async {
    await pumpTitleBar(tester, size: const Size(1100, 700));

    expect(find.byKey(const Key('shell-action-overflow')), findsOneWidget);
    expect(find.byKey(const Key('shell-action-launch')), findsNothing);

    await tapAction(tester, find.byKey(const Key('shell-action-overflow')));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('shell-action-launch')), findsOneWidget);
    expect(find.text('Launch Longshot'), findsOneWidget);
  });
}
