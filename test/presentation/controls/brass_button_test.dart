import 'package:bomb_flower/presentation/theme/bomb_flower_spacing.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/common/brass_button.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> pumpButton(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 700);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}

/// The opaque detector that owns the button's hit area.
final Finder _hitBox = find.descendant(
  of: find.byType(BrassButton),
  matching: find.byType(GestureDetector),
);

void main() {
  testWidgets('hit box covers the whole control box, not just the glyphs', (
    tester,
  ) async {
    var presses = 0;
    await pumpButton(
      tester,
      BrassButton(label: 'Open save', onPressed: () => presses++),
    );

    expect(_hitBox, findsOneWidget);
    final defaultSize = tester.getSize(_hitBox);
    expect(defaultSize.height, BombFlowerSpacing.buttonHeight);
    expect(
      defaultSize.width,
      greaterThanOrEqualTo(BombFlowerSpacing.minHitTarget),
    );

    // A point inside the control box but outside the painted glyph's visual
    // centre -- 4 px in from the top-left corner, in the border/padding band
    // rather than on the label -- still has to activate the button.
    final rect = tester.getRect(_hitBox);
    await tester.tapAt(rect.topLeft + const Offset(4, 4));
    await tester.pump();
    expect(presses, 1);

    // An explicit height must move the hit box with the painted control.
    await pumpButton(
      tester,
      BrassButton(label: 'Open save', height: 48, onPressed: _noop),
    );
    expect(tester.getSize(_hitBox).height, 48);
    expect(
      tester.getSize(_hitBox).width,
      greaterThanOrEqualTo(BombFlowerSpacing.minHitTarget),
    );
  });
}

void _noop() {}
