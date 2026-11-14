import 'dart:async';
import 'dart:convert';

import 'package:omni_network/omni_network.dart';
import 'package:test/test.dart';

OmniRawResponse json(Object body, [int status = 200]) => OmniRawResponse(
  statusCode: status,
  headers: {'content-type': 'application/json'},
  bodyBytes: utf8.encode(jsonEncode(body)),
);

String kind(RequestState<Object?> s) => switch (s) {
  RequestIdle() => 'idle',
  RequestLoading(:final previous) => 'loading($previous)',
  RequestSuccess(:final data) => 'success($data)',
  RequestEmpty() => 'empty',
  RequestError(:final error, :final previous) =>
    'error(${error.runtimeType},$previous)',
};

void main() {
  late MockTransport mock;
  late OmniNetwork api;

  setUp(() {
    mock = MockTransport((_) => json({'n': 1}));
    api = OmniNetwork(baseUrl: 'https://h.io', transport: mock);
  });
  tearDown(() => api.close());

  Future<List<String>> collect(
    RequestController<Object?> c,
    Future<void> Function() action,
  ) async {
    final seen = <String>[];
    final sub = c.stream.listen((s) => seen.add(kind(s)));
    await action();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    return seen;
  }

  test('idle -> loading -> success', () async {
    final c = api.watch<Map<String, dynamic>>('/a', autoLoad: false);
    addTearDown(c.close);
    expect(await collect(c, c.load), [
      'idle',
      'loading(null)',
      'success({n: 1})',
    ]);
    expect(c.state.data, {'n': 1});
  });

  test(
    'autoLoad starts immediately; late listener gets current state',
    () async {
      final c = api.watch<Map<String, dynamic>>('/a');
      addTearDown(c.close);
      expect(c.state, isA<RequestLoading<Map<String, dynamic>>>());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(await c.stream.first, isA<RequestSuccess<Map<String, dynamic>>>());
    },
  );

  test('empty detection: list, null, custom', () async {
    mock.handler = (_) => json([]);
    final list = api.watchList<int>('/l', decoder: (j) => j['v'] as int);
    addTearDown(list.close);
    await list.load();
    expect(list.state, isA<RequestEmpty<List<int>>>());

    mock.handler = (_) => OmniRawResponse(statusCode: 204);
    final none = api.watch<Map<String, dynamic>?>('/n');
    addTearDown(none.close);
    await none.load();
    expect(none.state, isA<RequestEmpty<Map<String, dynamic>?>>());

    mock.handler = (_) => json({'items': []});
    final custom = api.watch<Map<String, dynamic>>(
      '/c',
      isEmpty: (m) => (m['items'] as List).isEmpty,
    );
    addTearDown(custom.close);
    await custom.load();
    expect(custom.state, isA<RequestEmpty<Map<String, dynamic>>>());
  });

  test('refresh shows previous data; failure keeps it', () async {
    final c = api.watch<Map<String, dynamic>>('/a', autoLoad: false);
    addTearDown(c.close);
    await c.load();
    mock.handler = (_) => json({'e': 1}, 500);
    expect(await collect(c, c.refresh), [
      'success({n: 1})',
      'loading({n: 1})',
      'error(HttpFailure,{n: 1})',
    ]);
    final err = c.state as RequestError<Map<String, dynamic>>;
    expect(err.networkError, isA<HttpFailure>());
    expect(err.stackTrace, isNotNull);
    // Recovery.
    mock.handler = (_) => json({'n': 2});
    await c.refresh();
    expect(c.state.data, {'n': 2});
  });

  test('load() while loading shares the run; refresh() restarts and the '
      'stale result never emits', () async {
    final first = Completer<OmniRawResponse>();
    var calls = 0;
    mock.handler = (_) => ++calls == 1 ? first.future : json({'n': 2});
    // Without dedup the refreshed GET is a separate network call (with
    // dedup it would join the identical in-flight one).
    final plain = OmniNetwork(
      baseUrl: 'https://h.io',
      transport: mock,
      deduplicate: false,
    );
    addTearDown(plain.close);
    final c = plain.watch<Map<String, dynamic>>('/a', autoLoad: false);
    addTearDown(c.close);
    final seen = <String>[];
    c.stream.listen((s) => seen.add(kind(s)));
    final a = c.load();
    expect(identical(a, c.load()), isTrue);
    await Future<void>.delayed(Duration.zero);
    await c.refresh();
    first.complete(json({'n': 1}));
    await a;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(seen, ['idle', 'loading(null)', 'loading(null)', 'success({n: 2})']);
    expect(calls, 2);
  });

  test('with dedup, refresh during a load reuses the in-flight call', () async {
    final gate = Completer<OmniRawResponse>();
    mock.handler = (_) => gate.future;
    final c = api.watch<Map<String, dynamic>>('/a', autoLoad: false);
    addTearDown(c.close);
    final a = c.load();
    await Future<void>.delayed(Duration.zero);
    final b = c.refresh();
    await Future<void>.delayed(Duration.zero);
    gate.complete(json({'n': 3}));
    await Future.wait([a, b]);
    expect(c.state.data, {'n': 3});
    expect(mock.requests, hasLength(1));
  });

  test('non-network errors become RequestError too', () async {
    final c = RequestController<int>((_) async => throw StateError('bug'));
    addTearDown(c.close);
    await c.load();
    final s = c.state as RequestError<int>;
    expect(s.error, isA<StateError>());
    expect(s.networkError, isNull);
  });

  test('multiple listeners each get every change', () async {
    final c = api.watch<Map<String, dynamic>>('/a', autoLoad: false);
    addTearDown(c.close);
    final a = <String>[];
    final b = <String>[];
    c.stream.listen((s) => a.add(kind(s)));
    c.stream.listen((s) => b.add(kind(s)));
    await c.load();
    await Future<void>.delayed(Duration.zero);
    expect(a, b);
    expect(a, hasLength(3));
  });

  test('close cancels the request, completes streams, rejects loads', () async {
    mock.handler = (_) => Completer<OmniRawResponse>().future;
    final c = api.watch<Map<String, dynamic>>('/slow');
    final done = c.stream.toList();
    await Future<void>.delayed(Duration.zero);
    expect(api.pendingRequests, 1);
    await c.close();
    await Future<void>.delayed(Duration.zero);
    expect(api.pendingRequests, 0);
    expect(mock.inFlight, 0);
    expect((await done).map(kind), ['loading(null)']);
    expect(c.load, throwsStateError);
    expect(c.refresh, throwsStateError);
    expect(c.hasListeners, isFalse);
    // Listening after close: current state, then done.
    expect(await c.stream.toList(), hasLength(1));
    await c.close(); // idempotent
  });
}
