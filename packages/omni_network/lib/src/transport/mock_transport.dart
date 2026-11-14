import 'dart:async';

import '../core/cancel_signal.dart';
import '../core/omni_network_exception.dart';
import '../core/omni_response.dart';
import 'transport.dart';

/// Produces a response (or throws) for a request in [MockTransport].
typedef MockHandler =
    FutureOr<OmniRawResponse> Function(TransportRequest request);

/// In-memory [Transport] for tests: no sockets, no internet.
final class MockTransport implements Transport {
  /// Creates a mock that answers every request with [handler].
  MockTransport(this.handler);

  /// The handler answering requests.
  MockHandler handler;

  /// Every request received, in order.
  final List<TransportRequest> requests = [];

  int _inFlight = 0;
  bool _closed = false;

  /// Requests currently awaiting the handler.
  int get inFlight => _inFlight;

  /// Whether [close] was called.
  bool get isClosed => _closed;

  @override
  Future<OmniRawResponse> send(
    TransportRequest request,
    CancelSignal cancel,
  ) async {
    if (_closed) throw ConnectionFailure('MockTransport is closed');
    requests.add(request);
    if (cancel.isCancelled) {
      throw CancelledFailure(uri: safeUri(request.uri));
    }
    _inFlight++;
    try {
      final result = Future.sync(() => handler(request));
      return await Future.any<OmniRawResponse>([
        result,
        cancel.whenCancelled.then<OmniRawResponse>(
          (_) => throw CancelledFailure(uri: safeUri(request.uri)),
        ),
      ]);
    } finally {
      _inFlight--;
    }
  }

  @override
  Future<void> close({bool force = false}) async => _closed = true;
}
