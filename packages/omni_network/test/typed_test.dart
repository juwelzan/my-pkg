import 'dart:convert';

import 'package:omni_network/omni_network.dart';
import 'package:test/test.dart';

final class User {
  User(this.id, this.name);
  factory User.fromJson(Map<String, dynamic> j) =>
      User(j['id'] as int, j['name'] as String);
  final int id;
  final String name;
}

OmniRawResponse res(int status, [Object? body, String? text]) =>
    OmniRawResponse(
      statusCode: status,
      bodyBytes: utf8.encode(text ?? (body == null ? '' : jsonEncode(body))),
    );

void main() {
  late MockTransport mock;
  late OmniNetwork api;

  void reply(int status, [Object? body, String? text]) =>
      mock.handler = (_) => res(status, body, text);

  setUp(() {
    mock = MockTransport((_) => res(200));
    api = OmniNetwork(baseUrl: 'https://api.example.com', transport: mock);
  });
  tearDown(() => api.close());

  group('decoding', () {
    test('get<User> with decoder', () async {
      reply(200, {'id': 10, 'name': 'Ana'});
      final u = await api.get<User>('/users/10', decoder: User.fromJson);
      expect((u.id, u.name), (10, 'Ana'));
    });

    test('getList<User>', () async {
      reply(200, [
        {'id': 1, 'name': 'A'},
        {'id': 2, 'name': 'B'},
      ]);
      final list = await api.getList<User>('/users', decoder: User.fromJson);
      expect(list.map((u) => u.name), ['A', 'B']);
    });

    test('send<T> exposes status, headers and duration', () async {
      mock.handler = (_) => OmniRawResponse(
        statusCode: 201,
        headers: {'Location': '/users/3'},
        bodyBytes: utf8.encode('{"id":3,"name":"C"}'),
      );
      final r = await api.send<User>(
        const OmniRequest.post('/users', body: {'name': 'C'}),
        decoder: User.fromJson,
      );
      expect(r.statusCode, 201);
      expect(r.headers['location'], '/users/3');
      expect(r.data.id, 3);
    });

    test('no decoder: primitives, maps, String text, void/null', () async {
      reply(200, 42);
      expect(await api.get<int>('/n'), 42);
      reply(200, {'a': 1});
      expect(await api.get<Map<String, dynamic>>('/m'), {'a': 1});
      reply(200, null, 'plain text');
      expect(await api.get<String>('/t'), 'plain text');
      reply(204);
      await api.delete<void>('/users/1');
      expect(await api.get<User?>('/maybe'), isNull);
      reply(200, null, 'OK');
      expect(await api.delete<dynamic>('/x'), 'OK');
      reply(200, {'deleted': true});
      expect(await api.delete<dynamic>('/x'), {'deleted': true});
    });

    test('post/put/patch send bodies and decode', () async {
      mock.handler = (r) => res(200, {'id': 1, 'name': r.method.verb});
      for (final f in [api.post<User>, api.put<User>, api.patch<User>]) {
        await f('/u', body: {'x': 1}, decoder: User.fromJson);
      }
      expect(mock.requests.map((r) => r.method.verb), ['POST', 'PUT', 'PATCH']);
      expect(
        mock.requests.every((r) => utf8.decode(r.body!) == '{"x":1}'),
        isTrue,
      );
    });

    test('head returns status and headers', () async {
      mock.handler = (_) =>
          OmniRawResponse(statusCode: 200, headers: {'ETag': '"v1"'});
      expect((await api.head('/f')).headers['etag'], '"v1"');
    });
  });

  group('failures', () {
    test(
      'non-2xx throws HttpFailure with response, no body in message',
      () async {
        reply(404, {'error': 'secret-detail'});
        try {
          await api.get<User>('/users/9?token=T0K', decoder: User.fromJson);
          fail('should throw');
        } on HttpFailure catch (e) {
          expect(e.statusCode, 404);
          expect(e.response.json, {'error': 'secret-detail'});
          expect('$e', isNot(contains('secret-detail')));
          expect('$e', isNot(contains('T0K')));
          expect(e.uri.toString(), 'https://api.example.com/users/9');
        }
      },
    );

    test('sendRaw still returns non-2xx', () async {
      reply(500);
      expect((await api.sendRaw(const OmniRequest.get('/x'))).statusCode, 500);
    });

    test('invalid JSON is DecodeFailure without echoing the body', () async {
      reply(200, null, '<html>password=hunter2</html>');
      await expectLater(
        api.get<User>('/u', decoder: User.fromJson),
        throwsA(
          isA<DecodeFailure>().having(
            (e) => '$e',
            'text',
            isNot(contains('hunter2')),
          ),
        ),
      );
    });

    test('decoder throwing is DecodeFailure with cause and stack', () async {
      reply(200, {'id': 'not-int', 'name': 'A'});
      await expectLater(
        api.get<User>('/u', decoder: User.fromJson),
        throwsA(
          isA<DecodeFailure>()
              .having((e) => e.cause, 'cause', isA<TypeError>())
              .having((e) => e.stackTrace, 'stack', isNotNull),
        ),
      );
    });

    test('wrong shapes', () async {
      reply(200, [1]);
      await expectLater(
        api.get<User>('/u', decoder: User.fromJson),
        throwsA(isA<DecodeFailure>()),
      );
      await expectLater(
        api.getList<User>('/u', decoder: User.fromJson),
        throwsA(
          isA<DecodeFailure>().having(
            (e) => e.message,
            'message',
            contains('index 0'),
          ),
        ),
      );
      reply(200, {'a': 1});
      await expectLater(
        api.getList<User>('/u', decoder: User.fromJson),
        throwsA(isA<DecodeFailure>()),
      );
      await expectLater(api.get<int>('/u'), throwsA(isA<DecodeFailure>()));
      reply(200);
      await expectLater(
        api.get<User>('/u', decoder: User.fromJson),
        throwsA(isA<DecodeFailure>()),
      );
      await expectLater(api.get<int>('/u'), throwsA(isA<DecodeFailure>()));
    });
  });

  group('response adapters', () {
    test('client-level envelope adapter', () async {
      final env = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        responseAdapter: const EnvelopeResponseAdapter(errorKey: 'error'),
      );
      reply(200, {
        'data': {'id': 1, 'name': 'A'},
        'meta': {},
      });
      expect((await env.get<User>('/u', decoder: User.fromJson)).name, 'A');
      reply(200, {
        'data': [
          {'id': 1, 'name': 'A'},
        ],
      });
      expect(
        await env.getList<User>('/u', decoder: User.fromJson),
        hasLength(1),
      );
      reply(200, {
        'data': null,
        'error': {'code': 7},
      });
      await expectLater(
        env.get<User>('/u', decoder: User.fromJson),
        throwsA(isA<DecodeFailure>()),
      );
      reply(200, {'meta': {}});
      await expectLater(
        env.get<User>('/u', decoder: User.fromJson),
        throwsA(isA<DecodeFailure>()),
      );
    });

    test('per-call adapter overrides client adapter', () async {
      reply(200, {
        'payload': {'id': 2, 'name': 'B'},
      });
      final u = await api.get<User>(
        '/u',
        decoder: User.fromJson,
        adapter: const EnvelopeResponseAdapter(dataKey: 'payload'),
      );
      expect(u.id, 2);
    });
  });

  group('Result', () {
    test('Ok and Err', () async {
      reply(200, {'id': 1, 'name': 'A'});
      final ok = await api.get<User>('/u', decoder: User.fromJson).asResult();
      expect(ok, isA<Ok<User>>());
      expect(ok.valueOrNull?.id, 1);
      reply(401);
      final err = await api.get<User>('/u', decoder: User.fromJson).asResult();
      expect(switch (err) {
        Ok() => 'ok',
        Err(:final error) => error is HttpFailure ? 'http' : 'other',
      }, 'http');
      expect(err.isOk, isFalse);
    });

    test('programming errors are not swallowed', () async {
      await expectLater(
        Future<int>.error(StateError('bug')).asResult(),
        throwsStateError,
      );
    });
  });
}
