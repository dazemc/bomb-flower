import 'dart:ui' show PointerDeviceKind;

import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/controls/toast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> pumpToastWidget(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1100, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('StoneToast prints tone, message, and a dismiss button', (
    tester,
  ) async {
    var dismissed = false;
    await pumpToastWidget(
      tester,
      Center(
        child: SizedBox(
          width: 360,
          child: StoneToast(
            message: 'Save written to slot 1',
            tone: StoneToastTone.success,
            dismissButtonKey: const ValueKey<String>('dismiss'),
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    expect(find.text('SUCCESS'), findsOneWidget);
    expect(find.text('Save written to slot 1'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(StoneToast.messageKey)),
      isSemantics(label: 'Success: Save written to slot 1', isLiveRegion: true),
    );

    await tester.tap(find.byKey(const ValueKey<String>('dismiss')));
    await tester.pump();
    expect(dismissed, isTrue);
  });

  testWidgets('ToastHost shows a toast and dismisses it by button', (
    tester,
  ) async {
    final key = GlobalKey<ToastHostState>();
    await pumpToastWidget(
      tester,
      ToastHost(key: key, child: const SizedBox.expand()),
    );

    final id = key.currentState!.show(
      'Exported save',
      tone: StoneToastTone.info,
      duration: const Duration(seconds: 30),
    );
    await tester.pump();
    expect(find.text('Exported save'), findsOneWidget);
    expect(key.currentState!.visibleCount, 1);

    await tester.tap(find.byKey(ToastHost.dismissKey(id)));
    await tester.pump();
    expect(find.text('Exported save'), findsNothing);
    expect(key.currentState!.visibleCount, 0);
  });

  testWidgets('at most three toasts stack and the fourth waits', (
    tester,
  ) async {
    final key = GlobalKey<ToastHostState>();
    await pumpToastWidget(
      tester,
      ToastHost(key: key, child: const SizedBox.expand()),
    );

    for (var index = 0; index < 4; index++) {
      key.currentState!.show(
        'Toast $index',
        duration: const Duration(seconds: 30),
      );
    }
    await tester.pump();

    expect(find.byType(StoneToast), findsNWidgets(3));
    expect(key.currentState!.visibleCount, 3);
    expect(key.currentState!.pendingCount, 1);
    expect(find.text('Toast 3'), findsNothing);

    key.currentState!.dismiss(0);
    await tester.pump();
    expect(find.byType(StoneToast), findsNWidgets(3));
    expect(key.currentState!.pendingCount, 0);
    expect(find.text('Toast 3'), findsOneWidget);
  });

  testWidgets('auto-dismiss fires after the requested duration', (
    tester,
  ) async {
    final key = GlobalKey<ToastHostState>();
    await pumpToastWidget(
      tester,
      ToastHost(key: key, child: const SizedBox.expand()),
    );

    key.currentState!.show(
      'Temporary',
      duration: const Duration(milliseconds: 200),
    );
    await tester.pump();
    expect(find.text('Temporary'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 199));
    expect(find.text('Temporary'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(find.text('Temporary'), findsNothing);
    expect(key.currentState!.visibleCount, 0);
  });

  testWidgets('hover pauses auto-dismiss and exit restarts it', (tester) async {
    final key = GlobalKey<ToastHostState>();
    await pumpToastWidget(
      tester,
      ToastHost(key: key, child: const SizedBox.expand()),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    key.currentState!.show(
      'Paused',
      duration: const Duration(milliseconds: 200),
    );
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(StoneToast)));
    await tester.pump();

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Paused'), findsOneWidget);

    await gesture.moveTo(const Offset(1, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('Paused'), findsNothing);
  });

  testWidgets('long messages wrap at 1.3x without overflowing the stack', (
    tester,
  ) async {
    final key = GlobalKey<ToastHostState>();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 700);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: BombFlowerThemeData.build(),
        builder: (context, appChild) {
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: appChild!,
          );
        },
        home: Scaffold(
          body: ToastHost(key: key, child: const SizedBox.expand()),
        ),
      ),
    );

    key.currentState!.show(
      'The save file was written but the sidecar checksum could not be '
      'verified because the source file changed while exporting.',
      tone: StoneToastTone.warning,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('sidecar checksum'), findsOneWidget);
  });
}
