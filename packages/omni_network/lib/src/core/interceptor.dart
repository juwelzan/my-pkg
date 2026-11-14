import 'dart:async';

import 'omni_network_exception.dart';
import 'omni_request.dart';
import 'omni_response.dart';

/// Hooks around every request of an `OmniNetwork` client.
///
/// Override only what you need. `onRequest` runs in list order;
/// `onResponse` and `onError` run in reverse order (like nested
/// middleware). Interceptors are transport-independent: they never see
/// Dio types.
///
/// ```dart
/// final class AppVersion extends OmniInterceptor {
///   @override
///   OmniRequest onRequest(OmniRequest r) => r.withHeader('X-App', '1.4.0');
/// }
/// ```
///
/// Throwing an [OmniNetworkException] fails the request with it; any other
/// [Exception] becomes a [RequestFailure]. Exceptions thrown from [onError]
/// are ignored so the original failure is preserved.
abstract class OmniInterceptor {
  /// Const constructor for subclasses.
  const OmniInterceptor();

  /// Returns the request to send (e.g. with an added header).
  FutureOr<OmniRequest> onRequest(OmniRequest request) => request;

  /// Returns the response to hand back (any status code).
  FutureOr<OmniRawResponse> onResponse(
    OmniRequest request,
    OmniRawResponse response,
  ) => response;

  /// Observes a failure. The failure is rethrown afterwards.
  FutureOr<void> onError(OmniRequest request, OmniNetworkException error) {}
}
