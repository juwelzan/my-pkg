import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../auth/bearer_auth.dart';
import '../cache/omni_cache.dart';
import '../log/network_log.dart';
import '../log/network_logger.dart';
import '../log/redactor.dart';
import '../paging/omni_pager.dart';
import '../paging/pagination_strategy.dart';
import '../resilience/circuit_breaker.dart';
import '../resilience/retry_policy.dart';
import '../transfer/download_target.dart';
import '../transfer/file_target_stub.dart'
    if (dart.library.io) '../transfer/file_target_io.dart';
import '../transfer/multipart.dart';
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
  /// * [retry]: default [RetryPolicy] (none when `null`); overridable per
  ///   request via `OmniRequest(retry:)`.
  /// * [circuitBreaker]: fail fast for hosts that keep failing.
  /// * [cache]: response cache for GET requests, see [OmniCache].
  /// * [deduplicate]: identical concurrent GETs (same URL and headers) share
  ///   one network call; each caller keeps its own timeout and cancel.
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
    this.retry,
    this.circuitBreaker,
    this.cache,
    this.deduplicate = true,
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

  /// Default retry policy, or `null` for no retries.
  final RetryPolicy? retry;

  /// Circuit breaker, or `null`.
  final CircuitBreaker? circuitBreaker;

  int _cancelEpoch = 0;

  /// Response cache, or `null`.
  final OmniCache? cache;

  /// Whether identical concurrent GETs share one network call.
  final bool deduplicate;

  final Map<String, _Shared> _inflight = {};

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
    OmniRequest.get(
      path,
      query: query,
      headers: headers,
      timeout: timeout,
      cancelToken: cancelToken,
    ),
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
    OmniRequest.get(
      path,
      query: query,
      headers: headers,
      timeout: timeout,
      cancelToken: cancelToken,
    ),
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
    OmniRequest.head(
      path,
      query: query,
      headers: headers,
      timeout: timeout,
      cancelToken: cancelToken,
    ),
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

  /// A pager over the list at [path]; see [OmniPager].
  ///
  /// [itemsKey] is the JSON path of the items in the full body (e.g.
  /// `data`), so metadata such as `meta.next_cursor` stays visible to the
  /// [strategy]. Without it, the client's response adapter result must be
  /// the item array.
  OmniPager<T> paginate<T>(
    String path, {
    required JsonDecoder<T> decoder,
    required PaginationStrategy strategy,
    String? itemsKey,
    int? maxPages,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) => OmniPager<T>(
    client: this,
    request: OmniRequest.get(path, query: query, headers: headers),
    strategy: strategy,
    decoder: decoder,
    itemsKey: itemsKey,
    maxPages: maxPages,
  );

  /// Uploads [files] and text [fields] as `multipart/form-data` and decodes
  /// the 2xx response into `T` (see [send]).
  ///
  /// [onProgress] reports bytes handed to the transport. Transfers have no
  /// overall deadline unless [timeout] is given; instead they fail with
  /// [TimeoutFailure] when no progress happens for [idleTimeout] (default:
  /// the client [timeout]). Cancel with [cancelToken].
  Future<T> upload<T>(
    String path, {
    List<UploadFile> files = const [],
    Map<String, String> fields = const {},
    HttpMethod method = HttpMethod.post,
    ProgressCallback? onProgress,
    JsonDecoder<T>? decoder,
    ResponseAdapter? adapter,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    Duration? idleTimeout,
    OmniCancelToken? cancelToken,
  }) async {
    final request = OmniRequest(
      method,
      path,
      body: MultipartBody(fields: fields, files: files),
      query: query,
      headers: headers,
      cancelToken: cancelToken,
    );
    final raw = await _pipeline(
      request,
      _Transfer(onSend: onProgress, overall: timeout, idle: idleTimeout),
    );
    if (!raw.isSuccess) throw HttpFailure(raw);
    return decodeBody<T>(raw, decoder, adapter ?? responseAdapter);
  }

  /// Downloads [path] into memory. See [upload] for timeouts/cancel.
  /// [onProgress] receives bytes received and `content-length` (if sent).
  Future<Uint8List> downloadBytes(
    String path, {
    ProgressCallback? onProgress,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    Duration? idleTimeout,
    OmniCancelToken? cancelToken,
  }) async {
    final target = BytesTarget();
    await _downloadTo(
      target,
      OmniRequest.get(
        path,
        query: query,
        headers: headers,
        cancelToken: cancelToken,
      ),
      onProgress,
      timeout,
      idleTimeout,
    );
    return target.bytes;
  }

  /// Whether [downloadToFile] works on this platform (`false` on Web).
  static bool get supportsFileDownload => fileDownloadSupported;

  /// Downloads [path] to [filePath] (IO platforms only; on Web throws
  /// [UnsupportedError], use [downloadBytes]).
  ///
  /// Data is written to `<filePath>.part` and renamed on success. When the
  /// download fails or is cancelled the `.part` file is kept; with
  /// [resume] a later call continues it using an HTTP `Range` request if
  /// the server answers `206`, or starts over if it answers `200`.
  /// Returns the final response (status and headers; empty body).
  Future<OmniRawResponse> downloadToFile(
    String path,
    String filePath, {
    bool resume = false,
    ProgressCallback? onProgress,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    Duration? idleTimeout,
    OmniCancelToken? cancelToken,
  }) => _downloadTo(
    FileTarget(filePath, resume: resume),
    OmniRequest.get(
      path,
      query: query,
      headers: headers,
      cancelToken: cancelToken,
    ),
    onProgress,
    timeout,
    idleTimeout,
  );

  Future<OmniRawResponse> _downloadTo(
    DownloadTarget target,
    OmniRequest request,
    ProgressCallback? onProgress,
    Duration? timeout,
    Duration? idleTimeout,
  ) async {
    final from = await target.existingLength();
    final raw = await _pipeline(
      from > 0 ? request.withHeader('Range', 'bytes=$from-') : request,
      _Transfer(
        target: target,
        onReceive: onProgress,
        overall: timeout,
        idle: idleTimeout,
        resumeFrom: from,
      ),
    );
    if (!raw.isSuccess) throw HttpFailure(raw);
    return raw;
  }

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
  Future<OmniRawResponse> sendRaw(OmniRequest request) =>
      _pipeline(request, null);

  Future<OmniRawResponse> _pipeline(OmniRequest request, _Transfer? t) async {
    if (_closed) throw const ClosedFailure();
    if (request.cancelToken?.isCancelled ?? false) {
      throw const CancelledFailure();
    }
    var current = request;
    final epoch = _cancelEpoch;
    try {
      for (final i in interceptors) {
        final r = current;
        current = await _guard(() => i.onRequest(r));
      }
      var response = await _withRetry(current, t, epoch);
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

  Future<OmniRawResponse> _withRetry(
    OmniRequest request,
    _Transfer? t,
    int epoch,
  ) async {
    final policy = t == null ? request.retry ?? retry : null;
    if (policy == null || !policy.allows(request)) {
      return _guarded(request, t, epoch);
    }
    for (var attempt = 1; ; attempt++) {
      final last = attempt >= policy.maxAttempts;
      Duration? wait;
      try {
        final res = await _guarded(request, t, epoch);
        if (last || !policy.statuses.contains(res.statusCode)) return res;
        wait = policy.delayFor(attempt, res);
        if (wait == null) return res;
      } on OmniNetworkException catch (e) {
        if (last || !policy.retriesError(e)) rethrow;
        wait = policy.backoff(attempt);
      }
      await _sleep(wait, request);
      _checkStillWanted(request, epoch);
    }
  }

  Future<OmniRawResponse> _guarded(
    OmniRequest request,
    _Transfer? t,
    int epoch,
  ) async {
    final breaker = circuitBreaker;
    if (breaker == null) return _authorized(request, t, epoch);
    final uri = _resolveUri(request);
    final host = '${uri.host}:${uri.port}';
    breaker.acquire(host, safeUri(uri));
    try {
      final res = await _authorized(request, t, epoch);
      breaker.record(host, success: res.statusCode < 500);
      return res;
    } on OmniNetworkException catch (e) {
      if (e is TimeoutFailure || e is ConnectionFailure) {
        breaker.record(host, success: false);
      } else {
        breaker.release(host);
      }
      rethrow;
    }
  }

  Future<void> _sleep(Duration delay, OmniRequest request) async {
    final signal = CancelSignal();
    final timer = Timer(delay, signal.cancel);
    final detach = request.cancelToken?.attach(
      () => signal.cancel(_Reason.user),
    );
    _pending.add(signal);
    try {
      final reason = await signal.whenCancelled;
      if (reason == _Reason.closed) throw const ClosedFailure();
      if (reason == _Reason.user) throw const CancelledFailure();
    } finally {
      timer.cancel();
      detach?.call();
      _pending.remove(signal);
    }
  }

  /// Cancels every in-flight request (including ones waiting for a retry
  /// or a token refresh) with [CancelledFailure]; the client stays usable.
  void cancelAll() {
    _cancelEpoch++;
    for (final s in _pending.toList()) {
      s.cancel(_Reason.user);
    }
  }

  Future<OmniRawResponse> _authorized(
    OmniRequest request,
    _Transfer? t,
    int epoch,
  ) async {
    final auth = this.auth;
    if (auth == null ||
        request.skipAuth ||
        insideRefresh ||
        request.header(auth.headerName) != null) {
      return _sendOnce(request, t);
    }
    final used = await auth.current();
    _checkStillWanted(request, epoch);
    final first = await _sendOnce(auth.attach(request, used), t);
    if (!auth.isExpired(first)) return first;
    final fresh = await auth.recover(used, first);
    _checkStillWanted(request, epoch);
    return _sendOnce(auth.attach(request, fresh), t);
  }

  void _checkStillWanted(OmniRequest request, int epoch) {
    if (_closed) throw const ClosedFailure();
    if (epoch != _cancelEpoch) throw const CancelledFailure();
    if (request.cancelToken?.isCancelled ?? false) {
      throw const CancelledFailure();
    }
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

  Future<OmniRawResponse> _sendOnce(OmniRequest request, _Transfer? t) async {
    if (_closed) throw const ClosedFailure();
    final log = _logger;
    if (log == null) return _network(resolve(request), request, t);
    final id = ++_logSeq;
    final watch = Stopwatch()..start();
    TransportRequest? resolved;
    try {
      resolved = resolve(request);
      log.request(id, resolved);
      final response = await _network(resolved, request, t);
      log.response(id, resolved, response);
      return response;
    } on OmniNetworkException catch (e) {
      log.error(id, resolved, request.method.verb, e, watch.elapsed);
      rethrow;
    }
  }

  Future<OmniRawResponse> _network(
    TransportRequest resolved,
    OmniRequest request,
    _Transfer? t,
  ) async {
    final cache = this.cache;
    if (cache == null || t != null) return _transmit(resolved, request, t);
    final res = await cache.handle(
      resolved,
      request.cachePolicy,
      (r) => _transmit(r, request, null),
    );
    return res.requestUri != null
        ? res
        : res.finish(duration: res.duration, requestUri: safeUri(resolved.uri));
  }

  Future<OmniRawResponse> _shared(TransportRequest r, CancelSignal caller) {
    final key = [
      r.uri.toString(),
      for (final e
          in (r.headers.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key))))
        '${e.key}:${e.value}',
    ].join('\n');
    var shared = _inflight[key];
    if (shared == null) {
      final signal = CancelSignal();
      final s = shared = _Shared(
        signal,
        Future.sync(() => _transport.send(r, signal)),
      );
      _inflight[key] = s;
      s.future.whenComplete(() {
        if (identical(_inflight[key], s)) _inflight.remove(key);
      }).ignore();
    }
    final s = shared;
    s.waiters++;
    caller.whenCancelled.then((_) {
      if (--s.waiters == 0) {
        s.signal.cancel();
        if (identical(_inflight[key], s)) _inflight.remove(key);
      }
    });
    return s.future;
  }

  Future<OmniRawResponse> _transmit(
    TransportRequest resolved,
    OmniRequest request,
    _Transfer? t,
  ) async {
    final uri = safeUri(resolved.uri);
    final signal = CancelSignal();
    final limit = t == null ? request.timeout ?? timeout : t.overall;
    final timer = limit == null
        ? null
        : Timer(limit, () => signal.cancel(_Reason.timeout));
    Timer? idle;
    final idleLimit = t?.idle ?? timeout;
    void kick() {
      if (t == null || signal.isCancelled) return;
      idle?.cancel();
      idle = Timer(idleLimit, () => signal.cancel(_Reason.idle));
    }

    final detach = request.cancelToken?.attach(
      () => signal.cancel(_Reason.user),
    );
    _pending.add(signal);
    var outgoing = resolved;
    final open = resolved.bodyStream;
    if (t != null && open != null) {
      final total = resolved.contentLength;
      outgoing = resolved.withBodyStream(() {
        var sent = 0;
        return open().map((chunk) {
          sent += chunk.length;
          kick();
          t.onSend?.call(sent, total);
          return chunk;
        });
      });
    }
    final watch = Stopwatch()..start();
    try {
      kick();
      final target = t?.target;
      final response = await Future.any<OmniRawResponse>([
        Future.sync(
          () => target == null
              ? (deduplicate &&
                        outgoing.method == HttpMethod.get &&
                        outgoing.body == null &&
                        outgoing.bodyStream == null
                    ? _shared(outgoing, signal)
                    : _transport.send(outgoing, signal))
              : _download(outgoing, signal, t!, target, kick, uri),
        ),
        signal.whenCancelled.then<OmniRawResponse>(
          (_) => throw CancelledFailure(uri: uri),
        ),
      ]);
      return response.finish(duration: watch.elapsed, requestUri: uri);
    } on OmniNetworkException catch (e) {
      if (e is CancelledFailure && signal.isCancelled) {
        final reason = await signal.whenCancelled;
        if (reason == _Reason.timeout) throw TimeoutFailure(limit!, uri: uri);
        if (reason == _Reason.idle) throw TimeoutFailure(idleLimit, uri: uri);
        if (reason == _Reason.closed) throw ClosedFailure(uri: uri);
        throw CancelledFailure(uri: uri);
      }
      rethrow;
    } on Exception catch (e) {
      throw ConnectionFailure('Transport error', uri: uri, cause: e);
    } finally {
      timer?.cancel();
      idle?.cancel();
      detach?.call();
      _pending.remove(signal);
    }
  }

  Future<OmniRawResponse> _download(
    TransportRequest request,
    CancelSignal signal,
    _Transfer t,
    DownloadTarget target,
    void Function() kick,
    Uri uri,
  ) async {
    final res = await _transport.sendStreamed(request, signal);
    kick();
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    if (!ok) {
      // Error bodies are small: buffer them for HttpFailure/auth handling.
      final b = BytesBuilder(copy: false);
      await for (final chunk in res.body) {
        b.add(chunk);
      }
      return OmniRawResponse(
        statusCode: res.statusCode,
        headers: res.headers,
        bodyBytes: b.takeBytes(),
      );
    }
    final append = res.statusCode == 206 && t.resumeFrom > 0;
    var received = append ? t.resumeFrom : 0;
    final length = res.contentLength;
    final total = length == null ? null : length + received;
    await target.begin(append: append);
    final done = Completer<void>();
    void fail(Object e) {
      if (done.isCompleted) return;
      done.completeError(
        e is OmniNetworkException
            ? e
            : ConnectionFailure('Download failed', uri: uri, cause: e),
      );
    }

    late final StreamSubscription<List<int>> sub;
    sub = res.body.listen(
      (chunk) async {
        sub.pause();
        try {
          await target.add(chunk);
          received += chunk.length;
          kick();
          t.onReceive?.call(received, total);
        } catch (e) {
          await sub.cancel();
          fail(e);
        } finally {
          sub.resume();
        }
      },
      onError: (Object e) {
        sub.cancel();
        fail(e);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    unawaited(
      signal.whenCancelled.then((_) {
        sub.cancel();
        fail(CancelledFailure(uri: uri));
      }),
    );
    try {
      await done.future;
      await target.commit();
    } catch (_) {
      await target.abort();
      rethrow;
    }
    return OmniRawResponse(statusCode: res.statusCode, headers: res.headers);
  }

  /// Builds the [TransportRequest] for [request] without sending it.
  /// Throws [RequestFailure] for an unresolvable URL or unsupported body.
  TransportRequest resolve(OmniRequest request) {
    final uri = _resolveUri(request);
    final merged = {...headers, ..._lower(request.headers)};
    final body = request.body;
    if (body is MultipartBody) {
      if (request.method == HttpMethod.get ||
          request.method == HttpMethod.head) {
        throw RequestFailure(
          '${request.method.verb} requests cannot have a body',
          uri: safeUri(uri),
        );
      }
      merged['content-type'] = body.contentType;
      return TransportRequest(
        method: request.method,
        uri: uri,
        headers: merged,
        bodyStream: body.open,
        contentLength: body.length,
      );
    }
    final encoded = _encodeBody(request, merged, uri);
    return TransportRequest(
      method: request.method,
      uri: uri,
      headers: merged,
      body: encoded,
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
    for (final s in _inflight.values.toList()) {
      s.signal.cancel();
    }
    _inflight.clear();
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

final class _Shared {
  _Shared(this.signal, this.future);
  final CancelSignal signal;
  final Future<OmniRawResponse> future;
  int waiters = 0;
}

enum _Reason { timeout, idle, closed, user }

final class _Transfer {
  _Transfer({
    this.onSend,
    this.onReceive,
    this.target,
    this.overall,
    this.idle,
    this.resumeFrom = 0,
  });

  final ProgressCallback? onSend;
  final ProgressCallback? onReceive;
  final DownloadTarget? target;
  final Duration? overall;
  final Duration? idle;
  final int resumeFrom;
}
