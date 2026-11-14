import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import '../bloc/omni_bloc.dart';
import '../errors/omni_route_exception.dart';

/// Immutable description of a screen, independent of any route.
///
/// [type] is the stable identity (survives obfuscation). [debugName] comes
/// from `runtimeType.toString()` and must only be used for logs.
@immutable
class OmniScreenMetadata {
  const OmniScreenMetadata({
    required this.type,
    required this.screenName,
    required this.title,
    required this.debugName,
  });

  final Type type;
  final String screenName;
  final String title;
  final String debugName;

  @override
  bool operator ==(Object other) =>
      other is OmniScreenMetadata &&
      other.type == type &&
      other.screenName == screenName &&
      other.title == title;

  @override
  int get hashCode => Object.hash(type, screenName, title);

  @override
  String toString() => 'OmniScreenMetadata($debugName, "$screenName")';
}

/// Shared API of [OmniStatelessWidget] and [OmniStatefulWidget].
mixin OmniScreen on Widget {
  /// Human-readable name. Required; used for logs and the default title.
  String get screenName;

  /// Browser tab / app-switcher title. Defaults to [screenName].
  String get title => screenName;

  /// Blocs owned by (or lent to) this screen. Same API for stateless and
  /// stateful screens. Read them with `context.read<B>()`.
  List<Provide> get provide => const [];

  /// Runtime class name, for debugging only. Not stable under obfuscation.
  String get name => runtimeType.toString();

  OmniScreenMetadata get metadata => OmniScreenMetadata(
    type: runtimeType,
    screenName: screenName,
    title: title,
    debugName: name,
  );
}

/// Throws if [screen]'s metadata is invalid.
@internal
void validateScreen(OmniScreen screen) {
  if (screen.screenName.trim().isEmpty) {
    throw OmniRouteException(
      OmniErrorCode.emptyScreenName,
      '${screen.name}.screenName is empty.',
      hint: "Override `String get screenName => 'My screen';`.",
    );
  }
}
