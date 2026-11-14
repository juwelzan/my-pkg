import 'dart:async';

import 'package:omni_network/omni_network.dart';
import 'package:test/test.dart';

void main() {
  test('copyWith/withHeader keep every field (regression)', () {
    final token = OmniCancelToken();
    const policy = RetryPolicy(maxAttempts: 5);
    final r = OmniRequest.post(
      '/a',
      body: {'x': 1},
      query: {'q': 1},
      headers: {'A': '1'},
      timeout: const Duration(seconds: 3),
      skipAuth: true,
      cancelToken: token,
      retry: policy,
    ).withHeader('B', '2');
    expect(r.method, HttpMethod.post);
    expect(r.path, '/a');
    expect(r.body, {'x': 1});
    expect(r.query, {'q': 1});
    expect(r.headers, {'A': '1', 'B': '2'});
    expect(r.timeout, const Duration(seconds: 3));
    expect(r.skipAuth, isTrue);
    expect(r.cancelToken, same(token));
    expect(r.retry, same(policy));
    expect(r.copyWith(body: null).body, isNull);
  });

  test('cancelToken still works with auth and header interceptors '
      '(regression: withHeader dropped the token)', () async {
    final mock = MockTransport((_) => Completer<OmniRawResponse>().future);
    final api = OmniNetwork(
      baseUrl: 'https://h.io',
      transport: mock,
      auth: BearerAuth(token: () => 'T', refresh: () => null),
      interceptors: [_AddHeader()],
    );
    addTearDown(api.close);
    final token = OmniCancelToken();
    final f = api.get<dynamic>('/a', cancelToken: token);
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    await expectLater(
      f.timeout(const Duration(seconds: 2)),
      throwsA(isA<CancelledFailure>()),
    );
  });
}

final class _AddHeader extends OmniInterceptor {
  @override
  OmniRequest onRequest(OmniRequest r) => r.withHeader('X', '1');
}
