/// Editor preferences: the presentation-side store, and its two implementations.
///
/// This file is the single home of [SettingsStore] so a persisted store can be
/// written next to the in-memory one without either of them importing the
/// 600-line Settings page. `settings_tab.dart` re-exports it, so every existing
/// import path keeps working.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/preferences/preferences_backend.dart';

/// The executables the editor starts for the user.
///
/// Presentation keeps its own default so this file never imports the data-layer
/// launcher port; the title bar reads the persisted value from here.
const String kDefaultLongshotLauncherPath =
    '/home/daze/Personal/Downloads/LongshotLauncher-x86_64.AppImage';

/// The narrowest text scale the editor will apply, whatever is stored.
///
/// The Settings slider exposes 1.0-1.5 on purpose: that is the product range.
/// The applied range is wider so a hand-edited or externally written document
/// still renders legibly instead of pinning to something absurd, and a stored
/// value outside it is clamped rather than rejected.
const double kMinAppliedTextScale = 0.8;

/// The widest text scale the editor will apply, whatever is stored.
const double kMaxAppliedTextScale = 1.6;

/// What the editor should do when a save is about to be overwritten.
enum BackupPolicy { always, ask, never }

/// User-facing editor preferences.
///
/// This is a presentation-layer value: the store that persists it lives here
/// too, and the platform storage behind it is a [PreferencesBackend] in
/// `lib/data`, so neither layer imports the other's types.
final class EditorPreferences {
  const EditorPreferences({
    this.recentPaths = const <String>[],
    this.backupPolicy = BackupPolicy.ask,
    this.makeNewestSlotDefault = true,
    this.reducedMotion = false,
    this.textScale = 1.0,
    this.showHiddenEntries = false,
    this.launcherPath = kDefaultLongshotLauncherPath,
  });

  /// Recently opened save folders, newest first.
  final List<String> recentPaths;

  final BackupPolicy backupPolicy;

  /// Whether the newest save slot is preselected when a folder is opened.
  final bool makeNewestSlotDefault;

  /// Editor-level reduced motion, applied on the next launch.
  final bool reducedMotion;

  /// UI text scale applied inside the editor, 1.0 to 1.5.
  ///
  /// Applied through `MaterialApp.builder`; see [kMinAppliedTextScale].
  final double textScale;

  /// Whether the in-app picker lists dot-entries. Off by default.
  final bool showHiddenEntries;

  /// Executable the title-bar Launch action starts.
  final String launcherPath;

  EditorPreferences copyWith({
    List<String>? recentPaths,
    BackupPolicy? backupPolicy,
    bool? makeNewestSlotDefault,
    bool? reducedMotion,
    double? textScale,
    bool? showHiddenEntries,
    String? launcherPath,
  }) {
    return EditorPreferences(
      recentPaths: recentPaths ?? this.recentPaths,
      backupPolicy: backupPolicy ?? this.backupPolicy,
      makeNewestSlotDefault:
          makeNewestSlotDefault ?? this.makeNewestSlotDefault,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      textScale: textScale ?? this.textScale,
      showHiddenEntries: showHiddenEntries ?? this.showHiddenEntries,
      launcherPath: launcherPath ?? this.launcherPath,
    );
  }
}

/// Persistence boundary for [EditorPreferences].
///
/// [preferences] and [changes] exist so the app can apply a preference (the text
/// scale) in `MaterialApp.builder` on the frame that follows a write, without
/// awaiting a future from inside `build`.
abstract interface class SettingsStore {
  /// Reads the current value. Implementations may answer from a cache.
  Future<EditorPreferences> load();

  /// Writes [preferences]. Throws when the value was not stored.
  Future<void> save(EditorPreferences preferences);

  /// The current value, available synchronously.
  EditorPreferences get preferences;

  /// Notifies after [save] commits a new value.
  Listenable get changes;

  /// Whether writes survive the process.
  ///
  /// The Settings page states this honestly instead of claiming persistence a
  /// hermetic in-memory store does not have.
  bool get isPersistent;
}

/// Process-lifetime store used when the shell injects no [SettingsStore].
///
/// It keeps the last saved value in memory; nothing survives a restart, so
/// [isPersistent] is false and the tab says so.
final class InMemorySettingsStore extends ChangeNotifier
    implements SettingsStore {
  InMemorySettingsStore([EditorPreferences? seed])
    : _preferences = seed ?? const EditorPreferences();

  EditorPreferences _preferences;

  /// The most recent value handed to [save], for inspection.
  EditorPreferences get lastValue => _preferences;

  @override
  EditorPreferences get preferences => _preferences;

  @override
  Listenable get changes => this;

  @override
  bool get isPersistent => false;

  @override
  Future<EditorPreferences> load() async => _preferences;

  @override
  Future<void> save(EditorPreferences preferences) async {
    _preferences = preferences;
    notifyListeners();
  }
}

