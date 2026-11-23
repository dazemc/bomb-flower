import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/data/stat_tile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> pumpTile(
  WidgetTester tester,
  Widget child, {
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 700);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      builder: (context, appChild) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: appChild!,
        );
      },
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: child,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders label, string value, and unit', (tester) async {
    await pumpTile(
      tester,
      const SizedBox(
        width: 260,
        child: StatTile(
          label: 'Hearts',
          value: '20',
          unit: 'of 20',
          icon: Icons.favorite_outline,
        ),
      ),
    );

    expect(find.text('HEARTS'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('of 20'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_outline), findsOneWidget);
  });

  testWidgets('warning severity prints a word and a glyph, not just colour', (
    tester,
  ) async {
    await pumpTile(
      tester,
      const SizedBox(
        width: 260,
        child: StatTile(
          label: 'Checksum',
          value: 'Mismatch',
          severity: StatSeverity.warning,
        ),
      ),
    );

    expect(find.text('WARNING'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(StatTile)).label,
      'Checksum: Mismatch, Warning',
    );
  });

  testWidgets('the help text is a tooltip and the semantic hint', (
    tester,
  ) async {
    await pumpTile(
      tester,
      const SizedBox(
        width: 300,
        child: StatTile(
          key: ValueKey<String>('stat'),
          label: 'Skulltulas',
          value: '37',
          unit: 'of 100',
          help: 'Collected from the House of Skulltula.',
        ),
      ),
    );

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'Collected from the House of Skulltula.');
    expect(
      tester.getSemantics(find.byKey(const ValueKey<String>('stat'))),
      isSemantics(
        label: 'Skulltulas: 37 of 100',
        hint: 'Collected from the House of Skulltula.',
      ),
    );
  });

  testWidgets('long label and value wrap at 1.3x in a narrow tile', (
    tester,
  ) async {
    await pumpTile(
      tester,
      const SizedBox(
        width: 260,
        child: StatTile(
          label: 'Total collected gold skulltula tokens across every region',
          value: '123,456,789',
          unit: 'tokens',
          severity: StatSeverity.info,
          help: 'A deliberately long help sentence.',
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('123,456,789'), findsOneWidget);
  });

  testWidgets('unavailable tile never invents a value', (tester) async {
    await pumpTile(
      tester,
      const SizedBox(
        width: 260,
        child: UnavailableStatTile(label: 'Play time', icon: Icons.schedule),
      ),
    );

    expect(find.text('—'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
  });
}
