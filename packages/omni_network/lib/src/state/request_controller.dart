import 'dart:async';

import '../core/cancel_token.dart';
import 'request_state.dart';

/// Loads a value and exposes its [RequestState] as a stream.
///
/// ```dart
/// final user = api.watch<User>('/me', decoder: User.fromJson);
/// user.stream.listen(render);   // current state first, then changes
/// await user.refresh();
/// await user.close();
/// ```
///
/// * [load] returns the running load when one is already in progress;
///   [refresh] cancels it and starts over. A cancelled or superseded
///   load never emits.
/// * Failures keep the previous data (`RequestError.previous`), and
///   refreshes show it while loading (`RequestLoading.previous`).
/// * [close] cancels the in-flight request and completes [stream].
final class RequestController<T> {
  /// Creates a controller around [loader]; it receives a cancel token that
  /// it must pass to the request.
  RequestController(
    this._loader, {
    bool Function(T value)? isEmpty,
    bool autoLoad = false,
  }) : _isEmpty = isEmpty ?? _defaultIsEmpty {
    if (autoLoad) unawaited(load());
  }

  final Future<T> Function(OmniCancelToken cancelToken) _loader;
  final bool Function(T value) _isEmpty;
  final StreamController<RequestState<T>> _changes = StreamController.broadcast(
    sync: true,
  );

  RequestState<T> _state = RequestIdle<T>();
  T? _lastData;
  int _generation = 0;
  OmniCancelToken? _token;
  Future<void>? _running;
  bool _closed = false;

  static bool _defaultIsEmpty(Object? v) => switch (v) {
    null => true,
    Iterable() => v.isEmpty,
    Map() => v.isEmpty,
    String() => v.isEmpty,
    _ => false,
  };

  /// The current state.
  RequestState<T> get state => _state;

  /// The current state on listen, then every change. Each listener gets
  /// its own subscription; the stream completes on [close].
  Stream<RequestState<T>> get stream => Stream.multi((c) {
    if (_closed) {
      c.add(_state);
      c.close();
      return;
    }
    c.add(_state);
    final sub = _changes.stream.listen(c.add, onDone: c.close);
    c.onCancel = sub.cancel;
  });

  /// Whether [close] was called.
  bool get isClosed => _closed;

  /// Number of active [stream] listeners.
  bool get hasListeners => _changes.hasListener;

  void _emit(RequestState<T> s) {
    _state = s;
    if (!_closed) _changes.add(s);
  }

  /// Loads unless a load is already running (then returns that one).
  Future<void> load() {
    if (_closed) throw StateError('RequestController is closed');
    return _running ??= _run();
  }

  /// Cancels any running load and loads again.
  Future<void> refresh() {
    if (_closed) throw StateError('RequestController is closed');
    _cancelRunning();
    return _running = _run();
  }

  void _cancelRunning() {
    _generation++;
    _token?.cancel();
    _token = null;
    _running = null;
  }

  Future<void> _run() async {
    final generation = ++_generation;
    final token = _token = OmniCancelToken();
    _emit(RequestLoading<T>(previous: _lastData));
    try {
      final value = await _loader(token);
      if (generation != _generation || _closed) return;
      if (_isEmpty(value)) {
        _lastData = null;
        _emit(RequestEmpty<T>(value));
      } else {
        _lastData = value;
        _emit(RequestSuccess<T>(value));
      }
    } catch (e, st) {
      if (generation != _generation || _closed) return;
      _emit(RequestError<T>(e, previous: _lastData, stackTrace: st));
    } finally {
      if (generation == _generation) {
        _running = null;
        _token = null;
      }
    }
  }

  /// Cancels the running load and completes [stream]. Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _cancelRunning();
    _closed = true;
    await _changes.close();
  }
}
