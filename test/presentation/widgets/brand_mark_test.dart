import 'dart:io';
import 'dart:ui' as ui;

import 'package:bomb_flower/presentation/theme/bomb_flower_colors.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/chrome/app_title_bar.dart';
import 'package:bomb_flower/presentation/widgets/common/bomb_flower_mark.dart';
import 'package:bomb_flower/presentation/widgets/common/brand_mark.dart';
import 'package:bomb_flower/presentation/widgets/common/empty_state.dart';
import 'package:bomb_flower/presentation/widgets/common/open_save_scope.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A background no mark colour uses, so "differing from the background" is a
/// real ink measurement rather than a near-match.
const Color _probeBackground = Color(0xFF3366CC);

const List<double> _sizes = <double>[16, 24, 32, 48];

Widget _themed(Widget child, {Color background = BombFlowerColors.canopy1}) {
  return MaterialApp(
    theme: BombFlowerThemeData.build(),
    home: Scaffold(
      backgroundColor: background,
      body: Center(child: child),
    ),
  );
}

/// The asset provider behind a rendered [BombFlowerMark].
String _assetPathOf(WidgetTester tester, Finder mark) {
  final image = tester.widget<Image>(
    find.descendant(of: mark, matching: find.byType(Image)),
  );
  final provider = image.image;
  if (provider is ResizeImage) {
    final inner = provider.imageProvider;
    expect(inner, isA<AssetImage>());
    return (inner as AssetImage).assetName;
  }
  expect(provider, isA<AssetImage>());
  return (provider as AssetImage).assetName;
}

class _Rendered {
  _Rendered(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Renders [child] on a known background at 4x and returns raw RGBA.
Future<_Rendered> _renderRaw(WidgetTester tester, Widget child) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    _themed(
      RepaintBoundary(
        key: key,
        child: ColoredBox(color: _probeBackground, child: child),
      ),
      background: _probeBackground,
    ),
  );
  await tester.pump();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late ui.Image image;
  late ByteData data;
  late int width;
  late int height;
  await tester.runAsync(() async {
    image = await boundary.toImage(pixelRatio: 4);
    width = image.width;
    height = image.height;
    data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
  });
  return _Rendered(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    width,
    height,
  );
}

/// Pixel statistics over a rendered mark.
class _Stats {
  _Stats({
    required this.coverage,
    required this.distinctColours,
    required this.distinctBuckets,
    required this.toneShare,
    required this.offLineFraction,
  });

  final double coverage;
  final int distinctColours;
  final int distinctBuckets;
  final double toneShare;
  final double offLineFraction;
}

