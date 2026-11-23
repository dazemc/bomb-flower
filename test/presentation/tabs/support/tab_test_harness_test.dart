import 'package:bomb_flower/presentation/shell/tabs/placeholder_tab.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_colors.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_spacing.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'tab_test_harness.dart';

void main() {
  testWidgets('pumpTab pins the physical viewport at 1x', (tester) async {
    await pumpTab(tester, const Text('tab body'));

    expect(tester.view.physicalSize, const Size(1100, 700));
    expect(tester.view.devicePixelRatio, 1);
    expect(tester.getSize(find.byType(Scaffold)), const Size(1100, 700));

    await pumpTab(tester, const Text('tab body'), size: const Size(1280, 720));

    expect(tester.view.physicalSize, const Size(1280, 720));
    expect(tester.view.devicePixelRatio, 1);
    expect(tester.getSize(find.byType(Scaffold)), const Size(1280, 720));
  });

  testWidgets('pumpTab applies the Bomb Flower theme', (tester) async {
    late ThemeData theme;
    late BombFlowerTheme palette;

    await pumpTab(
      tester,
      Builder(
        builder: (context) {
          theme = Theme.of(context);
          palette = context.bombFlowerTheme;
          return const Text('themed body');
        },
      ),
    );

    expect(theme.scaffoldBackgroundColor, BombFlowerColors.canopy0);
    expect(theme.colorScheme.primary, BombFlowerColors.brass);
    expect(theme.extension<BombFlowerTheme>(), isNotNull);
    expect(palette.accent, BombFlowerColors.brass);
    expect(palette.surface, BombFlowerColors.parchment);
  });

  testWidgets('pumpTabPage uses the shell frame at every mandated viewport', (
    tester,
  ) async {
    const pageChildKey = ValueKey<String>('tab-page-child');

    for (final Size viewport in tabTestViewports) {
      await pumpTabPage(
        tester,
        const Column(
          key: pageChildKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Section title'),
            SizedBox(height: 12),
            Text('Body copy inside the shared shell frame.'),
          ],
        ),
        size: viewport,
      );

      expect(tester.view.physicalSize, viewport);
      expect(find.byType(TabPageFrame), findsOneWidget);
      expect(find.byKey(pageChildKey), findsOneWidget);

      final SingleChildScrollView frame = tester.widget<SingleChildScrollView>(
        find.ancestor(
          of: find.byKey(pageChildKey),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(
        frame.padding,
        const EdgeInsets.all(BombFlowerSpacing.contentGutter),
        reason:
            'the shell gutter must be reused at ${viewport.width.toInt()} px',
      );

      expectNoOverflow(tester);
    }
  });

  testWidgets('pumpTab honours 1.5x text and reduced motion', (tester) async {
    const label = 'Scaled body copy';

    await pumpTab(tester, const Text(label));
    final double unscaledHeight = tester.getSize(find.text(label)).height;

    late MediaQueryData media;
    await pumpTab(
      tester,
      Builder(
        builder: (context) {
          media = MediaQuery.of(context);
          return const Text(label);
        },
      ),
      size: const Size(1280, 720),
      textScaler: const TextScaler.linear(1.5),
      reduceMotion: true,
    );

    expect(media.textScaler.scale(20), 30);
    expect(media.disableAnimations, isTrue);

    final Size scaledSize = tester.getSize(find.text(label));
    expect(scaledSize.width, greaterThan(0));
    expect(scaledSize.height, greaterThan(unscaledHeight));
    expectNoOverflow(tester);
  });

  testWidgets('expectNoOverflow fails on a real overflow and drains it', (
    tester,
  ) async {
    await pumpTab(
      tester,
      const Row(
        children: <Widget>[
          SizedBox(width: 2000, height: 100),
          SizedBox(width: 2000, height: 100),
        ],
      ),
    );

    expect(
      () => expectNoOverflow(tester),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.message,
          'message',
          allOf(contains('Overflow'), contains('1100x700')),
        ),
      ),
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'expectNoOverflow must consume the overflow it reports',
    );
  });
}