/// Store that survives a restart by persisting one JSON document.
///
/// The document shape is owned here, not by the backend: a plugin key/value
/// store, a file, and the test double all see the same opaque string. Decoding
/// is tolerant field by field — a document written by an older build, hand
/// edited, or truncated falls back to the default for whatever it cannot read
/// instead of discarding every other preference or throwing at startup.
final class PersistedSettingsStore extends ChangeNotifier
    implements SettingsStore {
  /// Creates a store over [backend] with an already-known value.
  ///
  /// Production uses [open]; this constructor exists for tests that already
  /// hold a decoded value.
  PersistedSettingsStore(
    this._backend, {
    EditorPreferences initial = const EditorPreferences(),
  }) : _preferences = initial;

  /// Reads [backend] once and returns a store with whatever it held.
  ///
  /// A missing, unreadable, or malformed document yields the defaults; startup
  /// is never blocked by preferences.
  static Future<PersistedSettingsStore> open(PreferencesBackend backend) async {
    EditorPreferences loaded = const EditorPreferences();
    try {
      final raw = await backend.read();
      if (raw != null) {
        loaded = decode(raw);
      }
    } on Object catch (error) {
      debugPrint('[settings] preferences could not be read: $error');
    }
    return PersistedSettingsStore(backend, initial: loaded);
  }

  final PreferencesBackend _backend;
  EditorPreferences _preferences;

  @override
  EditorPreferences get preferences => _preferences;

  @override
  Listenable get changes => this;

  @override
  bool get isPersistent => true;

  @override
  Future<EditorPreferences> load() async => _preferences;

  @override
  Future<void> save(EditorPreferences preferences) async {
    // Applied before the write, so the value the user chose is what the app
    // renders even if the write then fails. The Settings page reports that
    // failure and keeps the same value, so an optimistically applied value is
    // consistent with what the UI says; a rejected write is never silent.
    _preferences = preferences;
    notifyListeners();
    await _backend.write(encode(preferences));
  }

  /// The stored JSON document for [preferences].
  static String encode(EditorPreferences preferences) {
    return jsonEncode(<String, Object?>{
      'recentPaths': preferences.recentPaths,
      'backupPolicy': preferences.backupPolicy.name,
      'makeNewestSlotDefault': preferences.makeNewestSlotDefault,
      'reducedMotion': preferences.reducedMotion,
      'textScale': preferences.textScale,
      'showHiddenEntries': preferences.showHiddenEntries,
      'launcherPath': preferences.launcherPath,
    });
  }

  /// Decodes [raw], substituting defaults for anything unreadable.
  ///
  /// Throws only when [raw] is not JSON at all; [open] catches that and starts
  /// from the defaults.
  static EditorPreferences decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      return const EditorPreferences();
    }
    const defaults = EditorPreferences();
    final policy = decoded['backupPolicy'];
    final textScale = decoded['textScale'];
    final launcherPath = decoded['launcherPath'];
    final recentPaths = decoded['recentPaths'];
    return EditorPreferences(
      recentPaths: recentPaths is List
          ? List<String>.unmodifiable(recentPaths.whereType<String>())
          : defaults.recentPaths,
      backupPolicy: policy is String
          ? BackupPolicy.values.asNameMap()[policy] ?? defaults.backupPolicy
          : defaults.backupPolicy,
      makeNewestSlotDefault: decoded['makeNewestSlotDefault'] is bool
          ? decoded['makeNewestSlotDefault']! as bool
          : defaults.makeNewestSlotDefault,
      reducedMotion: decoded['reducedMotion'] is bool
          ? decoded['reducedMotion']! as bool
          : defaults.reducedMotion,
      textScale: textScale is num
          ? textScale.toDouble().clamp(
              kMinAppliedTextScale,
              kMaxAppliedTextScale,
            )
          : defaults.textScale,
      showHiddenEntries: decoded['showHiddenEntries'] is bool
          ? decoded['showHiddenEntries']! as bool
          : defaults.showHiddenEntries,
      launcherPath: launcherPath is String && launcherPath.trim().isNotEmpty
          ? launcherPath
          : defaults.launcherPath,
    );
  }
}
