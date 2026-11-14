import 'package:flutter/widgets.dart';

import 'omni_screen.dart';
import 'omni_screen_host.dart';

/// A [StatelessWidget] screen with OmniRoute metadata.
///
/// ```dart
/// class StudentScreen extends OmniStatelessWidget {
///   const StudentScreen({super.key});
///   @override
///   String get screenName => 'Students';
///   @override
///   Widget build(BuildContext context) => const Placeholder();
/// }
/// ```
abstract class OmniStatelessWidget extends StatelessWidget with OmniScreen {
  /// Creates a stateless screen.
  const OmniStatelessWidget({super.key});

  @override
  StatelessElement createElement() => _OmniStatelessElement(this);
}

class _OmniStatelessElement extends StatelessElement {
  _OmniStatelessElement(OmniStatelessWidget super.widget);

  // Validating in build (not mount) lets Flutter show an ErrorWidget and
  // dispose the element normally.
  @override
  Widget build() {
    final screen = widget as OmniStatelessWidget;
    validateScreen(screen);
    if (isHosted(this, screen)) return super.build();
    // Shown outside a route: provide our own Blocs and build the screen
    // with a context below them.
    return hostScreen(
      screen,
      // This element owns the widget; calling its build is what
      // StatelessElement itself does, only with an inner context.
      // ignore: invalid_use_of_protected_member
      wrap: (_) => Builder(builder: screen.build),
    );
  }
}
