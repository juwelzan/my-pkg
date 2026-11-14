import 'dart:async';
import 'dart:convert';

import 'package:omni_network/omni_network.dart';
import 'package:test/test.dart';

OmniRawResponse status(int code, [Object? body]) => OmniRawResponse(
  statusCode: code,
  headers: {'content-type': 'application/json'},
  bodyBytes: body == null ? null : utf8.encode(jsonEncode(body)),
);

final class Recorder extends OmniInterceptor {
  Recorder(this.name, this.log);
  final String name;
  final List<String> log;
  @override
  OmniRequest onRequest(OmniRequest r) {
    log.add('$name.req');
    return r.withHeader('X-$name', '1');
  }

  @override
  OmniRawResponse onResponse(OmniRequest r, OmniRawResponse res) {
    log.add('$name.res');
    return res;
  }

  @override
  void onError(OmniRequest r, OmniNetworkException e) =>
      log.add('$name.err:${e.runtimeType}');
}

/// Fake server: accepts only `Bearer <validToken>`.
final class AuthServer {
  String validToken = 'T1';
  final seenTokens = <String?>[];
  late final mock = MockTransport((r) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final h = r.headers['authorization'];
    seenTokens.add(h);
    if (r.uri.path == '/auth/refresh') {
      return status(200, {'access_token': 'T2'});
    }
    return h == 'Bearer $validToken' ? status(200, {'ok': true}) : status(401);
  });
}

