import 'dart:async';
import 'dart:typed_data';

import '../core/cancel_signal.dart';
import '../core/omni_network_exception.dart';
import '../core/omni_response.dart';
import 'transport.dart';

/// Produces a response (or throws) for a request in [MockTransport].
typedef MockHandler =
    FutureOr<OmniRawResponse> Function(TransportRequest request);

/// In-memory [Transport] for tests: no sockets, no internet.
///
/// Streamed bodies (uploads) are read fully before [handler] runs, and the
/// recorded request carries them as `body`. Streamed responses (downloads)
/// are delivered in [chunkSize] pieces, [chunkDelay] apart.
final class MockTransport implements Transport {
  /// Creates a mock that answers every request with [handler].
  MockTransport(
    this.handler, {
    this.chunkSize = 1024,
    this.chunkDelay = Duration.zero,
  });

  /// The handler answering requests.
  MockHandler handler;

  /// Size of each chunk of a streamed response.
  int chunkSize;

  /// Pause before each chunk of a streamed response.
  Duration chunkDelay;

  /// Every request received, in order.
  final List<TransportRequest> requests = [];

  int _inFlight = 0;
  bool _closed = false;

  /// Requests (and response streams) currently active.
  int get inFlight => _inFlight;

  /// Whether [close] was called.
  bool get isClosed => _closed;

  @override
  Future<OmniRawResponse> send(
    TransportRequest request,
    CancelSignal cancel,
  ) async {
    if (_closed) throw const ConnectionFailure('MockTransport is closed');
    final uri = safeUri(request.uri);
    if (cancel.isCancelled) throw CancelledFailure(uri: uri);
    _inFlight++;
    try {
      return await Future.any<OmniRawResponse>([
        _handle(request),
        cancel.whenCancelled.then<OmniRawResponse>(
          (_) => throw CancelledFailure(uri: uri),
        ),
      ]);
    } finally {
      _inFlight--;
    }
  }

  Future<OmniRawResponse> _handle(TransportRequest request) async {
    var r = request;
    final open = request.bodyStream;
    if (open != null) {
      final b = BytesBuilder(copy: false);
      await for (final chunk in open()) {
        b.add(chunk);
      }
      r = TransportRequest(
        method: request.method,
        uri: request.uri,
        headers: request.headers,
        body: b.takeBytes(),
      );
    }
    requests.add(r);
    return handler(r);
  }

  @override
  Future<StreamedResponse> sendStreamed(
    TransportRequest request,
    CancelSignal cancel,
  ) async {
    final res = await send(request, cancel);
    final bytes = res.bodyBytes;
    final controller = StreamController<List<int>>();
    _inFlight++;
    var done = false;
    void finish() {
      if (done) return;
      done = true;
      _inFlight--;
    }

    controller.onListen = () async {
      try {
        for (var i = 0; i < bytes.length; i += chunkSize) {
          if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
          if (cancel.isCancelled || controller.isClosed) break;
          final end = i + chunkSize < bytes.length ? i + chunkSize : bytes.length;
          controller.add(Uint8List.sublistView(bytes, i, end));
        }
      } finally {
        finish();
        if (!controller.isClosed) await controller.close();
      }
    };
    controller.onCancel = finish;
    return StreamedResponse(
      statusCode: res.statusCode,
      headers: res.headers,
      body: controller.stream,
    );
  }

  @override
  Future<void> close({bool force = false}) async => _closed = true;
}
