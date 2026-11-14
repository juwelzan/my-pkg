import 'package:flutter/widgets.dart';

import 'package:go_router/go_router.dart';

import 'omni_screen.dart';

/// A [StatefulWidget] screen with OmniRoute metadata. Pair with [OmniState].
abstract class OmniStatefulWidget extends StatefulWidget with OmniScreen {
  const OmniStatefulWidget({super.key});

  @override
  State<OmniStatefulWidget> createState();

  @override
  StatefulElement createElement() => _OmniStatefulElement(this);
}

class _OmniStatefulElement extends StatefulElement {
  _OmniStatefulElement(OmniStatefulWidget super.widget);

  @override
  Widget build() {
    validateScreen(widget as OmniScreen);
    return super.build();
  }
}

/// [State] for an [OmniStatefulWidget]. Adds no lifecycle of its own:
/// `initState`, `didChangeDependencies`, `didUpdateWidget` and `dispose`
/// behave exactly as in Flutter.
abstract class OmniState<T extends OmniStatefulWidget> extends State<T> {
  /// Metadata of the current widget.
  OmniScreenMetadata get metadata => widget.metadata;

  /// Route state of the page this screen is on (path, query, extra).
  GoRouterState get routeState => GoRouterState.of(context);
}
