import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
  const OmniTitle({super.key, required this.title, required this.child});

  final String title;
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
        ApplicationSwitcherDescription(label: title, primaryColor: 0xFF000000),
      );
    }
    return child;
  }
}
