import 'dart:async';
import 'dart:convert';

import 'package:omni_network/advanced.dart';
import 'package:omni_network/testing.dart';
import 'package:test/test.dart';

void main() {
  late MockTransport mock;
  late OmniNetwork api;

  setUp(() {
    mock = MockTransport(
      (_) => OmniRawResponse(
        statusCode: 200,
        headers: {'content-type': 'text/event-stream'},
        bodyBytes: utf8.encode('abcdefghij'),
      ),
      chunkSize: 3,
      chunkDelay: const Duration(milliseconds: 5),
    );
    api = OmniNetwork(
      baseUrl: 'https://h.io',
      transport: mock,
      timeout: const Duration(milliseconds: 20),
    );
  });
  tearDown(() => api.close());

  test('headers first, then chunks; no timeout by default', () async {
    final res = await api.openStream(const OmniRequest.get('/events'));
    expect(res.statusCode, 200);
    expect(res.headers['content-type'], 'text/event-stream');
    final chunks = await res.body.map(utf8.decode).toList();
    expect(chunks, ['abc', 'def', 'ghi', 'j']);
    await Future<void>.delayed(Duration.zero); // pipeline cleanup
    expect(api.pendingRequests, 0);
  });

  test('non-2xx throws HttpFailure; 401 goes through token refresh', () async {
    mock.handler = (_) => OmniRawResponse(statusCode: 404);
    await expectLater(
      api.openStream(const OmniRequest.get('/x')),
      throwsA(isA<HttpFailure>()),
    );

    var token = 'OLD';
    mock.handler = (r) => r.headers['authorization'] == 'Bearer NEW'
        ? OmniRawResponse(statusCode: 200, bodyBytes: utf8.encode('ok'))
        : OmniRawResponse(statusCode: 401);
    final authed = OmniNetwork(
      baseUrl: 'https://h.io',
      transport: mock,
      auth: BearerAuth(token: () => token, refresh: () => token = 'NEW'),
    );
    addTearDown(authed.close);
    final res = await authed.openStream(const OmniRequest.get('/events'));
    expect(
      utf8.decode((await res.body.toList()).expand((c) => c).toList()),
      'ok',
    );
  });

  test('cancelling the subscription aborts the request', () async {
    final res = await api.openStream(const OmniRequest.get('/events'));
    final got = <String>[];
    late StreamSubscription<List<int>> sub;
    sub = res.body.listen((c) {
      got.add(utf8.decode(c));
      sub.cancel();
    });
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(got, ['abc']);
    expect(api.pendingRequests, 0);
    expect(mock.inFlight, 0);
  });

  test('idleTimeout and close deliver errors into the body', () async {
    mock.chunkDelay = const Duration(milliseconds: 100);
    final res = await api.openStream(
      const OmniRequest.get('/events'),
      idleTimeout: const Duration(milliseconds: 30),
    );
    await expectLater(res.body.toList(), throwsA(isA<TimeoutFailure>()));

    mock.chunkDelay = const Duration(milliseconds: 10);
    final res2 = await api.openStream(const OmniRequest.get('/events'));
    final done = expectLater(res2.body.toList(), throwsA(isA<ClosedFailure>()));
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await api.close();
    await done;
  });
}
