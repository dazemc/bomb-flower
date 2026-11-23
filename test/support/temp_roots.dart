/// Unique scratch roots inside the repository's gitignored `.tmp/` tree.
///
/// `flutter test` runs test files in separate processes, and a checkout can be
/// driven by two runs at once. A fixed `.tmp/...` path lets one run delete or
/// rewrite the files another run is still reading, so every file that needs
/// scratch space asks for a root here instead:
/// `.tmp/<label>/p<pid>-<counter>-<microsecondsSinceEpoch>`.
///
/// The pid separates concurrent `flutter test` processes, the counter
/// separates several roots in one process, and the clock component keeps two
/// processes that happen to reuse a pid apart.
library;

import 'dart:io';

int _counter = 0;

/// Creates and returns a fresh, empty root under `.tmp/<label>/`.
Directory createTempRoot(String label) {
  final unique = 'p$pid-${_counter++}-${DateTime.now().microsecondsSinceEpoch}';
  final root = Directory('.tmp/$label/$unique');
  root.createSync(recursive: true);
  return root;
}

/// Deletes [root] and the `<root>.bombflower-original` sidecar beside it.
///
/// Only the caller's own unique root is removed; never a shared parent.
void removeTempRoot(Directory root) {
  for (final suffix in const <String>['', '.bombflower-original']) {
    final directory = Directory('${root.path}$suffix');
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}

/// Recursively copies [source] into [target], which is created if absent.
void copyDirectorySync(Directory source, Directory target) {
  target.createSync(recursive: true);
  for (final entity in source.listSync(followLinks: false)) {
    // A Directory URI always ends with '/', so drop empty trailing segments.
    final name = entity.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    if (entity is File) {
      entity.copySync('${target.path}/$name');
    } else if (entity is Directory) {
      copyDirectorySync(entity, Directory('${target.path}/$name'));
    }
  }
}
