import 'dart:math';

import 'package:omni_network/omni_network.dart';
import 'package:test/test.dart';

final class User {
  User(this.id);
  factory User.fromJson(Map<String, dynamic> j) => User(j['id'] as int);
  final int id;
}

void main() {
  late OmniMock mock;
  late OmniNetwork api;

  setUp(() {
    mock = OmniMock(basePath: '/v1');
    api = OmniNetwork(baseUrl: 'https://api.test/v1', transport: mock);
  });
  tearDown(() => api.close());

  test('routes with path params, query, body and typed decoding', () async {
    mock
      ..get(
        '/users/{id}',
        (r) => MockResponse.json({
          'id': int.parse(r.pathParams['id']!),
          'q': r.query['expand'],
        }),
      )
      ..post('/users', (r) => MockResponse.json(r.json, status: 201));
    final u = await api.get<User>(
      '/users/7',
      decoder: User.fromJson,
      query: {'expand': 'x'},
    );
    expect(u.id, 7);
    final created = await api.send<Map<String, dynamic>>(
      const OmniRequest.post('/users', body: {'id': 9}),
    );
    expect((created.statusCode, created.data['id']), (201, 9));
    expect(mock.callsTo(HttpMethod.get, '/users/{id}').single.query, {
      'expand': 'x',
    });
    expect(mock.calls, hasLength(2));
  });

  test('later routes override earlier ones; params are decoded', () async {
    mock
      ..get('/f/{name}', (_) => MockResponse.text('old'))
      ..get(
        '/f/{name}',
        (r) => MockResponse.text('new ${r.pathParams['name']}'),
      );
    expect(await api.get<String>('/f/a%20b'), 'new a b');
  });

  test('strict: unmatched request fails loudly and is recorded', () async {
    await expectLater(
      api.get<dynamic>('/nope'),
      throwsA(
        isA<RequestFailure>().having(
          (e) => e.message,
          'message',
          contains('GET /nope'),
        ),
      ),
    );
    expect(mock.unmatched.single.path, '/nope');

    final lax = OmniMock(strict: false);
    final api2 = OmniNetwork(baseUrl: 'https://h.io', transport: lax);
    addTearDown(api2.close);
    expect((await api2.sendRaw(const OmniRequest.get('/x'))).statusCode, 404);
  });

  test('endpoint routes', () async {
    final byId = Endpoint.get<User>('/users/{id}', decoder: User.fromJson);
    mock.endpoint(
      byId,
      (r) => MockResponse.json({'id': int.parse(r.pathParams['id']!)}),
    );
    expect((await api.call(byId, path: {'id': 3})).id, 3);
  });

  test('scenarios switch behaviour', () async {
    mock
      ..get('/feed', (_) => MockResponse.json([1, 2]))
      ..scenario('offline', (s) => s.any((_) => const MockResponse.offline()))
      ..scenario('empty', (s) => s.get('/feed', (_) => MockResponse.json([])));
    expect(await api.get<List<dynamic>>('/feed'), [1, 2]);
    mock.use('offline');
    await expectLater(
      api.get<dynamic>('/feed'),
      throwsA(isA<ConnectionFailure>()),
    );
    mock.use('empty');
    expect(await api.get<List<dynamic>>('/feed'), isEmpty);
    mock.use(null);
    expect(await api.get<List<dynamic>>('/feed'), [1, 2]);
    expect(() => mock.use('nope'), throwsArgumentError);
  });

  test('sequence: offline, 503, then success (works with retry)', () async {
    mock.get(
      '/data',
      OmniMock.sequence([
        const MockResponse.offline(),
        const MockResponse.status(503),
        MockResponse.json({'ok': true}),
      ]),
    );
    final retrying = OmniNetwork(
      baseUrl: 'https://api.test/v1',
      transport: mock,
      retry: const RetryPolicy(
        baseDelay: Duration(milliseconds: 1),
        jitter: false,
      ),
    );
    addTearDown(retrying.close);
    expect(await retrying.get<dynamic>('/data'), {'ok': true});
    expect(mock.calls, hasLength(3));
    // Last response repeats.
    expect(await retrying.get<dynamic>('/data'), {'ok': true});
  });

  test('failNext injects failures', () async {
    mock.get('/a', (_) => const MockResponse.status(204));
    mock.failNext(2);
    for (var i = 0; i < 2; i++) {
      await expectLater(
        api.sendRaw(const OmniRequest.get('/a')),
        throwsA(isA<ConnectionFailure>()),
      );
    }
    expect((await api.sendRaw(const OmniRequest.get('/a'))).statusCode, 204);
    mock.failNext(1, TimeoutFailure(const Duration(seconds: 1)));
    await expectLater(
      api.sendRaw(const OmniRequest.get('/a')),
      throwsA(isA<TimeoutFailure>()),
    );
  });

  test('failureRate with seeded random is deterministic', () async {
    Future<int> failures(int seed) async {
      final m = OmniMock(failureRate: 0.5, random: Random(seed))
        ..get('/a', (_) => const MockResponse.status(200));
      final c = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: m,
        deduplicate: false,
      );
      var n = 0;
      for (var i = 0; i < 40; i++) {
        final r = await c.sendRaw(const OmniRequest.get('/a')).asResult();
        if (!r.isOk) n++;
      }
      await c.close();
      return n;
    }

    final a = await failures(3);
    expect(a, await failures(3));
    expect(a, inInclusiveRange(5, 35));
  });

  test(
    'latency and per-response delay; hang hits the client timeout',
    () async {
      mock
        ..latency = const Duration(milliseconds: 30)
        ..get(
          '/slow',
          (_) => MockResponse.json(1, delay: const Duration(milliseconds: 30)),
        )
        ..get('/hang', (_) => const MockResponse.hang());
      final watch = Stopwatch()..start();
      await api.get<int>('/slow');
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(55));
      await expectLater(
        api.sendRaw(
          const OmniRequest.get('/hang', timeout: Duration(milliseconds: 80)),
        ),
        throwsA(isA<TimeoutFailure>()),
      );
      expect(api.pendingRequests, 0);
    },
  );

  test('downloads and uploads go through the mock too', () async {
    mock
      ..get('/file', (_) => MockResponse.bytes(List.filled(40000, 7)))
      ..post('/upload', (r) => MockResponse.json({'len': r.raw.body!.length}));
    final progress = <int>[];
    final bytes = await api.downloadBytes(
      '/file',
      onProgress: (n, _) => progress.add(n),
    );
    expect(bytes.length, 40000);
    expect(progress.length, greaterThan(1));
    final res = await api.upload<Map<String, dynamic>>(
      '/upload',
      files: [UploadFile.fromBytes('f', List.filled(10, 1), filename: 'a')],
    );
    expect(res['len'], greaterThan(10));
  });

  test('resetCalls', () async {
    mock.get('/a', (_) => const MockResponse.status(200));
    mock.failNext(5);
    await api.sendRaw(const OmniRequest.get('/a')).asResult();
    mock.resetCalls();
    expect(mock.calls, isEmpty);
    expect((await api.sendRaw(const OmniRequest.get('/a'))).statusCode, 200);
  });
}
