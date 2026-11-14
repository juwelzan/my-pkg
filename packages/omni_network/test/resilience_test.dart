import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:omni_network/omni_network.dart';
import 'package:test/test.dart';

OmniRawResponse status(int code, {Map<String, String> headers = const {}}) =>
    OmniRawResponse(
      statusCode: code,
      headers: {'content-type': 'application/json', ...headers},
      bodyBytes: utf8.encode('{"s":$code}'),
    );

const fast = RetryPolicy(
  baseDelay: Duration(milliseconds: 2),
  jitter: false,
  maxAttempts: 3,
);

/// Answers with the queued outcomes in order (a response or an exception).
MockTransport scripted(List<Object> outcomes) {
  var i = 0;
  return MockTransport((_) {
    final o = outcomes[min(i++, outcomes.length - 1)];
    if (o is OmniNetworkException) throw o;
    return o as OmniRawResponse;
  });
}

void main() {
  group('RetryPolicy', () {
    test('GET retried on 503 until success', () async {
      final mock = scripted([status(503), status(503), status(200)]);
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        retry: fast,
      );
      addTearDown(api.close);
      expect(await api.get<dynamic>('/a'), {'s': 200});
      expect(mock.requests, hasLength(3));
    });

    test('gives up after maxAttempts and returns the last response', () async {
      final mock = scripted([status(503)]);
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        retry: fast,
      );
      addTearDown(api.close);
      await expectLater(
        api.get<dynamic>('/a'),
        throwsA(isA<HttpFailure>().having((e) => e.statusCode, 's', 503)),
      );
      expect(mock.requests, hasLength(3));
    });

    test('POST and PATCH are never retried by default', () async {
      for (final method in [HttpMethod.post, HttpMethod.patch]) {
        final mock = scripted([status(503), const ConnectionFailure('x')]);
        final api = OmniNetwork(
          baseUrl: 'https://h.io',
          transport: mock,
          retry: fast,
        );
        addTearDown(api.close);
        final r = await api.sendRaw(OmniRequest(method, '/a', body: {'a': 1}));
        expect(r.statusCode, 503);
        await expectLater(
          api.sendRaw(OmniRequest(method, '/a', body: {'a': 1})),
          throwsA(isA<ConnectionFailure>()),
        );
        expect(mock.requests, hasLength(2), reason: method.verb);
      }
    });

    test('POST with Idempotency-Key retried only when opted in', () async {
      const keyed = OmniRequest.post(
        '/pay',
        body: {'amount': 1},
        headers: {'Idempotency-Key': 'k-1'},
      );
      var mock = scripted([status(503), status(200)]);
      var api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        retry: fast,
      );
      await api.sendRaw(keyed);
      expect(mock.requests, hasLength(1));
      await api.close();

      mock = scripted([status(503), status(200)]);
      api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        retry: const RetryPolicy(
          baseDelay: Duration(milliseconds: 1),
          retryWithIdempotencyKey: true,
        ),
      );
      addTearDown(api.close);
      expect((await api.sendRaw(keyed)).statusCode, 200);
      expect(mock.requests, hasLength(2));
      expect(mock.requests.map((r) => r.headers['idempotency-key']), [
        'k-1',
        'k-1',
      ]);
      // Without the key, still not retried.
      mock.requests.clear();
      mock.handler = (_) => status(503);
      await api.sendRaw(const OmniRequest.post('/pay'));
      expect(mock.requests, hasLength(1));
    });

    test('PUT/DELETE only when added to methods', () async {
      final mock = scripted([status(503)]);
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        retry: fast,
      );
      addTearDown(api.close);
      await api.sendRaw(const OmniRequest.put('/a'));
      await api.sendRaw(const OmniRequest.delete('/a'));
      expect(mock.requests, hasLength(2));
      await api.sendRaw(
        const OmniRequest.delete(
          '/a',
          retry: RetryPolicy(
            baseDelay: Duration(milliseconds: 1),
            methods: {HttpMethod.delete},
          ),
        ),
      );
      expect(mock.requests, hasLength(5));
    });

    test('timeouts and connection errors retried; others not', () async {
      final mock = scripted([
        const TimeoutFailure(Duration(seconds: 1)),
        const ConnectionFailure('reset'),
        status(200),
      ]);
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        retry: fast,
      );
      addTearDown(api.close);
      expect(await api.get<dynamic>('/a'), {'s': 200});
      expect(mock.requests, hasLength(3));

      for (final e in <OmniNetworkException>[
        const RequestFailure('bad'),
        const CancelledFailure(),
        AuthFailure('x'),
        CircuitOpenFailure('h'),
      ]) {
        mock
          ..requests.clear()
          ..handler = (_) => throw e;
        await expectLater(
          api.sendRaw(const OmniRequest.get('/b')),
          throwsA(same(e)),
        );
        expect(mock.requests, hasLength(1), reason: '${e.runtimeType}');
      }
    });

    test('4xx (except 408/429) not retried', () async {
      final mock = scripted([status(404)]);
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        retry: fast,
      );
      addTearDown(api.close);
      await api.sendRaw(const OmniRequest.get('/a'));
      expect(mock.requests, hasLength(1));
    });

    test('Retry-After seconds honoured; too long is not waited for', () async {
      final mock = scripted([
        status(429, headers: {'Retry-After': '0'}),
        status(200),
      ]);
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        retry: fast,
      );
      addTearDown(api.close);
      expect(await api.get<dynamic>('/a'), {'s': 200});

      mock
        ..requests.clear()
        ..handler = (_) => status(503, headers: {'Retry-After': '3600'});
      final watch = Stopwatch()..start();
      final r = await api.sendRaw(const OmniRequest.get('/a'));
      expect(r.statusCode, 503);
      expect(mock.requests, hasLength(1));
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('Retry-After delay actually waited', () async {
      final mock = scripted([
        status(503, headers: {'Retry-After': '1'}),
        status(200),
      ]);
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        retry: fast,
      );
      addTearDown(api.close);
      final watch = Stopwatch()..start();
      await api.get<dynamic>('/a');
      expect(
        watch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 950)),
      );
    });

    test('parseRetryAfter', () {
      final now = DateTime.utc(2015, 10, 21, 7, 28);
      expect(
        RetryPolicy.parseRetryAfter('120', now),
        const Duration(minutes: 2),
      );
      expect(
        RetryPolicy.parseRetryAfter('Wed, 21 Oct 2015 07:28:30 GMT', now),
        const Duration(seconds: 30),
      );
      expect(
        RetryPolicy.parseRetryAfter('Wed, 21 Oct 2015 07:00:00 GMT', now),
        Duration.zero,
      );
      expect(RetryPolicy.parseRetryAfter('soon', now), isNull);
      expect(RetryPolicy.parseRetryAfter('-5', now), isNull);
    });

    test('exponential backoff, capped, jitter within 50-100 %', () {
      const p = RetryPolicy(
        baseDelay: Duration(milliseconds: 100),
        maxDelay: Duration(milliseconds: 500),
        jitter: false,
      );
      expect(
        [for (var i = 1; i <= 5; i++) p.backoff(i).inMilliseconds],
        [100, 200, 400, 500, 500],
      );
      final j = RetryPolicy(
        baseDelay: const Duration(milliseconds: 100),
        random: Random(1),
      );
      for (var i = 0; i < 100; i++) {
        final d = j.backoff(1).inMilliseconds;
        expect(d, inInclusiveRange(50, 100));
      }
    });

    test('per-request RetryPolicy.none disables retries', () async {
      final mock = scripted([status(503)]);
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        retry: fast,
      );
      addTearDown(api.close);
      await api.sendRaw(const OmniRequest.get('/a', retry: RetryPolicy.none));
      expect(mock.requests, hasLength(1));
    });

    test('cancel during backoff stops further attempts', () async {
      final mock = scripted([status(503)]);
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        retry: const RetryPolicy(
          baseDelay: Duration(seconds: 5),
          jitter: false,
        ),
      );
      addTearDown(api.close);
      final token = OmniCancelToken();
      final f = api.sendRaw(OmniRequest.get('/a', cancelToken: token));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(api.pendingRequests, 1); // waiting for the retry
      token.cancel();
      await expectLater(f, throwsA(isA<CancelledFailure>()));
      expect(mock.requests, hasLength(1));
      expect(api.pendingRequests, 0);
    });

    test('close during backoff => ClosedFailure, timers released', () async {
      final mock = scripted([status(503)]);
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        retry: const RetryPolicy(
          baseDelay: Duration(seconds: 5),
          jitter: false,
        ),
      );
      final f = api.sendRaw(const OmniRequest.get('/a'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await api.close();
      await expectLater(f, throwsA(isA<ClosedFailure>()));
      expect(api.pendingRequests, 0);
    });

    test('each attempt is logged', () async {
      final sink = _Sink();
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: scripted([status(503), status(200)]),
        retry: fast,
        enableLogging: true,
        logSink: sink,
      );
      addTearDown(api.close);
      await api.sendRaw(const OmniRequest.get('/a'));
      expect(sink.records.map((r) => (r.kind, r.statusCode)), [
        (NetworkLogKind.request, null),
        (NetworkLogKind.response, 503),
        (NetworkLogKind.request, null),
        (NetworkLogKind.response, 200),
      ]);
    });

    test('downloads are not retried automatically', () async {
      final mock = scripted([status(503)]);
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        retry: fast,
      );
      addTearDown(api.close);
      await expectLater(api.downloadBytes('/f'), throwsA(isA<HttpFailure>()));
      expect(mock.requests, hasLength(1));
    });
  });

  group('cancel groups', () {
    test('cancelAll cancels in-flight requests; client stays usable', () async {
      final gate = Completer<OmniRawResponse>();
      final mock = MockTransport(
        (r) => r.uri.path == '/ok' ? status(200) : gate.future,
      );
      final api = OmniNetwork(baseUrl: 'https://h.io', transport: mock);
      addTearDown(api.close);
      final fs = [
        for (var i = 0; i < 3; i++) api.get<dynamic>('/slow').asResult(),
      ];
      await Future<void>.delayed(Duration.zero);
      api.cancelAll();
      final rs = await Future.wait(fs);
      expect(
        rs.map((r) => (r as Err).error),
        everyElement(isA<CancelledFailure>()),
      );
      expect(await api.get<dynamic>('/ok'), {'s': 200});
    });

    test(
      'cancelAll also cancels a request waiting for a token refresh',
      () async {
        final refresh = Completer<String?>();
        final mock = MockTransport((r) => status(401));
        final auth = BearerAuth(
          token: () => 'T',
          refresh: () => refresh.future,
        );
        final api = OmniNetwork(
          baseUrl: 'https://h.io',
          transport: mock,
          auth: auth,
        );
        addTearDown(api.close);
        final f = api.get<dynamic>('/a');
        while (!auth.isRefreshing) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        api.cancelAll();
        refresh.complete('T2');
        await expectLater(f, throwsA(isA<CancelledFailure>()));
        expect(mock.requests, hasLength(1));
      },
    );

    test('child token: parent cancels child; child alone does not cancel '
        'parent', () {
      final parent = OmniCancelToken();
      final a = parent.child();
      final b = parent.child();
      a.cancel();
      expect(parent.isCancelled, isFalse);
      expect(parent.attachedRequests, 1); // a detached itself
      parent.cancel();
      expect(b.isCancelled, isTrue);
      expect(parent.child().isCancelled, isTrue);
    });
  });

  group('CircuitBreaker', () {
    late DateTime now;
    late CircuitBreaker breaker;
    late MockTransport mock;
    late OmniNetwork api;

    setUp(() {
      now = DateTime(2026);
      breaker = CircuitBreaker(
        failureThreshold: 3,
        openDuration: const Duration(seconds: 30),
        now: () => now,
      );
      mock = MockTransport((_) => status(500));
      api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        circuitBreaker: breaker,
      );
    });
    tearDown(() => api.close());

    Future<Object> call([String url = '/a']) async {
      try {
        return (await api.sendRaw(OmniRequest.get(url))).statusCode;
      } on OmniNetworkException catch (e) {
        return e;
      }
    }

    test('opens after threshold, fails fast without sending', () async {
      for (var i = 0; i < 3; i++) {
        expect(await call(), 500);
      }
      expect(breaker.stateOf('h.io:443'), CircuitState.open);
      expect(await call(), isA<CircuitOpenFailure>());
      expect(mock.requests, hasLength(3));
    });

    test('half-open allows one probe; success closes', () async {
      for (var i = 0; i < 3; i++) {
        await call();
      }
      now = now.add(const Duration(seconds: 31));
      expect(breaker.stateOf('h.io:443'), CircuitState.halfOpen);
      final gate = Completer<OmniRawResponse>();
      mock.handler = (_) => gate.future;
      final probe = call();
      await Future<void>.delayed(Duration.zero);
      expect(await call(), isA<CircuitOpenFailure>()); // second probe refused
      gate.complete(status(200));
      expect(await probe, 200);
      expect(breaker.stateOf('h.io:443'), CircuitState.closed);
    });

    test('half-open failure re-opens', () async {
      for (var i = 0; i < 3; i++) {
        await call();
      }
      now = now.add(const Duration(seconds: 31));
      mock.handler = (_) => throw const ConnectionFailure('down');
      expect(await call(), isA<ConnectionFailure>());
      expect(breaker.stateOf('h.io:443'), CircuitState.open);
    });

    test('4xx and cancellations do not count; success resets', () async {
      mock.handler = (_) => status(404);
      for (var i = 0; i < 5; i++) {
        await call();
      }
      expect(breaker.stateOf('h.io:443'), CircuitState.closed);
      mock.handler = (_) => status(500);
      await call();
      await call();
      mock.handler = (_) => status(200);
      await call();
      mock.handler = (_) => status(500);
      await call();
      await call();
      expect(breaker.stateOf('h.io:443'), CircuitState.closed);
    });

    test('hosts are independent', () async {
      for (var i = 0; i < 3; i++) {
        await call();
      }
      mock.handler = (_) => status(200);
      expect(await call('https://other.io/x'), 200);
      expect(breaker.stateOf('other.io:443'), CircuitState.closed);
    });

    test('retries stop as soon as the circuit opens', () async {
      final retrying = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        circuitBreaker: breaker,
        retry: const RetryPolicy(
          maxAttempts: 10,
          baseDelay: Duration(milliseconds: 1),
          jitter: false,
        ),
      );
      addTearDown(retrying.close);
      await expectLater(
        retrying.sendRaw(const OmniRequest.get('/a')),
        throwsA(isA<CircuitOpenFailure>()),
      );
      expect(mock.requests, hasLength(3));
    });
  });
}

final class _Sink implements LogSink {
  final records = <NetworkLogRecord>[];
  @override
  void log(NetworkLogRecord r) => records.add(r);
}
