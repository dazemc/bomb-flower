import 'package:bomb_flower/app.dart';
import 'package:bomb_flower/data/system/shared_preferences_backend.dart';
import 'package:bomb_flower/domain/preferences/preferences_backend.dart';
import 'package:bomb_flower/presentation/shell/tabs/settings_tab.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_slider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tabs/support/tab_test_harness.dart';

/// A preferences document held in memory, standing in for the plugin store.
final class _MemoryBackend implements PreferencesBackend {
  _MemoryBackend([this.contents]);

  String? contents;
  int writes = 0;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String value) async {
    writes++;
    contents = value;
  }
}

Future<void> _pumpApp(WidgetTester tester, SettingsStore store) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1360, 880);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    BombFlowerApp(enableWindowChrome: false, settingsStore: store),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Settings text scale scales the running app', (tester) async {
    final store = PersistedSettingsStore(_MemoryBackend());
    await _pumpApp(tester, store);

    await tester.tap(find.byKey(const Key('nav-tab-settings')));
    await tester.pumpAndSettle();

    // A real heading inside the page, not just the store's number.
    final heading = find.descendant(
      of: find.byType(SettingsTab),
      matching: find.text('Settings'),
    );
    expect(heading, findsOneWidget);
    expect(
      MediaQuery.textScalerOf(tester.element(heading)).scale(10),
      closeTo(10, 0.001),
    );
    final before = tester.getSize(heading);

    tester.widget<BrassSlider>(find.byKey(SettingsTab.textScaleKey)).onChanged!(
      1.3,
    );
    await tester.pumpAndSettle();

    expect(
      MediaQuery.textScalerOf(tester.element(heading)).scale(10),
      closeTo(13, 0.001),
    );
    final after = tester.getSize(heading);
    expect(
      after.height / before.height,
      closeTo(1.3, 0.02),
      reason: 'the rendered heading must grow by the scale, not only the store',
    );
    expect(store.preferences.textScale, 1.3);
    expect(
      store.preferences.textScale,
      store.preferences.textScale.clamp(
        kMinAppliedTextScale,
        kMaxAppliedTextScale,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a persisted store says preferences survive a restart', (
    tester,
  ) async {
    final store = PersistedSettingsStore(_MemoryBackend());
    expect(store.isPersistent, isTrue);
    await pumpTab(tester, SettingsTab(store: store));
    await tester.pump();

    expect(find.byKey(SettingsTab.persistenceCaptionKey), findsOneWidget);
    expect(find.textContaining('survive a restart'), findsOneWidget);
    expectNoOverflow(tester);
  });

  test('text scale and backup policy survive a fresh store instance', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final backend = const SharedPreferencesBackend();

    final first = await PersistedSettingsStore.open(backend);
    expect(first.preferences.textScale, 1.0, reason: 'defaults when unset');
    await first.save(
      const EditorPreferences(
        textScale: 1.3,
        backupPolicy: BackupPolicy.never,
        recentPaths: <String>['/saves/a.sav', '/saves/b.sav'],
      ),
    );

    // A different store object over the same platform store: the value has to
    // come back from the backend, not from the first instance's memory.
    final second = await PersistedSettingsStore.open(backend);
    expect(second.preferences.textScale, 1.3);
    expect(second.preferences.backupPolicy, BackupPolicy.never);
    expect(second.preferences.recentPaths, <String>[
      '/saves/a.sav',
      '/saves/b.sav',
    ]);
  });

  test(
    'a malformed document falls back to defaults without throwing',
    () async {
      // `shared_preferences` owns its own encoding, so the only thing worth
      // pinning here is this store's decoding of the document it owns.
      for (final raw in <String>[
        '{not json',
        '[]',
        '{"textScale": "huge"}',
        '{"backupPolicy": "sometimes"}',
      ]) {
        final store = await PersistedSettingsStore.open(_MemoryBackend(raw));
        expect(store.preferences.textScale, 1.0, reason: raw);
        expect(store.preferences.backupPolicy, BackupPolicy.ask, reason: raw);
        expect(store.preferences.makeNewestSlotDefault, isTrue, reason: raw);
      }
    },
  );

  test('a stored text scale outside the applied range is clamped', () async {
    final high = await PersistedSettingsStore.open(
      _MemoryBackend('{"textScale": 9.0}'),
    );
    expect(high.preferences.textScale, kMaxAppliedTextScale);

    final low = await PersistedSettingsStore.open(
      _MemoryBackend('{"textScale": 0.1}'),
    );
    expect(low.preferences.textScale, kMinAppliedTextScale);
  });
}
