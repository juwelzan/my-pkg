/// Base class of every error thrown by OmniNetwork.
sealed class OmniNetworkException implements Exception {
  const OmniNetworkException(this.message, {this.uri, this.cause});

  /// Human-readable description (never contains headers or bodies).
  final String message;

  /// Request URL with the query string removed (it may carry secrets).
  final Uri? uri;

  /// Underlying error, if any.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message${uri == null ? '' : ' ($uri)'}';
}

/// The request did not finish within its timeout.
final class TimeoutFailure extends OmniNetworkException {
  /// Creates a timeout failure.
  const TimeoutFailure(this.timeout, {super.uri})
    : super('Request timed out after $timeout');

  /// The timeout that elapsed.
  final Duration timeout;
}

/// The server could not be reached or the connection broke.
final class ConnectionFailure extends OmniNetworkException {
  /// Creates a connection failure.
  const ConnectionFailure(super.message, {super.uri, super.cause});
}

/// The request was cancelled.
final class CancelledFailure extends OmniNetworkException {
  /// Creates a cancellation failure.
  const CancelledFailure({super.uri}) : super('Request cancelled');
}

/// The client was closed before or while the request ran.
final class ClosedFailure extends OmniNetworkException {
  /// Creates a closed-client failure.
  const ClosedFailure({super.uri}) : super('OmniNetwork client is closed');
}

/// The request could not be built (bad URL, unsupported body…).
final class RequestFailure extends OmniNetworkException {
  /// Creates a request-building failure.
  const RequestFailure(super.message, {super.uri, super.cause});
}

/// Removes user info, query and fragment so errors never leak secrets.
Uri safeUri(Uri uri) => Uri(
  scheme: uri.scheme,
  host: uri.host,
  port: uri.hasPort ? uri.port : null,
  path: uri.path,
);
