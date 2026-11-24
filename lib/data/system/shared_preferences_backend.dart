/// The `shared_preferences` implementation of the preference document port.
///
/// Lives in the data layer because it touches a platform plugin; presentation
/// only sees `PreferencesBackend`.
///
/// The resolved plugin writes
/// `<getApplicationSupportPath()>/shared_preferences.json`. On Linux that path
/// is `$XDG_DATA_HOME/<APPLICATION_ID>` (falling back to
/// `~/.local/share/<APPLICATION_ID>`); `path_provider_linux` takes the id from
/// the running GTK application, which `linux/CMakeLists.txt` sets to
/// `dev.dazemc.bomb_flower`. On Windows, `path_provider_windows` builds the
/// path from the executable's VERSIONINFO as
/// `%APPDATA%\<CompanyName>\<ProductName>`, i.e.
/// `%APPDATA%\bomb-flower\Bomb Flower\shared_preferences.json` for the
/// `Runner.rc` values. That Windows path is derived, never observed.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/preferences/preferences_backend.dart';

/// Stores one JSON document as a single string preference.
final class SharedPreferencesBackend implements PreferencesBackend {
  /// Creates a backend reading and writing [key].
  const SharedPreferencesBackend({this.key = defaultKey});

  /// Preference key holding the whole document.
  static const String defaultKey = 'bomb_flower.preferences.v1';

  /// Preference key this backend owns.
  final String key;

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(key);
  }

  @override
  Future<void> write(String contents) async {
    final preferences = await SharedPreferences.getInstance();
    final written = await preferences.setString(key, contents);
    if (!written) {
      throw StateError('the preferences store refused the write');
    }
  }
}
