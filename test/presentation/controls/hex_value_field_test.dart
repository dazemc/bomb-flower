import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/controls/hex_value_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> pumpHex(
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
  testWidgets('renders canonical hex and the decimal equivalent', (
    tester,
  ) async {
    await pumpHex(
      tester,
      const SizedBox(
        width: 360,
        child: HexValueField(
          value: 0x00FF,
          width: 4,
          label: 'Seed',
          onChanged: _noop,
        ),
      ),
    );

    expect(find.text('Seed'), findsOneWidget);
    expect(find.text('0x00FF'), findsOneWidget);
    expect(find.text('Decimal 255'), findsOneWidget);
  });

  testWidgets('bare hex commits on Enter and normalises', (tester) async {
    final changed = <int>[];
    await pumpHex(
      tester,
      SizedBox(
        width: 360,
        child: HexValueField(
          value: 0,
          width: 4,
          label: 'Value',
          onChanged: changed.add,
        ),
      ),
    );

    await tester.enterText(find.byKey(HexValueField.fieldKey), 'beef');
    await tester.pump();
    expect(find.text('Decimal 48,879'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(changed, <int>[0xBEEF]);
    expect(
      tester
          .widget<TextField>(find.byKey(HexValueField.fieldKey))
          .controller
          ?.text,
      '0xBEEF',
    );
  });

  testWidgets('0xZZ is rejected inline and never committed', (tester) async {
    final changed = <int>[];
    await pumpHex(
      tester,
      SizedBox(
        width: 360,
        child: HexValueField(
          value: 0,
          width: 4,
          label: 'Value',
          onChanged: changed.add,
        ),
      ),
    );

    await tester.enterText(find.byKey(HexValueField.fieldKey), '0xZZ');
    await tester.pump();
    expect(find.text('Use only hex digits 0-9 and A-F.'), findsOneWidget);
    expect(find.byKey(HexValueField.errorKey), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(changed, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(HexValueField.fieldKey))
          .controller
          ?.text,
      '0xZZ',
    );
  });

  testWidgets('too-wide values are rejected with the width in the message', (
    tester,
  ) async {
    final changed = <int>[];
    await pumpHex(
      tester,
      SizedBox(
        width: 360,
        child: HexValueField(
          value: 0,
          width: 4,
          label: 'Value',
          onChanged: changed.add,
        ),
      ),
    );

    await tester.enterText(find.byKey(HexValueField.fieldKey), '0x12345');
    await tester.pump();
    expect(find.text('Use at most 4 hex digits (16 bits).'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(changed, isEmpty);
  });

  testWidgets('maxValue bound is reported instead of clamped', (tester) async {
    final changed = <int>[];
    await pumpHex(
      tester,
      SizedBox(
        width: 360,
        child: HexValueField(
          value: 0,
          width: 4,
          maxValue: 255,
          label: 'Byte',
          onChanged: changed.add,
        ),
      ),
    );

    await tester.enterText(find.byKey(HexValueField.fieldKey), '0x1FF');
    await tester.pump();
    expect(find.text('Must be at most 255 (0x00FF).'), findsOneWidget);
    expect(changed, isEmpty);
  });

  testWidgets('blur commits a valid bare value', (tester) async {
    final changed = <int>[];
    await pumpHex(
      tester,
      SizedBox(
        width: 360,
        child: HexValueField(
          value: 0,
          width: 2,
          label: 'Byte',
          onChanged: changed.add,
        ),
      ),
    );

    await tester.enterText(find.byKey(HexValueField.fieldKey), '7f');
    await tester.pump();
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(changed, <int>[0x7F]);
  });

  testWidgets('long label survives 1.3x text at 280 px', (tester) async {
    await pumpHex(
      tester,
      const SizedBox(
        width: 280,
        child: HexValueField(
          value: 0x1234,
          width: 4,
          label: 'Raw actor definition pointer offset in the scene table',
          onChanged: _noop,
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(HexValueField.fieldKey), findsOneWidget);
  });
}

void _noop(int value) {}
