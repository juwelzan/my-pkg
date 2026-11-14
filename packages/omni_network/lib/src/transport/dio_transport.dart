import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/cancel_signal.dart';
import '../core/omni_network_exception.dart';
import '../core/omni_response.dart';
import 'transport.dart';

/// Default [Transport] backed by `package:dio`.
///
/// Dio is an implementation detail: no Dio type appears in OmniNetwork's
/// request/response API. Status codes are never turned into errors here,
/// and timeouts are enforced by `OmniNetwork`, not by Dio.
final class DioTransport implements Transport {
  /// Creates a transport. Pass [dio] to customise the adapter (e.g. a
  /// native adapter or proxy); its interceptors still run.
  DioTransport({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  final Set<CancelToken> _active = {};

  @override
  Future<OmniRawResponse> send(
    TransportRequest request,
    CancelSignal cancel,
  ) async {
    final r = await _request<List<int>>(request, cancel, ResponseType.bytes);
    final data = r.data;
    return OmniRawResponse(
      statusCode: r.statusCode ?? 0,
      headers: _headers(r.headers),
      bodyBytes: data == null
          ? null
          : data is Uint8List
          ? data
          : Uint8List.fromList(data),
    );
  }

  @override
  Future<StreamedResponse> sendStreamed(
    TransportRequest request,
    CancelSignal cancel,
  ) async {
    final r = await _request<ResponseBody>(
      request,
      cancel,
      ResponseType.stream,
    );
    final body = r.data;
    return StreamedResponse(
      statusCode: r.statusCode ?? 0,
      headers: _headers(r.headers),
      body: body == null
          ? const Stream<List<int>>.empty()
          : body.stream.handleError((Object e) {
              throw ConnectionFailure(
                'Connection lost while reading the body',
                uri: safeUri(request.uri),
                cause: e,
              );
            }),
    );
  }

  static Map<String, String> _headers(Headers h) => {
    for (final e in h.map.entries) e.key: e.value.join(', '),
  };

  Future<Response<T>> _request<T>(
    TransportRequest request,
    CancelSignal cancel,
    ResponseType type,
  ) async {
    final token = CancelToken();
    _active.add(token);
    final sub = cancel.whenCancelled.then((_) => token.cancel());
    if (cancel.isCancelled) token.cancel();
    final open = request.bodyStream;
    final headers = {
      ...request.headers,
      if (open != null && request.contentLength != null)
        'content-length': '${request.contentLength}',
    };
    try {
      return await _dio.requestUri<T>(
        request.uri,
        data: open != null ? open() : request.body,
        cancelToken: token,
        options: Options(
          method: request.method.verb,
          headers: headers,
          responseType: type,
          validateStatus: (_) => true,
          followRedirects: true,
          // Dio would otherwise pick a content type; ours is in headers.
          contentType: request.headers['content-type'],
        ),
      );
    } on DioException catch (e) {
      final uri = safeUri(request.uri);
      if (e.type == DioExceptionType.cancel) {
        throw CancelledFailure(uri: uri);
      }
      throw ConnectionFailure(
        'Network error (${e.type.name})',
        uri: uri,
        cause: e.error ?? e.type,
      );
    } finally {
      _active.remove(token);
      sub.ignore();
    }
  }

  @override
  Future<void> close({bool force = false}) async {
    if (force) {
      for (final t in _active.toList()) {
        t.cancel();
      }
    }
    _dio.close(force: force);
  }
}
