# OmniNetwork — Design Document (v0, awaiting approval)

Status: **design only**. No implementation code exists yet. Nothing under the
root `lib/` or `test/` (OmniRoute) is touched by this work.

Versions in this document were checked on pub.dev on 2026-11-14.

---

## 1. Architecture audit of the existing project

| Area | Finding | Consequence for OmniNetwork |
|---|---|---|
| SDK | `sdk: ^3.12.0`, `flutter: ">=3.44.0"`; local toolchain Flutter 3.50.0 / Dart 3.13.4 | Core uses `sdk: ^3.12.0` too (same floor, no Flutter constraint). Allows sealed classes, records, patterns, extension types. |
| Dependencies | Few, caret-pinned, all well-maintained (go_router, flutter_bloc, meta) | Same policy: minimal deps, caret constraints, no unmaintained packages. |
| Lints | `flutter_lints` + `public_member_api_docs` | Core uses `package:lints/recommended.yaml` (pure Dart) + `public_member_api_docs`; Flutter adapters use `flutter_lints`. |
| Naming | Public types prefixed `Omni*`; one barrel file `lib/omni_route.dart` with explicit `show`/`hide`; implementation in `lib/src/<area>/` | Same: `lib/omni_network.dart` barrel, `lib/src/{core,auth,log,retry,cache,...}`. Prefix `Omni*` only on top-level entry types (`OmniNetwork`, `OmniRequest`, `OmniResponse`, `OmniNetworkException`); avoid prefix noise on small value types where unambiguous. |
| Errors | Dedicated exception with error codes (`OmniErrorCode`) | `OmniNetworkException` sealed hierarchy + `OmniNetworkErrorCode`. |
| Tests | 78 tests; `test/flutter_test_config.dart` enables `LeakTesting` with `withTrackedAll()` for every test; separate perf/platform/web test files | Core is pure Dart → `package:test`; leak tracking is a Flutter tool, so core uses explicit **disposal tests** (every `close()` cancels timers, subscriptions, in-flight requests; asserted via counters/`fake_async`). Flutter adapter packages reuse the same `flutter_test_config.dart` pattern. |
| Docs | `doc/` with architecture, migration, platforms, performance, release; CHANGELOG with Fix/New entries | Mirror: `packages/omni_network/doc/` + its own CHANGELOG. |
| Release | `publish_to: none` until release checklist | Same; each package versioned independently starting at `0.1.0-dev`. |
| Public API compat | Changelog-driven, explicit exports, `hide` for internals | Explicit `show` exports; anything not exported is internal; `@experimental` (from `meta`) on adapters until 1.0. |

## 2. Feature feasibility matrix (25 phases)

Legend: ✅ feasible in pure Dart core · 🧩 feasible as optional package ·
🖥 needs server cooperation · 📱 needs platform support · ⏸ recommend defer ·
❌ recommend not doing (as specified)

