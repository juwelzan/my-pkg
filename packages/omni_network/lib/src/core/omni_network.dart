import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../auth/bearer_auth.dart';
import '../log/network_log.dart';
import '../log/network_logger.dart';
import '../log/redactor.dart';
import '../transport/dio_transport.dart';
import '../transport/transport.dart';
import 'cancel_signal.dart';
import 'cancel_token.dart';
import 'decoding.dart';
import 'interceptor.dart';
import 'omni_network_exception.dart';
import 'omni_request.dart';
import 'omni_response.dart';
import 'response_adapter.dart';

/// An HTTP client. Independent of Flutter, routing and state management.
///
/// ```dart
/// final api = OmniNetwork(baseUrl: 'https://api.example.com/v1');
/// final user = await api.get<User>('/users/10', decoder: User.fromJson);
/// await api.close();
/// ```
final class OmniNetwork {
  /// Creates a client.
  ///
  /// * [baseUrl]: joined with relative request paths (`/users` and `users`
  ///   both resolve under it, including its path, e.g. `/v1/users`).
  /// * [headers]: default headers, overridden per request.
  /// * [timeout]: overall deadline per request (connect + send + receive).
  /// * [transport]: defaults to a [DioTransport] owned by this client. A
  ///   transport you pass in is **not** closed by [close]; you own it.
  /// * [responseAdapter]: applied to every JSON body before decoding,
  ///   e.g. [EnvelopeResponseAdapter]; overridable per call.
  /// * [enableLogging]: the single logging switch, default `false`. When
  ///   off, nothing is formatted and [logSink] is never called. When on,
  ///   every request, response and failure goes to [logSink] (default:
  ///   [PrintLogSink]) after [redactor] masked secrets; [logBodies]
  ///   includes redacted, truncated bodies. Redaction cannot be disabled.
  /// * [interceptors]: see [OmniInterceptor].
  /// * [auth]: token injection and single-flight refresh, see [BearerAuth].
  OmniNetwork({
    String? baseUrl,
    Map<String, String> headers = const {},
    this.timeout = const Duration(seconds: 30),
    Transport? transport,
    this.responseAdapter = const PlainResponseAdapter(),
    this.enableLogging = false,
    LogSink? logSink,
    Redactor redactor = const Redactor(),
    bool logBodies = true,
    List<OmniInterceptor> interceptors = const [],
    this.auth,
  }) : interceptors = List.unmodifiable(interceptors),
       _logger = enableLogging
           ? NetworkLogger(
               logSink ?? const PrintLogSink(),
               redactor,
               logBodies: logBodies,
             )
           : null,
       baseUri = baseUrl == null ? null : _parseBase(baseUrl),
       headers = Map.unmodifiable(_lower(headers)),
       _transport = transport ?? DioTransport(),
       _ownsTransport = transport == null;

  /// Parsed base URL (always ending in `/`), or `null`.
  final Uri? baseUri;

  /// Default headers (lower-case names).
  final Map<String, String> headers;

  /// Default overall request timeout.
  final Duration timeout;

  /// Interceptors, in `onRequest` order.
  final List<OmniInterceptor> interceptors;

  /// Token auth, or `null`.
  final BearerAuth? auth;

  /// Whether requests are logged. See the constructor.
  final bool enableLogging;

  final NetworkLogger? _logger;
  int _logSeq = 0;

  /// Default [ResponseAdapter] for typed calls.
  final ResponseAdapter responseAdapter;

  final Transport _transport;
  final bool _ownsTransport;
  final Set<CancelSignal> _pending = {};
  bool _closed = false;
  Future<void>? _closing;

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  /// Number of requests currently in flight.
  int get pendingRequests => _pending.length;

