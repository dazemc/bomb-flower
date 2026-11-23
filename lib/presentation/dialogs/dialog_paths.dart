/// Path comparison helpers for the save dialogs.
///
/// Presentation must not import `dart:io`, so this mirrors the engine's
/// separator and trailing-slash normalisation for display comparisons only.
library;

/// Normalises a user-entered path for equality checks.
///
/// This never touches the filesystem; [SaveFolderProbe] owns that.
String normalizeSavePath(String path) {
  var normalized = path.trim().replaceAll('\\', '/');
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

/// Whether [a] and [b] name the same folder after normalisation.
bool sameSavePath(String a, String b) =>
    normalizeSavePath(a) == normalizeSavePath(b);

/// A short label for a long recent path: the last two segments.
String shortPathLabel(String path) {
  final normalized = path.trim().replaceAll(RegExp(r'[/\\]+$'), '');
  final segments = normalized.split(RegExp(r'[/\\]'));
  if (segments.length <= 2) {
    return normalized;
  }
  return '…/${segments.sublist(segments.length - 2).join('/')}';
}
