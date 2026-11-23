/// Pure-Dart description of a new save to create.
///
/// This library contains no byte layout and no I/O. It carries the choices
/// that are not already in the schema so the builder can turn them into bytes.
library;

/// A position in the save's world coordinates.
///
/// The three components are stored as binary32 values. The builder rejects a
/// position that is not finite or that does not fit a finite binary32.
final class SavePosition {
  /// Creates a position.
  const SavePosition({required this.x, required this.y, required this.z});

  /// The x component.
  final double x;

  /// The y component.
  final double y;

  /// The z component.
  final double z;
}

/// The presets the schema can justify.
///
/// There is exactly one Adult/Child default difference in the whole schema:
/// `MiniGame_Fishing_RecordFishSize_Adult` is 45 and
/// `MiniGame_Fishing_RecordFishSize_Child` is 40. Every other field has one
/// default, so an Adult or Child preset would have to invent a rule the schema
/// does not contain. Only [schemaDefaults] is offered.
enum NewSavePreset {
  /// Use the schema's own default for every field.
  ///
  /// The scene and map path still come from the verified caption samples, not
  /// from the schema: the schema has no caption fields at all.
  schemaDefaults,
}

/// The non-schema choices for a new save.
final class NewSaveSpec {
  /// Creates a spec.
  ///
  /// [scene] and [mapPath] are written into `caption.sav` and must be
  /// printable ASCII of at most 63 code units. [profileName] is rejected by
  /// the builder because no verified schema field carries a profile name.
  const NewSaveSpec({
    required this.scene,
    required this.mapPath,
    this.profileName,
    this.startPosition,
    this.createCaptionScreenshot = true,
  });

  /// A profile or player name to store, or `null`.
  ///
  /// No verified schema field carries a profile or player name: the only
  /// name-like on-disk fields are `PlayerStatus.*` equipment strings and
  /// `WarpPoint_*.LocationName`. A non-null value is therefore rejected by
  /// the builder with `profile_name_unavailable`; it is never ignored.
  final String? profileName;

  /// The scene name written to `caption.sav`.
  ///
  /// The span is 64 bytes (`CaptionLayout.nameLength`); the builder requires
  /// at most 63 printable-ASCII code units so a NUL terminator always fits.
  final String scene;

  /// The scene/map path written to `caption.sav`.
  ///
  /// The verified samples use values such as
  /// `KokiriForest/KokiriForest_Child`, not a numeric map id. The same
  /// 63-code-unit printable-ASCII rule as [scene] applies.
  final String mapPath;

  /// When non-null, replaces the default of the verified
  /// `Player_Pos_For_Map` Vector3 field (hash `0x960AD56A`).
  ///
  /// The components must be finite and representable as finite binary32.
  /// When the field is absent from the on-disk schema, the builder throws
  /// `start_position_unavailable`.
  final SavePosition? startPosition;

  /// Whether to embed the builder's original 1x1 JPEG in `caption.sav`.
  ///
  /// When `false`, the builder writes the 4-byte marker pair
  /// `FF D8 FF D9` instead. `CaptionCodec.decode` accepts that shape as a
  /// 1,400-byte caption file. The default is `true`; the CLI's
  /// `--no-screenshot` reconstructs a spec through this public constructor,
  /// so [NewSaveSpec.preset] does not need a screenshot parameter.
  final bool createCaptionScreenshot;

  /// Builds the one verified preset.
  ///
  /// The scene `KokiriForest` and map path
  /// `KokiriForest/KokiriForest_Child` are the exact values observed in the
  /// three verified caption samples (see `CaptionLayout.sceneName` and
  /// `CaptionLayout.mapPath`). They are sample-observed, not schema defaults.
  ///
  /// [createCaptionScreenshot] keeps its constructor default of `true`; use
  /// the public constructor to turn the screenshot off.
  factory NewSaveSpec.preset(
    NewSavePreset preset, {
    String? profileName,
    SavePosition? startPosition,
  }) {
    return switch (preset) {
      NewSavePreset.schemaDefaults => NewSaveSpec(
        scene: 'KokiriForest',
        mapPath: 'KokiriForest/KokiriForest_Child',
        profileName: profileName,
        startPosition: startPosition,
      ),
    };
  }
}
