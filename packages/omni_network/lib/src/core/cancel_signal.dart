import 'dart:async';

/// A one-shot signal telling a [Transport] to abandon a request.
///
/// Created by [OmniNetwork] for every request; transports listen to
/// [whenCancelled] and abort the underlying I/O.
final class CancelSignal {
  final Completer<Object> _completer = Completer<Object>();

  /// Whether [cancel] has been called.
  bool get isCancelled => _completer.isCompleted;

  /// Completes with the cancellation reason once [cancel] is called.
  Future<Object> get whenCancelled => _completer.future;

  /// Cancels with [reason]. Later calls are ignored.
  void cancel([Object reason = 'cancelled']) {
    if (!_completer.isCompleted) _completer.complete(reason);
  }
}
