/// Which host operating system this process runs on, as an injectable value.
///
/// The data layer takes the platform from here instead of reading
/// `Platform.isWindows` (and friends) at each call site, so every Windows rule
/// can be exercised by tests on a Linux host through an injected [HostPlatform].
/// `lib/domain` never imports this: path rules are a data-layer concern.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// The host operating systems whose path rules this app distinguishes.
enum HostPlatform {
  /// Linux, including Steam Deck.
  linux,

  /// Microsoft Windows.
  windows,

  /// Apple macOS.
  macos,

  /// Google Fuchsia, which follows the Linux/XDG rules.
  fuchsia,

  /// Any other host; no path rules are invented for it.
  other,
}

/// The platform this process is actually running on.
///
/// This is the mapping the path rules use; no path resolver calls
/// `Platform.isWindows` (or friends) directly, so the platform can be injected.
HostPlatform currentHostPlatform() {
  if (Platform.isLinux) {
    return HostPlatform.linux;
  }
  if (Platform.isWindows) {
    return HostPlatform.windows;
  }
  if (Platform.isMacOS) {
    return HostPlatform.macos;
  }
  if (Platform.isFuchsia) {
    return HostPlatform.fuchsia;
  }
  return HostPlatform.other;
}

/// The `package:path` context matching [platform].
///
/// Windows paths are built with `package:path`'s Windows context and everything
/// else with its POSIX context. `Platform.pathSeparator` is never consulted for
/// these rules, so the Windows rules produce the same result on a Linux test
/// host as they would on Windows.
p.Context hostPathContext(HostPlatform platform) => switch (platform) {
  HostPlatform.windows => p.windows,
  _ => p.posix,
};
