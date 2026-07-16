import 'package:flutter/widgets.dart';

/// Lightweight KO/EN localization without codegen. An [AppLocale] is provided
/// above the MaterialApp; [tr] (or [AppLocale.t]) returns the string for the
/// current language. [onToggle] flips and persists the choice (wired in main).
class AppLocale extends InheritedWidget {
  const AppLocale({
    super.key,
    required this.english,
    required this.onToggle,
    required super.child,
  });

  /// true = English, false = Korean (default).
  final bool english;
  final VoidCallback onToggle;

  /// Pick the string for the current language.
  String t(String ko, String en) => english ? en : ko;

  static AppLocale of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<AppLocale>();
    assert(w != null, 'AppLocale not found above this context');
    return w!;
  }

  @override
  bool updateShouldNotify(AppLocale oldWidget) => english != oldWidget.english;
}

/// Shorthand for `AppLocale.of(context).t(ko, en)`.
String tr(BuildContext context, String ko, String en) =>
    AppLocale.of(context).t(ko, en);
