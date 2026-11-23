import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_slider.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> pumpSlider(
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
  testWidgets('renders label, readout, and a 32 px track', (tester) async {
    await pumpSlider(
      tester,
      const SizedBox(
        width: 360,
        child: BrassSlider(
          value: 25,
          min: 0,
          max: 100,
          divisions: 4,
          label: 'Volume',
          onChanged: _noop,
        ),
      ),
    );

    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('25'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(BrassSlider.trackKey)).height,
      BrassSlider.trackHeight,
    );
  });

  testWidgets('tapping the middle emits the snapped middle value', (
    tester,
  ) async {
    final changed = <double>[];
    await pumpSlider(
      tester,
      SizedBox(
        width: 360,
        child: BrassSlider(
          value: 0,
          min: 0,
          max: 100,
          divisions: 4,
          label: 'Volume',
          onChanged: changed.add,
        ),
      ),
    );

    await tester.tapAt(tester.getCenter(find.byKey(BrassSlider.trackKey)));
    await tester.pump();
    expect(changed, <double>[50]);
  });

  testWidgets('arrow keys move by one division and Home/End jump', (
    tester,
  ) async {
    final values = ValueNotifier<double>(50);
    addTearDown(values.dispose);
    await pumpSlider(
      tester,
      SizedBox(
        width: 360,
        child: ValueListenableBuilder<double>(
          valueListenable: values,
          builder: (context, value, _) {
            return BrassSlider(
              value: value,
              min: 0,
              max: 100,
              divisions: 4,
              autofocus: true,
              label: 'Volume',
              onChanged: (next) => values.value = next,
            );
          },
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(values.value, 75);
    expect(find.text('75'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(values.value, 50);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(values.value, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(values.value, 100);
  });

  testWidgets('exposes slider semantics with increase/decrease actions', (
    tester,
  ) async {
    await pumpSlider(
      tester,
      SizedBox(
        width: 360,
        child: BrassSlider(
          key: const ValueKey<String>('slider'),
          value: 40,
          min: 0,
          max: 100,
          divisions: 4,
          label: 'Opacity',
          onChanged: _noop,
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byKey(const ValueKey<String>('slider'))),
      isSemantics(
        label: 'Opacity',
        value: '40',
        isSlider: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );
  });

  testWidgets('custom valueLabel is printed instead of the number', (
    tester,
  ) async {
    await pumpSlider(
      tester,
      const SizedBox(
        width: 360,
        child: BrassSlider(
          value: 2,
          min: 0,
          max: 3,
          divisions: 3,
          label: 'Time of day',
          valueLabel: 'Evening',
          onChanged: _noop,
        ),
      ),
    );

    expect(find.text('Evening'), findsOneWidget);
  });

  testWidgets('disabled slider cannot be changed', (tester) async {
    await pumpSlider(
      tester,
      const SizedBox(
        width: 360,
        child: BrassSlider(
          key: ValueKey<String>('disabled-slider'),
          value: 20,
          min: 0,
          max: 100,
          label: 'Locked',
          onChanged: null,
        ),
      ),
    );

    await tester.tapAt(tester.getCenter(find.byKey(BrassSlider.trackKey)));
    await tester.pump();
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey<String>('disabled-slider')),
      ),
      isSemantics(isEnabled: false, isSlider: true),
    );
  });

  testWidgets('long label and readout wrap at 1.3x', (tester) async {
    await pumpSlider(
      tester,
      const SizedBox(
        width: 260,
        child: BrassSlider(
          value: 12.5,
          min: 0,
          max: 100,
          divisions: 8,
          label:
              'Dungeon completion percentage including every optional '
              'skulltula token',
          onChanged: _noop,
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(BrassSlider.trackKey), findsOneWidget);
  });
}

void _noop(double value) {}
