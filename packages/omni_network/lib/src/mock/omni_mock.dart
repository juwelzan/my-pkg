import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../core/cancel_signal.dart';
import '../core/omni_network_exception.dart';
import '../core/omni_request.dart';
import '../core/omni_response.dart';
import '../endpoint/endpoint.dart';
import '../transport/mock_transport.dart';
import '../transport/transport.dart';

/// A request received by [OmniMock].
@immutable
final class MockRequest {
  /// Creates a mock request.
  const MockRequest(this.raw, this.path, this.pathParams);

  /// The transport-level request.
  final TransportRequest raw;

  /// Path relative to [OmniMock.basePath].
  final String path;

  /// Values of `{params}` from the matched template (decoded).
  final Map<String, String> pathParams;

  /// HTTP method.
  HttpMethod get method => raw.method;

  /// Query parameters (first value per key).
  Map<String, String> get query => raw.uri.queryParameters;

  /// Request headers (lower-case names).
  Map<String, String> get headers => raw.headers;

  /// Body as text.
  String get text => utf8.decode(raw.body ?? const [], allowMalformed: true);

  /// Body parsed as JSON (`null` when empty).
  Object? get json => (raw.body?.isEmpty ?? true) ? null : jsonDecode(text);
}

/// What [OmniMock] answers. Build with the factories.
@immutable
final class MockResponse {
  const MockResponse._({
    this.status = 200,
    this.headers = const {},
    this.body,
    this.error,
    this.delay = Duration.zero,
    this.hang = false,
  });

  /// JSON response.
  factory MockResponse.json(
    Object? body, {
    int status = 200,
    Map<String, String> headers = const {},
    Duration delay = Duration.zero,
  }) => MockResponse._(
    status: status,
    headers: {'content-type': 'application/json', ...headers},
    body: utf8.encode(jsonEncode(body)),
    delay: delay,
  );

  /// Text response.
  factory MockResponse.text(
    String body, {
    int status = 200,
    Map<String, String> headers = const {},
    Duration delay = Duration.zero,
  }) => MockResponse._(
    status: status,
    headers: {'content-type': 'text/plain; charset=utf-8', ...headers},
    body: utf8.encode(body),
    delay: delay,
  );

  /// Raw bytes response.
  factory MockResponse.bytes(
    List<int> body, {
    int status = 200,
    String contentType = 'application/octet-stream',
    Map<String, String> headers = const {},
    Duration delay = Duration.zero,
  }) => MockResponse._(
    status: status,
    headers: {
      'content-type': contentType,
      'content-length': '${body.length}',
      ...headers,
    },
    body: body,
    delay: delay,
  );

  /// Empty response with [status] (e.g. 204, 404, 503).
  const MockResponse.status(
    int status, {
    Map<String, String> headers = const {},
    Duration delay = Duration.zero,
  }) : this._(status: status, headers: headers, delay: delay);

  /// The request fails without a response (e.g. `ConnectionFailure`).
  const MockResponse.error(
    OmniNetworkException error, {
    Duration delay = Duration.zero,
  }) : this._(error: error, delay: delay);

  /// Simulates "no network": a [ConnectionFailure].
  const MockResponse.offline({Duration delay = Duration.zero})
    : this._(error: const ConnectionFailure('Mock: offline'), delay: delay);

  /// Never answers (the client's timeout or cancel ends the request).
  const MockResponse.hang() : this._(hang: true);

  /// Status code.
  final int status;

  /// Headers.
  final Map<String, String> headers;

  /// Body bytes.
  final List<int>? body;

  /// Failure to throw instead of answering.
  final OmniNetworkException? error;

  /// Extra latency for this response.
  final Duration delay;

  /// Whether it never answers.
  final bool hang;
}

/// Produces a [MockResponse] for a [MockRequest].
typedef MockRouteHandler = FutureOr<MockResponse> Function(MockRequest request);

