import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/controls/labelled_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> pumpLabelled(
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
  testWidgets('renders label above the supplied control', (tester) async {
    await pumpLabelled(
      tester,
      const SizedBox(
        width: 360,
        child: LabelledField(label: 'Player name', child: Text('Link')),
      ),
    );

    expect(find.text('Player name'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget);
  });

  testWidgets('modified and invalid stamps are visible words', (tester) async {
    await pumpLabelled(
      tester,
      const SizedBox(
        width: 360,
        child: LabelledField(
          label: 'Seed',
          modified: true,
          invalid: true,
          child: Text('0x1234'),
        ),
      ),
    );

    expect(find.text('MODIFIED'), findsOneWidget);
    expect(find.text('INVALID'), findsOneWidget);
  });

  testWidgets('help is a tooltip and the row semantic hint', (tester) async {
    await pumpLabelled(
      tester,
      const SizedBox(
        width: 360,
        child: LabelledField(
          key: ValueKey<String>('labelled'),
          label: 'Checksum',
          help: 'Computed over bytes 0x00..0x1C.',
          child: Text('0xAA'),
        ),
      ),
    );

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'Computed over bytes 0x00..0x1C.');
    expect(
      tester.getSemantics(find.byKey(const ValueKey<String>('labelled'))),
      isSemantics(label: 'Checksum', hint: 'Computed over bytes 0x00..0x1C.'),
    );
  });

  testWidgets('long label and stamps wrap at 1.3x', (tester) async {
    await pumpLabelled(
      tester,
      const SizedBox(
        width: 260,
        child: LabelledField(
          label: 'Optional dungeon completion flag stored in the scene table',
          help: 'A long help sentence that must remain readable.',
          modified: true,
          invalid: true,
          child: Text('control'),
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('MODIFIED'), findsOneWidget);
    expect(find.text('INVALID'), findsOneWidget);
  });

  testWidgets('invalid does not hide or disable the child', (tester) async {
    var tapped = false;
    await pumpLabelled(
      tester,
      SizedBox(
        width: 360,
        child: LabelledField(
          label: 'Value',
          invalid: true,
          child: TextButton(
            onPressed: () => tapped = true,
            child: const Text('Edit'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(tapped, isTrue);
  });
}
