import 'dart:convert';

import 'package:omni_network/advanced.dart';
import 'package:omni_network/testing.dart';
import 'package:test/test.dart';

final class User {
  User(this.id, this.name);
  factory User.fromJson(Map<String, dynamic> j) =>
      User(j['id'] as int, j['name'] as String);
  final int id;
  final String name;
}

abstract final class UserApi {
  static final byId = Endpoint.get<User>(
    '/users/{id}',
    decoder: User.fromJson,
    name: 'getUser',
    tags: {'users'},
  );
  static final list = Endpoint.getList<User>(
    '/users',
    decoder: User.fromJson,
    query: {'limit': 20},
  );
  static final create = Endpoint.post<User>('/users', decoder: User.fromJson);
  static final remove = Endpoint.delete<void>('/users/{id}');
  static final file = Endpoint.get<String>('/orgs/{org}/files/{name}');
}

OmniRawResponse json(Object body, [int status = 200]) => OmniRawResponse(
  statusCode: status,
  headers: {'content-type': 'application/json'},
  bodyBytes: utf8.encode(jsonEncode(body)),
);

void main() {
  late MockTransport mock;
  late OmniNetwork api;

  setUp(() {
    mock = MockTransport(
      (r) => switch (r.uri.path) {
        '/v1/users' when r.method == HttpMethod.get => json([
          {'id': 1, 'name': 'A'},
        ]),
        '/v1/users' => json({'id': 2, 'name': 'B'}, 201),
        _ when r.method == HttpMethod.delete => OmniRawResponse(
          statusCode: 204,
        ),
        _ => json({'id': 10, 'name': 'Ana'}),
      },
    );
    api = OmniNetwork(
      baseUrl: 'https://api.example.com/v1',
      headers: {'Accept': 'application/json'},
      transport: mock,
    );
  });
  tearDown(() => api.close());

  group('Endpoint', () {
    test('call with path params, defaults and typed results', () async {
      final u = await api.call(UserApi.byId, path: {'id': 10});
      expect(u.name, 'Ana');
      expect(mock.requests.last.uri.path, '/v1/users/10');

      final list = await api.call(UserApi.list, query: {'page': 2});
      expect(list.single.id, 1);
      expect(mock.requests.last.uri.queryParameters, {
        'limit': '20',
        'page': '2',
      });

      final created = await api.callResponse(
        UserApi.create,
        body: {'name': 'B'},
      );
      expect((created.statusCode, created.data.id), (201, 2));

      await api.call(UserApi.remove, path: {'id': 3});
      expect(mock.requests.last.method, HttpMethod.delete);
    });

    test('path values are URL-encoded; missing/unknown params rejected', () {
      expect(
        UserApi.file.expand({'org': 'a b', 'name': '../x?y'}),
        '/orgs/a%20b/files/..%2Fx%3Fy',
      );
      expect(() => UserApi.byId.expand({}), throwsArgumentError);
      expect(
        () => UserApi.byId.expand({'id': 1, 'extra': 2}),
        throwsArgumentError,
      );
      expect(UserApi.file.pathParams, ['org', 'name']);
    });

    test('non-2xx throws HttpFailure', () async {
      mock.handler = (_) => json({}, 404);
      await expectLater(
        api.call(UserApi.byId, path: {'id': 1}),
        throwsA(isA<HttpFailure>()),
      );
    });
  });

  group('EndpointRegistry', () {
    test('lookup by name/route, tags, match concrete paths', () {
      final reg = EndpointRegistry([
        UserApi.byId,
        UserApi.list,
        UserApi.create,
      ]);
      expect(reg['getUser'], same(UserApi.byId));
      expect(reg['GET /users'], same(UserApi.list));
      expect(reg.tagged('users'), [UserApi.byId]);
      expect(reg.match(HttpMethod.get, '/users/10'), same(UserApi.byId));
      expect(reg.match(HttpMethod.get, '/users/10/posts'), isNull);
      expect(reg.match(HttpMethod.post, '/users'), same(UserApi.create));
      expect(reg.all, hasLength(3));
    });

    test('duplicates rejected', () {
      final reg = EndpointRegistry([UserApi.byId]);
      expect(() => reg.register(UserApi.byId), throwsArgumentError);
      expect(
        () => reg.register(Endpoint.get<Object?>('/users/{id}', name: 'other')),
        throwsArgumentError,
      );
    });
  });

  group('request builder', () {
    test('builds and sends', () async {
      final token = OmniCancelToken();
      final b = api
          .request('/users')
          .query('page', 2)
          .queryAll({
            'tag': ['a', 'b'],
          })
          .header('X-Trace', 't1')
          .timeout(const Duration(seconds: 5))
          .cancelToken(token)
          .retry(RetryPolicy.none)
          .cache(CachePolicy.noCache);
      final r = b.build();
      expect(r.method, HttpMethod.get);
      expect(r.query, {
        'page': 2,
        'tag': ['a', 'b'],
      });
      expect(r.timeout, const Duration(seconds: 5));
      expect(r.cancelToken, same(token));
      expect(r.retry, same(RetryPolicy.none));
      expect(r.cachePolicy, CachePolicy.noCache);
      final list = await b.sendList<User>(decoder: User.fromJson);
      expect(list.single.name, 'A');
      expect(mock.requests.last.headers['x-trace'], 't1');
    });

    test('json, form, text, bytes bodies', () async {
      await api
          .request('/users', method: HttpMethod.post)
          .json({'name': 'B'})
          .send<User>(decoder: User.fromJson);
      expect(utf8.decode(mock.requests.last.body!), '{"name":"B"}');

      await api.request('/login', method: HttpMethod.post).form({
        'user': 'a b',
        'password': 'p&q',
      }).sendRaw();
      expect(utf8.decode(mock.requests.last.body!), 'user=a+b&password=p%26q');
      expect(
        mock.requests.last.headers['content-type'],
        'application/x-www-form-urlencoded',
      );

      await api.request('/t', method: HttpMethod.put).text('hi').sendRaw();
      expect(
        mock.requests.last.headers['content-type'],
        'text/plain; charset=utf-8',
      );

      await api.request('/b', method: HttpMethod.put).bytes([1, 2]).sendRaw();
      expect(mock.requests.last.body, [1, 2]);
    });

    test('skipAuth', () {
      expect(api.request('/p').skipAuth().build().skipAuth, isTrue);
    });
  });

  group('cURL export', () {
    test('redacts secrets by default', () {
      final curl = api.toCurl(
        const OmniRequest.post(
          '/login',
          query: {'api_key': 'Q-SECRET', 'v': '1'},
          headers: {'Authorization': 'Bearer H-SECRET', 'Cookie': 'C-SECRET'},
          body: {'user': 'ana', 'password': 'B-SECRET'},
        ),
      );
      for (final s in ['Q-SECRET', 'H-SECRET', 'C-SECRET', 'B-SECRET']) {
        expect(curl, isNot(contains(s)));
      }
      expect(curl, contains("-X POST"));
      expect(
        curl,
        contains("'https://api.example.com/v1/login?api_key=***&v=1'"),
      );
      expect(curl, contains("-H 'accept: application/json'"));
      expect(curl, contains('"user":"ana"'));
    });

    test('quotes single quotes safely; binary/multipart not inlined', () {
      final c = api.toCurl(
        const OmniRequest.post('/t', body: "it's"),
        redact: false,
      );
      expect(c, contains(r"--data-raw 'it'\''s'"));
      final bin = api.toCurl(const OmniRequest.post('/b', body: [1, 2, 3]));
      expect(bin, contains('# body: 3 bytes'));
      final mp = api.toCurl(
        OmniRequest.post(
          '/m',
          body: MultipartBody(
            files: [
              UploadFile.fromBytes('f', [1], filename: 'x'),
            ],
          ),
        ),
      );
      expect(mp, contains('not included'));
    });

    test('builder toCurl', () {
      expect(
        api.request('/x').query('a', 1).toCurl(),
        contains("'https://api.example.com/v1/x?a=1'"),
      );
    });
  });

  group('cURL import', () {
    test('typical browser "copy as cURL"', () {
      final r = parseCurl(r'''
curl 'https://api.example.com/v1/users?page=2&tag=a&tag=b' \
  -H 'accept: application/json' \
  -H "x-note: say \"hi\"" \
  --data-raw '{"name":"Ana"}' \
  -H 'content-type: application/json' \
  --compressed -k
''');
      final q = r.request;
      expect(q.method, HttpMethod.post);
      expect(q.path, 'https://api.example.com/v1/users');
      expect(q.query, {
        'page': '2',
        'tag': ['a', 'b'],
      });
      expect(q.headers['x-note'], 'say "hi"');
      expect(q.body, {'name': 'Ana'});
      expect(r.warnings, ['Ignored option --compressed', 'Ignored option -k']);
    });

    test('-X, -G, -u, --json, -I, -F, @file', () {
      expect(
        parseCurl("curl -X DELETE https://h.io/a").request.method,
        HttpMethod.delete,
      );
      final g = parseCurl("curl -G https://h.io/s -d q=x -d n=1").request;
      expect((g.method, g.body), (HttpMethod.get, null));
      expect(g.query, {'q': 'x', 'n': '1'});
      final u = parseCurl("curl -u ana:pw https://h.io").request;
      expect(
        u.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('ana:pw'))}',
      );
      final j = parseCurl("curl --json '{\"a\":1}' https://h.io/j").request;
      expect(
        (j.method, j.headers['Content-Type']),
        (HttpMethod.post, 'application/json'),
      );
      expect(j.body, {'a': 1});
      expect(parseCurl('curl -I https://h.io').request.method, HttpMethod.head);
      final f = parseCurl("curl -F file=@a.png -d @body.json https://h.io/u");
      expect(f.warnings, hasLength(2));
      final form = parseCurl("curl https://h.io/f -d a=1 -d b=2").request;
      expect(
        (form.body, form.headers['Content-Type']),
        ('a=1&b=2', 'application/x-www-form-urlencoded'),
      );
    });

    test('errors', () {
      expect(() => parseCurl('curl -H "x: y"'), throwsFormatException);
      expect(() => parseCurl("curl 'https://h.io"), throwsFormatException);
      expect(
        () => parseCurl('curl -X BREW https://h.io'),
        throwsFormatException,
      );
    });

    test('round trip: export (unredacted) -> import -> same request', () async {
      const original = OmniRequest.patch(
        '/users/7',
        query: {
          'fields': ['a', 'b'],
          'q': "it's & more",
        },
        headers: {'X-Trace': 'abc'},
        body: {
          'name': "O'Neil",
          'tags': [1, 2],
          'nested': {'ok': true},
        },
      );
      final curl = api.toCurl(original, redact: false);
      final back = parseCurl(curl).request;
      final a = api.resolve(original);
      final b = api.resolve(back);
      expect(b.method, a.method);
      expect(b.uri, a.uri);
      expect(b.headers, a.headers);
      expect(
        jsonDecode(utf8.decode(b.body!)),
        jsonDecode(utf8.decode(a.body!)),
      );
      expect(parseCurl(curl).warnings, isEmpty);
    });
  });
}
