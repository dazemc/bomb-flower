import 'package:bomb_flower/presentation/theme/bomb_flower_colors.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/data/provenance_badge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> pumpBadge(
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
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}

void main() {
  for (final level in ProvenanceLevel.values) {
    testWidgets('${level.name} badge prints its level word', (tester) async {
      await pumpBadge(
        tester,
        ProvenanceBadge(level: level, source: 'progress.sav offset 0x1C'),
      );

      expect(find.text(level.label.toUpperCase()), findsOneWidget);
      expect(find.byIcon(level.icon), findsOneWidget);
    });
  }

  testWidgets('source is both the tooltip and the semantic tooltip', (
    tester,
  ) async {
    const source =
        'Verified against progress.sav bytes 0x1C..0x1D on 2026-11-20.';
    await pumpBadge(
      tester,
      const ProvenanceBadge(level: ProvenanceLevel.verified, source: source),
    );

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, source);
    final node = tester.getSemantics(
      find.bySemanticsLabel('Provenance: Verified'),
    );
    expect(node.label, 'Provenance: Verified');
    expect(node.tooltip, source);
  });

  testWidgets('unknown uses a danger-tinted, distinctly shaped badge', (
    tester,
  ) async {
    await pumpBadge(
      tester,
      const ProvenanceBadge(
        level: ProvenanceLevel.unknown,
        source: 'No citation available.',
      ),
    );

    expect(find.text('UNKNOWN'), findsOneWidget);
    expect(find.byIcon(Icons.question_mark), findsOneWidget);
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(ProvenanceBadge),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, BombFlowerColors.dangerSurface);
  });

  testWidgets('long citations do not affect badge layout at 1.3x', (
    tester,
  ) async {
    await pumpBadge(
      tester,
      const ProvenanceBadge(
        level: ProvenanceLevel.inferred,
        source:
            'Inferred from the actor catalogue entry for the Kokiri Sword and '
            'the scene table offset 0x1C, pending a verified fixture.',
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('INFERRED'), findsOneWidget);
  });
}
