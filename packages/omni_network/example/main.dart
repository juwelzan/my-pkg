// Runnable tour of OmniNetwork against an in-memory fake backend:
//   dart run example/main.dart
// No internet needed. Swap `transport: backend` for nothing (Dio) and a
// real baseUrl to talk to a server.

import 'package:omni_network/omni_network.dart';
import 'package:omni_network/testing.dart';

final class User {
  const User({required this.id, required this.name});

  factory User.fromJson(Map<String, dynamic> json) =>
      User(id: json['id'] as int, name: json['name'] as String);

  final int id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  @override
  String toString() => 'User($id, $name)';
}

/// Typed endpoints (what the OpenAPI generator would produce).
abstract final class UserApi {
  static final byId = Endpoint.get<User>(
    '/users/{id}',
    decoder: User.fromJson,
    name: 'getUser',
  );
  static final create = Endpoint.post<User>('/users', decoder: User.fromJson);
}

OmniMock fakeBackend() {
  final users = {1: 'Ana', 2: 'Bo', 3: 'Cy', 4: 'Di', 5: 'Ed'};
  var token = 'token-1';
  return OmniMock(basePath: '/v1')
    // Auth: only the current token is accepted.
    ..post('/auth/refresh', (_) {
      token = 'token-2';
      return MockResponse.json({'access_token': token});
    })
    ..get('/users/{id}', (r) {
      if (r.headers['authorization'] != 'Bearer $token') {
        return const MockResponse.status(401);
      }
      final id = int.parse(r.pathParams['id']!);
      final name = users[id];
      return name == null
          ? MockResponse.json({'error': 'not found'}, status: 404)
          : MockResponse.json({'id': id, 'name': name});
    })
    ..get('/users', (r) {
      final page = int.parse(r.query['page'] ?? '1');
      final ids = users.keys.skip((page - 1) * 2).take(2);
      return MockResponse.json([
        for (final id in ids) {'id': id, 'name': users[id]},
      ]);
    })
    ..post('/users', (r) {
      final name = (r.json! as Map<String, dynamic>)['name'] as String;
      users[users.length + 1] = name;
      return MockResponse.json({'id': users.length, 'name': name}, status: 201);
    })
    ..get(
      '/flaky',
      OmniMock.sequence([
        const MockResponse.offline(),
        const MockResponse.status(503),
        MockResponse.json({'ok': true}),
      ]),
    );
}

Future<void> main() async {
  final backend = fakeBackend();
  var accessToken = 'token-1-expired';

  late final OmniNetwork api;
  api = OmniNetwork(
    baseUrl: 'https://api.example.com/v1',
    transport: backend,
    enableLogging: false, // the one logging switch (secrets are redacted)
    auth: BearerAuth(
      token: () => accessToken,
      refresh: () async {
        // Requests made inside refresh skip auth automatically.
        final r = await api.post<Map<String, dynamic>>('/auth/refresh');
        return accessToken = r['access_token'] as String;
      },
      onRefreshFailed: () => print('logged out'),
    ),
    retry: const RetryPolicy(baseDelay: Duration(milliseconds: 50)),
    cache: OmniCache(),
  );

  // 1. Typed GET. The first try gets 401, the token is refreshed once,
  //    and the request is replayed.
  final user = await api.get<User>('/users/1', decoder: User.fromJson);
  print('1. $user (token now $accessToken)');

  // 2. Endpoint registry + POST with a JSON body.
  final created = await api.call(UserApi.create, body: {'name': 'Fay'});
  final again = await api.call(UserApi.byId, path: {'id': created.id});
  print('2. created $created, fetched $again');

  // 3. Errors are typed; or use Result instead of try/catch.
  switch (await api.get<User>('/users/99', decoder: User.fromJson).asResult()) {
    case Ok(:final value):
      print('3. unexpected $value');
    case Err(:final error):
      print('3. failed as expected: $error');
  }

  // 4. Pagination.
  final pager = api.paginate<User>(
    '/users',
    decoder: User.fromJson,
    strategy: const PagePagination(pageSize: 2),
  );
  while (pager.hasMore) {
    await pager.next();
  }
  print('4. ${pager.pageCount} pages: ${pager.items.map((u) => u.name)}');
  await pager.close();

  // 5. Retry (GET only by default): offline, 503, then success.
  print('5. flaky -> ${await api.get<Map<String, dynamic>>('/flaky')}');

  // 6. Request state for UIs.
  final state = api.watch<User>('/users/2', decoder: User.fromJson);
  await state.load();
  print('6. state: ${state.state}');
  await state.close();

  // 7. Per-call options: no auth, no retry, full response.
  final res = await api.getResponse<User>(
    '/users/3',
    decoder: User.fromJson,
    retry: RetryPolicy.none,
    cache: CachePolicy.noCache,
  );
  print(
    '7. ${res.statusCode} ${res.data} in ${res.duration.inMilliseconds} ms',
  );
  final anonymous = await api
      .get<User>('/users/3', decoder: User.fromJson, auth: false)
      .asResult();
  print('   without auth: ${anonymous is Err ? 'rejected (401)' : 'ok'}');

  await api.close();
}