  /// Sends [request] and decodes a 2xx body into `T`.
  ///
  /// With [decoder], the body must be a JSON object (after [adapter]).
  /// Without it: nullable `T` (incl. `void`) accepts an empty body;
  /// `String` returns the text; `void`/`dynamic`/`Object?` return the parsed
  /// JSON, or the text if it is not JSON; other `T` (e.g. `int`,
  /// `Map<String, dynamic>`) are cast from the parsed JSON.
  ///
  /// Throws [HttpFailure] for non-2xx, [DecodeFailure] for a bad body, and
  /// everything [sendRaw] throws.
  Future<OmniResponse<T>> send<T>(
    OmniRequest request, {
    JsonDecoder<T>? decoder,
    ResponseAdapter? adapter,
  }) async {
    final raw = await _ok(request);
    return OmniResponse(
      decodeBody<T>(raw, decoder, adapter ?? responseAdapter),
      raw,
    );
  }

  /// Like [send] for a JSON array of objects.
  Future<OmniResponse<List<T>>> sendList<T>(
    OmniRequest request, {
    required JsonDecoder<T> decoder,
    ResponseAdapter? adapter,
  }) async {
    final raw = await _ok(request);
    return OmniResponse(
      decodeList<T>(raw, decoder, adapter ?? responseAdapter),
      raw,
    );
  }

  /// GET [path] decoded into `T`. See [send].
  ///
  /// ```dart
  /// final user = await api.get<User>('/users/10', decoder: User.fromJson);
  /// ```
  Future<T> get<T>(
    String path, {
    JsonDecoder<T>? decoder,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    OmniCancelToken? cancelToken,
    ResponseAdapter? adapter,
  }) async => (await send<T>(
    OmniRequest.get(path, query: query, headers: headers, timeout: timeout,
        cancelToken: cancelToken),
    decoder: decoder,
    adapter: adapter,
  )).data;

  /// GET [path] decoded into `List<T>`. See [sendList].
  Future<List<T>> getList<T>(
    String path, {
    required JsonDecoder<T> decoder,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    OmniCancelToken? cancelToken,
    ResponseAdapter? adapter,
  }) async => (await sendList<T>(
    OmniRequest.get(path, query: query, headers: headers, timeout: timeout,
        cancelToken: cancelToken),
    decoder: decoder,
    adapter: adapter,
  )).data;

  /// POST [body] to [path]; decodes the response into `T`. See [send].
  Future<T> post<T>(
    String path, {
    Object? body,
    JsonDecoder<T>? decoder,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    OmniCancelToken? cancelToken,
    ResponseAdapter? adapter,
  }) => _body<T>(
    HttpMethod.post,
    path,
    body,
    decoder,
    query,
    headers,
    timeout,
    cancelToken,
    adapter,
  );

  /// PUT [body] to [path]; decodes the response into `T`. See [send].
  Future<T> put<T>(
    String path, {
    Object? body,
    JsonDecoder<T>? decoder,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    OmniCancelToken? cancelToken,
    ResponseAdapter? adapter,
  }) => _body<T>(
    HttpMethod.put,
    path,
    body,
    decoder,
    query,
    headers,
    timeout,
    cancelToken,
    adapter,
  );

  /// PATCH [body] to [path]; decodes the response into `T`. See [send].
  Future<T> patch<T>(
    String path, {
    Object? body,
    JsonDecoder<T>? decoder,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    OmniCancelToken? cancelToken,
    ResponseAdapter? adapter,
  }) => _body<T>(
    HttpMethod.patch,
    path,
    body,
    decoder,
    query,
    headers,
    timeout,
    cancelToken,
    adapter,
  );

  /// DELETE [path]; decodes the response into `T` (often `void`).
  Future<T> delete<T>(
    String path, {
    Object? body,
    JsonDecoder<T>? decoder,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    OmniCancelToken? cancelToken,
    ResponseAdapter? adapter,
  }) => _body<T>(
    HttpMethod.delete,
    path,
    body,
    decoder,
    query,
    headers,
    timeout,
    cancelToken,
    adapter,
  );

  /// HEAD [path]; returns the 2xx response (status and headers only).
  Future<OmniRawResponse> head(
    String path, {
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    OmniCancelToken? cancelToken,
  }) => _ok(
    OmniRequest.head(path, query: query, headers: headers, timeout: timeout,
        cancelToken: cancelToken),
  );