final class _Route {
  _Route(this.method, this.template, this.handler)
    : names = [for (final m in _param.allMatches(template)) m[1]!],
      pattern = RegExp(
        '^${template.split(_param).map(RegExp.escape).join('([^/]+)')}\$',
      );

  static final _param = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');
  final HttpMethod? method;
  final String template;
  final List<String> names;
  final RegExp pattern;
  final MockRouteHandler handler;

  Map<String, String>? match(HttpMethod m, String path) {
    if (method != null && method != m) return null;
    final r = pattern.firstMatch(path);
    if (r == null) return null;
    return {
      for (var i = 0; i < names.length; i++)
        names[i]: Uri.decodeComponent(r[i + 1]!),
    };
  }
}

/// A recorded call.
@immutable
final class MockCall {
  /// Creates a record.
  const MockCall(this.request, this.template);

  /// The request.
  final MockRequest request;

  /// Matched route template, or `null` when unmatched.
  final String? template;
}

/// A programmable fake backend that plugs in as a [Transport]: routes with
/// path templates, scenarios, latency, response sequences and failure
/// injection. No sockets, no internet.
///
/// ```dart
/// final mock = OmniMock(basePath: '/v1')
///   ..get('/users/{id}', (r) => MockResponse.json({'id': r.pathParams['id']}))
///   ..post('/users', (r) => MockResponse.json(r.json, status: 201))
///   ..scenario('offline', (s) => s.any((_) => const MockResponse.offline()));
///
/// final api = OmniNetwork(baseUrl: 'https://api.test/v1', transport: mock);
/// mock.use('offline'); // switch behaviour mid-test
/// ```
///
/// Routes added later win over earlier ones; the active scenario's routes
/// win over the base routes. With [strict] (default) an unmatched request
/// fails with [RequestFailure] naming it; otherwise it gets a 404.
final class OmniMock implements Transport {
  /// Creates a mock backend.
  OmniMock({
    this.basePath = '',
    this.strict = true,
    this.latency = Duration.zero,
    this.failureRate = 0,
    Random? random,
    int chunkSize = 16 * 1024,
  }) : _random = random ?? Random(),
       assert(failureRate >= 0 && failureRate <= 1) {
    _transport = MockTransport(_handle, chunkSize: chunkSize);
  }

  /// Prefix removed from request paths before matching (e.g. `/v1`).
  final String basePath;

  /// Fail unmatched requests loudly instead of answering 404.
  final bool strict;

  /// Latency added to every response.
  Duration latency;

  /// Probability (0–1) that a request fails with [ConnectionFailure].
  double failureRate;

  final Random _random;
  late final MockTransport _transport;
  final List<_Route> _routes = [];
  final Map<String, OmniMock> _scenarios = {};
  final List<OmniNetworkException> _failNext = [];
  String? _active;

  /// Every call, in order.
  final List<MockCall> calls = [];

  /// Requests no route matched.
  List<MockRequest> get unmatched => [
    for (final c in calls)
      if (c.template == null) c.request,
  ];

  /// Name of the active scenario, or `null`.
  String? get activeScenario => _active;

  /// Adds a route for [method] (or any method when `null`) and [template].
  void on(HttpMethod? method, String template, MockRouteHandler handler) =>
      _routes.add(_Route(method, template, handler));

  /// GET route.
  void get(String template, MockRouteHandler handler) =>
      on(HttpMethod.get, template, handler);

  /// POST route.
  void post(String template, MockRouteHandler handler) =>
      on(HttpMethod.post, template, handler);

  /// PUT route.
  void put(String template, MockRouteHandler handler) =>
      on(HttpMethod.put, template, handler);

  /// PATCH route.
  void patch(String template, MockRouteHandler handler) =>
      on(HttpMethod.patch, template, handler);

  /// DELETE route.
  void delete(String template, MockRouteHandler handler) =>
      on(HttpMethod.delete, template, handler);

