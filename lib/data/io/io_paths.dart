/// Filesystem path helpers for the data/io layer.
library;

import 'dart:io';

/// Joins a trusted root with a layout-supplied relative path.
///
/// Rejects absolute paths, `.`/`..` segments, and empty paths so a layout
/// cannot escape the open save root.
String resolveUnderRoot(String root, String relativePath) {
  if (relativePath.trim().isEmpty) {
    throw ArgumentError.value(
      relativePath,
      'relativePath',
      'must not be empty',
    );
  }
  final normalized = relativePath.replaceAll('\\', '/');
  if (normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
    throw ArgumentError.value(relativePath, 'relativePath', 'must be relative');
  }
  final segments = normalized.split('/');
  for (final segment in segments) {
    if (segment.isEmpty || segment == '.' || segment == '..') {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'contains an unsafe segment',
      );
    }
  }
  final separator = Platform.pathSeparator;
  final trimmedRoot = root.endsWith(separator)
      ? root.substring(0, root.length - 1)
      : root;
  return '$trimmedRoot$separator${segments.join(separator)}';
}

/// Normalises a path for comparison without touching the filesystem.
String normalizeForComparison(String path) {
  var normalized = path.trim().replaceAll('\\', '/');
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

/// Whether [child] is a strict descendant of [parent] after normalisation.
bool pathIsWithin(String child, String parent) {
  final c = normalizeForComparison(child);
  final p = normalizeForComparison(parent);
  return c != p && c.startsWith('$p/');
}

/// The adjacent sidecar path for [rootPath].
String sidecarPathFor(String rootPath, String suffix) => '$rootPath$suffix';
