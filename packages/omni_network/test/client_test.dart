import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:omni_network/omni_network.dart';
import 'package:test/test.dart';

OmniRawResponse ok([String body = '']) =>
    OmniRawResponse(statusCode: 200, bodyBytes: utf8.encode(body));

void main() {
  late MockTransport mock;
  late OmniNetwork api;

  setUp(() {
    mock = MockTransport((_) => ok());
    api = OmniNetwork(
      baseUrl: 'https://api.example.com/v1',
      headers: {'Accept': 'application/json', 'X-App': 'a'},
      transport: mock,
    );
  });
  tearDown(() => api.close());

  group('URL resolution', () {
    test('joins base path with leading-slash and bare paths', () async {
      await api.sendRaw(const OmniRequest.get('/users/10'));
      await api.sendRaw(const OmniRequest.get('users/11'));
      expect(mock.requests.map((r) => '${r.uri}'), [
        'https://api.example.com/v1/users/10',
        'https://api.example.com/v1/users/11',
      ]);
    });

    test('base URL with trailing slash behaves the same', () {
      final a = OmniNetwork(
        baseUrl: 'https://h.io/v1/',
        transport: MockTransport((_) => ok()),
      );
      expect(
        a.resolve(const OmniRequest.get('/x')).uri.toString(),
        'https://h.io/v1/x',
      );
    });

    test('absolute URL bypasses base', () {
      expect(
        api.resolve(const OmniRequest.get('http://other.io/a')).uri,
        Uri.parse('http://other.io/a'),
      );
    });

    test(
      'query: nulls dropped, iterables repeated, merged with path query',
      () {
        final uri = api
            .resolve(
              const OmniRequest.get(
                '/s?a=1',
                query: {
                  'q': 'hello world',
                  'id': [1, 2],
                  'skip': null,
                  'flag': true,
                },
              ),
            )
            .uri;
        expect(uri.queryParametersAll, {
          'a': ['1'],
          'q': ['hello world'],
          'id': ['1', '2'],
          'flag': ['true'],
        });
      },
    );

    test('relative path without baseUrl is a RequestFailure', () {
      final a = OmniNetwork(transport: mock);
      expect(
        () => a.sendRaw(const OmniRequest.get('/x')),
        throwsA(isA<RequestFailure>()),
      );
    });

    test('non-http scheme rejected', () {
      expect(
        () => api.resolve(const OmniRequest.get('file:///etc/passwd')),
        throwsA(isA<RequestFailure>()),
      );
    });

    test('invalid baseUrl rejected at construction', () {
      expect(
        () => OmniNetwork(baseUrl: 'api.example.com'),
        throwsArgumentError,
      );
      expect(
        () => OmniNetwork(baseUrl: 'https://h.io?k=1'),
        throwsArgumentError,
      );
    });
  });

  group('methods, headers, bodies', () {
    test('every method is sent with its verb', () async {
      for (final r in [
        const OmniRequest.get('/a'),
        const OmniRequest.post('/a'),
        const OmniRequest.put('/a'),
        const OmniRequest.patch('/a'),
        const OmniRequest.delete('/a'),
        const OmniRequest.head('/a'),
      ]) {
        await api.sendRaw(r);
      }
      expect(mock.requests.map((r) => r.method.verb), [
        'GET',
        'POST',
        'PUT',
        'PATCH',
        'DELETE',
        'HEAD',
      ]);
    });

    test('request headers override defaults case-insensitively', () async {
      await api.sendRaw(const OmniRequest.get('/a', headers: {'x-APP': 'b'}));
      expect(mock.requests.single.headers, {
        'accept': 'application/json',
        'x-app': 'b',
      });
    });

    test('JSON body encoded with content type', () async {
      await api.sendRaw(const OmniRequest.post('/u', body: {'name': 'Ana'}));
      final r = mock.requests.single;
      expect(utf8.decode(r.body!), '{"name":"Ana"}');
      expect(r.headers['content-type'], 'application/json; charset=utf-8');
    });

    test('string and byte bodies; explicit content type kept', () async {
      await api.sendRaw(const OmniRequest.post('/t', body: 'hi'));
      await api.sendRaw(
        OmniRequest.put(
          '/b',
          body: Uint8List.fromList([1, 2, 3]),
          headers: {'Content-Type': 'image/png'},
        ),
      );
      expect(
        mock.requests[0].headers['content-type'],
        'text/plain; charset=utf-8',
      );
      expect(mock.requests[1].body, [1, 2, 3]);
      expect(mock.requests[1].headers['content-type'], 'image/png');
    });

    test('GET with body and unsupported body types rejected', () {
      expect(
        () => api.sendRaw(OmniRequest(HttpMethod.get, '/a', body: 'x')),
        throwsA(isA<RequestFailure>()),
      );
      expect(
        () => api.sendRaw(OmniRequest.post('/a', body: Object())),
        throwsA(isA<RequestFailure>()),
      );
      expect(
        () => api.sendRaw(OmniRequest.post('/a', body: [Object()])),
        throwsA(isA<RequestFailure>()),
      );
      expect(mock.requests, isEmpty);
    });
  });

  group('responses', () {
    test('non-2xx statuses are returned, not thrown', () async {
      mock.handler = (_) => OmniRawResponse(
        statusCode: 404,
        headers: {'Content-Type': 'application/json'},
        bodyBytes: utf8.encode('{"error":"nope"}'),
      );
      final res = await api.sendRaw(const OmniRequest.get('/missing'));
      expect(res.statusCode, 404);
      expect(res.isSuccess, isFalse);
      expect(res.headers['content-type'], 'application/json');
      expect(res.json, {'error': 'nope'});
    });

    test('duration measured; empty body json is null', () async {
      mock.handler = (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return ok();
      };
      final res = await api.sendRaw(const OmniRequest.get('/a'));
      expect(
        res.duration,
        greaterThanOrEqualTo(const Duration(milliseconds: 15)),
      );
      expect(res.json, isNull);
    });
  });

  group('errors', () {
    test('timeout from client default and per-request override', () async {
      mock.handler = (_) => Completer<OmniRawResponse>().future; // never
      final fast = OmniNetwork(
        baseUrl: 'https://h.io',
        timeout: const Duration(milliseconds: 30),
        transport: mock,
      );
      await expectLater(
        fast.sendRaw(const OmniRequest.get('/a')),
        throwsA(isA<TimeoutFailure>()),
      );
      await expectLater(
        api.sendRaw(
          const OmniRequest.get('/a', timeout: Duration(milliseconds: 30)),
        ),
        throwsA(
          isA<TimeoutFailure>().having(
            (e) => e.timeout,
            'timeout',
            const Duration(milliseconds: 30),
          ),
        ),
      );
      expect(fast.pendingRequests, 0);
      expect(api.pendingRequests, 0);
      expect(mock.inFlight, 0);
    });

    test('transport exceptions become ConnectionFailure', () async {
      mock.handler = (_) => throw const FormatException('boom');
      await expectLater(
        api.sendRaw(const OmniRequest.get('/a')),
        throwsA(isA<ConnectionFailure>()),
      );
    });

    test('error messages never contain query secrets or user info', () async {
      mock.handler = (_) => throw const ConnectionFailure('x');
      final a = OmniNetwork(
        baseUrl: 'https://user:pw@h.io',
        timeout: const Duration(milliseconds: 20),
        transport: MockTransport((_) => Completer<OmniRawResponse>().future),
      );
      try {
        await a.sendRaw(
          const OmniRequest.get('/a', query: {'token': 'S3CRET'}),
        );
        fail('should time out');
      } on TimeoutFailure catch (e) {
        expect('$e', isNot(contains('S3CRET')));
        expect('$e', isNot(contains('pw')));
        expect(e.uri.toString(), 'https://h.io/a');
      }
    });
  });

  group('close / disposal', () {
    test('close fails in-flight requests and rejects new ones', () async {
      mock.handler = (_) => Completer<OmniRawResponse>().future;
      final f = api.sendRaw(const OmniRequest.get('/slow'));
      await Future<void>.delayed(Duration.zero);
      expect(api.pendingRequests, 1);
      await api.close();
      await expectLater(f, throwsA(isA<ClosedFailure>()));
      expect(api.pendingRequests, 0);
      expect(mock.inFlight, 0);
      await expectLater(
        api.sendRaw(const OmniRequest.get('/a')),
        throwsA(isA<ClosedFailure>()),
      );
    });

    test(
      'close is idempotent; user-provided transport is not closed',
      () async {
        await api.close();
        await api.close();
        expect(api.isClosed, isTrue);
        expect(mock.isClosed, isFalse);
      },
    );

    test('timers are released: no pending work after many requests', () async {
      for (var i = 0; i < 200; i++) {
        await api.sendRaw(const OmniRequest.get('/a'));
      }
      expect(api.pendingRequests, 0);
      expect(mock.inFlight, 0);
    });
  });
}
