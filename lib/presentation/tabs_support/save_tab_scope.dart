/// Provides a [SaveTabSource] to the editor tabs below it.
library;

import 'package:flutter/widgets.dart';

import 'save_tab_source.dart';

/// An [InheritedWidget] that hands a [SaveTabSource] to save-editing tabs.
///
/// A tab that finds no scope is not broken: it calls [maybeOf] and renders an
/// honest "not connected" state. [of] exists for widgets that cannot function
/// without a source and should fail loudly instead.
class SaveTabScope extends InheritedWidget {
  /// Creates a scope exposing [source] to [child].
  const SaveTabScope({super.key, required this.source, required super.child});

  /// The source every descendant tab reads and edits through.
  final SaveTabSource source;

  /// The nearest [SaveTabSource], or `null` when no [SaveTabScope] is above.
  static SaveTabSource? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SaveTabScope>()?.source;
  }

  /// The nearest [SaveTabSource], or a [StateError] when none is above.
  ///
  /// Only widgets that cannot render without a save should call this; a tab
  /// that can show an empty state must use [maybeOf] instead.
  static SaveTabSource of(BuildContext context) {
    final source = maybeOf(context);
    if (source == null) {
      throw StateError(
        'SaveTabScope.of() was called with a context that has no SaveTabScope '
        'ancestor. Wrap this widget in a SaveTabScope, or call '
        'SaveTabScope.maybeOf() and render the not-connected state.',
      );
    }
    return source;
  }

  /// Rebuilds dependents only when a different source instance is provided.
  @override
  bool updateShouldNotify(SaveTabScope oldWidget) => oldWidget.source != source;
}
