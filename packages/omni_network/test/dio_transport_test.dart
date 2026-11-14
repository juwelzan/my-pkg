@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:omni_network/omni_network.dart';
import 'package:test/test.dart';

/// Real DioTransport against a loopback server: no internet involved.
void main() {
  late HttpServer server;
  late OmniNetwork api;
  final hang = <HttpRequest>[];

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      if (req.uri.path.endsWith('/hang')) {
        hang.add(req);
        return;
      }
      req.response
        ..statusCode = req.uri.path.endsWith('/missing') ? 404 : 200
        ..headers.contentType = ContentType.json
        ..headers.add('X-Multi', 'a')
        ..headers.add('X-Multi', 'b')
        ..write(
          jsonEncode({
            'method': req.method,
            'path': req.uri.path,
            'query': req.uri.queryParametersAll,
            'auth': req.headers.value('x-test'),
            'ctype': req.headers.contentType?.mimeType,
            'body': body,
          }),
        );
      await req.response.close();
    });
    api = OmniNetwork(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      headers: {'X-Test': 'yes'},
    );
  });

  tearDown(() async {
    await api.close();
    for (final r in hang) {
      await r.response.close().catchError((_) {});
    }
    hang.clear();
    await server.close(force: true);
  });

  test('round-trips method, path, query, headers and JSON body', () async {
    final res = await api.sendRaw(
      OmniRequest.post(
        '/users',
        query: {
          'id': [1, 2],
        },
        body: {'name': 'Ana'},
      ),
    );
    expect(res.statusCode, 200);
    expect(res.headers['content-type'], startsWith('application/json'));
    expect(res.headers['x-multi'], 'a, b');
    expect(res.json, {
      'method': 'POST',
      'path': '/v1/users',
      'query': {
        'id': ['1', '2'],
      },
      'auth': 'yes',
      'ctype': 'application/json',
      'body': '{"name":"Ana"}',
    });
  });

  test('404 is returned as a response', () async {
    final res = await api.sendRaw(const OmniRequest.get('/missing'));
    expect(res.statusCode, 404);
  });

  test('HEAD has no body', () async {
    final res = await api.sendRaw(const OmniRequest.head('/x'));
    expect(res.statusCode, 200);
    expect(res.bodyBytes, isEmpty);
  });

  test('timeout aborts a hanging request', () async {
    await expectLater(
      api.sendRaw(
        const OmniRequest.get('/hang', timeout: Duration(milliseconds: 100)),
      ),
      throwsA(isA<TimeoutFailure>()),
    );
    expect(api.pendingRequests, 0);
  });

  test('close aborts in-flight request with ClosedFailure', () async {
    final f = api.sendRaw(const OmniRequest.get('/hang'));
    while (hang.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await api.close();
    await expectLater(f, throwsA(isA<ClosedFailure>()));
  });

  test('unreachable host is a ConnectionFailure', () async {
    final port = server.port;
    await server.close(force: true);
    final dead = OmniNetwork(baseUrl: 'http://127.0.0.1:$port');
    addTearDown(dead.close);
    await expectLater(
      dead.sendRaw(const OmniRequest.get('/a')),
      throwsA(isA<ConnectionFailure>()),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
}
