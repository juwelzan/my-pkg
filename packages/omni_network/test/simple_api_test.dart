import 'package:omni_network/omni_network.dart';
import 'package:omni_network/testing.dart';
import 'package:test/test.dart';

/// S3: the token shortcut and the friendly error getters, with only the
/// simple import.
void main() {
  late OmniMock mock;
  setUp(() {
    mock = OmniMock()
      ..get(
        '/me',
        (r) => r.headers['authorization'] == 'Bearer good'
            ? MockResponse.json({'ok': true})
            : const MockResponse.status(401),
      );
  });

  group('token: shortcut', () {
    test('adds the bearer header and reads the token on every call', () async {
      var token = 'good';
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        token: () => token,
      );
      addTearDown(api.close);
      expect(await api.get<Map<String, dynamic>>('/me'), {'ok': true});
      token = 'changed';
      await api.get<void>('/me').asResult();
      expect(
        mock.calls.last.request.headers['authorization'],
        'Bearer changed',
      );
    });

    test('async token, null token and auth: false', () async {
      String? token;
      final api = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        token: () async => token,
      );
      addTearDown(api.close);
      await api.get<void>('/me').asResult();
      expect(
        mock.calls.last.request.headers.containsKey('authorization'),
        isFalse,
      );
      token = 'good';
      await api.get<void>('/me', auth: false).asResult();
      expect(
        mock.calls.last.request.headers.containsKey('authorization'),
        isFalse,
      );
    });

    test(
      '401 is an HttpFailure (no refresh), flagged isUnauthorized',
      () async {
        final api = OmniNetwork(
          baseUrl: 'https://h.io',
          transport: mock,
          token: () => 'bad',
        );
        addTearDown(api.close);
        try {
          await api.get<void>('/me');
          fail('should throw');
        } on OmniNetworkException catch (e) {
          expect(e, isA<HttpFailure>());
          expect(
            (e.statusCode, e.isUnauthorized, e.isOffline),
            (401, true, false),
          );
        }
        expect(mock.calls, hasLength(1));
      },
    );

    test('token and auth together are rejected (debug)', () {
      var asserts = false;
      assert(asserts = true);
      if (!asserts) return markTestSkipped('asserts disabled');
      expect(
        () => OmniNetwork(token: () => 'a', auth: OmniAuth()),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('error getters', () {
    final cases = <String, (OmniNetworkException, int?, bool, bool, bool, bool)>{
      // name: (error, statusCode, isOffline, isTimeout, isCancelled, isUnauthorized)
      'connection': (
        const ConnectionFailure('x'),
        null,
        true,
        false,
        false,
        false,
      ),
      'timeout': (
        TimeoutFailure(const Duration(seconds: 1)),
        null,
        true,
        true,
        false,
        false,
      ),
      'cancelled': (const CancelledFailure(), null, false, false, true, false),
      'closed': (const ClosedFailure(), null, false, false, true, false),
      'http 404': (
        HttpFailure(OmniRawResponse(statusCode: 404)),
        404,
        false,
        false,
        false,
        false,
      ),
      'http 401': (
        HttpFailure(OmniRawResponse(statusCode: 401)),
        401,
        false,
        false,
        false,
        true,
      ),
      'auth': (
        AuthFailure('x', response: OmniRawResponse(statusCode: 401)),
        401,
        false,
        false,
        false,
        true,
      ),
      'decode': (const DecodeFailure('x'), null, false, false, false, false),
      'request': (const RequestFailure('x'), null, false, false, false, false),
    };
    for (final MapEntry(key: name, value: c) in cases.entries) {
      test(name, () {
        final (e, status, offline, timeout, cancelled, unauthorized) = c;
        expect(
          (
            e.statusCode,
            e.isOffline,
            e.isTimeout,
            e.isCancelled,
            e.isUnauthorized,
          ),
          (status, offline, timeout, cancelled, unauthorized),
        );
        expect(e.message, isNotEmpty);
      });
    }

    test('real offline call', () async {
      mock.get('/down', (_) => const MockResponse.offline());
      final api = OmniNetwork(baseUrl: 'https://h.io', transport: mock);
      addTearDown(api.close);
      final r = await api.get<void>('/down').asResult();
      expect((r as Err).error.isOffline, isTrue);
    });
  });
}
