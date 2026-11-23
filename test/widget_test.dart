import 'package:bomb_flower/app.dart';
import 'package:bomb_flower/presentation/widgets/app_title_bar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shell renders without native window chrome', (tester) async {
    await tester.pumpWidget(const BombFlowerApp(enableWindowChrome: false));

    expect(find.text('Bomb Flower'), findsWidgets);
    expect(find.text('Save editor shell — engine pending'), findsOneWidget);
    expect(find.byType(AppTitleBar), findsOneWidget);
    expect(tester.getSize(find.byType(AppTitleBar)).height, 44);
  });

  testWidgets('title bar controls are inert when chrome is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(const BombFlowerApp(enableWindowChrome: false));

    for (final tooltip in ['Minimize', 'Maximize', 'Close']) {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pump();
    }

    // Let the title bar's double-tap recognizer timer expire.
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
  });
}
