import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'ws_connect_web.dart' if (dart.library.io) 'ws_connect_io.dart';

/// Opens a channel; inject for tests or custom transports.
typedef WebSocketConnector =
    WebSocketChannel Function(
      Uri uri,
      Iterable<String>? protocols,
      Map<String, String> headers,
    );

/// Connection state of an [OmniWebSocket].
enum WebSocketState {
  /// Opening a connection.
  connecting,

  /// Connected.
  open,

  /// Lost; waiting before the next attempt.
  reconnecting,

  /// Closed for good (by you, by a normal server close, or after giving up).
  closed,
}

/// A WebSocket that reconnects with backoff and never queues silently.
///
/// ```dart
/// final ws = OmniWebSocket(Uri.parse('wss://api.example.com/live'),
///     headers: () async => {'authorization': 'Bearer ${await token()}'});
/// ws.messages.listen(print);
/// ws.sendJson({'subscribe': 'prices'});
/// await ws.close();
/// ```
///
/// * Reconnects after errors and abnormal closes (not after a normal close
///   `1000` from the server, nor after [close]). Delays grow
///   exponentially from [minDelay] to [maxDelay] with jitter;
///   [maxReconnects] bounds consecutive failures.
/// * [headers] is evaluated on every (re)connect, so a refreshed token is
///   used. Handshake headers work on IO platforms only; browsers forbid
///   them ([supportsHandshakeHeaders]).
/// * [send] while not open throws [StateError] unless
///   [bufferWhileDisconnected] is set; then up to [maxBuffered] messages
///   are kept and sent in order after reconnecting (overflow throws).
/// * [onOpen] runs after each successful (re)connect, e.g. to resubscribe.
final class OmniWebSocket {
  /// Connects immediately.
  OmniWebSocket(
    this.uri, {
    this.protocols,
    this._headers,
    this.minDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.maxReconnects,
    this.bufferWhileDisconnected = false,
    this.maxBuffered = 100,
    this.onOpen,
    WebSocketConnector? connector,
    Random? random,
  }) : _connector = connector ?? platformConnect,
       _random = random ?? Random() {
    unawaited(_loop());
  }

  /// Server URL (`ws:` or `wss:`).
  final Uri uri;

  /// Sub-protocols offered.
  final Iterable<String>? protocols;

  /// Initial reconnect delay.
  final Duration minDelay;

  /// Maximum reconnect delay.
  final Duration maxDelay;

  /// Consecutive failed attempts allowed (`null` = unlimited).
  final int? maxReconnects;

  /// Keep messages sent while disconnected (explicit opt-in).
  final bool bufferWhileDisconnected;

  /// Buffer limit when [bufferWhileDisconnected].
  final int maxBuffered;

  /// Runs after every successful connect.
  final FutureOr<void> Function(OmniWebSocket socket)? onOpen;

  /// Whether this platform can send handshake headers.
  static bool get supportsHandshakeHeaders => handshakeHeadersSupported;

  final FutureOr<Map<String, String>> Function()? _headers;
  final WebSocketConnector _connector;
  final Random _random;
  final _messages = StreamController<Object>.broadcast();
  final _states = StreamController<WebSocketState>.broadcast(sync: true);
  final List<Object> _buffer = [];
  WebSocketChannel? _channel;
  WebSocketState _state = WebSocketState.connecting;
  Completer<void>? _wait;
  bool _closed = false;
  int _connects = 0;

  /// Incoming messages (`String` or `List<int>`), broadcast. Errors that
  /// end reconnecting are delivered as stream errors.
  Stream<Object> get messages => _messages.stream;

  /// Incoming text messages parsed as JSON.
  Stream<Object?> get jsonMessages =>
      messages.where((m) => m is String).map((m) => jsonDecode(m as String));

  /// State changes, broadcast.
  Stream<WebSocketState> get states => _states.stream;

  /// Current state.
  WebSocketState get state => _state;

  /// Successful connects so far (diagnostics/tests).
  int get connectCount => _connects;

  /// Messages waiting to be sent after reconnect.
  int get buffered => _buffer.length;

  /// Close code of the last connection, if any.
  int? get lastCloseCode => _lastCloseCode;
  int? _lastCloseCode;

  void _set(WebSocketState s) {
    if (_state == s) return;
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  Future<void> _loop() async {
    var failures = 0;
    while (!_closed) {
      _set(WebSocketState.connecting);
      WebSocketChannel? channel;
      try {
        final headers = await _headers?.call() ?? const <String, String>{};
        channel = _connector(uri, protocols, headers);
        await channel.ready;
        if (_closed) {
          await channel.sink.close(1000);
          break;
        }
        _channel = channel;
        _connects++;
        failures = 0;
        _set(WebSocketState.open);
        while (_buffer.isNotEmpty) {
          channel.sink.add(_buffer.removeAt(0));
        }
        await onOpen?.call(this);
        await for (final m in channel.stream) {
          if (!_messages.isClosed) _messages.add(m as Object);
        }
        _lastCloseCode = channel.closeCode;
        _channel = null;
        if (_closed || channel.closeCode == 1000) break;
      } catch (e) {
        _channel = null;
        if (_closed) break;
        failures++;
      }
      if (maxReconnects case final max? when failures > max) {
        if (!_messages.isClosed) {
          _messages.addError(
            StateError('WebSocket: gave up after $max reconnect attempts'),
          );
        }
        break;
      }
      _set(WebSocketState.reconnecting);
      await _sleep(_delay(max(1, failures)));
    }
    _closed = true;
    _set(WebSocketState.closed);
    _buffer.clear();
    if (!_messages.isClosed) await _messages.close();
    if (!_states.isClosed) await _states.close();
  }

  Duration _delay(int attempt) {
    final ms = min(
      minDelay.inMilliseconds * pow(2, attempt - 1).toDouble(),
      maxDelay.inMilliseconds.toDouble(),
    );
    return Duration(
      milliseconds: (ms * (0.8 + _random.nextDouble() * 0.2)).round(),
    );
  }

  Future<void> _sleep(Duration d) {
    final c = _wait = Completer<void>();
    final t = Timer(d, () {
      if (!c.isCompleted) c.complete();
    });
    return c.future.whenComplete(t.cancel);
  }

  /// Sends a text or binary message. See the class docs for behaviour while
  /// disconnected.
  void send(Object message) {
    if (message is! String && message is! List<int>) {
      throw ArgumentError.value(
        message,
        'message',
        'must be String or List<int>',
      );
    }
    if (_closed) throw StateError('OmniWebSocket is closed');
    final ch = _channel;
    if (ch != null && _state == WebSocketState.open) {
      ch.sink.add(message);
      return;
    }
    if (!bufferWhileDisconnected) {
      throw StateError(
        'OmniWebSocket is not connected (state: ${_state.name})',
      );
    }
    if (_buffer.length >= maxBuffered) {
      throw StateError('OmniWebSocket buffer is full ($maxBuffered messages)');
    }
    _buffer.add(message);
  }

  /// Sends [value] encoded as JSON text.
  void sendJson(Object? value) => send(jsonEncode(value));

  /// Closes for good with [code]; buffered messages are dropped.
  Future<void> close([int code = 1000, String? reason]) async {
    if (_closed && _state == WebSocketState.closed) return;
    _closed = true;
    final w = _wait;
    if (w != null && !w.isCompleted) w.complete();
    await _channel?.sink.close(code, reason);
    await _states.done.timeout(const Duration(seconds: 5), onTimeout: () {});
  }
}
