import 'package:bomb_flower/data/system/directory_picker.dart';
import 'package:bomb_flower/data/system/longshot_launcher.dart';
import 'package:bomb_flower/presentation/shell/tabs/settings_tab.dart';
import 'package:bomb_flower/presentation/widgets/common/brass_button.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_slider.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_toggle.dart';
import 'package:bomb_flower/presentation/widgets/selectors/searchable_select.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/tab_test_harness.dart';

/// An in-memory store that records every successful save.
final class FakeSettingsStore extends ChangeNotifier implements SettingsStore {
  FakeSettingsStore({
    EditorPreferences? seeded,
    this.failSave = false,
    this.persistent = false,
  }) : _preferences = seeded ?? const EditorPreferences();

  final EditorPreferences _preferences;

  /// When true, [save] throws instead of recording.
  final bool failSave;

  /// What the store reports through [isPersistent].
  final bool persistent;

  @override
  EditorPreferences get preferences => _preferences;

  @override
  Listenable get changes => this;

  @override
  bool get isPersistent => persistent;

  /// Values accepted by [save], in order.
  final List<EditorPreferences> saves = <EditorPreferences>[];

  /// Number of [load] calls.
  int loads = 0;

  @override
  Future<EditorPreferences> load() async {
    loads++;
    return _preferences;
  }

  @override
  Future<void> save(EditorPreferences preferences) async {
    if (failSave) {
      throw StateError('store offline');
    }
    saves.add(preferences);
  }
}

/// Records the chooser request and answers with a scripted path.
final class FakeFilePicker implements FilePicker {
  FakeFilePicker(this.picked);

  /// What the chooser returns; `null` means the user cancelled.
  final String? picked;

  /// Initial paths the row handed to the chooser, in order.
  final List<String> calls = <String>[];

  @override
  Future<String?> pickFile({String? title, String? initialPath}) async {
    calls.add(initialPath ?? '');
    return picked;
  }
}

Future<void> _pumpSettings(
  WidgetTester tester,
  SettingsStore store, {
  Size size = const Size(1100, 700),
  FilePicker? picker,
}) async {
  await pumpTab(
    tester,
    SettingsTab(store: store, launcherPicker: picker),
    size: size,
  );
  await tester.pump();
}