  /// Route for every method and path (use in scenarios).
  void any(MockRouteHandler handler) =>
      _routes.add(_Route(null, '{_any}', handler));

  /// Route for [endpoint]'s method and path template.
  void endpoint(Endpoint<Object?> endpoint, MockRouteHandler handler) =>
      on(endpoint.method, endpoint.path, handler);

  /// A handler answering [responses] in order, then repeating the last
  /// (e.g. `[offline, status(503), json(data)]` to test recovery).
  static MockRouteHandler sequence(List<MockResponse> responses) {
    assert(responses.isNotEmpty);
    var i = 0;
    return (_) => responses[min(i++, responses.length - 1)];
  }

  /// Defines a named scenario; its routes take precedence while active.
  void scenario(String name, void Function(OmniMock s) define) {
    final s = OmniMock(basePath: basePath, strict: false);
    define(s);
    _scenarios[name] = s;
  }

  /// Activates scenario [name] (`null` = base routes only).
  void use(String? name) {
    if (name != null && !_scenarios.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'unknown scenario');
    }
    _active = name;
  }

  /// The next [times] requests fail with [error] (default: offline).
  void failNext([
    int times = 1,
    OmniNetworkException error = const ConnectionFailure('Mock: injected'),
  ]) {
    for (var i = 0; i < times; i++) {
      _failNext.add(error);
    }
  }

  /// Calls matching [method] and [template] (as registered).
  List<MockRequest> callsTo(HttpMethod method, String template) => [
    for (final c in calls)
      if (c.template == template && c.request.method == method) c.request,
  ];

  /// Clears recorded calls and pending injected failures.
  void resetCalls() {
    calls.clear();
    _failNext.clear();
  }

  String _relative(Uri uri) {
    final p = uri.path;
    if (basePath.isNotEmpty && p.startsWith(basePath)) {
      final rest = p.substring(basePath.length);
      return rest.isEmpty ? '/' : rest;
    }
    return p;
  }

  (_Route, Map<String, String>)? _find(HttpMethod m, String path) {
    for (final r in _routes.reversed) {
      if (r.template == '{_any}') return (r, const {});
      final params = r.match(m, path);
      if (params != null) return (r, params);
    }
    return null;
  }

  Future<OmniRawResponse> _handle(TransportRequest raw) async {
    final path = _relative(raw.uri);
    final scenario = _active == null ? null : _scenarios[_active];
    final found = scenario?._find(raw.method, path) ?? _find(raw.method, path);
    final request = MockRequest(raw, path, found?.$2 ?? const {});
    calls.add(MockCall(request, found?.$1.template));
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (_failNext.isNotEmpty) throw _failNext.removeAt(0);
    if (failureRate > 0 && _random.nextDouble() < failureRate) {
      throw const ConnectionFailure('Mock: random failure');
    }
    if (found == null) {
      if (strict) {
        throw RequestFailure('OmniMock: no route for ${raw.method.verb} $path');
      }
      return OmniRawResponse(statusCode: 404);
    }
    final res = await found.$1.handler(request);
    if (res.delay > Duration.zero) await Future<void>.delayed(res.delay);
    if (res.hang) await Completer<void>().future;
    if (res.error case final e?) throw e;
    final body = res.body;
    return OmniRawResponse(
      statusCode: res.status,
      headers: res.headers,
      bodyBytes: body == null
          ? null
          : body is Uint8List
          ? body
          : Uint8List.fromList(body),
    );
  }

  @override
  Future<OmniRawResponse> send(TransportRequest request, CancelSignal cancel) =>
      _transport.send(request, cancel);

  @override
  Future<StreamedResponse> sendStreamed(
    TransportRequest request,
    CancelSignal cancel,
  ) => _transport.sendStreamed(request, cancel);

  @override
  Future<void> close({bool force = false}) => _transport.close(force: force);
}