void main() {
  group('interceptors', () {
    test('request in order, response in reverse, headers applied', () async {
      final log = <String>[];
      final mock = MockTransport((_) => status(200));
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        interceptors: [Recorder('A', log), Recorder('B', log)],
      );
      addTearDown(api.close);
      await api.sendRaw(const OmniRequest.get('/x'));
      expect(log, ['A.req', 'B.req', 'B.res', 'A.res']);
      expect(mock.requests.single.headers, containsPair('x-a', '1'));
      expect(mock.requests.single.headers, containsPair('x-b', '1'));
    });

    test('onError sees failures in reverse order; failure rethrown', () async {
      final log = <String>[];
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: MockTransport((_) => throw const ConnectionFailure('x')),
        interceptors: [Recorder('A', log), Recorder('B', log)],
      );
      addTearDown(api.close);
      await expectLater(
        api.sendRaw(const OmniRequest.get('/x')),
        throwsA(isA<ConnectionFailure>()),
      );
      expect(log.where((l) => l.contains('err')), [
        'B.err:ConnectionFailure',
        'A.err:ConnectionFailure',
      ]);
    });

    test('throwing interceptor becomes RequestFailure; nothing sent', () async {
      final mock = MockTransport((_) => status(200));
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        interceptors: [_Throwing()],
      );
      addTearDown(api.close);
      await expectLater(
        api.sendRaw(const OmniRequest.get('/x')),
        throwsA(isA<RequestFailure>()),
      );
      expect(mock.requests, isEmpty);
    });

    test('onResponse can turn a response into a typed failure', () async {
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: MockTransport((_) => status(503)),
        interceptors: [_Maintenance()],
      );
      addTearDown(api.close);
      await expectLater(
        api.get<dynamic>('/x'),
        throwsA(
          isA<RequestFailure>().having((e) => e.message, 'm', 'maintenance'),
        ),
      );
    });
  });

  group('BearerAuth', () {
    late AuthServer server;
    late String stored;
    late int logouts;
    late OmniNetwork api;

    BearerAuth makeAuth({
      FutureOr<String?> Function()? refresh,
      Duration timeout = const Duration(seconds: 5),
    }) => BearerAuth(
      token: () => stored,
      refresh:
          refresh ??
          () async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            server.validToken = 'T2';
            return stored = 'T2';
          },
      onRefreshFailed: () => logouts++,
      refreshTimeout: timeout,
    );

    setUp(() {
      server = AuthServer();
      stored = 'T1';
      logouts = 0;
    });
    tearDown(() => api.close());

    OmniNetwork client(BearerAuth auth) => api = OmniNetwork(
      baseUrl: 'https://h.io',
      transport: server.mock,
      auth: auth,
    );

    test('adds Authorization header', () async {
      client(makeAuth());
      await api.get<dynamic>('/me');
      expect(server.seenTokens.single, 'Bearer T1');
    });

    test('10 concurrent 401s => exactly one refresh, all replayed', () async {
      final auth = makeAuth();
      client(auth);
      server.validToken = 'EXPIRED-T1-REJECTED';
      final results = await Future.wait([
        for (var i = 0; i < 10; i++) api.get<dynamic>('/r$i'),
      ]);
      expect(results, everyElement({'ok': true}));
      expect(auth.refreshCount, 1);
      expect(logouts, 0);
      expect(server.seenTokens.where((t) => t == 'Bearer T2'), hasLength(10));
      expect(server.seenTokens, hasLength(20));
    });

    test(
      'requests started during a refresh wait and use the new token',
      () async {
        final auth = makeAuth();
        client(auth);
        server.validToken = 'X';
        final first = api.get<dynamic>('/a');
        while (!auth.isRefreshing) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        final late = await api.get<dynamic>('/b');
        expect(late, {'ok': true});
        await first;
        expect(auth.refreshCount, 1);
        // /b was sent once, with the new token only.
        expect(server.seenTokens.last, 'Bearer T2');
        expect(server.seenTokens.where((t) => t == 'Bearer T1'), hasLength(1));
      },
    );

    test(
      'refresh failure => callback once, all fail with AuthFailure',
      () async {
        final auth = makeAuth(
          refresh: () async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return null;
          },
        );
        client(auth);
        server.validToken = 'X';
        final results = await Future.wait([
          for (var i = 0; i < 5; i++) api.get<dynamic>('/r$i').asResult(),
        ]);
        expect(
          results.map((r) => (r as Err).error),
          everyElement(isA<AuthFailure>()),
        );
        expect(logouts, 1);
        expect(auth.refreshCount, 1);
        // A later 401 with the same stale token does not refresh again.
        await expectLater(
          api.get<dynamic>('/again'),
          throwsA(isA<AuthFailure>()),
        );
        expect(auth.refreshCount, 1);
        expect(logouts, 1);
        // After a new login, auth works again.
        stored = 'NEW';
        server.validToken = 'NEW';
        expect(await api.get<dynamic>('/ok'), {'ok': true});
      },
    );

    test('refresh throwing or timing out => AuthFailure with cause', () async {
      client(makeAuth(refresh: () => throw StateError('refresh crashed')));
      server.validToken = 'X';
      await expectLater(
        api.get<dynamic>('/a'),
        throwsA(
          isA<AuthFailure>()
              .having((e) => e.cause, 'cause', isA<StateError>())
              .having((e) => e.response?.statusCode, 'status', 401),
        ),
      );
      await api.close();
      stored = 'T1';
      client(
        makeAuth(
          refresh: () => Completer<String?>().future,
          timeout: const Duration(milliseconds: 30),
        ),
      );
      await expectLater(api.get<dynamic>('/a'), throwsA(isA<AuthFailure>()));
      expect(logouts, 2);
    });

    test('replayed request getting 401 again is returned, no loop', () async {
      final auth = makeAuth(refresh: () async => stored = 'T2');
      client(auth);
      server.validToken = 'NEVER';
      final res = await api.sendRaw(const OmniRequest.get('/a'));
      expect(res.statusCode, 401);
      expect(auth.refreshCount, 1);
      expect(server.seenTokens, ['Bearer T1', 'Bearer T2']);
    });

    test('refresh using the same client skips auth automatically', () async {
      final auth = makeAuth(
        refresh: () async {
          final r = await api.post<Map<String, dynamic>>(
            '/auth/refresh',
            body: {'refresh_token': 'R'},
          );
          server.validToken = r['access_token'] as String;
          return stored = server.validToken;
        },
      );
      client(auth);
      server.validToken = 'X';
      expect(await api.get<dynamic>('/me'), {'ok': true});
      // refresh call carried no Authorization header.
      expect(server.seenTokens, ['Bearer T1', null, 'Bearer T2']);
    });

    test('skipAuth and explicit header bypass auth', () async {
      final auth = makeAuth();
      client(auth);
      await api.sendRaw(const OmniRequest.get('/public', skipAuth: true));
      final r = await api.sendRaw(
        const OmniRequest.get(
          '/x',
          headers: {'authorization': 'Bearer CUSTOM'},
        ),
      );
      expect(server.seenTokens, [null, 'Bearer CUSTOM']);
      expect(r.statusCode, 401);
      expect(auth.refreshCount, 0);
    });

    test('no token => no header; 401 then tries refresh once', () async {
      final auth = BearerAuth(token: () => null, refresh: () => null);
      client(auth);
      await expectLater(api.sendRaw(const OmniRequest.get('/x')),
          throwsA(isA<AuthFailure>()));
      expect(server.seenTokens.single, isNull);
      expect(auth.refreshCount, 1);
    });

    test('close while waiting for refresh => ClosedFailure', () async {
      final gate = Completer<String?>();
      final auth = makeAuth(refresh: () => gate.future);
      client(auth);
      server.validToken = 'X';
      final f = api.get<dynamic>('/a');
      while (!auth.isRefreshing) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await api.close();
      gate.complete('T2');
      await expectLater(f, throwsA(isA<ClosedFailure>()));
    });

    test('tokens are redacted in logs', () async {
      final sink = _Sink();
      api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: server.mock,
        auth: makeAuth(),
        enableLogging: true,
        logSink: sink,
      );
      server.validToken = 'X';
      await api.sendRaw(const OmniRequest.get('/a'));
      expect(sink.out, isNot(contains('T1')));
      expect(sink.out, isNot(contains('T2')));
      expect(sink.out, contains('authorization: ***'));
    });
  });
}

final class _Throwing extends OmniInterceptor {
  @override
  OmniRequest onRequest(OmniRequest r) => throw const FormatException('bad');
}

final class _Maintenance extends OmniInterceptor {
  @override
  OmniRawResponse onResponse(OmniRequest r, OmniRawResponse res) =>
      res.statusCode == 503 ? throw const RequestFailure('maintenance') : res;
}

final class _Sink implements LogSink {
  final b = StringBuffer();
  String get out => '$b';
  @override
  void log(NetworkLogRecord r) => b.writeln(r.message);
}
