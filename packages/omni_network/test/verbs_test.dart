import 'dart:async';

import 'package:omni_network/omni_network.dart';
import 'package:omni_network/advanced.dart' show BearerAuth;
import 'package:omni_network/testing.dart';
import 'package:test/test.dart';

/// The verbs with every per-call option, using only the simple import.
void main() {
  late OmniMock mock;
  late OmniNetwork api;

  setUp(() {
    mock = OmniMock()
      ..on(
        null,
        '/echo',
        (r) => MockResponse.json({
          'method': r.method.verb,
          'query': r.query,
          'auth': r.headers['authorization'],
          'x': r.headers['x-trace'],
          'body': r.json,
        }, status: r.method == HttpMethod.post ? 201 : 200),
      );
    api = OmniNetwork(baseUrl: 'https://h.io', transport: mock);
  });
  tearDown(() => api.close());

  test('every verb passes query, headers and body', () async {
    final results = [
      await api.get<Map<String, dynamic>>(
        '/echo',
        query: {'q': 1},
        headers: {'X-Trace': 't'},
      ),
      await api.post<Map<String, dynamic>>(
        '/echo',
        body: {'a': 1},
        query: {'q': 1},
        headers: {'X-Trace': 't'},
      ),
      await api.put<Map<String, dynamic>>(
        '/echo',
        body: {'a': 1},
        query: {'q': 1},
        headers: {'X-Trace': 't'},
      ),
      await api.patch<Map<String, dynamic>>(
        '/echo',
        body: {'a': 1},
        query: {'q': 1},
        headers: {'X-Trace': 't'},
      ),
      await api.delete<Map<String, dynamic>>(
        '/echo',
        body: {'a': 1},
        query: {'q': 1},
        headers: {'X-Trace': 't'},
      ),
    ];
    expect(results.map((r) => r['method']), [
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE',
    ]);
    for (final r in results) {
      expect(r['query'], {'q': '1'});
      expect(r['x'], 't');
    }
    expect(results.skip(1).map((r) => r['body']), everyElement({'a': 1}));
  });

  test('xxxResponse variants return status and headers', () async {
    final g = await api.getResponse<Map<String, dynamic>>('/echo');
    final p = await api.postResponse<Map<String, dynamic>>('/echo', body: {});
    final u = await api.putResponse<Map<String, dynamic>>('/echo');
    final pa = await api.patchResponse<Map<String, dynamic>>('/echo');
    final d = await api.deleteResponse<Map<String, dynamic>>('/echo');
    expect([g, p, u, pa, d].map((r) => r.statusCode), [
      200,
      201,
      200,
      200,
      200,
    ]);
    expect(g.headers['content-type'], 'application/json');
    expect(g.source, ResponseSource.network);
  });

  test('timeout and cancelToken per call', () async {
    mock
      ..get('/slow', (_) => const MockResponse.hang())
      ..post('/slow', (_) => const MockResponse.hang());
    await expectLater(
      api.get<void>('/slow', timeout: const Duration(milliseconds: 20)),
      throwsA(isA<TimeoutFailure>()),
    );
    final token = OmniCancelToken();
    final f = api.post<void>('/slow', cancelToken: token);
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    await expectLater(f, throwsA(isA<CancelledFailure>()));
  });

  group('auth: false', () {
    test('sends no token and never refreshes', () async {
      var refreshes = 0;
      final authed = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        auth: BearerAuth(
          token: () => 'T',
          refresh: () {
            refreshes++;
            return null;
          },
        ),
      );
      addTearDown(authed.close);
      mock.post(
        '/login',
        (r) => r.headers['authorization'] == null
            ? MockResponse.json({'ok': true})
            : const MockResponse.status(400),
      );
      expect(await authed.post<Map<String, dynamic>>('/login', auth: false), {
        'ok': true,
      });
      expect(
        (await authed.get<Map<String, dynamic>>('/echo'))['auth'],
        'Bearer T',
      );
      mock.get('/public', (_) => const MockResponse.status(401));
      await expectLater(
        authed.get<void>('/public', auth: false),
        throwsA(isA<HttpFailure>()),
      );
      expect(refreshes, 0);
    });
  });

  group('retry per call', () {
    test(
      'turns retry on for one call, or off against the client default',
      () async {
        var n = 0;
        mock.get(
          '/flaky',
          (_) => ++n % 2 == 1
              ? const MockResponse.status(503)
              : MockResponse.json({'ok': true}),
        );
        const fast = RetryPolicy(
          baseDelay: Duration(milliseconds: 1),
          jitter: false,
        );
        expect(await api.get<Map<String, dynamic>>('/flaky', retry: fast), {
          'ok': true,
        });
        expect(n, 2);

        final retrying = OmniNetwork(
          baseUrl: 'https://h.io',
          transport: mock,
          retry: fast,
        );
        addTearDown(retrying.close);
        await expectLater(
          retrying.get<void>('/flaky', retry: RetryPolicy.none),
          throwsA(isA<HttpFailure>()),
        );
        expect(n, 3);
      },
    );
  });

  test('cache policy per GET', () async {
    var hits = 0;
    mock.get('/feed', (_) {
      hits++;
      return MockResponse.json(
        [hits],
        headers: {'cache-control': 'max-age=60'},
      );
    });
    final cached = OmniNetwork(
      baseUrl: 'https://h.io',
      transport: mock,
      cache: OmniCache(),
    );
    addTearDown(cached.close);
    expect(await cached.get<List<dynamic>>('/feed'), [1]);
    expect(await cached.get<List<dynamic>>('/feed'), [1]); // from cache
    expect(
      await cached.get<List<dynamic>>('/feed', cache: CachePolicy.noCache),
      [2],
    );
    final r = await cached.getResponse<List<dynamic>>(
      '/feed',
      cache: CachePolicy.cacheFirst,
    );
    expect(r.source, ResponseSource.cache);
  });

  test('getList and head take the same options', () async {
    mock
      ..get(
        '/items',
        (r) => MockResponse.json([
          {'id': int.parse(r.query['n']!)},
        ]),
      )
      ..on(
        HttpMethod.head,
        '/file',
        (_) => const MockResponse.status(200, headers: {'etag': '"1"'}),
      );
    final items = await api.getList<int>(
      '/items',
      decoder: (j) => j['id'] as int,
      query: {'n': 7},
      retry: RetryPolicy.none,
    );
    expect(items, [7]);
    expect((await api.head('/file', auth: false)).headers['etag'], '"1"');
  });
}
