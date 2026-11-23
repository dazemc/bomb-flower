import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bomb_flower/presentation/theme/bomb_flower_colors.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/chrome/app_title_bar.dart';
import 'package:bomb_flower/presentation/widgets/common/bomb_flower_mark.dart';
import 'package:bomb_flower/presentation/widgets/common/brand_mark.dart';
import 'package:bomb_flower/presentation/widgets/common/empty_state.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Set `BRAND_MARK_CAPTURE=1` to write review PNGs into
/// `build/brand-mark-review/`. A normal `flutter test` only registers a no-op,
/// so it never writes files.
const String _captureFlag = 'BRAND_MARK_CAPTURE';

const String _outDir = 'build/brand-mark-review';

const Map<String, String> _fonts = <String, String>{
  'Noto Sans': '/usr/share/fonts/noto/NotoSans-Regular.ttf',
  'Noto Serif': '/usr/share/fonts/noto/NotoSerif-Regular.ttf',
  'Liberation Sans': '/usr/share/fonts/liberation/LiberationSans-Regular.ttf',
  'DejaVu Sans': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
};

Future<void> _loadFonts() async {
  for (final entry in _fonts.entries) {
    final file = File(entry.value);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    final loader = FontLoader(entry.key)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

Future<ui.Image> _grab(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late ui.Image image;
  await tester.runAsync(() async {
    image = await boundary.toImage(pixelRatio: 1);
  });
  return image;
}

/// Lets a freshly pumped `Image` finish decoding in the real event loop, then
/// paints the decoded frame. Without this the first grab of each cache key is
/// blank in widget tests.
Future<void> _settleImage(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
  );
  await tester.pump();
}

Future<void> _writePng(
  WidgetTester tester,
  ui.Image image,
  String name,
) async {
  await tester.runAsync(() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/$name')..createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// Nearest-neighbour upscale, so a reviewer sees the actual pixels.
Future<void> _writeUpscaled(
  WidgetTester tester,
  ui.Image image,
  String name,
  int factor,
) async {
  await tester.runAsync(() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final src = data!.buffer.asUint8List();
    final w = image.width;
    final h = image.height;
    final out = Uint8List(w * factor * h * factor * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final si = (y * w + x) * 4;
        for (var dy = 0; dy < factor; dy++) {
          for (var dx = 0; dx < factor; dx++) {
            final di =
                (((y * factor + dy) * w * factor) + x * factor + dx) * 4;
            out[di] = src[si];
            out[di + 1] = src[si + 1];
            out[di + 2] = src[si + 2];
            out[di + 3] = src[si + 3];
          }
        }
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      out,
      w * factor,
      h * factor,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final scaled = await completer.future;
    final png = await scaled.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/$name')..createSync(recursive: true);
    file.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Widget _app(Widget child, {Color background = BombFlowerColors.canopy1}) {
  return MaterialApp(
    theme: BombFlowerThemeData.build(),
    home: Scaffold(
      backgroundColor: background,
      body: Center(child: child),
    ),
  );
}

Widget _markTile({
  required double size,
  required Color background,
  bool monochrome = false,
  bool onDark = true,
}) {
  return RepaintBoundary(
    child: ColoredBox(
      color: background,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: BombFlowerMark(
            size: size,
            monochrome: monochrome,
            onDark: onDark,
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.environment[_captureFlag] != '1') {
    test('brand mark captures are opt-in via $_captureFlag=1', () {});
    return;
  }

  testWidgets('write the brand mark review captures', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Directory(_outDir).createSync(recursive: true);

    Future<void> captureMark(
      String name, {
      required double size,
      required Color background,
      bool monochrome = false,
      bool onDark = true,
    }) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        _app(
          RepaintBoundary(
            key: key,
            child: _markTile(
              size: size,
              background: background,
              monochrome: monochrome,
              onDark: onDark,
            ),
          ),
          background: background,
        ),
      );
      await _settleImage(tester);
      final image = await _grab(tester, key);
      await _writePng(tester, image, name);
      if (size == 24) {
        await _writeUpscaled(tester, image, '${name.split('.').first}_x8.png', 8);
      }
      image.dispose();
    }

    await captureMark(
      'mark_24_wood.png',
      size: 24,
      background: BombFlowerColors.wood,
    );
    await captureMark(
      'mark_32_wood.png',
      size: 32,
      background: BombFlowerColors.wood,
    );
    await captureMark(
      'mark_48_parchment.png',
      size: 48,
      background: BombFlowerColors.parchment,
      onDark: false,
    );
    await captureMark(
      'mark_24_mono_wood.png',
      size: 24,
      background: BombFlowerColors.wood,
      monochrome: true,
    );
    await captureMark(
      'mark_32_mono_wood.png',
      size: 32,
      background: BombFlowerColors.wood,
      monochrome: true,
    );

    // The vector fallback, for comparison against the primary artwork.
    for (final entry in <(String, BrandMark)>[
      ('brand_mark_painter_48.png', const BrandMark(size: 48)),
      (
        'brand_mark_painter_48_mono.png',
        const BrandMark(size: 48, monochrome: true),
      ),
    ]) {
      final key = GlobalKey();
      await tester.pumpWidget(
        _app(
          RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: BombFlowerColors.wood,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(child: entry.$2),
              ),
            ),
          ),
          background: BombFlowerColors.wood,
        ),
      );
      await _settleImage(tester);
      final image = await _grab(tester, key);
      await _writePng(tester, image, entry.$1);
      image.dispose();
    }

    // The first screen: an empty state at 48 px on both surfaces.
    Future<void> captureEmptyState(String name, {required bool onDark}) async {
      final key = GlobalKey();
      final background = onDark
          ? BombFlowerColors.canopy1
          : BombFlowerColors.parchment;
      await tester.pumpWidget(
        _app(
          RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: background,
              child: SizedBox(
                width: 520,
                height: 300,
                child: EmptyState(
                  title: 'No save loaded',
                  message: 'Open a save to begin.',
                  onDark: onDark,
                ),
              ),
            ),
          ),
          background: background,
        ),
      );
      await tester.pumpAndSettle();
      await _settleImage(tester);
      final image = await _grab(tester, key);
      await _writePng(tester, image, name);
      image.dispose();
    }

    await captureEmptyState('empty_state_48_wood.png', onDark: true);
    await captureEmptyState('empty_state_48_parchment.png', onDark: false);

    // Title bar at the two integrator sizes, with the real system font.
    Future<void> captureTitleBar(String name, Size size) async {
      tester.view.physicalSize = size;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: BombFlowerThemeData.build(),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: const Column(
                  children: <Widget>[
                    AppTitleBar(interactive: false, saveName: 'slot_00'),
                    Expanded(
                      child: ColoredBox(color: BombFlowerColors.canopy0),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _settleImage(tester);
      final image = await _grab(tester, key);
      await _writePng(tester, image, name);
      image.dispose();
    }

    await captureTitleBar('title_bar_1360x880.png', const Size(1360, 880));
    await captureTitleBar('title_bar_1100x700.png', const Size(1100, 700));
  });
}
