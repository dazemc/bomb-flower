import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import 'brand_mark.dart';

/// Bundled path of the project's bomb-flower artwork.
const String kBrandMarkAsset = 'assets/brand/bombflower.png';

/// The application's brand mark.
///
/// Primary artwork is [kBrandMarkAsset]; the vector [BrandMark] is painted only
/// when the image cannot be loaded. Both call sites go through this widget so
/// sizing, bounded decoding and the fallback exist once.
class BombFlowerMark extends StatelessWidget {
  const BombFlowerMark({
    super.key,
    this.size = 24,
    this.onDark = true,
    this.monochrome = false,
    this.tone = BombFlowerColors.bone,
    this.assetPath = kBrandMarkAsset,
  });

  /// Width and height of the slot. The artwork keeps its own aspect ratio
  /// inside it.
  final double size;

  /// Tone handed to the vector fallback.
  final bool onDark;

  /// Paint the artwork as a single-colour silhouette in [tone].
  final bool monochrome;

  /// Ink colour for [monochrome].
  final Color tone;

  /// Overridable for the fallback test; production always uses
  /// [kBrandMarkAsset].
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    // Bound decoding by the device-pixel width of the slot. Only the width is
    // passed to ResizeImage: giving it both axes makes the engine stretch the
    // decode to that box independently, which would squash this landscape
    // artwork. A single cached provider keeps the decode stable across
    // rebuilds.
    final extent = math.max(
      16,
      (size * MediaQuery.devicePixelRatioOf(context)).round(),
    );
    return _StableMarkImage(
      assetPath: assetPath,
      extent: extent,
      size: size,
      monochrome: monochrome,
      tone: tone,
      onDark: onDark,
    );
  }
}

class _StableMarkImage extends StatefulWidget {
  const _StableMarkImage({
    required this.assetPath,
    required this.extent,
    required this.size,
    required this.monochrome,
    required this.tone,
    required this.onDark,
  });

  final String assetPath;
  final int extent;
  final double size;
  final bool monochrome;
  final Color tone;
  final bool onDark;

  @override
  State<_StableMarkImage> createState() => _StableMarkImageState();
}

class _StableMarkImageState extends State<_StableMarkImage> {
  int? _extent;
  String? _assetPath;
  ImageProvider? _provider;

  ImageProvider _providerFor() {
    if (_provider == null ||
        _extent != widget.extent ||
        _assetPath != widget.assetPath) {
      _extent = widget.extent;
      _assetPath = widget.assetPath;
      _provider = ResizeImage(
        AssetImage(widget.assetPath),
        width: widget.extent,
      );
    }
    return _provider!;
  }

  @override
  Widget build(BuildContext context) {
    final image = Image(
      image: _providerFor(),
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      semanticLabel: 'Bomb flower',
      errorBuilder: (context, error, stackTrace) =>
          BrandMark(size: widget.size, onDark: widget.onDark),
    );
    if (!widget.monochrome) return image;
    return ColorFiltered(
      colorFilter: ColorFilter.mode(widget.tone, BlendMode.srcIn),
      child: image,
    );
  }
}