_Stats _stats(_Rendered rendered, {required bool monochrome}) {
  final bgR = (_probeBackground.r * 255).round();
  final bgG = (_probeBackground.g * 255).round();
  final bgB = (_probeBackground.b * 255).round();
  final bytes = rendered.bytes;
  // `toImage` darkens the outermost row/column of a repaint boundary (clip
  // antialiasing against the layer edge). Skip a 2 px border so that artefact
  // is not mistaken for a second hue.
  const border = 2;
  final startX = border;
  final endX = rendered.width - border;
  final startY = border;
  final endY = rendered.height - border;
  final total = (endX - startX) * (endY - startY);
  final colours = <int>{};
  final buckets = <int>{};
  final tone = BombFlowerColors.bone;
  final tr = (tone.r * 255).round();
  final tg = (tone.g * 255).round();
  final tb = (tone.b * 255).round();
  var ink = 0;
  var offLine = 0;
  var tonePixels = 0;

  for (var y = startY; y < endY; y++) {
    for (var x = startX; x < endX; x++) {
      final i = y * rendered.width + x;
      final r = bytes[i * 4];
      final g = bytes[i * 4 + 1];
      final b = bytes[i * 4 + 2];
      if (r == bgR && g == bgG && b == bgB) continue;
      ink++;
      colours.add((r << 16) | (g << 8) | b);
      buckets.add(((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4));
      if ((r - tr).abs() <= 2 && (g - tg).abs() <= 2 && (b - tb).abs() <= 2) {
        tonePixels++;
      }
      if (monochrome) {
        // Short note for future readers: the check below is a blend-line test,
        // not a hue test. A correctly tinted mark is near-grey by construction;
        // antialiasing turns edge pixels into a continuous blend of the single
        // tone and the background, so "one hue" means "every ink pixel lies on
        // that line", not "the hue spread is small" (HSV hue on a near-grey ink
        // is numerically unstable). Likewise exact RGB counts grow with the
        // number of blend steps, so they cannot be an absolute threshold.
        final dr = tr - bgR;
        final dg = tg - bgG;
        final db = tb - bgB;
        final denom = dr * dr + dg * dg + db * db;
        final t = denom == 0
            ? 0.0
            : ((r - bgR) * dr + (g - bgG) * dg + (b - bgB) * db) / denom;
        final expectedR = (bgR + t * dr).round();
        final expectedG = (bgG + t * dg).round();
        final expectedB = (bgB + t * db).round();
        if ((r - expectedR).abs() > 6 ||
            (g - expectedG).abs() > 6 ||
            (b - expectedB).abs() > 6) {
          offLine++;
        }
      }
    }
  }

  final stats = _Stats(
    coverage: ink / total,
    distinctColours: colours.length,
    distinctBuckets: buckets.length,
    toneShare: ink == 0 ? 0 : tonePixels / ink,
    offLineFraction: ink == 0 ? 0 : offLine / ink,
  );
  if (Platform.environment['BRAND_MARK_STATS'] == '1') {
    debugPrint(
      'BRAND_MARK_STATS mono=$monochrome coverage=${stats.coverage.toStringAsFixed(4)} '
      'exact=${stats.distinctColours} buckets=${stats.distinctBuckets} '
      'toneShare=${stats.toneShare.toStringAsFixed(4)} '
      'offLine=${stats.offLineFraction.toStringAsFixed(4)}',
    );
  }
  return stats;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the brand artwork is bundled and is a PNG', () async {
    final data = await rootBundle.load(kBrandMarkAsset);
    expect(data.lengthInBytes, greaterThan(0));
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    expect(
      bytes.take(8).toList(),
      <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    );
  });

  testWidgets('BrandMark honours the requested width at 16/24/32/48', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 320);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in _sizes) {
      for (final onDark in <bool>[true, false]) {
        for (final monochrome in <bool>[false, true]) {
          await tester.pumpWidget(
            _themed(
              BrandMark(
                size: size,
                onDark: onDark,
                monochrome: monochrome,
                tone: BombFlowerColors.bone,
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          final mark = find.byType(BrandMark);
          expect(mark, findsOneWidget);
          expect(tester.getSize(mark).width, size);
          expect(tester.getSize(mark).height, closeTo(size / 1.3, 0.01));
        }
      }
    }
  });

  testWidgets('colour mark paints a real, multi-colour region at 48px', (
    tester,
  ) async {
    final rendered = await _renderRaw(tester, const BrandMark(size: 48));
    final stats = _stats(rendered, monochrome: false);
    expect(
      stats.coverage,
      greaterThan(0.15),
      reason: 'a blank or near-blank painter must fail this',
    );
    expect(stats.distinctColours, greaterThanOrEqualTo(4));
  });

  testWidgets('colour mark still paints a non-zero region at 16px', (
    tester,
  ) async {
    final rendered = await _renderRaw(tester, const BrandMark(size: 16));
    final stats = _stats(rendered, monochrome: false);
    expect(stats.coverage, greaterThan(0.05));
    expect(stats.distinctColours, greaterThanOrEqualTo(4));
  });

  testWidgets('monochrome mark is one hue over a real region at 48px', (
    tester,
  ) async {
    final mono = await _renderRaw(
      tester,
      const BrandMark(size: 48, monochrome: true),
    );
    final monoStats = _stats(mono, monochrome: true);

    expect(monoStats.coverage, greaterThan(0.15));
    // Measured 0.0000 over the 2 px-inset window: every ink pixel lies on the
    // background -> tone line. A second hue anywhere in the mark breaks this.
    expect(monoStats.offLineFraction, 0);
    // 93.1% of ink pixels are exactly `tone` (±2 per channel); the rest are
    // antialiased edges. Measured 0.9311, so 0.85 leaves only renderer slack.
    expect(monoStats.toneShare, greaterThan(0.85));
  });

  test('the one-hue predicate flags a synthetic two-hue buffer', () {
    const width = 64;
    const height = 64;
    Uint8List buffer(Color Function(int x) colourFor) {
      final out = Uint8List(width * height * 4);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final c = colourFor(x);
          final i = (y * width + x) * 4;
          out[i] = (c.r * 255).round();
          out[i + 1] = (c.g * 255).round();
          out[i + 2] = (c.b * 255).round();
          out[i + 3] = 255;
        }
      }
      return out;
    }

    final oneHue = _stats(
      _Rendered(buffer((x) => BombFlowerColors.bone), width, height),
      monochrome: true,
    );
    final twoHue = _stats(
      _Rendered(
        buffer(
          (x) => x < width ~/ 2
              ? BombFlowerColors.bone
              : const Color(0xFFC0442A),
        ),
        width,
        height,
      ),
      monochrome: true,
    );

    expect(oneHue.offLineFraction, 0);
    expect(oneHue.toneShare, 1);
    expect(twoHue.toneShare, lessThan(0.9));
    // The orange half is nowhere near the bone blend line, so the predicate
    // must catch it: this is the control that keeps "one hue" honest.
    expect(twoHue.offLineFraction, greaterThan(0.4));
  });

  testWidgets('shouldRepaint is false for an identical configuration', (
    tester,
  ) async {
    await tester.pumpWidget(_themed(const BrandMark(size: 24)));
    await tester.pump();
    final painter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(BrandMark),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    expect(painter, isA<CustomPainter>());
    expect(painter.shouldRepaint(painter), isFalse);

    const a = BrandMarkPainter.dark();
    const b = BrandMarkPainter.dark();
    const c = BrandMarkPainter.parchment();
    expect(a.shouldRepaint(b), isFalse);
    expect(a.shouldRepaint(c), isTrue);
  });

  testWidgets('title bar renders the asset image, not the fallback', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1360, 880);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: BombFlowerThemeData.build(),
        home: const Scaffold(
          body: Column(
            children: <Widget>[
              AppTitleBar(interactive: false, saveName: 'slot_00'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BombFlowerMark), findsOneWidget);
    expect(_assetPathOf(tester, find.byType(BombFlowerMark)), kBrandMarkAsset);
    expect(find.byType(BrandMark), findsNothing);
  });

  testWidgets('a missing asset falls back to the vector BrandMark', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themed(
        const BombFlowerMark(
          size: 24,
          assetPath: 'assets/brand/does_not_exist.png',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BrandMark), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('empty state renders the asset mark at motifSize', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pumpState({
      required bool onDark,
      required bool withScope,
    }) async {
      Widget state = const EmptyState(
        title: 'Nothing here yet',
        message: 'Open a save to begin.',
        motifSize: 48,
      );
      state = onDark
          ? state
          : EmptyState(
              title: 'Nothing here yet',
              message: 'Open a save to begin.',
              motifSize: 48,
              onDark: false,
            );
      if (withScope) {
        state = OpenSaveScope(open: (_) async {}, child: state);
      }
      await tester.pumpWidget(
        _themed(
          state,
          background: onDark
              ? BombFlowerColors.canopy1
              : BombFlowerColors.parchment,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final mark = find.byType(BombFlowerMark);
      expect(mark, findsOneWidget);
      expect(tester.getSize(mark).width, 48);
      expect(_assetPathOf(tester, mark), kBrandMarkAsset);
      expect(find.byType(BrandMark), findsNothing);
    }

    await pumpState(onDark: true, withScope: false);
    await pumpState(onDark: true, withScope: true);
    await pumpState(onDark: false, withScope: false);
  });
}
