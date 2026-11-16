import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// Sets the browser tab / app-switcher title while its page is visible and
/// the top page of its Navigator.
///
/// It rebuilds when the page becomes current again after a pop (ModalRoute
/// notifies on `isCurrent` changes) and when a StatefulShell tab becomes
/// visible (hidden branches run with tickers disabled). The returned tree is
/// always just [child], so the screen's state is never reset.
@internal
class OmniTitle extends StatelessWidget {
  const OmniTitle({
    super.key,
    required this.title,
    this.color,
    required this.child,
  });

  final String title;

  /// App-switcher colour; null = the theme's primary colour (black when
  /// there is no Material theme).
  final Color? color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final visible =
        (route == null || route.isCurrent) &&
        TickerMode.valuesOf(context).enabled;
    if (visible) {
      // Same call Flutter's `Title` widget makes in its build.
      SystemChrome.setApplicationSwitcherDescription(
        ApplicationSwitcherDescription(
          label: title,
          primaryColor: _color(context).toARGB32(),
        ),
      );
    }
    return child;
  }

  Color _color(BuildContext context) {
    if (color != null) return color!;
    // Theme.of falls back to a default theme; only use it when the app has
    // a real one.
    final hasTheme = context.findAncestorWidgetOfExactType<Theme>() != null;
    return hasTheme
        ? Theme.of(context).colorScheme.primary
        : const Color(0xFF000000);
  }
}