| # | Feature | Verdict | Notes |
|---|---|---|---|
| 1 | HTTP client (GET/POST/PUT/PATCH/DELETE/HEAD, query, headers, timeouts) | ✅ | Thin layer over a `Transport` interface; Dio default implementation. |
| 2 | Serialization (JSON decode/encode, typed decoders) | ✅ | Decoder functions (`User.fromJson`) — **no mandatory codegen**. Works with json_serializable/freezed output if the user chooses them. |
| 3 | Response adapters (envelope unwrapping e.g. `{data, meta, error}`) | ✅ | `ResponseAdapter` strategy configured once per client/endpoint. |
| 4 | Auth + token refresh | ✅ 🖥 | Single-flight refresh (one refresh for N concurrent 401s), queue waiting requests, logout callback on refresh failure. Requires the server to signal expiry (401 or configurable predicate). |
| 5 | Pagination | ✅ 🖥 | Strategies: page/limit, offset, cursor, Link header. Must match server contract; no universal auto-detection. |
| 6 | Request state (idle/loading/success/error/empty, refresh) | ✅ core + 🧩 bloc | Core: `Stream<RequestState<T>>`/`ValueListenable`-free plain Dart. Bloc/Cubit mapping in `omni_network_bloc`. |
| 7 | Upload (multipart, progress, cancel) | ✅ | Dio `FormData` + `onSendProgress`. Web: progress works via XHR adapter. |
| 8 | Download (to file, progress, resume via Range) | ✅ 📱 🖥 | File paths are `dart:io` only — not on Web (Web returns bytes/stream). Resume needs server `Accept-Ranges`. **No OS background transfers** (needs platform plugins; ⏸). |
| 9 | WebSocket adapter | 🧩 | `web_socket_channel` 3.0.3; reconnect with backoff; separate package. |
| 10 | SSE adapter | 🧩 🖥 | Streamed response parsing on IO; on Web via streaming fetch/XHR — CORS applies. |
| 11 | GraphQL adapter | 🧩 ⏸ | Simple query/mutation over the core client is cheap; normalized cache/subscriptions → defer to `graphql` (5.2.4) users. |
| 12 | gRPC adapter | ⏸ ❌ for now | `grpc` 5.2.0 has its own transport/codegen (protoc); wrapping adds little. Web needs grpc-web proxy 🖥. Recommend documenting interop only. |
| 13 | Request builder (fluent) | ✅ | Thin sugar over `OmniRequest`; optional. |
| 14 | Interceptors | ✅ | Own `OmniInterceptor` chain (transport-independent), not Dio interceptors exposed publicly. |
| 15 | Retry / resilience (backoff, jitter, circuit breaker, timeout) | ✅ | **Only idempotent methods retried by default** (GET/HEAD/OPTIONS/PUT/DELETE per RFC 9110 — DELETE/PUT opt-in configurable); POST/PATCH never retried unless request carries an `Idempotency-Key` and the user opts in. Respect `Retry-After`. |
| 16 | Cancellation | ✅ | `CancelToken`-like `OmniCancelToken`; cancel groups; auto-cancel on `close()`. |
| 17 | Offline queue | ✅ ⏸ partially | Queue only **explicitly marked** requests; destructive ops require explicit `queueOffline: QueuePolicy.explicit` + idempotency key; never silent. Persistent storage = pluggable `QueueStore` (in-memory default; Flutter storage in adapter). Connectivity detection 📱 (`connectivity_plus` 7.3.2) lives in the Flutter adapter. |
| 18 | Cache (memory, HTTP semantics ETag/Cache-Control, stale-while-revalidate) | ✅ | Memory store in core; disk store pluggable. Never cache responses with `Authorization` unless explicitly allowed. |
| 19 | Validation (request/response schema checks) | ✅ | Validator callbacks; no JSON-Schema engine in v1 (⏸). |
| 20 | Endpoint registry | ✅ | Typed `Endpoint<Req, Res>` constants; enables mocking, inspector, docs. |
| 21 | OpenAPI → Dart CLI | 🧩 ⏸ | Large effort; separate dev package `omni_network_openapi` with `build`-free CLI generating Endpoint registry + models. Do after core is stable. |
| 22 | Logger (`enableLogging` single switch, redaction) | ✅ | Default off. Redacts `Authorization`, `Cookie`, `Set-Cookie`, `*token*`, `password`, `secret`, `api_key` in headers, query and JSON bodies; body truncation; never logs binary/multipart content. Pluggable `LogSink` (default `print`/`dart:developer` log). |
| 23 | Mocking | ✅ | `MockTransport` with route matchers, latency, error injection; also used by our own tests. |
| 24 | cURL import / export | ✅ | Export with redaction by default (`redact: true`); import parses a safe subset (`-X -H -d --data-raw -F -u`). |
| 25 | Dev inspector (in-app request list UI) | 🧩 | Core emits an event stream (`NetworkEvent`); Flutter UI in `omni_network_flutter`; disabled/no-op in release by default. |
| — | Security (TLS pinning, HTTPS-only, secrets) | ✅ 📱 | HTTPS enforcement option; certificate pinning only on IO (`HttpClient.badCertificateCallback`/`SecurityContext`) — **impossible on Web** (browser controls TLS). |
| — | Performance (connection reuse, isolate JSON decode, dedup) | ✅ | Large JSON decode on isolate via `Isolate.run` (IO only; Web runs inline). In-flight GET deduplication. |

Recommended **not** to do: mandatory code generation; global singletons as the only access path; blind retries of POST/PATCH; silent offline queuing of destructive operations; logging enabled by default; background transfer service in v1.

## 3. Public API specification

### 3.1 Construction

