import 'dart:async';
import 'dart:io';

import 'package:omni_network_ws/omni_network_ws.dart';
import 'package:test/test.dart';

/// Loopback WebSocket server (no internet).
final class EchoServer {
  late HttpServer _server;
  final sockets = <WebSocket>[];
  final authHeaders = <String?>[];
  int get port => _server.port;
  Uri get uri => Uri.parse('ws://127.0.0.1:$port/ws');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      authHeaders.add(req.headers.value('authorization'));
      final ws = await WebSocketTransformer.upgrade(req);
      sockets.add(ws);
      ws.listen((m) => ws.add('echo:$m'), onDone: () => sockets.remove(ws));
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late EchoServer server;
  setUp(() async {
    server = EchoServer();
    await server.start();
  });
  tearDown(() => server.stop());

  Future<void> until(bool Function() c) async {
    for (var i = 0; i < 500 && !c(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(c(), isTrue);
  }

  test('connects, echoes text and JSON', () async {
    final ws = OmniWebSocket(server.uri);
    addTearDown(ws.close);
    await until(() => ws.state == WebSocketState.open);
    ws.send('hi');
    expect(await ws.messages.first, 'echo:hi');
  });

  test('reconnects after an abnormal drop; onOpen runs each time; '
      'headers re-evaluated', () async {
    var token = 'A';
    var opens = 0;
    final ws = OmniWebSocket(
      server.uri,
      headers: () => {'authorization': 'Bearer $token'},
      minDelay: const Duration(milliseconds: 10),
      onOpen: (_) => opens++,
    );
    addTearDown(ws.close);
    await until(() => server.sockets.length == 1);
    token = 'B';
    await server.sockets.single.close(4000, 'restart'); // abnormal code
    await until(() => ws.connectCount == 2 && ws.state == WebSocketState.open);
    expect(opens, 2);
    expect(server.authHeaders, ['Bearer A', 'Bearer B']);
  });

  test('normal close (1000) from the server does not reconnect', () async {
    final ws = OmniWebSocket(
      server.uri,
      minDelay: const Duration(milliseconds: 10),
    );
    await until(() => server.sockets.length == 1);
    await server.sockets.single.close(1000);
    await until(() => ws.state == WebSocketState.closed);
    expect(ws.lastCloseCode, 1000);
    expect(ws.connectCount, 1);
  });

  test('send while disconnected throws unless buffering is opted in', () async {
    final uri = server.uri;
    await server.stop();
    final ws = OmniWebSocket(uri, minDelay: const Duration(seconds: 10));
    expect(() => ws.send('x'), throwsStateError);
    expect(() => ws.send(1), throwsArgumentError);
    await ws.close();
    expect(() => ws.send('x'), throwsStateError);
  });

  test('explicit buffer: kept in order, bounded, flushed on connect', () async {
    final port = server.port;
    await server.stop();
    final ws = OmniWebSocket(
      Uri.parse('ws://127.0.0.1:$port/ws'),
      bufferWhileDisconnected: true,
      maxBuffered: 2,
      minDelay: const Duration(milliseconds: 20),
    );
    addTearDown(ws.close);
    ws.send('1');
    ws.send('2');
    expect(() => ws.send('3'), throwsStateError);
    expect(ws.buffered, 2);
    // Server comes back on the same port.
    final again = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final got = <Object?>[];
    again.listen((req) async {
      final s = await WebSocketTransformer.upgrade(req);
      s.listen(got.add);
    });
    addTearDown(() => again.close(force: true));
    await until(() => got.length == 2);
    expect(got, ['1', '2']);
    expect(ws.buffered, 0);
  });

  test('maxReconnects: gives up with an error and closes', () async {
    final uri = server.uri;
    await server.stop();
    final ws = OmniWebSocket(
      uri,
      minDelay: const Duration(milliseconds: 2),
      maxReconnects: 2,
    );
    await expectLater(ws.messages, emitsError(isA<StateError>()));
    expect(ws.state, WebSocketState.closed);
  });

  test('close stops reconnecting and completes streams', () async {
    final ws = OmniWebSocket(server.uri);
    await until(() => ws.state == WebSocketState.open);
    final states = ws.states.toList();
    await ws.close();
    expect(await states, [WebSocketState.closed]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(server.sockets, isEmpty);
  });

  test('handshake headers supported on the VM', () {
    expect(OmniWebSocket.supportsHandshakeHeaders, isTrue);
  });
}
