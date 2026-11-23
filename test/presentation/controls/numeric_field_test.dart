import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/controls/numeric_field.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> pumpNumeric(
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
  testWidgets('renders value, label, and unit', (tester) async {
    await pumpNumeric(
      tester,
      const SizedBox(
        width: 360,
        child: NumericField(
          value: 10,
          min: 0,
          max: 99,
          label: 'Hearts',
          unit: 'HP',
          onChanged: _noop,
        ),
      ),
    );

    expect(find.text('Hearts'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(NumericField.fieldKey))
          .decoration
          ?.suffixText,
      'HP',
    );
  });

  testWidgets('stepper increments and decrements', (tester) async {
    final value = ValueNotifier<num>(10);
    addTearDown(value.dispose);
    final calls = <num>[];

    await pumpNumeric(
      tester,
      SizedBox(
        width: 360,
        child: ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, _) {
            return NumericField(
              value: current,
              min: 0,
              max: 100,
              label: 'Arrows',
              onChanged: (next) {
                calls.add(next);
                value.value = next;
              },
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(NumericField.incrementKey));
    await tester.pump();
    expect(value.value, 11);
    expect(find.text('11'), findsOneWidget);

    await tester.tap(find.byKey(NumericField.decrementKey));
    await tester.pump();
    expect(value.value, 10);
    expect(calls, <num>[11, 10]);
  });

  testWidgets('steppers are reachable from the field with Tab', (tester) async {
    final value = ValueNotifier<num>(10);
    addTearDown(value.dispose);

    await pumpNumeric(
      tester,
      SizedBox(
        width: 360,
        child: ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, _) {
            return NumericField(
              value: current,
              min: 0,
              max: 100,
              label: 'Keyboard stepper',
              onChanged: (next) => value.value = next,
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(NumericField.fieldKey));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(value.value, 9);
  });

  testWidgets('typing then Enter commits once', (tester) async {
    final value = ValueNotifier<num>(10);
    addTearDown(value.dispose);
    final calls = <num>[];

    await pumpNumeric(
      tester,
      SizedBox(
        width: 360,
        child: ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, _) {
            return NumericField(
              value: current,
              min: 0,
              max: 100,
              label: 'Commit',
              onChanged: (next) {
                calls.add(next);
                value.value = next;
              },
            );
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(NumericField.fieldKey), '42');
    await tester.pump();
    expect(calls, isEmpty);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(value.value, 42);
    expect(calls, <num>[42]);
  });

  testWidgets('below-min text shows an inline error and never commits', (
    tester,
  ) async {
    final value = ValueNotifier<num>(10);
    addTearDown(value.dispose);
    final calls = <num>[];

    await pumpNumeric(
      tester,
      SizedBox(
        width: 360,
        child: ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, _) {
            return NumericField(
              value: current,
              min: 10,
              max: 100,
              label: 'Floor',
              onChanged: (next) {
                calls.add(next);
                value.value = next;
              },
            );
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(NumericField.fieldKey), '5');
    await tester.pump();
    expect(find.text('Must be at least 10.'), findsOneWidget);
    expect(find.byKey(NumericField.errorKey), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(calls, isEmpty);
    expect(value.value, 10);
    expect(
      tester
          .widget<TextField>(find.byKey(NumericField.fieldKey))
          .controller
          ?.text,
      '5',
    );
  });

  testWidgets('above-max text shows an inline error and never commits', (
    tester,
  ) async {
    final value = ValueNotifier<num>(50);
    addTearDown(value.dispose);
    final calls = <num>[];

    await pumpNumeric(
      tester,
      SizedBox(
        width: 360,
        child: ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, _) {
            return NumericField(
              value: current,
              min: 0,
              max: 100,
              label: 'Ceiling',
              onChanged: (next) {
                calls.add(next);
                value.value = next;
              },
            );
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(NumericField.fieldKey), '101');
    await tester.pump();
    expect(find.text('Must be at most 100.'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(calls, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(NumericField.fieldKey))
          .controller
          ?.text,
      '101',
    );
  });

  testWidgets('stepping past the maximum reports the error, not a clamp', (
    tester,
  ) async {
    final value = ValueNotifier<num>(100);
    addTearDown(value.dispose);
    final calls = <num>[];

    await pumpNumeric(
      tester,
      SizedBox(
        width: 360,
        child: ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, _) {
            return NumericField(
              value: current,
              min: 0,
              max: 100,
              label: 'Edge',
              onChanged: (next) {
                calls.add(next);
                value.value = next;
              },
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(NumericField.incrementKey));
    await tester.pump();
    expect(calls, isEmpty);
    expect(find.text('Must be at most 100.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(NumericField.fieldKey))
          .controller
          ?.text,
      '101',
    );
  });

  testWidgets('negative values are rejected when not allowed', (tester) async {
    final value = ValueNotifier<num>(1);
    addTearDown(value.dispose);
    final calls = <num>[];

    await pumpNumeric(
      tester,
      SizedBox(
        width: 360,
        child: ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, _) {
            return NumericField(
              value: current,
              min: 0,
              max: 10,
              allowNegative: false,
              label: 'Unsigned',
              onChanged: (next) {
                calls.add(next);
                value.value = next;
              },
            );
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(NumericField.fieldKey), '-1');
    await tester.pump();
    expect(find.text('Negative values are not allowed.'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('custom validator error is shown and blocks the commit', (
    tester,
  ) async {
    final value = ValueNotifier<num>(2);
    addTearDown(value.dispose);
    final calls = <num>[];

    await pumpNumeric(
      tester,
      SizedBox(
        width: 360,
        child: ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, _) {
            return NumericField(
              value: current,
              min: 0,
              max: 100,
              label: 'Even only',
              validator: (candidate) {
                if (candidate == null) return null;
                return candidate % 2 == 0 ? null : 'Must be even.';
              },
              onChanged: (next) {
                calls.add(next);
                value.value = next;
              },
            );
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(NumericField.fieldKey), '3');
    await tester.pump();
    expect(find.text('Must be even.'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(calls, isEmpty);
  });

  testWidgets('blur commits a valid value', (tester) async {
    final value = ValueNotifier<num>(1);
    addTearDown(value.dispose);
    final calls = <num>[];

    await pumpNumeric(
      tester,
      SizedBox(
        width: 360,
        child: ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, _) {
            return NumericField(
              value: current,
              min: 0,
              max: 100,
              label: 'Blur',
              onChanged: (next) {
                calls.add(next);
                value.value = next;
              },
            );
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(NumericField.fieldKey), '42');
    await tester.pump();
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(calls, <num>[42]);
  });

  testWidgets('garbage text shows a parse error and commits nothing', (
    tester,
  ) async {
    final calls = <num>[];
    await pumpNumeric(
      tester,
      SizedBox(
        width: 360,
        child: NumericField(value: 1, label: 'Parse', onChanged: calls.add),
      ),
    );

    await tester.enterText(find.byKey(NumericField.fieldKey), 'not a number');
    await tester.pump();
    expect(find.text('Enter a valid number.'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(calls, isEmpty);
  });

  testWidgets('long label and unit survive 1.3x text at 300 px', (
    tester,
  ) async {
    await pumpNumeric(
      tester,
      const SizedBox(
        width: 300,
        child: NumericField(
          value: 65535,
          min: 0,
          max: 65535,
          step: 10,
          label:
              'Maximum carry capacity including every purchased wallet '
              'upgrade',
          unit: 'rupees',
          onChanged: _noop,
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(NumericField.fieldKey), findsOneWidget);
  });
}

void _noop(num value) {}
