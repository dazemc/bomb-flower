import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import 'presentation/bloc/shell/shell_cubit.dart';
import 'presentation/shell/app_shell.dart';
import 'presentation/theme/bomb_flower_theme.dart';

/// Root widget.
///
/// [enableWindowChrome] is false in widget tests: bitsdojo's native window
/// calls do not exist in a headless test binding, so the title bar renders but
/// its controls become no-ops.
class BombFlowerApp extends StatelessWidget {
  const BombFlowerApp({super.key, this.enableWindowChrome = true});

  final bool enableWindowChrome;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bomb Flower',
      debugShowCheckedModeBanner: false,
      theme: BombFlowerThemeData.build(),
      home: BlocProvider<ShellCubit>(
        create: (_) => ShellCubit(windowChromeEnabled: enableWindowChrome),
        child: const AppShell(),
      ),
    );
  }
}
