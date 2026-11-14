/// Cancels one or more requests from outside.
///
/// ```dart
/// final token = OmniCancelToken();
/// final f = api.get<User>('/slow', decoder: User.fromJson, cancelToken: token);
/// token.cancel(); // f fails with CancelledFailure
/// ```
///
/// A token can be shared by many requests; cancelling it cancels all of
/// them, and requests sent with an already-cancelled token fail at once.
/// Tokens hold no timers and keep no reference to finished requests.
final class OmniCancelToken {
  /// Creates an un-cancelled token.
  OmniCancelToken();

  final Set<void Function()> _listeners = {};
  bool _cancelled = false;

  /// Whether [cancel] was called.
  bool get isCancelled => _cancelled;

  /// Number of requests currently attached (diagnostics/tests).
  int get attachedRequests => _listeners.length;

  /// Cancels every attached and future request. Idempotent.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in _listeners.toList()) {
      l();
    }
    _listeners.clear();
  }

  /// A token that is cancelled when this one is (but can also be
  /// cancelled on its own), e.g. one per screen under an app-wide token.
  OmniCancelToken child() {
    final c = OmniCancelToken();
    final detach = attach(c.cancel);
    c.attach(detach);
    return c;
  }

  /// Registers [onCancel]; returns a function that unregisters it. Internal.
  void Function() attach(void Function() onCancel) {
    if (_cancelled) {
      onCancel();
      return () {};
    }
    _listeners.add(onCancel);
    return () => _listeners.remove(onCancel);
  }
}
