import 'omni_response.dart';

/// Base class of every error thrown by OmniNetwork.
sealed class OmniNetworkException implements Exception {
  const OmniNetworkException(this.message, {this.uri, this.cause});

  /// Human-readable description (never contains headers or bodies).
  final String message;

  /// Request URL with the query string removed (it may carry secrets).
  final Uri? uri;

  /// Underlying error, if any.
  final Object? cause;

  /// HTTP status of the response, or `null` when there was no response
  /// (offline, timeout, cancelled…).
  int? get statusCode => null;

  /// No connection to the server, or it did not answer in time.
  bool get isOffline => this is ConnectionFailure || this is TimeoutFailure;

  /// The request timed out.
  bool get isTimeout => this is TimeoutFailure;

  /// The request was cancelled or the client was closed.
  bool get isCancelled => this is CancelledFailure || this is ClosedFailure;

  /// Not signed in or the session expired (401, or the token refresh
  /// failed).
  bool get isUnauthorized => this is AuthFailure || statusCode == 401;

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

/// The server answered with a non-2xx status (typed calls only; `sendRaw`
/// returns every status).
final class HttpFailure extends OmniNetworkException {
  /// Creates an HTTP status failure for [response].
  HttpFailure(this.response)
    : super('HTTP ${response.statusCode}', uri: response.requestUri);

  /// The full response, e.g. to read an error body via `response.json`.
  /// Not included in [toString], so it is never logged by accident.
  final OmniRawResponse response;

  /// HTTP status code.
  @override
  int get statusCode => response.statusCode;
}

/// The body could not be parsed or decoded into the requested type.
final class DecodeFailure extends OmniNetworkException {
  /// Creates a decoding failure.
  const DecodeFailure(super.message, {super.uri, super.cause, this.stackTrace});

  /// Where the decoder threw, when the failure came from a decoder.
  final StackTrace? stackTrace;
}

/// Authentication failed and could not be recovered: the token refresh
/// failed, threw or timed out (the refresh-failed callback has run).
final class AuthFailure extends OmniNetworkException {
  /// Creates an auth failure.
  const AuthFailure(super.message, {super.uri, super.cause, this.response});

  /// The 401 (or other expired-token) response that triggered the refresh.
  final OmniRawResponse? response;

  @override
  int? get statusCode => response?.statusCode;
}

/// The circuit breaker for [host] is open: the request was not sent.
final class CircuitOpenFailure extends OmniNetworkException {
  /// Creates an open-circuit failure.
  CircuitOpenFailure(this.host, {super.uri})
    : super('Circuit open for $host; request not sent');

  /// `host:port` whose circuit is open.
  final String host;
}

/// Removes user info, query and fragment so errors never leak secrets.
Uri safeUri(Uri uri) => Uri(
  scheme: uri.scheme,
  host: uri.host,
  port: uri.hasPort ? uri.port : null,
  path: uri.path,
);
