/// The in-app open-save dialog.
///
/// The single implementation lives in `open_save_browser.dart` as
/// [OpenSaveDialog]: the typed `open-save-path` field plus the keyed listing,
/// parent, validity, blocked and listing-error affordances. This file remains
/// the import path for callers and tests, so the widget has one implementation
/// and one public name.
library;

export 'open_save_browser.dart' show OpenSaveDialog;
