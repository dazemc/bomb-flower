/// A single persisted document for user preferences.
///
/// The port is deliberately opaque: it moves one string, so the platform
/// implementation (a plugin store, a file, or a test double) never sees
/// presentation types and the store that owns the JSON shape never sees
/// `dart:io` or a Flutter plugin. `lib/data` implements it; `lib/domain` names
/// it; `lib/presentation` uses it and is the only layer that knows what the
/// document contains.
library;

/// Reads and writes one preference document.
abstract interface class PreferencesBackend {
  /// The stored document, or `null` when nothing has been written yet.
  ///
  /// Implementations must surface an unreadable store as `null` rather than
  /// throwing where they can do so honestly; a caller still tolerates a throw.
  Future<String?> read();

  /// Replaces the stored document with [contents].
  ///
  /// Implementations either complete or throw; a caller reports a failure to
  /// the user instead of assuming the value was persisted.
  Future<void> write(String contents);
}
