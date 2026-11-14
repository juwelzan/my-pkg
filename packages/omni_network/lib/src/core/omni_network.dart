import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../transport/dio_transport.dart';
import '../transport/transport.dart';
import 'cancel_signal.dart';
import 'omni_network_exception.dart';
import 'omni_request.dart';
import 'omni_response.dart';

/// An HTTP client. Independent of Flutter, routing and state management.
///
/// ```dart
/// final api = OmniNetwork(baseUrl: 'https://api.example.com/v1');
/// final res = await api.send(const OmniRequest.get('/users/10'));
/// print(res.statusCode);
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
  OmniNetwork({
    String? baseUrl,
    Map<String, String> headers = const {},
    this.timeout = const Duration(seconds: 30),
    Transport? transport,
  }) : baseUri = baseUrl == null ? null : _parseBase(baseUrl),
       headers = Map.unmodifiable(_lower(headers)),
       _transport = transport ?? DioTransport(),
       _ownsTransport = transport == null;

  /// Parsed base URL (always ending in `/`), or `null`.
  final Uri? baseUri;

  /// Default headers (lower-case names).
  final Map<String, String> headers;

  /// Default overall request timeout.
  final Duration timeout;

  final Transport _transport;
  final bool _ownsTransport;
  final Set<CancelSignal> _pending = {};
  bool _closed = false;
  Future<void>? _closing;

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  /// Number of requests currently in flight.
  int get pendingRequests => _pending.length;

  /// Sends [request] and returns the raw response for any status code.
  ///
  /// Throws an [OmniNetworkException]: [TimeoutFailure], [ConnectionFailure],
  /// [ClosedFailure] or [RequestFailure].
  Future<OmniRawResponse> send(OmniRequest request) async {
    if (_closed) throw const ClosedFailure();
    final resolved = resolve(request);
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
      return response.withDuration(watch.elapsed);
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
