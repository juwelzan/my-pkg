import 'package:meta/meta.dart';

/// HTTP methods supported by [OmniRequest].
enum HttpMethod {
  /// GET
  get('GET'),

  /// POST
  post('POST'),

  /// PUT
  put('PUT'),

  /// PATCH
  patch('PATCH'),

  /// DELETE
  delete('DELETE'),

  /// HEAD
  head('HEAD');

  const HttpMethod(this.verb);

  /// Wire name, e.g. `GET`.
  final String verb;
}

/// An immutable description of one HTTP request.
///
/// [path] is resolved against the client's base URL unless it is absolute.
/// [body] may be `null`, a `String`, a `List<int>` (raw bytes), or a JSON
/// value (`Map`/`List`/`num`/`bool`) which is encoded as JSON.
@immutable
final class OmniRequest {
  /// Creates a request.
  const OmniRequest(
    this.method,
    this.path, {
    this.query = const {},
    this.headers = const {},
    this.body,
    this.timeout,
  });

  /// GET request.
  const OmniRequest.get(
    String path, {
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
  }) : this(
         HttpMethod.get,
         path,
         query: query,
         headers: headers,
         timeout: timeout,
       );

  /// POST request.
  const OmniRequest.post(
    String path, {
    Object? body,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
  }) : this(
         HttpMethod.post,
         path,
         body: body,
         query: query,
         headers: headers,
         timeout: timeout,
       );

  /// PUT request.
  const OmniRequest.put(
    String path, {
    Object? body,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
  }) : this(
         HttpMethod.put,
         path,
         body: body,
         query: query,
         headers: headers,
         timeout: timeout,
       );

  /// PATCH request.
  const OmniRequest.patch(
    String path, {
    Object? body,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
  }) : this(
         HttpMethod.patch,
         path,
         body: body,
         query: query,
         headers: headers,
         timeout: timeout,
       );

  /// DELETE request.
  const OmniRequest.delete(
    String path, {
    Object? body,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
  }) : this(
         HttpMethod.delete,
         path,
         body: body,
         query: query,
         headers: headers,
         timeout: timeout,
       );

  /// HEAD request.
  const OmniRequest.head(
    String path, {
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
  }) : this(
         HttpMethod.head,
         path,
         query: query,
         headers: headers,
         timeout: timeout,
       );

  /// HTTP method.
  final HttpMethod method;

  /// Relative path (joined to the base URL) or absolute `http(s)` URL.
  final String path;

  /// Query parameters. `null` values are dropped; `Iterable` values become
  /// repeated keys (`?id=1&id=2`); other values use `toString()`.
  final Map<String, Object?> query;

  /// Headers; override the client's default headers (case-insensitive).
  final Map<String, String> headers;

  /// Request body, see class docs.
  final Object? body;

  /// Overall deadline for this request; overrides the client's timeout.
  final Duration? timeout;

  @override
  String toString() => 'OmniRequest(${method.verb} $path)';
}