```dart
final api = OmniNetwork(
  baseUrl: 'https://api.example.com/v1',
  enableLogging: true,                 // the one switch; default false
  timeout: const Duration(seconds: 20),
  headers: {'Accept': 'application/json'},
  auth: BearerAuth(
    readToken: tokens.access,
    refresh: (client) async => tokens.refresh(),   // single-flight
    onRefreshFailed: session.logout,
  ),
  retry: const RetryPolicy(maxAttempts: 3),         // idempotent only
  interceptors: [AppVersionHeader()],
);
// ...
await api.close(); // cancels in-flight requests, timers, sockets
```

### 3.2 Typed calls — Option A vs Option B

**Option A: throwing API (recommended default)**

```dart
final User user = await api.get<User>('/users/10', decoder: User.fromJson);
final users = await api.getList<User>('/users', decoder: User.fromJson);
await api.post<void>('/users', body: newUser.toJson());
```
Errors throw `OmniNetworkException` (sealed: `TimeoutFailure`, `ConnectionFailure`,
`HttpFailure(statusCode, body)`, `DecodeFailure`, `CancelledFailure`, `AuthFailure`).

**Option B: result type**

```dart
final Result<User> r = await api.getResult<User>('/users/10', decoder: User.fromJson);
switch (r) {
  case Ok(:final value): show(value);
  case Err(:final error): showError(error);
}
```

Comparison: A is idiomatic Dart and shortest; B forces error handling and is
nicer in Blocs. **Recommendation:** A as primary, B as a thin `*Result`
wrapper (`api.get(...).asResult()` extension) so we maintain one code path.

### 3.3 Full response access

```dart
final OmniResponse<User> res = await api.send(
  OmniRequest.get('/users/10', query: {'expand': 'roles'}),
  decoder: User.fromJson,
);
res.statusCode; res.headers; res.data; res.duration;
```

### 3.4 Endpoint registry — Option A (constants) vs Option B (class methods)

```dart
// A: typed endpoint constants (recommended; enables mocks/inspector/OpenAPI output)
abstract final class UserApi {
  static final byId = Endpoint.get<User>('/users/{id}', decoder: User.fromJson);
}
final u = await api.call(UserApi.byId, path: {'id': 10});

// B: hand-written repository methods
class UserRepository {
  UserRepository(this._api);
  final OmniNetwork _api;
  Future<User> byId(int id) => _api.get('/users/$id', decoder: User.fromJson);
}
```
Both are supported; A is what the OpenAPI generator will emit.

### 3.5 Cancel, upload, download, pagination, state

```dart
final token = OmniCancelToken();
api.get<User>('/slow', decoder: User.fromJson, cancelToken: token);
token.cancel();

await api.upload('/avatar', files: [UploadFile.fromBytes('a.png', bytes)],
    onProgress: (sent, total) {});

await api.download('/report.pdf', to: '/tmp/r.pdf',           // IO only
    onProgress: (got, total) {});

final pager = api.paginate<User>('/users', decoder: User.fromJson,
    strategy: const PagePagination(pageParam: 'page', sizeParam: 'limit'));
await pager.next();

final state = api.watch<User>('/users/10', decoder: User.fromJson);
state.stream.listen((s) => switch (s) {
  Loading() => ..., Success(:final data) => ..., Failure(:final error) => ...,
});
```

### 3.6 Interceptor & transport contracts

```dart
abstract interface class OmniInterceptor {
  FutureOr<OmniRequest> onRequest(OmniRequest request) => request;
  FutureOr<OmniRawResponse> onResponse(OmniRawResponse response) => response;
  FutureOr<void> onError(OmniNetworkException error) {}
}

abstract interface class Transport {      // Dio, MockTransport, package:http
  Future<OmniRawResponse> send(OmniRequest request, {OmniCancelToken? cancel});
  Future<void> close({bool force = false});
}
```

## 4. Dependency evaluation

