import 'package:bomb_flower/presentation/shell/tabs/placeholder_tab.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The two mandated desktop viewports. Tabs must not overflow at either.
const List<Size> tabTestViewports = <Size>[Size(1100, 700), Size(1280, 720)];

/// Pumps [child] in the real app theme at exactly [size] logical pixels with
/// a 1.0 device pixel ratio and the requested text scaling and motion policy.
Future<void> pumpTab(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1100, 700),
  TextScaler textScaler = TextScaler.noScaling,
  bool reduceMotion = false,
}) {
  return _pumpTab(
    tester,
    child,
    size: size,
    textScaler: textScaler,
    reduceMotion: reduceMotion,
  );
}

/// Pumps [child] inside the shell's shared [TabPageFrame] so a tab body is
/// tested in the same 24/32 px gutter the shell uses.
Future<void> pumpTabPage(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1100, 700),
  TextScaler textScaler = TextScaler.noScaling,
  bool reduceMotion = false,
}) {
  return _pumpTab(
    tester,
    TabPageFrame(child: child),
    size: size,
    textScaler: textScaler,
    reduceMotion: reduceMotion,
  );
}

/// Fails with a viewport-named [TestFailure] if the last frame reported an
/// overflow, and rethrows any other pending exception untouched.
void expectNoOverflow(WidgetTester tester) {
  final Object? exception = tester.takeException();
  if (exception == null) {
    return;
  }
  if (exception is FlutterError && exception.message.contains('overflowed')) {
    final Size logicalSize =
        tester.view.physicalSize / tester.view.devicePixelRatio;
    fail(
      'Overflow at ${logicalSize.width.toStringAsFixed(0)}x'
      '${logicalSize.height.toStringAsFixed(0)} logical px '
      '(devicePixelRatio ${tester.view.devicePixelRatio}).\n'
      '${exception.message}',
    );
  }
  throw exception;
}

Future<void> _pumpTab(
  WidgetTester tester,
  Widget child, {
  required Size size,
  required TextScaler textScaler,
  required bool reduceMotion,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      builder: (context, appChild) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: textScaler, disableAnimations: reduceMotion),
          child: appChild!,
        );
      },
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}
