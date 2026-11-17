@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:omni_network/advanced.dart';
import 'package:omni_network/testing.dart';
import 'package:test/test.dart';

/// Security, memory and performance hardening.
void main() {
  group('redirects are credential-safe', () {
    late MockTransport mock;
    late OmniNetwork api;

    OmniRawResponse redirect(int code, String to) =>
        OmniRawResponse(statusCode: code, headers: {'location': to});
    OmniRawResponse ok() =>
        OmniRawResponse(statusCode: 200, bodyBytes: utf8.encode('ok'));

    setUp(() {
      api = OmniNetwork(
        baseUrl: 'https://api.test',
        headers: {'Cookie': 'sid=SECRET', 'X-Keep': '1'},
        transport: mock = MockTransport((_) => ok()),
        token: () => 'TOKEN',
      );
    });
    tearDown(() => api.close());

    test('cross-origin redirect drops Authorization and Cookie', () async {
      mock.handler = (r) => r.uri.host == 'api.test'
          ? redirect(302, 'https://cdn.other/f')
          : ok();
      expect(await api.get<String>('/file'), 'ok');
      final hop = mock.requests.last;
      expect(hop.uri.toString(), 'https://cdn.other/f');
      expect(hop.headers.containsKey('authorization'), isFalse);
      expect(hop.headers.containsKey('cookie'), isFalse);
      expect(hop.headers['x-keep'], '1');
    });

    test('same-origin redirect keeps credentials; relative Location', () async {
      mock.handler = (r) => r.uri.path == '/old' ? redirect(301, '/new') : ok();
      await api.get<String>('/old');
      expect(mock.requests.last.uri.toString(), 'https://api.test/new');
      expect(mock.requests.last.headers['authorization'], 'Bearer TOKEN');
    });

    test('HTTPS -> HTTP downgrade is never followed', () async {
      mock.handler = (_) => redirect(302, 'http://api.test/plain');
      final r = await api.sendRaw(const OmniRequest.get('/x'));
      expect(r.statusCode, 302);
      expect(mock.requests, hasLength(1));
    });

    test('303 (and 302 after POST) continue as GET without a body', () async {
      for (final code in [303, 302]) {
        mock.requests.clear();
        mock.handler = (r) =>
            r.method == HttpMethod.post ? redirect(code, '/done') : ok();
        await api.post<String>('/form', body: {'a': 1});
        final hop = mock.requests.last;
        expect(
          (hop.method, hop.body, hop.headers['content-type']),
          (HttpMethod.get, null, null),
        );
      }
    });

    test('307/308 keep method and body', () async {
      mock.handler = (r) => r.uri.path == '/a' ? redirect(307, '/b') : ok();
      await api.post<String>('/a', body: {'x': 1});
      expect(mock.requests.last.method, HttpMethod.post);
      expect(utf8.decode(mock.requests.last.body!), '{"x":1}');
    });

    test('maxRedirects and followRedirects: false', () async {
      mock.handler = (r) => redirect(302, '${r.uri.path}x');
      final r = await api.sendRaw(const OmniRequest.get('/a'));
      expect(r.statusCode, 302);
      expect(mock.requests, hasLength(6)); // first + 5 hops

      final noFollow = OmniNetwork(
        baseUrl: 'https://api.test',
        transport: mock,
        followRedirects: false,
      );
      addTearDown(noFollow.close);
      mock.requests.clear();
      expect(
        (await noFollow.sendRaw(const OmniRequest.get('/a'))).statusCode,
        302,
      );
      expect(mock.requests, hasLength(1));
    });

    test(
      'Dio does not follow by itself; OmniNetwork does (loopback)',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final paths = <String>[];
        server.listen((req) async {
          paths.add(req.uri.path);
          if (req.uri.path == '/start') {
            req.response
              ..statusCode = 302
              ..headers.set('location', '/final');
          } else {
            req.response.write('done');
          }
          await req.response.close();
        });
        final real = OmniNetwork(baseUrl: 'http://127.0.0.1:${server.port}');
        expect(await real.get<String>('/start'), 'done');
        expect(paths, ['/start', '/final']);
        final raw = OmniNetwork(
          baseUrl: 'http://127.0.0.1:${server.port}',
          followRedirects: false,
        );
        expect(
          (await raw.sendRaw(const OmniRequest.get('/start'))).statusCode,
          302,
        );
        await real.close();
        await raw.close();
        await server.close(force: true);
      },
    );
  });

  group('authenticated cache', () {
    test('persistent store without authScope is rejected', () {
      expect(
        () => OmniCache(cacheAuthenticated: true, store: _FakeStore()),
        throwsArgumentError,
      );
      expect(
        () => OmniCache(
          cacheAuthenticated: true,
          store: _FakeStore(),
          authScope: () => 'u',
        ),
        returnsNormally,
      );
    });

    test(
      'memory store partitions by the exact token (no hash collisions)',
      () async {
        // Find two different tokens with the same String.hashCode.
        final seen = <int, String>{};
        late String a, b;
        for (var i = 0; ; i++) {
          final t = 'Bearer t$i';
          final prev = seen[t.hashCode];
          if (prev != null) {
            (a, b) = (prev, t);
            break;
          }
          seen[t.hashCode] = t;
        }
        expect(a.hashCode, b.hashCode);
        final mock = OmniMock()
          ..get(
            '/me',
            (r) => MockResponse.text(
              '${r.headers['authorization']}',
              headers: {'cache-control': 'max-age=60'},
            ),
          );
        final api = OmniNetwork(
          baseUrl: 'https://h.io',
          transport: mock,
          cache: OmniCache(cacheAuthenticated: true),
        );
        addTearDown(api.close);
        expect(await api.get<String>('/me', headers: {'authorization': a}), a);
        expect(
          await api.get<String>('/me', headers: {'authorization': b}),
          b,
        ); // not a's data
        expect(await api.get<String>('/me', headers: {'authorization': a}), a);
        expect(mock.calls, hasLength(2)); // the third came from a's own entry
      },
    );
  });

  group('large bodies', () {
    late OmniMock mock;
    late OmniNetwork api;
    final big = [
      for (var i = 0; i < 20000; i++) {'id': i, 'name': 'item $i'},
    ];
    setUp(() {
      mock = OmniMock()
        ..get('/big', (_) => MockResponse.json(big))
        ..get('/bigtext', (_) => MockResponse.text('x' * (300 * 1024)));
      api = OmniNetwork(baseUrl: 'https://h.io', transport: mock);
    });
    tearDown(() => api.close());

    test(
      'decoded correctly off the main isolate (typed, list, dynamic)',
      () async {
        expect(utf8.encode(jsonEncode(big)).length, greaterThan(256 * 1024));
        final list = await api.getList<int>(
          '/big',
          decoder: (j) => j['id'] as int,
        );
        expect((list.length, list.last), (20000, 19999));
        final raw = await api.get<List<dynamic>>('/big');
        expect(raw.length, 20000);
        final any = await api.get<dynamic>('/big');
        expect((any as List).first, {'id': 0, 'name': 'item 0'});
      },
    );

    test(
      'large non-JSON: text for String/dynamic, DecodeFailure for Map',
      () async {
        expect((await api.get<String>('/bigtext')).length, 300 * 1024);
        expect(
          (await api.get<dynamic>('/bigtext') as String).length,
          300 * 1024,
        );
        await expectLater(
          api.get<Map<String, dynamic>>('/bigtext'),
          throwsA(isA<DecodeFailure>()),
        );
      },
    );

    test('huge bodies are logged whole (redacted)', () async {
      final out = <String>[];
      final logged = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        enableLogging: true,
        logSink: PrettyLogSink(
          options: const LogOptions(colors: false),
          printer: out.add,
        ),
      );
      addTearDown(logged.close);
      await logged.get<void>('/big');
      expect(out.single, isNot(contains('too large to show')));
      expect(out.single, contains('"name": "item 0"'));
      expect(out.single, contains('"name": "item 19999"'));
    });
  });

  test('friendly HTTP messages', () {
    expect(
      HttpFailure(OmniRawResponse(statusCode: 404)).message,
      'HTTP 404 Not Found',
    );
    expect(HttpFailure(OmniRawResponse(statusCode: 599)).message, 'HTTP 599');
  });

  group('no leaks', () {
    test(
      'child tokens: parent cancels them, cancelled children are pruned',
      () {
        final parent = OmniCancelToken();
        final kids = [for (var i = 0; i < 100; i++) parent.child()];
        for (final k in kids.take(60)) {
          k.cancel();
        }
        parent.child(); // prunes cancelled children
        expect(parent.debugChildren, 41);
        parent.cancel();
        expect(kids.every((k) => k.isCancelled), isTrue);
        expect(parent.debugChildren, 0);
      },
    );

    test('pretty log buffer is bounded', () {
      final sink = PrettyLogSink(printer: (_) {});
      for (var i = 0; i < 1000; i++) {
        sink.log(
          NetworkLogRecord(
            kind: NetworkLogKind.request,
            requestId: i,
            method: 'GET',
            url: 'u',
            message: '',
          ),
        );
      }
      expect(sink.debugOpenRequests, 256);
    });

    test('2000 mixed calls leave no pending work behind', () async {
      final sink = PrettyLogSink(printer: (_) {});
      final mock = OmniMock()
        ..get('/ok/{n}', (_) => MockResponse.json(1))
        ..get('/missing/{n}', (_) => const MockResponse.status(404))
        ..get('/down/{n}', (_) => const MockResponse.offline())
        ..get('/hang/{n}', (_) => const MockResponse.hang());
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        timeout: const Duration(milliseconds: 50),
        enableLogging: true,
        logSink: sink,
        cache: OmniCache(),
        retry: const RetryPolicy(
          maxAttempts: 2,
          baseDelay: Duration(milliseconds: 1),
        ),
      );
      final token = OmniCancelToken();
      for (var batch = 0; batch < 10; batch++) {
        final calls = <Future<Object?>>[
          for (var i = 0; i < 200; i++)
            switch (i % 5) {
              0 => api.get<int>('/ok/$i'),
              1 => api.get<void>('/missing/$i'),
              2 => api.get<void>('/down/$i'),
              3 => api.get<void>('/hang/$i'),
              _ => api.get<void>('/hang/c$i', cancelToken: token.child()),
            }.asResult(),
        ];
        await Future<void>.delayed(const Duration(milliseconds: 5));
        api.cancelAll();
        await Future.wait(calls);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(api.pendingRequests, 0);
      expect(mock.calls, isNotEmpty);
      expect(sink.debugOpenRequests, 0);
      expect(token.attachedRequests, 0);
      token.cancel();
      expect(token.debugChildren, 0);
      await api.close();
    });
  });
}

final class _FakeStore implements CacheStore {
  @override
  CacheEntry? get(String key) => null;
  @override
  void set(String key, CacheEntry entry) {}
  @override
  void remove(String key) {}
  @override
  void removeUrl(String url) {}
  @override
  void clear() {}
}