| Package | Latest | Role | Decision |
|---|---|---|---|
| `dio` | 5.11.1 (2026-09-04) | Default transport | **Use** behind `Transport` interface (never leaked in public API) — gives multipart, progress, cancel, web adapter, HTTP/2 option. Swappable. |
| `dio_web_adapter` | 2.2.2 | Web transport (bundled by dio) | Transitive via dio. |
| `native_dio_adapter` | 1.8.0 | Cronet/URLSession | Optional, documented, not a dependency. |
| `http` | 1.6.0 | Alternative transport | Optional `HttpTransport` in a later phase; useful for users avoiding dio. |
| `logger` | 2.8.0 | Pretty logging | **Do not depend in core.** Core has `LogSink` interface + simple default; a 10-line adapter for `logger` documented. Avoids forcing formatting deps. |
| `pretty_dio_logger` | 1.4.0 (2024) | — | Not used (no redaction; Dio-specific). |
| `dio_smart_retry` / `dio_cache_interceptor` | 7.0.1 (2024) / 4.0.7 | — | Not used: Dio-coupled; our retry/cache must be transport-independent and idempotency-aware. |
| `web_socket_channel` | 3.0.3 | WebSocket | In `omni_network_ws` only. |
| `graphql` / `grpc` | 5.2.4 / 5.2.0 | — | Not wrapped (see matrix). |
| `meta` | ^1.18 | annotations | Core dependency. |
| `connectivity_plus` | 7.3.2 | connectivity | Flutter adapter only. |
| `test`, `fake_async`, `lints` | 1.33.0, 1.3.3, 6.1.0 | dev | Core dev deps. No `mocktail`/`http_mock_adapter` — our `MockTransport` covers it. |

Core runtime deps: **`dio`, `meta`** only.

## 5. Platform compatibility matrix

| Capability | Android | iOS | macOS | Windows | Linux | Web |
|---|---|---|---|---|---|---|
| Core HTTP, JSON, interceptors, auth, retry, cache (memory) | ✅ | ✅ | ✅ (needs `com.apple.security.network.client` entitlement) | ✅ | ✅ | ✅ |
| Arbitrary request headers / cookies | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠ browser forbids some headers (`Cookie`, `Host`, `User-Agent`…); cookies managed by browser |
| CORS | n/a | n/a | n/a | n/a | n/a | ⚠ server must send CORS headers; preflight for custom headers; non-safelisted response headers need `Access-Control-Expose-Headers` |
| Upload progress | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (XHR) |
| Download to file / resume | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ bytes only; save via browser |
| Background transfers (app suspended) | ❌ v1 | ❌ v1 | ❌ | ❌ | ❌ | ❌ |
| Certificate pinning | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ impossible |
| Cleartext HTTP | ⚠ blocked by default (network security config) | ⚠ ATS | ⚠ ATS | ✅ | ✅ | ⚠ mixed content blocked on https pages |
| Isolate JSON decode | ✅ | ✅ | ✅ | ✅ | ✅ | inline (no isolates) |
| WebSocket | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (no custom headers on handshake) |
| SSE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ with CORS |
| Connectivity detection (Flutter adapter) | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠ coarse |

Core will be tested on the Dart VM and Chrome (`dart test -p vm,chrome`).

## 6. Package / module layout

```
my pkg/                        (existing omni_route package — untouched)
├── lib/ test/ example/ doc/   OmniRoute
└── packages/
    ├── omni_network/          pure Dart core  (deps: dio, meta)
    │   ├── lib/omni_network.dart
    │   ├── lib/src/{core,transport,auth,log,retry,cache,paging,state,queue,mock,curl,endpoint}/
    │   ├── test/  doc/  CHANGELOG.md  pubspec.yaml
    ├── omni_network_flutter/  inspector UI, connectivity, persistent stores   (later)
    ├── omni_network_bloc/     RequestState ↔ Cubit helpers (flutter_bloc)     (later)
    ├── omni_network_ws/       WebSocket + SSE                                  (later)
    └── omni_network_openapi/  CLI generator (dev dependency)                   (later)
```

Decision: **sibling packages inside this repo under `packages/`, without a pub
workspace for now.** Reasons:
- One repo keeps shared conventions/CI and the user's existing workflow.
- The root `omni_route` package stays exactly as is; converting the root into a
  pub workspace would require editing the root `pubspec.yaml` (adding
  `workspace:`) and changes lockfile resolution — that is a separate decision
  we can take later with approval.
- Each package has its own `pubspec.yaml`, `analysis_options.yaml`, tests and
  versioning; adapters depend on the core by `path:` during development.
- Root `flutter test` only runs root `test/`, so OmniRoute's 78 tests are not
  affected. One caveat: `flutter analyze` at the root may also walk into
  `packages/`; we will verify and, if needed, add `packages/**` to root
  `analyzer.exclude` (one-line config change, will ask first).

