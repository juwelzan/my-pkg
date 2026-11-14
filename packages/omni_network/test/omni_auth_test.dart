import 'dart:async';
import 'dart:convert';

import 'package:omni_network/advanced.dart';
import 'package:omni_network/testing.dart';
import 'package:test/test.dart';

/// Fake API: accepts `Bearer <valid>`; `/auth/refresh` rotates tokens.
final class Server {
  String valid = 'A1';
  int refreshCalls = 0;
  String? refreshTokenSeen;
  bool refreshFails = false;
  final seen = <String?>[];
  late final mock = OmniMock()
    ..post('/auth/refresh', (r) async {
      refreshCalls++;
      refreshTokenSeen = (r.json! as Map)['refresh_token'] as String?;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (refreshFails) return const MockResponse.status(401);
      valid = 'A${refreshCalls + 1}';
      return MockResponse.json({'access_token': valid, 'expires_in': 60});
    })
    ..get('/me', (r) {
      seen.add(r.headers['authorization']);
      return r.headers['authorization'] == 'Bearer $valid'
          ? MockResponse.json(
              {'ok': true},
              headers: {'cache-control': 'max-age=60'},
            )
          : const MockResponse.status(401);
    });
}

void main() {
  late Server server;
  late DateTime now;
  late int logouts;
  late OmniNetwork api;

  OmniAuth makeAuth({TokenStorage? storage, bool withRefresh = true}) =>
      OmniAuth(
        now: () => now,
        storage: storage,
        onLogout: () => logouts++,
        refresh: !withRefresh
            ? null
            : (tokens, api) async {
                final r = await api.post<Map<String, dynamic>>(
                  '/auth/refresh',
                  body: {'refresh_token': tokens.refresh},
                );
                return Tokens(
                  access: r['access_token'] as String,
                  expiresIn: Duration(seconds: r['expires_in'] as int),
                );
              },
      );

  setUp(() {
    server = Server();
    now = DateTime(2026, 1, 1, 12);
    logouts = 0;
  });
  tearDown(() => api.close());

  OmniNetwork client(OmniAuth auth, {OmniCache? cache}) => api = OmniNetwork(
    baseUrl: 'https://h.io',
    transport: server.mock,
    auth: auth,
    cache: cache,
  );

  test(
    'every client has a token manager: login adds the header, logout removes it',
    () async {
      api = OmniNetwork(baseUrl: 'https://h.io', transport: server.mock);
      final states = <AuthState>[];
      api.auth.changes.listen(states.add);
      expect(api.auth.isLoggedIn, isFalse);
      await api.get<void>('/me').asResult();
      expect(server.seen.last, isNull);

      await api.auth.login(const Tokens(access: 'A1'));
      expect(await api.get<Map<String, dynamic>>('/me'), {'ok': true});
      expect(server.seen.last, 'Bearer A1');

      await api.auth.logout();
      await api.get<void>('/me').asResult();
      expect(server.seen.last, isNull);
      expect(states, [AuthState.signedIn, AuthState.signedOut]);
    },
  );

  test(
    '401 refreshes once with the stored refresh token and replays',
    () async {
      client(makeAuth());
      await api.auth.login(const Tokens(access: 'OLD', refresh: 'R1'));
      final results = await Future.wait([
        for (var i = 0; i < 5; i++) api.get<Map<String, dynamic>>('/me'),
      ]);
      expect(results, everyElement({'ok': true}));
      expect(server.refreshCalls, 1);
      expect(server.refreshTokenSeen, 'R1');
      expect(api.auth.tokens!.access, 'A2');
      // The server did not rotate the refresh token: the old one is kept.
      expect(api.auth.tokens!.refresh, 'R1');
      expect(api.auth.tokens!.expiresAt, now.add(const Duration(seconds: 60)));
      expect(logouts, 0);
    },
  );

  test(
    'refreshes shortly before expiry so the user never sees a 401',
    () async {
      client(makeAuth());
      await api.auth.login(
        Tokens(
          access: 'A1',
          refresh: 'R',
          expiresIn: const Duration(minutes: 5),
        ),
      );
      await api.get<void>('/me');
      expect(server.refreshCalls, 0);

      now = now.add(
        const Duration(minutes: 4, seconds: 40),
      ); // 20 s left < 30 s
      server.valid =
          'A2'; // the server would still accept A1, but we refresh first
      await Future.wait([for (var i = 0; i < 3; i++) api.get<void>('/me')]);
      expect(server.refreshCalls, 1);
      expect(
        server.seen.skip(1),
        everyElement('Bearer A2'),
      ); // no 401 round trip
    },
  );

  test('refresh failure: tokens cleared, onLogout once, AuthFailure', () async {
    client(makeAuth());
    await api.auth.login(const Tokens(access: 'OLD', refresh: 'R'));
    server.refreshFails = true;
    final results = await Future.wait([
      for (var i = 0; i < 4; i++) api.get<void>('/me').asResult(),
    ]);
    for (final r in results) {
      final e = (r as Err).error;
      expect(e, isA<AuthFailure>());
      expect(e.isUnauthorized, isTrue);
    }
    expect(logouts, 1);
    expect(api.auth.isLoggedIn, isFalse);
    // Later calls go out without a token and do not log out again.
    await api.get<void>('/me').asResult();
    expect(server.seen.last, isNull);
    expect(logouts, 1);
  });

  test(
    'without refresh, a 401 is a plain HttpFailure and keeps the session',
    () async {
      client(makeAuth(withRefresh: false));
      await api.auth.login(const Tokens(access: 'WRONG'));
      final r = await api.get<void>('/me').asResult();
      expect((r as Err).error, isA<HttpFailure>());
      expect(api.auth.isLoggedIn, isTrue);
      expect(logouts, 0);
    },
  );

  test(
    'logout clears the cache and calls onLogout only when signed in',
    () async {
      final cache = OmniCache();
      client(makeAuth(), cache: cache);
      await api.auth.logout();
      expect(logouts, 0);
      await api.auth.login(const Tokens(access: 'A1'));
      // Authenticated responses are not cached by default; prove clear() runs
      // with an unauthenticated entry.
      server.mock.get(
        '/public',
        (_) => MockResponse.json(1, headers: {'cache-control': 'max-age=60'}),
      );
      await api.get<int>('/public', auth: false);
      expect(
        (await api.getResponse<int>('/public', auth: false)).source,
        ResponseSource.cache,
      );
      await api.auth.logout();
      expect(logouts, 1);
      expect(
        (await api.getResponse<int>('/public', auth: false)).source,
        ResponseSource.network,
      );
    },
  );

  test(
    'restores tokens from storage on first use; writes on login/logout',
    () async {
      final storage = _RecordingStorage(
        const Tokens(access: 'A1', refresh: 'R'),
      );
      client(makeAuth(storage: storage));
      expect(api.auth.isLoggedIn, isFalse); // not loaded yet
      expect(await api.get<Map<String, dynamic>>('/me'), {'ok': true});
      expect(server.seen.single, 'Bearer A1');
      expect(api.auth.isLoggedIn, isTrue);
      await api.auth.logout();
      expect(storage.writes.last, isNull);
      await api.auth.login(const Tokens(access: 'X'));
      expect(storage.writes.last!.access, 'X');
      expect(await api.auth.restore(), isTrue);
    },
  );

  test('auth: false skips the token', () async {
    client(makeAuth());
    await api.auth.login(const Tokens(access: 'A1'));
    await api.get<void>('/me', auth: false).asResult();
    expect(server.seen.last, isNull);
  });

  test('Tokens: JSON round trip and no secrets in toString', () {
    final t = Tokens(
      access: 'SECRET-A',
      refresh: 'SECRET-R',
      expiresAt: DateTime.utc(2026, 5),
    );
    final back = Tokens.fromJson(
      jsonDecode(jsonEncode(t.toJson())) as Map<String, Object?>,
    );
    expect(
      (back.access, back.refresh, back.expiresAt),
      (t.access, t.refresh, t.expiresAt),
    );
    expect('$t', isNot(contains('SECRET')));
  });

  test('api.auth with token: or BearerAuth throws a clear StateError; '
      'one OmniAuth per client', () async {
    final a = OmniNetwork(
      baseUrl: 'https://h.io',
      transport: server.mock,
      token: () => 'x',
    );
    addTearDown(a.close);
    expect(() => a.auth, throwsStateError);
    final shared = OmniAuth();
    api = OmniNetwork(
      baseUrl: 'https://h.io',
      transport: server.mock,
      auth: shared,
    );
    expect(
      () => OmniNetwork(
        baseUrl: 'https://h.io',
        transport: server.mock,
        auth: shared,
      ),
      throwsStateError,
    );
  });

  test('close completes the changes stream', () async {
    client(makeAuth());
    final done = api.auth.changes.toList();
    await api.close();
    expect(await done, isEmpty);
  });
}

final class _RecordingStorage implements TokenStorage {
  _RecordingStorage(this._t);
  Tokens? _t;
  final writes = <Tokens?>[];
  @override
  Future<Tokens?> read() async => _t;
  @override
  Future<void> write(Tokens? t) async {
    writes.add(t);
    _t = t;
  }
}
