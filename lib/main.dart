import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'data/adapter/progress_field_value_codec.dart';
import 'data/adapter/progress_layout_builder.dart';
import 'data/adapter/progress_layout_resolver.dart';
import 'data/io/file_save_repository.dart';
import 'data/system/startup_open.dart';
import 'domain/core/layout.dart';
import 'domain/engine/save_engine.dart';
import 'domain/schema/gamedata_schema.dart';
import 'presentation/bloc/save_session/save_session_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  doWhenWindowReady(() {
    appWindow.title = 'Bomb Flower';
    appWindow.minSize = const Size(1100, 700);
    appWindow.size = const Size(1360, 880);
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

  runApp(BombFlowerApp(session: session));

  // A bad or missing folder must not block startup: opening it surfaces the
  // cubit's typed error state instead.
  switch (resolveStartupOpen()) {
    case StartupOpenRequested(:final path):
      await session.openPath(path);
    case StartupOpenInvalid(:final path):
      await session.openPath(path);
    case StartupOpenAbsent():
      break;
  }
}