  Future<T> _body<T>(
    HttpMethod method,
    String path,
    Object? body,
    JsonDecoder<T>? decoder,
    Map<String, Object?> query,
    Map<String, String> headers,
    Duration? timeout,
    OmniCancelToken? cancelToken,
    ResponseAdapter? adapter,
  ) async => (await send<T>(
    OmniRequest(
      method,
      path,
      body: body,
      query: query,
      headers: headers,
      timeout: timeout,
      cancelToken: cancelToken,
    ),
    decoder: decoder,
    adapter: adapter,
  )).data;

  Future<OmniRawResponse> _ok(OmniRequest request) async {
    final raw = await sendRaw(request);
    if (!raw.isSuccess) throw HttpFailure(raw);
    return raw;
  }

  /// Sends [request] and returns the raw response for **any** status code
  /// (no decoding, no status check).
  ///
  /// Throws an [OmniNetworkException]: [TimeoutFailure], [ConnectionFailure],
  /// [ClosedFailure] or [RequestFailure].
  Future<OmniRawResponse> sendRaw(OmniRequest request) async {
    if (_closed) throw const ClosedFailure();
    var current = request;
    try {
      for (final i in interceptors) {
        final r = current;
        current = await _guard(() => i.onRequest(r));
      }
      var response = await _authorized(current);
      for (final i in interceptors.reversed) {
        final res = response;
        final r = current;
        response = await _guard(() => i.onResponse(r, res));
      }
      return response;
    } on OmniNetworkException catch (e) {
      for (final i in interceptors.reversed) {
        try {
          await i.onError(current, e);
        } catch (_) {
          // Keep the original failure.
        }
      }
      rethrow;
    }
  }

  Future<OmniRawResponse> _authorized(OmniRequest request) async {
    final auth = this.auth;
    if (auth == null ||
        request.skipAuth ||
        insideRefresh ||
        request.header(auth.headerName) != null) {
      return _sendOnce(request);
    }
    final used = await auth.current();
    if (_closed) throw const ClosedFailure();
    final first = await _sendOnce(auth.attach(request, used));
    if (!auth.isExpired(first)) return first;
    final fresh = await auth.recover(used, first);
    if (_closed) throw const ClosedFailure();
    return _sendOnce(auth.attach(request, fresh));
  }

  static Future<T> _guard<T>(FutureOr<T> Function() run) async {
    try {
      return await run();
    } on OmniNetworkException {
      rethrow;
    } on Exception catch (e) {
      throw RequestFailure('Interceptor threw ${e.runtimeType}', cause: e);
    }
  }

  Future<OmniRawResponse> _sendOnce(OmniRequest request) async {
    if (_closed) throw const ClosedFailure();
    final log = _logger;
    if (log == null) return _transmit(resolve(request), request);
    final id = ++_logSeq;
    final watch = Stopwatch()..start();
    TransportRequest? resolved;
    try {
      resolved = resolve(request);
      log.request(id, resolved);
      final response = await _transmit(resolved, request);
      log.response(id, resolved, response);
      return response;
    } on OmniNetworkException catch (e) {
      log.error(id, resolved, request.method.verb, e, watch.elapsed);
      rethrow;
    }
  }

  Future<OmniRawResponse> _transmit(
    TransportRequest resolved,
    OmniRequest request,
  ) async {
    final uri = safeUri(resolved.uri);
    final signal = CancelSignal();
    final limit = request.timeout ?? timeout;
    final timer = Timer(limit, () => signal.cancel(_Reason.timeout));
    _pending.add(signal);
    final watch = Stopwatch()..start();
    try {
      final response = await Future.any<OmniRawResponse>([
        Future.sync(() => _transport.send(resolved, signal)),
        signal.whenCancelled.then<OmniRawResponse>(
          (_) => throw CancelledFailure(uri: uri),
        ),
      ]);
      return response.finish(duration: watch.elapsed, requestUri: uri);
    } on OmniNetworkException catch (e) {
      if (e is CancelledFailure && signal.isCancelled) {
        final reason = await signal.whenCancelled;
        if (reason == _Reason.timeout) throw TimeoutFailure(limit, uri: uri);
        if (reason == _Reason.closed) throw ClosedFailure(uri: uri);
      }
      rethrow;
    } on Exception catch (e) {
      throw ConnectionFailure('Transport error', uri: uri, cause: e);
    } finally {
      timer.cancel();
      _pending.remove(signal);
    }
  }

