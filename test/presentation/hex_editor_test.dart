import 'package:bomb_flower/presentation/widgets/hex/hex.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

HexEditorController makeController({
  int length = 512,
  int baseOffset = 0,
  bool readOnly = false,
  HexEditableRange? editableRange,
}) {
  final bytes = Uint8List(length);
  for (var offset = 0; offset < length; offset++) {
    bytes[offset] = offset & 0xFF;
  }
  return HexEditorController(
    bytes: bytes,
    baseOffset: baseOffset,
    readOnly: readOnly,
    editableRange: editableRange,
  );
}

Future<void> pumpEditor(
  WidgetTester tester,
  HexEditorController controller, {
  Size size = const Size(1000, 600),
  HexEditorThemeData theme = const HexEditorThemeData(),
  BitLabelProvider? bitLabelProvider,
  Map<int, ByteMarkKind> marks = const <int, ByteMarkKind>{},
  Set<int> modifiedOffsets = const <int>{},
  String? title,
  bool isLoading = false,
  String? errorMessage,
  VoidCallback? onRetry,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HexEditor(
          controller: controller,
          theme: theme,
          bitLabelProvider: bitLabelProvider,
          marks: marks,
          modifiedOffsets: modifiedOffsets,
          title: title,
          isLoading: isLoading,
          errorMessage: errorMessage,
          onRetry: onRetry,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> typeHex(WidgetTester tester, String digits) async {
  const keys = <String, LogicalKeyboardKey>{
    '0': LogicalKeyboardKey.digit0,
    '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2,
    '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4,
    '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6,
    '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8,
    '9': LogicalKeyboardKey.digit9,
    'a': LogicalKeyboardKey.keyA,
    'b': LogicalKeyboardKey.keyB,
    'c': LogicalKeyboardKey.keyC,
    'd': LogicalKeyboardKey.keyD,
    'e': LogicalKeyboardKey.keyE,
    'f': LogicalKeyboardKey.keyF,
  };
  for (final digit in digits.toLowerCase().split('')) {
    await tester.sendKeyEvent(keys[digit]!, character: digit);
    await tester.pump();
  }
}

void main() {
  group('HexEditor rendering', () {
    testWidgets('renders a 512-byte buffer with 16 bytes per row', (
      tester,
    ) async {
      final controller = makeController();
      await pumpEditor(tester, controller);

      final grid = find.byKey(const ValueKey<String>('hex-grid-16'));
      expect(
        find.descendant(of: grid, matching: find.text('00000000')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: grid, matching: find.text('00000010')),
        findsOneWidget,
      );
      expect(grid, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('hex-ascii-gutter')),
        findsWidgets,
      );
      expect(find.byType(HexByteCell), findsWidgets);
    });

    testWidgets('empty buffer shows the empty state', (tester) async {
      await pumpEditor(tester, HexEditorController(bytes: Uint8List(0)));

      expect(find.text('Empty buffer'), findsOneWidget);
      expect(find.text('This buffer contains 0 bytes.'), findsOneWidget);
      expect(find.byType(HexByteCell), findsNothing);
    });

    testWidgets('error state shows the message and retries', (tester) async {
      var retries = 0;
      await pumpEditor(
        tester,
        makeController(),
        errorMessage: 'Could not read this slot.',
        onRetry: () => retries++,
      );

      expect(find.text('Could not read this slot.'), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.warning_amber_rounded)).color,
        const HexEditorThemeData().dangerLight,
      );
      await tester.tap(find.byKey(HexEditor.retryKey));
      await tester.pump();
      expect(retries, 1);
    });
  });

  group('HexEditor editing', () {
    testWidgets('typing two hex digits overwrites the cell and marks it', (
      tester,
    ) async {
      final controller = makeController();
      await pumpEditor(tester, controller);

      await tester.tap(find.byKey(HexEditor.cellKey(0x1F)));
      await tester.pump();
      expect(controller.activeOffset, 0x1F);

      await typeHex(tester, 'a5');

      expect(controller.bytes[0x1F], 0xA5);
      expect(controller.marks[0x1F], ByteMarkKind.modified);
      expect(controller.modifiedOffsets, contains(0x1F));
      expect(controller.activeOffset, 0x20);
    });

    testWidgets('bytes outside editableRange are read-only with a tooltip', (
      tester,
    ) async {
      final controller = makeController(
        editableRange: const HexEditableRange(start: 4, end: 8),
      );
      await pumpEditor(tester, controller);

      expect(
        tester.widget<HexByteCell>(find.byKey(HexEditor.cellKey(3))).editable,
        isFalse,
      );
      expect(
        tester.widget<HexByteCell>(find.byKey(HexEditor.cellKey(5))).editable,
        isTrue,
      );
      final readOnlyTooltip = tester.widget<Tooltip>(
        find.descendant(
          of: find.byKey(HexEditor.cellKey(3)),
          matching: find.byType(Tooltip),
        ),
      );
      expect(readOnlyTooltip.message, 'Read-only byte');

      await tester.tap(find.byKey(HexEditor.cellKey(3)));
      await tester.pump();
      await typeHex(tester, 'ff');
      expect(controller.bytes[3], 0x03);
      expect(controller.marks, isEmpty);
    });

    testWidgets('read-only mode prevents typed edits', (tester) async {
      final controller = makeController(readOnly: true);
      await pumpEditor(tester, controller);

      await tester.tap(find.byKey(HexEditor.cellKey(2)));
      await tester.pump();
      await typeHex(tester, 'ff');

      expect(find.text('READ-ONLY'), findsOneWidget);
      expect(controller.bytes[2], 0x02);
      expect(controller.marks, isEmpty);
    });

    testWidgets('multi-byte selection is editable through the hex field', (
      tester,
    ) async {
      final controller = makeController();
      await pumpEditor(tester, controller);

      await tester.tap(find.byKey(HexEditor.cellKey(4)));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      for (var index = 0; index < 3; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(controller.selectionLength, 4);

      await tester.enterText(
        find.byKey(HexEditor.selectionFieldKey),
        '01 02 03 04',
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(controller.bytes.sublist(4, 8), <int>[1, 2, 3, 4]);
      expect(controller.modifiedOffsets, containsAll(<int>[4, 5, 6, 7]));
    });
  });

  group('HexEditor keyboard', () {
    testWidgets('arrow, Home and End keys move the selection', (tester) async {
      final controller = makeController();
      await pumpEditor(tester, controller);

      await tester.tap(find.byKey(HexEditor.cellKey(0x10)));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.activeOffset, 0x20);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(controller.activeOffset, 0x21);

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(controller.activeOffset, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(controller.activeOffset, controller.length - 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pump();
      expect(controller.activeOffset, controller.length - 1 - 16 * 8);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      expect(controller.activeOffset, controller.length - 1);
    });

    testWidgets('Shift+arrows extend a selection range', (tester) async {
      final controller = makeController();
      await pumpEditor(tester, controller);

      await tester.tap(find.byKey(HexEditor.cellKey(0x10)));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      for (var index = 0; index < 3; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(controller.selectionAnchor, 0x10);
      expect(controller.selectionExtent, 0x13);
      expect(controller.selectionStart, 0x10);
      expect(controller.selectionEnd, 0x14);
      expect(controller.selectionLength, 4);
    });

    testWidgets('Backspace clears the selection without writing', (
      tester,
    ) async {
      final controller = makeController();
      await pumpEditor(tester, controller);

      await tester.tap(find.byKey(HexEditor.cellKey(0x10)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(controller.selectionAnchor, isNull);
      expect(controller.selectionLength, 0);
      expect(controller.bytes[0x10], 0x10);
    });
  });

  group('HexEditor validation and states', () {
    testWidgets('out-of-range and non-hex addresses show inline errors', (
      tester,
    ) async {
      await pumpEditor(tester, makeController());

      await tester.enterText(find.byKey(HexEditor.jumpFieldKey), 'FFFFFFFF');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump();
      expect(find.textContaining('must be within'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byKey(HexEditor.jumpFieldKey), 'not-hex');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump();
      expect(find.textContaining('1-8 hex digits'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('search finds every match and cycles through them', (
      tester,
    ) async {
      final bytes = Uint8List(64);
      for (final offset in <int>[8, 24, 40]) {
        bytes.setRange(offset, offset + 4, <int>[0xDE, 0xAD, 0xBE, 0xEF]);
      }
      await pumpEditor(tester, HexEditorController(bytes: bytes));

      await tester.enterText(
        find.byKey(HexEditor.searchFieldKey),
        'DE AD BE EF',
      );
      await tester.pump();
      expect(find.text('3 matches'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);

      await tester.tap(find.byKey(HexEditor.searchNextKey));
      await tester.pump();
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.tap(find.byKey(HexEditor.searchNextKey));
      await tester.pump();
      expect(find.text('3 / 3'), findsOneWidget);

      await tester.tap(find.byKey(HexEditor.searchNextKey));
      await tester.pump();
      expect(find.text('1 / 3'), findsOneWidget);

      await tester.tap(find.byKey(HexEditor.searchPreviousKey));
      await tester.pump();
      expect(find.text('3 / 3'), findsOneWidget);
    });

    testWidgets('malformed search shows an inline error', (tester) async {
      await pumpEditor(tester, makeController());

      await tester.enterText(find.byKey(HexEditor.searchFieldKey), 'DE A');
      await tester.pump();

      expect(find.textContaining('even number of hex digits'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ASCII search mode finds text', (tester) async {
      final bytes = Uint8List(32);
      bytes.setRange(4, 9, 'HELLO'.codeUnits);
      await pumpEditor(tester, HexEditorController(bytes: bytes));

      await tester.enterText(find.byKey(HexEditor.searchFieldKey), 'HELLO');
      await tester.pump();
      expect(find.textContaining('even number of hex digits'), findsOneWidget);

      await tester.tap(find.byKey(HexEditor.searchAsciiKey));
      await tester.pump();
      expect(find.text('1 match'), findsOneWidget);

      await tester.tap(find.byKey(HexEditor.searchNextKey));
      await tester.pump();
      expect(find.text('1 / 1'), findsOneWidget);
    });

    testWidgets('bit labels render from the injected provider', (tester) async {
      final controller = makeController(length: 16)..selectByte(1);
      await pumpEditor(
        tester,
        controller,
        bitLabelProvider: (offset, bit) {
          if (offset != 1) return null;
          if (bit == 7) return 'Sign';
          if (bit == 0) return 'Carry';
          return null;
        },
      );

      expect(find.text('Sign'), findsOneWidget);
      expect(find.text('Carry'), findsOneWidget);
      expect(find.text('Bit inspector'), findsOneWidget);
    });

    testWidgets('marks and modified offsets tint cells and render a legend', (
      tester,
    ) async {
      final controller = makeController(length: 32)
        ..setMark(1, ByteMarkKind.invalid);
      await pumpEditor(
        tester,
        controller,
        marks: const <int, ByteMarkKind>{2: ByteMarkKind.verified},
        modifiedOffsets: const <int>{3},
      );

      for (final name in <String>[
        'Modified',
        'Invalid',
        'Unknown',
        'Verified',
      ]) {
        expect(find.text(name), findsOneWidget);
      }

      expect(
        tester.widget<HexByteCell>(find.byKey(HexEditor.cellKey(1))).mark,
        ByteMarkKind.invalid,
      );
      expect(
        tester.widget<HexByteCell>(find.byKey(HexEditor.cellKey(2))).mark,
        ByteMarkKind.verified,
      );
      expect(
        tester.widget<HexByteCell>(find.byKey(HexEditor.cellKey(3))).modified,
        isTrue,
      );
    });

    testWidgets('invalid marks paint the lifted danger tone on the canopy', (
      tester,
    ) async {
      const theme = HexEditorThemeData();
      final controller = makeController(length: 32)
        ..setMark(1, ByteMarkKind.invalid);
      await pumpEditor(tester, controller);

      final cell = find.byKey(HexEditor.cellKey(1));
      expect(tester.widget<HexByteCell>(cell).mark, ByteMarkKind.invalid);

      final glyph = tester.widget<Text>(
        find.descendant(of: cell, matching: find.byType(Text)),
      );
      expect(glyph.style?.color, theme.dangerLight);
      expect(glyph.style?.color, isNot(theme.danger));
    });

    testWidgets('read-only badge paints the lifted danger tone', (tester) async {
      const theme = HexEditorThemeData();
      await pumpEditor(tester, makeController(length: 16, readOnly: true));

      final label = tester.widget<Text>(find.text('READ-ONLY'));
      expect(label.style?.color, theme.dangerLight);
      expect(label.style?.color, isNot(theme.danger));

      final badge = tester.widget<Container>(
        find
            .ancestor(of: find.text('READ-ONLY'), matching: find.byType(Container))
            .first,
      );
      final border = (badge.decoration! as BoxDecoration).border!;
      expect(border.top.color, theme.dangerLight);
    });

    testWidgets('clicking a bit toggles exactly that bit', (tester) async {
      final controller = HexEditorController(bytes: Uint8List(16))
        ..selectByte(1);
      await pumpEditor(tester, controller);

      await tester.tap(find.byKey(HexEditor.bitKey(1, 3)));
      await tester.pump();

      expect(controller.bytes[1], 0x08);
      expect(controller.bytes[0], 0x00);
      expect(controller.bytes[2], 0x00);
    });

    testWidgets('2/4-byte selections show both endian interpretations', (
      tester,
    ) async {
      final controller = HexEditorController(
        bytes: Uint8List.fromList(<int>[0xDE, 0xAD, 0xBE, 0xEF]),
      )..selectRange(0, 3);
      await pumpEditor(tester, controller);

      expect(find.text('Big endian'), findsOneWidget);
      expect(find.text('Little endian'), findsOneWidget);
      expect(find.textContaining('0xDEADBEEF'), findsOneWidget);
      expect(find.textContaining('0xEFBEADDE'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(HexEditor.selectionFieldKey))
            .controller
            ?.text,
        'DE AD BE EF',
      );
    });

    testWidgets('a 120 KB buffer stays virtualised', (tester) async {
      final controller = HexEditorController(bytes: Uint8List(120572));
      await pumpEditor(tester, controller);

      final grid = find.byKey(const ValueKey<String>('hex-grid-16'));
      expect(
        find.descendant(of: grid, matching: find.text('00000000')),
        findsOneWidget,
      );
      expect(find.byKey(HexEditor.cellKey(120571)), findsNothing);
      expect(
        find.byType(HexByteCell).evaluate().length,
        lessThan(1000),
        reason: 'Only viewport rows (plus cache extent) should be built.',
      );
    });

    testWidgets('700px width uses 8 bytes per row without overflow', (
      tester,
    ) async {
      final controller = makeController()..selectByte(8);
      await pumpEditor(tester, controller, size: const Size(700, 600));

      expect(find.byKey(const ValueKey<String>('hex-grid-8')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('hex-ascii-gutter')),
        findsNothing,
      );
      expect(find.text('Bit inspector'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('HexEditorController bounds guards', () {
    test('writeByte beyond the buffer throws RangeError', () {
      final controller = HexEditorController(bytes: Uint8List(16));

      expect(() => controller.writeByte(16, 0x00), throwsA(isA<RangeError>()));
      expect(() => controller.writeByte(-1, 0x00), throwsA(isA<RangeError>()));
      expect(() => controller.writeByte(0, 0x100), throwsA(isA<RangeError>()));
      expect(controller.bytes[0], 0);
    });

    test('writeByte outside editableRange throws and never clamps', () {
      final controller = HexEditorController(
        bytes: Uint8List(16),
        editableRange: const HexEditableRange(start: 4, end: 8),
      );

      expect(controller.isEditable(4), isTrue);
      expect(controller.isEditable(7), isTrue);
      expect(controller.isEditable(3), isFalse);
      expect(controller.isEditable(8), isFalse);

      expect(() => controller.writeByte(3, 0xAA), throwsA(isA<RangeError>()));
      expect(() => controller.writeByte(8, 0xAA), throwsA(isA<RangeError>()));
      expect(() => controller.toggleBit(3, 0), throwsA(isA<RangeError>()));

      controller.writeByte(4, 0xAA);
      expect(controller.bytes[4], 0xAA);
      expect(controller.bytes[3], 0);
      expect(controller.bytes[8], 0);
    });

    test('toggleBit flips exactly one bit', () {
      final controller = HexEditorController(
        bytes: Uint8List.fromList(<int>[0x00, 0x00, 0x00]),
      );

      controller.toggleBit(1, 3);
      expect(controller.bytes, <int>[0x00, 0x08, 0x00]);

      controller.toggleBit(1, 3);
      expect(controller.bytes, <int>[0x00, 0x00, 0x00]);
    });

    test('read-only controllers refuse writes with StateError', () {
      final controller = HexEditorController(
        bytes: Uint8List(4),
        readOnly: true,
      );

      expect(() => controller.writeByte(0, 1), throwsStateError);
      expect(() => controller.toggleBit(0, 0), throwsStateError);
    });
  });

  group('HexEditorThemeData danger tokens', () {
    test('invalid marks use the lifted canopy tone, not the parchment danger', () {
      const theme = HexEditorThemeData();
      final invalid = theme.markColor(ByteMarkKind.invalid);

      expect(invalid, theme.dangerLight);
      expect(invalid, const Color(0xFFE88B7D));
      expect(invalid, isNot(theme.danger));
    });
  });
}
