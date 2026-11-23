import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_toggle.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> pumpToggle(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1100, 800),
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      builder: (context, appChild) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: textScaler,
            disableAnimations: disableAnimations,
          ),
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
  testWidgets('renders a 44x24 switch in a 32 px hit target', (tester) async {
    await pumpToggle(
      tester,
      const BrassToggle(
        value: false,
        onChanged: _noop,
        label: 'Equip on load',
        description: 'Applies when a save is opened.',
      ),
    );

    expect(
      tester.getSize(find.byKey(BrassToggle.trackKey)),
      const Size(44, 24),
    );
    expect(
      tester.getSize(find.byKey(BrassToggle.controlKey)),
      const Size(44, 32),
    );
    expect(find.text('Equip on load'), findsOneWidget);
    expect(find.text('Applies when a save is opened.'), findsOneWidget);
  });

  testWidgets('exposes a labelled toggled state and taps to true', (
    tester,
  ) async {
    bool? changed;
    await pumpToggle(
      tester,
      BrassToggle(
        key: const ValueKey<String>('toggle'),
        value: false,
        onChanged: (value) => changed = value,
        label: 'Equip on load',
      ),
    );

    final node = tester.getSemantics(
      find.byKey(const ValueKey<String>('toggle')),
    );
    expect(
      node,
      isSemantics(
        label: 'Equip on load',
        hasToggledState: true,
        isToggled: false,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.byKey(BrassToggle.controlKey));
    await tester.pump();
    expect(changed, isTrue);
  });

  testWidgets('Space toggles when focused', (tester) async {
    bool? changed;
    await pumpToggle(
      tester,
      BrassToggle(
        value: true,
        autofocus: true,
        onChanged: (value) => changed = value,
        label: 'Focus',
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(changed, isFalse);
  });

  testWidgets('disabled toggle stays visible but cannot change', (
    tester,
  ) async {
    var calls = 0;
    await pumpToggle(
      tester,
      BrassToggle(
        key: const ValueKey<String>('disabled-toggle'),
        value: true,
        onChanged: null,
        enabled: false,
        label: 'Locked',
      ),
    );

    await tester.tap(find.byKey(BrassToggle.controlKey));
    await tester.pump();
    expect(calls, 0);
    final node = tester.getSemantics(
      find.byKey(const ValueKey<String>('disabled-toggle')),
    );
    expect(node, isSemantics(isEnabled: false, isToggled: true));
    expect(find.text('Locked'), findsOneWidget);
  });

  testWidgets('long labels wrap at 320 px and 1.3x without overflow', (
    tester,
  ) async {
    await pumpToggle(
      tester,
      const SizedBox(
        width: 300,
        child: BrassToggle(
          value: false,
          onChanged: _noop,
          label:
              'Automatically equip the selected shield on save load and after '
              'every dungeon transition',
          description:
              'This is a deliberately long description that must wrap rather '
              'than clip or push the switch off the panel.',
        ),
      ),
      size: const Size(400, 700),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(BrassToggle.controlKey), findsOneWidget);
  });

  testWidgets('reduced motion shortens the thumb animation', (tester) async {
    await pumpToggle(
      tester,
      const BrassToggle(value: false, onChanged: _noop, label: 'Reduced'),
      disableAnimations: true,
    );

    await tester.tap(find.byKey(BrassToggle.controlKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
  });
}

void _noop(bool value) {}
