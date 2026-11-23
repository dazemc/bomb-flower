import 'package:material_ui/material_ui.dart';

import 'presentation/widgets/app_title_bar.dart';

/// Dark forest-green palette used by the shell and, later, the editor UI.
abstract final class BombFlowerColors {
  static const forest = Color(0xFF0E2418);
  static const forestRaised = Color(0xFF173A28);
  static const moss = Color(0xFF8FD6A8);
  static const parchment = Color(0xFFE6EFE3);
}

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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D6A4F),
          brightness: Brightness.dark,
          surface: BombFlowerColors.forest,
        ),
        scaffoldBackgroundColor: BombFlowerColors.forest,
      ),
      home: BombFlowerShell(enableWindowChrome: enableWindowChrome),
    );
  }
}

/// Application shell: custom title bar plus the current placeholder body.
class BombFlowerShell extends StatelessWidget {
  const BombFlowerShell({super.key, required this.enableWindowChrome});

  final bool enableWindowChrome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppTitleBar(interactive: enableWindowChrome),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Bomb Flower',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: BombFlowerColors.parchment,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Save editor shell — engine pending',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: BombFlowerColors.moss),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