Alternative: a separate repository — cleaner publishing story but splits the
work; can be done later by `git subtree split` if desired.

## 7. Incremental roadmap (each step = its own approval gate)

| Step | Scope | Tests |
|---|---|---|
| 1 | Package skeleton, `Transport` interface, Dio transport, `MockTransport`, GET/POST/PUT/PATCH/DELETE, query/headers/timeouts, `close()` | Mock-transport request shape tests; timeout; close cancels in-flight; analyzer clean |
| 2 | Typed responses: decoders, list decoding, `OmniResponse`, sealed exceptions, response adapters, `Result` extension | Decode success/failure, envelope unwrap, error mapping per status |
| 3 | Logger + redaction (`enableLogging`), `LogSink` | Off ⇒ zero sink calls; on ⇒ redacted headers/query/body; truncation; multipart not logged |
| 4 | Interceptors + auth (Bearer, single-flight refresh, logout on failure) | 10 concurrent 401s ⇒ exactly 1 refresh; refresh failure ⇒ all fail + callback once; no infinite loop |
| 5 | Upload/download with progress & cancel | Progress callbacks monotonic; cancel mid-transfer; Web skip for file paths |
| 6 | Retry/backoff/`Retry-After`/cancel groups/circuit breaker | POST never retried; GET retried N times with fake_async timings; cancel stops retries |
| 7 | Pagination strategies | Page/offset/cursor/Link; end detection; concurrent `next()` guarded |
| 8 | Cache (memory, ETag, max-age, SWR), in-flight dedup | 304 handling; auth responses not cached; dedup shares one transport call |
| 9 | Request state stream | State sequence, refresh, disposal closes stream |
| 10 | Offline queue (explicit only, idempotency keys, pluggable store) | Unmarked requests never queued; destructive requires opt-in; replay order; dedupe |
| 11 | "API studio": endpoint registry + request builder + cURL import/export | Round-trip cURL; redaction on export |
| 12 | Mocking public API polish (scenarios, latency, error injection) | — |
| 13 | OpenAPI CLI package | Golden tests on sample specs |
| 14 | WebSocket/SSE package | Local in-process server (`dart:io` HttpServer on loopback) |
| 15 | Inspector (Flutter package) | Widget tests with leak tracking config |

## 8. Testing strategy

- **No real internet in unit tests.** All core tests use `MockTransport`.
  Dio transport integration tests run against a loopback `HttpServer`
  started in the test (`dart:io`, VM only), tagged `integration`.
- **Time-dependent logic** (retry backoff, timeouts, circuit breaker, cache
  expiry) uses `fake_async` and an injectable `Clock`.
- **Auth concurrency:** fire N parallel requests that receive 401, assert one
  refresh, all replayed with new token, refresh failure path, and refresh
  endpoint itself excluded from auth interception.
- **Retry safety:** matrix of methods × errors asserting which are retried;
  `Retry-After` honored; no retry after cancellation.
- **Cancellation:** cancel before send, during send, during retry wait,
  during refresh wait; `close()` cancels everything and further calls throw.
- **Logger:** on/off switch, snapshot of redacted output, secrets never
  appear (test greps sink output for known secret values).
- **Leak/disposal:** core has no Flutter leak tracker, so every component
  with resources exposes debug counters (open timers/subscriptions/pending
  requests) asserted to be zero after `close()`; Flutter adapter packages use
  the same `flutter_test_config.dart` + `LeakTesting.enable()` as OmniRoute.
- **Platforms:** `dart test -p vm,chrome` for core; web-specific behaviour
  (no file download, no pinning) tested to fail with a clear error.
- **Regression rule:** every bug gets a test reproducing it before the fix.
- **Honest reporting:** test counts reported from actual runs only.

## 9. Open questions for approval

1. Layout: `packages/omni_network/` sibling packages (recommended) — OK?
2. Dio as default transport behind our own `Transport` interface — OK?
3. Throwing API primary + `Result` wrapper — OK, or Result-first?
4. Default retry set: GET/HEAD/OPTIONS only (PUT/DELETE opt-in) — OK?
5. Defer gRPC and OS background transfers; GraphQL only as thin helper later — OK?
6. Permission to add `packages/**` to root `analyzer.exclude` if root analysis picks up the new packages.
