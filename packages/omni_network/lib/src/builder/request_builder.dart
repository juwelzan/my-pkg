import 'dart:convert';

import '../cache/omni_cache.dart' show CachePolicy;
import '../core/cancel_token.dart';
import '../core/decoding.dart';
import '../core/omni_network.dart';
import '../core/omni_request.dart';
import '../core/omni_response.dart';
import '../resilience/retry_policy.dart';

/// Fluent sugar over [OmniRequest]. Create with `OmniNetwork.request`.
///
/// ```dart
/// final users = await api
///     .request('/users')
///     .query('page', 2)
///     .header('X-Trace', id)
///     .timeout(const Duration(seconds: 5))
///     .sendList<User>(decoder: User.fromJson);
///
/// await api.request('/login', method: HttpMethod.post)
///     .form({'user': u, 'password': p})
///     .send<void>();
/// ```
final class OmniRequestBuilder {
  /// Creates a builder. Prefer `OmniNetwork.request`.
  OmniRequestBuilder(this._client, this._method, this._path);

  final OmniNetwork _client;
  HttpMethod _method;
  final String _path;
  final Map<String, Object?> _query = {};
  final Map<String, String> _headers = {};
  Object? _body;
  Duration? _timeout;
  OmniCancelToken? _cancelToken;
  RetryPolicy? _retry;
  CachePolicy? _cachePolicy;
  bool _skipAuth = false;

  /// Sets the HTTP method.
  OmniRequestBuilder method(HttpMethod method) {
    _method = method;
    return this;
  }

  /// Adds a query parameter (an `Iterable` value repeats the key).
  OmniRequestBuilder query(String name, Object? value) {
    _query[name] = value;
    return this;
  }

  /// Adds several query parameters.
  OmniRequestBuilder queryAll(Map<String, Object?> values) {
    _query.addAll(values);
    return this;
  }

  /// Sets a header.
  OmniRequestBuilder header(String name, String value) {
    _headers[name] = value;
    return this;
  }

  /// JSON body (`Map`/`List`/`num`/`bool`).
  OmniRequestBuilder json(Object? value) {
    _body = value;
    return this;
  }

  /// Plain-text body.
  OmniRequestBuilder text(
    String value, {
    String contentType = 'text/plain; charset=utf-8',
  }) {
    _body = value;
    _headers['content-type'] = contentType;
    return this;
  }

  /// Raw bytes body.
  OmniRequestBuilder bytes(
    List<int> value, {
    String contentType = 'application/octet-stream',
  }) {
    _body = value;
    _headers['content-type'] = contentType;
    return this;
  }

  /// `application/x-www-form-urlencoded` body.
  OmniRequestBuilder form(Map<String, String> fields) {
    _body = fields.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    _headers['content-type'] = 'application/x-www-form-urlencoded';
    return this;
  }

  /// Any body accepted by [OmniRequest.body].
  OmniRequestBuilder body(Object? value) {
    _body = value;
    return this;
  }

  /// Overall timeout.
  OmniRequestBuilder timeout(Duration value) {
    _timeout = value;
    return this;
  }

  /// Cancel token.
  OmniRequestBuilder cancelToken(OmniCancelToken token) {
    _cancelToken = token;
    return this;
  }

  /// Retry policy.
  OmniRequestBuilder retry(RetryPolicy policy) {
    _retry = policy;
    return this;
  }

  /// Cache policy.
  OmniRequestBuilder cache(CachePolicy policy) {
    _cachePolicy = policy;
    return this;
  }

  /// Skip the client's auth.
  OmniRequestBuilder skipAuth() {
    _skipAuth = true;
    return this;
  }

  /// The built request.
  OmniRequest build() => OmniRequest(
    _method,
    _path,
    query: Map.of(_query),
    headers: Map.of(_headers),
    body: _body,
    timeout: _timeout,
    cancelToken: _cancelToken,
    retry: _retry,
    cachePolicy: _cachePolicy,
    skipAuth: _skipAuth,
  );

  /// Sends and decodes into `T`; see `OmniNetwork.send`.
  Future<T> send<T>({JsonDecoder<T>? decoder}) async =>
      (await _client.send<T>(build(), decoder: decoder)).data;

  /// Sends and decodes a JSON array.
  Future<List<T>> sendList<T>({required JsonDecoder<T> decoder}) async =>
      (await _client.sendList<T>(build(), decoder: decoder)).data;

  /// Sends and returns the raw response (any status).
  Future<OmniRawResponse> sendRaw() => _client.sendRaw(build());

  /// The request as a (redacted by default) cURL command.
  String toCurl({bool redact = true}) =>
      _client.toCurl(build(), redact: redact);

  @override
  String toString() => jsonEncode({'method': _method.verb, 'path': _path});
}
