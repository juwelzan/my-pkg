import 'dart:async';

import 'package:omni_network/advanced.dart';
import 'package:omni_network/testing.dart';
import 'package:test/test.dart';

String plain(String s) => s.replaceAll(RegExp('\x1B\\[[0-9;]*m'), '');
String stable(String s) => plain(s).replaceAll(RegExp(r'\d+ ms'), 'N ms');

void main() {
  late OmniMock mock;
  late List<String> out;

  OmniNetwork client({
    LogOptions options = const LogOptions(colors: false),
    bool enable = true,
  }) => OmniNetwork(
    baseUrl: 'https://api.test/v1',
    headers: {
      'Authorization': 'Bearer HEADER-SECRET',
      'Accept': 'application/json',
    },
    transport: mock,
    enableLogging: enable,
    logSink: PrettyLogSink(options: options, printer: out.add),
  );

  setUp(() {
    out = [];
    mock = OmniMock(basePath: '/v1')
      ..get(
        '/users/{id}',
        (_) => MockResponse.json({
          'id': 10,
          'name': 'Ana',
          'access_token': 'BODY-SECRET',
        }),
      )
      ..post('/orders', (_) => MockResponse.json({'error': 'qty'}, status: 422))
      ..get('/down', (_) => const MockResponse.offline())
      ..get('/big', (_) => MockResponse.json([for (var i = 0; i < 50; i++) i]))
      ..get('/bin', (_) => MockResponse.bytes([1, 2, 3]));
  });

  test('GET 200: exact block', () async {
    final api = client();
    addTearDown(api.close);
    await api.get<void>('/users/10');
    expect(stable(out.single), '''
┌────────────────────────────────────────────────────────────
│ GET  https://api.test/v1/users/10
├────────────────────────────────────────────────────────────
│ ✔ 200 OK · N ms · 51 B
│ {
│   "id": 10,
│   "name": "Ana",
│   "access_token": "***"
│ }
└────────────────────────────────────────────────────────────
''');
  });

  test('POST 422 with request body, and a connection failure', () async {
    final api = client();
    addTearDown(api.close);
    await api
        .post<void>('/orders', body: {'item': 7, 'password': 'PW-SECRET'})
        .asResult();
    await api.get<void>('/down').asResult();
    expect(stable(out[0]), '''
┌────────────────────────────────────────────────────────────
│ POST https://api.test/v1/orders
│ ⇢ body  {"item":7,"password":"***"}
├────────────────────────────────────────────────────────────
│ ✖ 422 Unprocessable Entity · N ms · 15 B
│ {
│   "error": "qty"
│ }
└────────────────────────────────────────────────────────────
''');
    expect(stable(out[1]), '''
┌────────────────────────────────────────────────────────────
│ GET  https://api.test/v1/down
├────────────────────────────────────────────────────────────
│ ✖ ConnectionFailure: Mock: offline · N ms
└────────────────────────────────────────────────────────────
''');
  });

  test(
    'colours: green 2xx, yellow 4xx, red failures; plain text identical',
    () async {
      final api = client(options: const LogOptions(colors: true));
      addTearDown(api.close);
      await api.get<void>('/users/1');
      await api.post<void>('/orders').asResult();
      await api.get<void>('/down').asResult();
      expect(out[0], contains('\x1B[32m✔ 200 OK'));
      expect(out[1], contains('\x1B[33m✖ 422'));
      expect(out[2], contains('\x1B[31m✖ ConnectionFailure'));
      final noColor = <String>[];
      final api2 = OmniNetwork(
        baseUrl: 'https://api.test/v1',
        transport: mock,
        enableLogging: true,
        logSink: PrettyLogSink(
          options: const LogOptions(colors: false),
          printer: noColor.add,
        ),
      );
      addTearDown(api2.close);
      await api2.get<void>('/users/1');
      expect(stable(out[0]), stable(noColor[0]));
    },
  );

  test('secrets never printed, even with headers on', () async {
    final api = client(options: const LogOptions(colors: false, headers: true));
    addTearDown(api.close);
    await api.get<void>('/users/1', query: {'api_key': 'QUERY-SECRET'});
    await api.post<void>('/orders', body: {'password': 'PW-SECRET'}).asResult();
    final all = out.join();
    for (final s in [
      'HEADER-SECRET',
      'BODY-SECRET',
      'QUERY-SECRET',
      'PW-SECRET',
    ]) {
      expect(all, isNot(contains(s)));
    }
    expect(
      all,
      contains('⇢ headers  authorization: ***  accept: application/json'),
    );
    expect(all, contains('⇠ headers  content-type: application/json'));
    expect(all, contains('api_key=***'));
  });

  test(
    'long bodies cut after maxLines; binary bodies summarised; options',
    () async {
      final api = client(
        options: const LogOptions(
          colors: false,
          maxLines: 5,
          requestBody: false,
        ),
      );
      addTearDown(api.close);
      await api.get<void>('/big');
      await api.get<void>('/bin');
      await api.post<void>('/orders', body: {'x': 1}).asResult();
      final big = plain(out[0]).split('\n');
      expect(
        big.where((l) => l.startsWith('│   ')),
        hasLength(4),
      ); // 5 lines incl. "["
      expect(out[0], contains('… 47 more lines'));
      expect(
        out[1],
        contains('<3 bytes, application/octet-stream, not shown>'),
      );
      expect(out[2], isNot(contains('⇢ body')));
    },
  );

  test('retry and token-refresh notes', () async {
    var n = 0;
    var token = 'OLD';
    mock
      ..get(
        '/flaky',
        (_) => ++n < 2 ? const MockResponse.status(503) : MockResponse.json(1),
      )
      ..get(
        '/me',
        (r) => r.headers['authorization'] == 'Bearer NEW'
            ? MockResponse.json(1)
            : const MockResponse.status(401),
      );
    final api = OmniNetwork(
      baseUrl: 'https://api.test/v1',
      transport: mock,
      enableLogging: true,
      logSink: PrettyLogSink(
        options: const LogOptions(colors: false),
        printer: out.add,
      ),
      retry: const RetryPolicy(
        baseDelay: Duration(milliseconds: 1),
        jitter: false,
      ),
      auth: BearerAuth(token: () => token, refresh: () => token = 'NEW'),
    );
    addTearDown(api.close);
    await api.get<void>('/flaky');
    await api.get<void>('/me');
    expect(out[1], contains('│ ↻ retry 2/3'));
    expect(out[3], contains('│ 🔑 token refreshed'));
    expect(out[0], isNot(contains('retry')));
  });

  test('cache hits are marked', () async {
    mock.get(
      '/c',
      (_) => MockResponse.json(1, headers: {'cache-control': 'max-age=60'}),
    );
    final api = OmniNetwork(
      baseUrl: 'https://api.test/v1',
      transport: mock,
      enableLogging: true,
      cache: OmniCache(),
      logSink: PrettyLogSink(
        options: const LogOptions(colors: false),
        printer: out.add,
      ),
    );
    addTearDown(api.close);
    await api.get<void>('/c');
    await api.get<void>('/c');
    expect(out[1], contains('✔ 200 OK · '));
    expect(out[1], contains(' · cache'));
  });

  test('concurrent calls print whole blocks, never interleaved', () async {
    mock.get(
      '/slow/{n}',
      (r) => MockResponse.json(
        {'n': r.pathParams['n']},
        delay: Duration(milliseconds: 5 * (5 - int.parse(r.pathParams['n']!))),
      ),
    );
    final api = client();
    addTearDown(api.close);
    await Future.wait([for (var i = 0; i < 5; i++) api.get<void>('/slow/$i')]);
    expect(out, hasLength(5));
    for (final block in out) {
      expect('┌'.allMatches(block), hasLength(1));
      expect('└'.allMatches(block), hasLength(1));
      final n = RegExp(r'/slow/(\d)').firstMatch(block)![1];
      expect(block, contains('"n": "$n"'));
    }
  });

  group('switch', () {
    tearDown(() => OmniNetwork.isReleaseBuild = false);

    test('enableLogging: false prints nothing', () async {
      final api = client(enable: false);
      addTearDown(api.close);
      await api.get<void>('/users/1');
      expect(out, isEmpty);
      expect(api.isLogging, isFalse);
    });

    test('release builds never log unless logInRelease', () async {
      OmniNetwork.isReleaseBuild = true;
      final api = client();
      addTearDown(api.close);
      await api.get<void>('/users/1');
      expect(out, isEmpty);
      expect((api.enableLogging, api.isLogging), (true, false));

      final forced = OmniNetwork(
        baseUrl: 'https://api.test/v1',
        transport: mock,
        enableLogging: true,
        logInRelease: true,
        logSink: PrettyLogSink(
          options: const LogOptions(colors: false),
          printer: out.add,
        ),
      );
      addTearDown(forced.close);
      await forced.get<void>('/users/1');
      expect(out, hasLength(1));
    });

    test(
      'enableLogging: true uses the pretty printer by default (print)',
      () async {
        final printed = <String>[];
        await runZoned(
          () async {
            final api = OmniNetwork(
              baseUrl: 'https://api.test/v1',
              transport: mock,
              enableLogging: true,
              logOptions: const LogOptions(colors: false),
            );
            await api.get<void>('/users/1');
            await api.close();
          },
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => printed.add(line),
          ),
        );
        expect(printed.single, startsWith('┌'));
        expect(printed.single, contains('GET  https://api.test/v1/users/1'));
      },
    );
  });
}
