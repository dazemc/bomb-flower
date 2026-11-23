import 'package:material_ui/material_ui.dart';

/// Exposes an optional opener for [HelpSurface] to the subtree below it.
///
/// The empty state uses this seam so a first-run page can offer "How this
/// works" without importing the shell. A missing scope simply returns `null`.
class HelpScope extends InheritedWidget {
  /// Creates a help scope.
  const HelpScope({super.key, required this.open, required super.child});

  /// Opens the help surface, or `null` when this subtree has no opener.
  final Future<void> Function(BuildContext context)? open;

  /// The nearest opener, or `null` when no [HelpScope] is above [context].
  static Future<void> Function(BuildContext context)? maybeOf(
    BuildContext context,
  ) {
    return context.dependOnInheritedWidgetOfExactType<HelpScope>()?.open;
  }

  @override
  bool updateShouldNotify(HelpScope oldWidget) => open != oldWidget.open;
}
