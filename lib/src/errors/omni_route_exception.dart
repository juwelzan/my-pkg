/// Category of an [OmniRouteException].
enum OmniErrorCode {
  emptyScreenName,
  emptyRoutePath,
  invalidRoutePath,
  duplicateRoute,
  missingRoute,
  missingBlocFactory,
  duplicateBlocRegistration,
  invalidParameter,
  redirectLoop,
  notInitialized,
  unsupportedConfiguration,
}

/// The single exception type thrown by OmniRoute for configuration and
/// usage mistakes. [message] says what went wrong; [hint] how to fix it.
class OmniRouteException implements Exception {
  const OmniRouteException(this.code, this.message, {this.hint});

  final OmniErrorCode code;
  final String message;
  final String? hint;

  @override
  String toString() {
    final buffer = StringBuffer('OmniRouteException(${code.name}): $message');
    if (hint != null) buffer.write('\nHint: $hint');
    return buffer.toString();
  }
}
