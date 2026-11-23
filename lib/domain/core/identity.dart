/// Stable logical identities used by the save engine.
///
/// Identity types are extension types over [String]: they are zero-cost,
/// structurally equal, and cannot be confused with arbitrary strings at
/// compile time.
library;

/// Names a logical slot (file family) inside a save folder.
///
/// A slot id is not a path. [LayoutDescriptor] owns the relative path, so the
/// same logical slot may live at a different path in another layout version.
extension type const SaveSlotId(String value) {
  /// The account-wide save file.
  static const SaveSlotId account = SaveSlotId('account');

  /// The options/settings save file.
  static const SaveSlotId options = SaveSlotId('option');

  /// The progress slot with [index], rendered as `slot_00`, `slot_01`, ...
  static SaveSlotId progress(int index) {
    if (index < 0) {
      throw RangeError.range(index, 0, null, 'index');
    }
    return SaveSlotId('slot_${index.toString().padLeft(2, '0')}');
  }
}

/// A stable, dotted key for one editable field, such as `player.health`.
///
/// The string is opaque to the engine; layout research defines the keys.
extension type const FieldId(String value) {}
