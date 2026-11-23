import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'data/adapter/progress_field_value_codec.dart';
import 'data/adapter/progress_layout_builder.dart';
import 'data/adapter/progress_layout_resolver.dart';
import 'data/io/file_save_repository.dart';
import 'data/system/shared_preferences_backend.dart';
import 'data/system/startup_open.dart';
import 'domain/core/layout.dart';
import 'domain/engine/save_engine.dart';
import 'domain/schema/gamedata_schema.dart';
import 'presentation/bloc/save_session/save_session_cubit.dart';
import 'presentation/settings/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  doWhenWindowReady(() {
    appWindow.title = 'Bomb Flower';
    appWindow.minSize = const Size(800, 600);
    appWindow.alignment = Alignment.center;
    appWindow.show();
  });

  final schema = await GameDataSchema.load(
    () => rootBundle.loadString('assets/schema/gamedata_110.json'),
  );
  // Progress slots derive their spans per file, so the format registers no
  // static layouts; the resolver hands the detected descriptor to the engine.
  final engine = const SaveEngine(
    SaveFormat(
      'oot-remake',
      'Ocarina of Time (Switch 2 remake)',
      <LayoutDescriptor>[],
    ),
    valueCodec: ProgressFieldValueCodec(),
  );
  final resolver = ProgressLayoutResolver(ProgressLayoutBuilder(schema));
  final repository = FileSaveRepository(
    engine: engine,
    resolveLayout: resolver.call,
  );
  final session = SaveSessionCubit(
    engine: engine,
    repository: repository,
    resolveLayout: resolver.call,
  );

  // A bad or missing folder must not block startup: the app opens it through
  // its single open path, which surfaces a typed error state instead.
  final initialOpenPath = switch (resolveStartupOpen()) {
    StartupOpenRequested(:final path) => path,
    StartupOpenInvalid(:final path) => path,
    StartupOpenAbsent() => null,
  };

  // Preferences are resolved before the first frame so the applied text scale
  // is right on the first paint; `open` never throws and falls back to the
  // defaults when the store is missing or unreadable.
  final settingsStore = await PersistedSettingsStore.open(
    const SharedPreferencesBackend(),
  );

  runApp(
    BombFlowerApp(
      session: session,
      initialOpenPath: initialOpenPath,
      settingsStore: settingsStore,
    ),
  );
}
