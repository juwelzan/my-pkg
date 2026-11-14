import 'package:meta/meta.dart';

import 'cancel_token.dart';

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
    this.skipAuth = false,
    this.cancelToken,
  });

  /// GET request.
  const OmniRequest.get(
    String path, {
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    bool skipAuth = false,
    OmniCancelToken? cancelToken,
  }) : this(
         HttpMethod.get,
         path,
         query: query,
         headers: headers,
         timeout: timeout,
         skipAuth: skipAuth,
         cancelToken: cancelToken,
       );

  /// POST request.
  const OmniRequest.post(
    String path, {
    Object? body,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    bool skipAuth = false,
    OmniCancelToken? cancelToken,
  }) : this(
         HttpMethod.post,
         path,
         body: body,
         query: query,
         headers: headers,
         timeout: timeout,
         skipAuth: skipAuth,
         cancelToken: cancelToken,
       );

  /// PUT request.
  const OmniRequest.put(
    String path, {
    Object? body,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    bool skipAuth = false,
    OmniCancelToken? cancelToken,
  }) : this(
         HttpMethod.put,
         path,
         body: body,
         query: query,
         headers: headers,
         timeout: timeout,
         skipAuth: skipAuth,
         cancelToken: cancelToken,
       );

  /// PATCH request.
  const OmniRequest.patch(
    String path, {
    Object? body,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    bool skipAuth = false,
    OmniCancelToken? cancelToken,
  }) : this(
         HttpMethod.patch,
         path,
         body: body,
         query: query,
         headers: headers,
         timeout: timeout,
         skipAuth: skipAuth,
         cancelToken: cancelToken,
       );

  /// DELETE request.
  const OmniRequest.delete(
    String path, {
    Object? body,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    bool skipAuth = false,
    OmniCancelToken? cancelToken,
  }) : this(
         HttpMethod.delete,
         path,
         body: body,
         query: query,
         headers: headers,
         timeout: timeout,
         skipAuth: skipAuth,
         cancelToken: cancelToken,
       );

  /// HEAD request.
  const OmniRequest.head(
    String path, {
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    bool skipAuth = false,
    OmniCancelToken? cancelToken,
  }) : this(
         HttpMethod.head,
         path,
         query: query,
         headers: headers,
         timeout: timeout,
         skipAuth: skipAuth,
         cancelToken: cancelToken,
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

  /// When `true`, the client's auth (e.g. `BearerAuth`) neither adds a
  /// token nor refreshes on 401 for this request. Requests made from inside
  /// a refresh callback skip auth automatically.
  final bool skipAuth;

  /// Cancels this request when cancelled, see [OmniCancelToken].
  final OmniCancelToken? cancelToken;

  /// Copy with the given fields replaced.
  OmniRequest copyWith({
    HttpMethod? method,
    String? path,
    Map<String, Object?>? query,
    Map<String, String>? headers,
    Object? body = _unset,
    Duration? timeout,
    bool? skipAuth,
    OmniCancelToken? cancelToken,
  }) => OmniRequest(
    method ?? this.method,
    path ?? this.path,
    query: query ?? this.query,
    headers: headers ?? this.headers,
    body: identical(body, _unset) ? this.body : body,
    timeout: timeout ?? this.timeout,
    skipAuth: skipAuth ?? this.skipAuth,
  );

  /// Copy with header [name] set to [value] (replacing any existing header
  /// of that name, case-insensitively).
  OmniRequest withHeader(String name, String value) {
    final lower = name.toLowerCase();
    return copyWith(
      headers: {
        for (final e in headers.entries)
          if (e.key.toLowerCase() != lower) e.key: e.value,
        name: value,
      },
    );
  }

  /// Value of header [name] (case-insensitive), or `null`.
  String? header(String name) {
    final lower = name.toLowerCase();
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
    }
    return null;
  }

  @override
  String toString() => 'OmniRequest(${method.verb} $path)';
}

const Object _unset = Object();
