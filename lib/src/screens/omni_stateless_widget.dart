import 'package:flutter/widgets.dart';

import 'omni_screen.dart';

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
    validateScreen(widget as OmniScreen);
    return super.build();
  }
}
