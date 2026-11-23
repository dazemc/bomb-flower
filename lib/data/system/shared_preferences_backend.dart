/// The `shared_preferences` implementation of the preference document port.
///
/// Lives in the data layer because it touches a platform plugin; presentation
/// only sees `PreferencesBackend`. On Linux the plugin resolves
/// `shared_preferences_linux`, which stores the document under
/// `$XDG_CONFIG_HOME` (or `~/.config`) in the app's own directory.
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
