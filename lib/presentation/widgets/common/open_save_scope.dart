/// Hands the app's single "open another save" action to empty states.
library;

import 'package:flutter/widgets.dart';

/// An [InheritedWidget] exposing the one open-save dialog path to descendants.
///
/// The empty states that invite the user to open a save live deep inside tabs
/// and must not own a session or a dialog. The app provides this scope once,
/// around the shell, and every [EmptyState] below it can offer the invitation.
/// A widget that finds no scope is unaffected: [maybeOf] returns null.
class OpenSaveScope extends InheritedWidget {
  /// Creates a scope exposing [open] to [child].
  const OpenSaveScope({super.key, required this.open, required super.child});

  /// Shows the open-save dialog and opens the chosen folder.
  ///
  /// A null value means no opener is wired, so an invitation renders disabled
  /// rather than pretending to work.
  final Future<void> Function(BuildContext context)? open;

  /// The nearest opener, or `null` when no [OpenSaveScope] is above [context].
  static Future<void> Function(BuildContext context)? maybeOf(
    BuildContext context,
  ) {
    return context.dependOnInheritedWidgetOfExactType<OpenSaveScope>()?.open;
  }

  /// Rebuilds dependents only when the opener itself changes.
  @override
  bool updateShouldNotify(OpenSaveScope oldWidget) => oldWidget.open != open;
}
