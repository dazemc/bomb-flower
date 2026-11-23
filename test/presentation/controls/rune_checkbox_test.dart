import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/controls/rune_checkbox.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> pumpCheckbox(
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
  testWidgets('renders a 20 px mark in a 32 px hit target', (tester) async {
    await pumpCheckbox(
      tester,
      const RuneCheckbox(
        value: false,
        onChanged: _noop,
        label: 'Show raw values',
      ),
    );

    expect(
      tester.getSize(find.byKey(RuneCheckbox.markKey)),
      const Size(20, 20),
    );
    expect(
      tester.getSize(find.byKey(RuneCheckbox.controlKey)),
      const Size(32, 32),
    );
    expect(find.text('Show raw values'), findsOneWidget);
  });

  testWidgets('taps cycle a two-state checkbox', (tester) async {
    bool? changed;
    await pumpCheckbox(
      tester,
      RuneCheckbox(
        key: const ValueKey<String>('checkbox'),
        value: false,
        onChanged: (value) => changed = value,
        label: 'Enabled',
      ),
    );

    expect(
      tester.getSemantics(find.byKey(const ValueKey<String>('checkbox'))),
      isSemantics(
        label: 'Enabled',
        hasCheckedState: true,
        isChecked: false,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.byKey(RuneCheckbox.controlKey));
    await tester.pump();
    expect(changed, isTrue);
  });

  testWidgets('tristate cycles mixed, true, false, mixed', (tester) async {
    final value = ValueNotifier<bool?>(null);
    addTearDown(value.dispose);
    final seen = <bool?>[];

    await pumpCheckbox(
      tester,
      ValueListenableBuilder<bool?>(
        valueListenable: value,
        builder: (context, current, _) {
          return RuneCheckbox(
            key: const ValueKey<String>('tristate'),
            value: current,
            tristate: true,
            onChanged: (next) {
              seen.add(next);
              value.value = next;
            },
            label: 'Search all values',
          );
        },
      ),
    );

    expect(
      tester.getSemantics(find.byKey(const ValueKey<String>('tristate'))),
      isSemantics(isCheckStateMixed: true),
    );

    for (final expected in <bool?>[true, false, null]) {
      await tester.tap(find.byKey(RuneCheckbox.controlKey));
      await tester.pump();
      expect(value.value, expected);
    }
    expect(seen, <bool?>[true, false, null]);
  });

  testWidgets('Space activates the checkbox', (tester) async {
    bool? changed;
    await pumpCheckbox(
      tester,
      RuneCheckbox(
        value: true,
        autofocus: true,
        onChanged: (value) => changed = value,
        label: 'Keyboard',
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(changed, isFalse);
  });

  testWidgets('disabled checkbox keeps its label and semantics', (
    tester,
  ) async {
    await pumpCheckbox(
      tester,
      const RuneCheckbox(
        key: ValueKey<String>('disabled-checkbox'),
        value: true,
        onChanged: null,
        label: 'Read-only option',
      ),
    );

    await tester.tap(find.byKey(RuneCheckbox.controlKey));
    await tester.pump();
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey<String>('disabled-checkbox')),
      ),
      isSemantics(isEnabled: false, isChecked: true, label: 'Read-only option'),
    );
    expect(find.text('Read-only option'), findsOneWidget);
  });

  testWidgets('long labels wrap at 1.3x without overflow', (tester) async {
    await pumpCheckbox(
      tester,
      const SizedBox(
        width: 280,
        child: RuneCheckbox(
          value: true,
          onChanged: _noop,
          label:
              'Show every raw hexadecimal byte in the advanced data inspector '
              'instead of the friendly decoded values',
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(RuneCheckbox.controlKey), findsOneWidget);
  });
}

void _noop(bool? value) {}
