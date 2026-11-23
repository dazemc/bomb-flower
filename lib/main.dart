import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  doWhenWindowReady(() {
    appWindow.title = 'Bomb Flower';
    appWindow.minSize = const Size(1100, 700);
    appWindow.size = const Size(1360, 880);
    appWindow.alignment = Alignment.center;
    appWindow.show();
  });

  runApp(const BombFlowerApp());
}