  /// Builds the [TransportRequest] for [request] without sending it.
  /// Throws [RequestFailure] for an unresolvable URL or unsupported body.
  TransportRequest resolve(OmniRequest request) {
    final uri = _resolveUri(request);
    final merged = {...headers, ..._lower(request.headers)};
    final body = _encodeBody(request, merged, uri);
    return TransportRequest(
      method: request.method,
      uri: uri,
      headers: merged,
      body: body,
    );
  }

  /// Closes the client: in-flight requests fail with [ClosedFailure], new
  /// ones are rejected, and an owned transport is closed. Idempotent.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    for (final s in _pending.toList()) {
      s.cancel(_Reason.closed);
    }
    if (_ownsTransport) await _transport.close(force: true);
  }

  Uri _resolveUri(OmniRequest request) {
    final Uri parsed;
    try {
      parsed = Uri.parse(request.path);
    } on FormatException catch (e) {
      throw RequestFailure('Invalid path', cause: e);
    }
    final Uri target;
    if (parsed.hasScheme) {
      if (parsed.scheme != 'http' && parsed.scheme != 'https') {
        throw RequestFailure('Unsupported URL scheme "${parsed.scheme}"');
      }
      target = parsed;
    } else {
      final base = baseUri;
      if (base == null) {
        throw const RequestFailure(
          'Relative path used but no baseUrl was configured',
        );
      }
      var rel = request.path;
      while (rel.startsWith('/')) {
        rel = rel.substring(1);
      }
      target = base.resolve(rel);
    }
    if (request.query.isEmpty) return target;
    final all = <String, List<String>>{
      for (final e in target.queryParametersAll.entries) e.key: [...e.value],
    };
    for (final MapEntry(:key, :value) in request.query.entries) {
      if (value == null) continue;
      final values = value is Iterable
          ? [
              for (final v in value)
                if (v != null) '$v',
            ]
          : ['$value'];
      (all[key] ??= []).addAll(values);
    }
    return target.replace(queryParameters: all);
  }

  static Uint8List? _encodeBody(
    OmniRequest request,
    Map<String, String> headers,
    Uri uri,
  ) {
    final body = request.body;
    if (body == null) return null;
    if (request.method == HttpMethod.get || request.method == HttpMethod.head) {
      throw RequestFailure(
        '${request.method.verb} requests cannot have a body',
        uri: safeUri(uri),
      );
    }
    void type(String t) => headers.putIfAbsent('content-type', () => t);
    switch (body) {
      case Uint8List():
        type('application/octet-stream');
        return body;
      case List<int>():
        type('application/octet-stream');
        return Uint8List.fromList(body);
      case String():
        type('text/plain; charset=utf-8');
        return utf8.encode(body);
      case Map() || List() || num() || bool():
        type('application/json; charset=utf-8');
        try {
          return utf8.encode(jsonEncode(body));
        } on JsonUnsupportedObjectError catch (e) {
          throw RequestFailure(
            'Body is not JSON-encodable',
            uri: safeUri(uri),
            cause: e,
          );
        }
      default:
        throw RequestFailure(
          'Unsupported body type ${body.runtimeType}; pass a JSON value, '
          'String or List<int>',
          uri: safeUri(uri),
        );
    }
  }

  static Uri _parseBase(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'must be an absolute http(s) URL',
      );
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'must not contain a query or fragment',
      );
    }
    return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
  }

  static Map<String, String> _lower(Map<String, String> h) => {
    for (final e in h.entries) e.key.toLowerCase(): e.value,
  };
}

enum _Reason { timeout, closed }