void main() {
  testWidgets('renders seeded paths, policy, toggles, and text scale', (
    tester,
  ) async {
    final store = FakeSettingsStore(
      seeded: const EditorPreferences(
        recentPaths: <String>['/saves/a.sav', '/saves/b.sav'],
        backupPolicy: BackupPolicy.always,
        makeNewestSlotDefault: false,
        reducedMotion: true,
        textScale: 1.25,
      ),
    );
    await _pumpSettings(tester, store);

    expect(store.loads, 1);
    expect(find.text('/saves/a.sav'), findsOneWidget);
    expect(find.text('/saves/b.sav'), findsOneWidget);
    expect(find.text('Always keep a backup'), findsOneWidget);

    expect(
      tester.widget<BrassToggle>(find.byKey(SettingsTab.reduceMotionKey)).value,
      isTrue,
    );
    expect(
      tester
          .widget<BrassToggle>(find.byKey(SettingsTab.newestDefaultKey))
          .value,
      isFalse,
    );

    final slider = tester.widget<BrassSlider>(
      find.byKey(SettingsTab.textScaleKey),
    );
    expect(slider.value, 1.25);
    expect(slider.min, 1);
    expect(slider.max, 1.5);
    expect(slider.divisions, 5);
    expect(find.text('1.25x'), findsOneWidget);

    expectNoOverflow(tester);
  });

  testWidgets('toggling reduce motion saves once with reducedMotion true', (
    tester,
  ) async {
    final store = FakeSettingsStore();
    await _pumpSettings(tester, store);

    await tester.tap(find.text('Reduce motion'));
    await tester.pump();
    await tester.pump();

    expect(store.saves, hasLength(1));
    final saved = store.saves.single;
    expect(saved.reducedMotion, isTrue);
    expect(saved.backupPolicy, BackupPolicy.ask);
    expect(saved.makeNewestSlotDefault, isTrue);
    expect(saved.textScale, 1.0);
    expect(
      tester.widget<BrassToggle>(find.byKey(SettingsTab.reduceMotionKey)).value,
      isTrue,
    );
  });

  testWidgets('changing backup policy saves the chosen policy', (tester) async {
    final store = FakeSettingsStore();
    await _pumpSettings(tester, store);

    await tester.tap(find.byKey(SearchableSelect.fieldKey));
    await tester.pump();
    await tester.tap(find.text('Never keep a backup').last);
    await tester.pump();
    await tester.pump();

    expect(store.saves, hasLength(1));
    expect(store.saves.single.backupPolicy, BackupPolicy.never);
    expect(find.text('Never keep a backup'), findsOneWidget);
  });

  testWidgets('clearing recent paths saves an empty list', (tester) async {
    final store = FakeSettingsStore(
      seeded: const EditorPreferences(
        recentPaths: <String>['/saves/a.sav', '/saves/b.sav'],
      ),
    );
    await _pumpSettings(tester, store);

    await tester.tap(find.text('Clear recent paths'));
    await tester.pump();
    await tester.pump();

    expect(store.saves, hasLength(1));
    expect(store.saves.single.recentPaths, isEmpty);
    expect(find.text('/saves/a.sav'), findsNothing);
    expect(find.text('No recent save folders recorded.'), findsOneWidget);
    expect(
      tester
          .widget<BrassButton>(find.byKey(SettingsTab.clearRecentKey))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a failed save shows the danger banner and keeps the UI usable', (
    tester,
  ) async {
    final store = FakeSettingsStore(failSave: true);
    await _pumpSettings(tester, store);

    await tester.tap(find.text('Reduce motion'));
    await tester.pump();
    await tester.pump();

    expect(store.saves, isEmpty);
    expect(find.text('Could not save preferences'), findsOneWidget);
    // The control keeps the value the user chose; the save is not pretended.
    expect(
      tester.widget<BrassToggle>(find.byKey(SettingsTab.reduceMotionKey)).value,
      isTrue,
    );

    // Still usable: another control responds without throwing.
    await tester.tap(find.text('Make the newest slot the default'));
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<BrassToggle>(find.byKey(SettingsTab.newestDefaultKey))
          .value,
      isFalse,
    );
    expectNoOverflow(tester);
  });

  testWidgets('the in-memory default says preferences do not persist', (
    tester,
  ) async {
    await pumpTab(tester, const SettingsTab());
    await tester.pump();

    expect(find.byKey(SettingsTab.persistenceCaptionKey), findsOneWidget);
    expect(
      find.textContaining('held in memory for this session only'),
      findsOneWidget,
    );
    // The default in-memory store still loads, so the controls render.
    expect(find.byKey(SettingsTab.reduceMotionKey), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('settings tab fits 1100x700 without overflow', (tester) async {
    final store = FakeSettingsStore(
      seeded: const EditorPreferences(
        recentPaths: <String>['/saves/a-very-long-folder-name/oot.sav'],
        backupPolicy: BackupPolicy.never,
        textScale: 1.5,
      ),
    );
    await _pumpSettings(tester, store, size: const Size(1100, 700));

    expect(find.text('Settings'), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('editing the launcher path saves only that field', (
    tester,
  ) async {
    const seeded = '/opt/longshot/Launcher.AppImage';
    final store = FakeSettingsStore(
      seeded: const EditorPreferences(
        backupPolicy: BackupPolicy.always,
        makeNewestSlotDefault: false,
        reducedMotion: true,
        textScale: 1.25,
        launcherPath: seeded,
      ),
    );
    await _pumpSettings(tester, store);

    final field = tester.widget<TextField>(
      find.byKey(SettingsTab.launcherPathKey),
    );
    expect(field.controller!.text, seeded);

    const edited = '/opt/longshot/LongshotLauncher-x86_64.AppImage';
    await tester.enterText(find.byKey(SettingsTab.launcherPathKey), edited);
    await tester.ensureVisible(find.byKey(SettingsTab.launcherPathSaveKey));
    await tester.tap(find.byKey(SettingsTab.launcherPathSaveKey));
    await tester.pump();
    await tester.pump();

    expect(store.saves, hasLength(1));
    final saved = store.saves.single;
    expect(saved.launcherPath, edited);
    expect(saved.backupPolicy, BackupPolicy.always);
    expect(saved.makeNewestSlotDefault, isFalse);
    expect(saved.reducedMotion, isTrue);
    expect(saved.textScale, 1.25);
    expectNoOverflow(tester);
  });

  testWidgets('an unset launcher path shows the shared empty state', (
    tester,
  ) async {
    final store = FakeSettingsStore();
    await _pumpSettings(tester, store);

    expect(find.byKey(SettingsTab.launcherPathEmptyKey), findsOneWidget);
    expect(find.text(kNoLongshotLauncherConfigured), findsOneWidget);
    // The same sentence is what the title bar reports; there is no
    // second "reset to default" phrasing to drift from it.
    expect(find.text('Reset to default'), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('Choose… fills the field and saves the picked launcher', (
    tester,
  ) async {
    const picked = '/opt/longshot/Launcher.AppImage';
    final store = FakeSettingsStore();
    final picker = FakeFilePicker(picked);
    await _pumpSettings(tester, store, picker: picker);

    await tester.ensureVisible(find.byKey(SettingsTab.launcherPathChooseKey));
    await tester.tap(find.byKey(SettingsTab.launcherPathChooseKey));
    await tester.pump();
    await tester.pump();

    expect(picker.calls, hasLength(1));
    expect(store.saves, hasLength(1));
    expect(store.saves.single.launcherPath, picked);

    final field = tester.widget<TextField>(
      find.byKey(SettingsTab.launcherPathKey),
    );
    expect(field.controller!.text, picked);
    expect(find.byKey(SettingsTab.launcherPathEmptyKey), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('a cancelled chooser leaves the empty state and saves nothing', (
    tester,
  ) async {
    final store = FakeSettingsStore();
    final picker = FakeFilePicker(null);
    await _pumpSettings(tester, store, picker: picker);

    await tester.ensureVisible(find.byKey(SettingsTab.launcherPathChooseKey));
    await tester.tap(find.byKey(SettingsTab.launcherPathChooseKey));
    await tester.pump();
    await tester.pump();

    expect(picker.calls, hasLength(1));
    expect(store.saves, isEmpty);
    expect(find.byKey(SettingsTab.launcherPathEmptyKey), findsOneWidget);
    expectNoOverflow(tester);
  });
}
