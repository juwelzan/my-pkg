# OmniNetwork — full guide

The [README](../README.md) covers the everyday path. This guide has every
option, with the import each API needs:

| Import | What it gives you |
|---|---|
| `package:omni_network/omni_network.dart` | The default: client, verbs, errors, `OmniAuth`, retry, cache, pagination, request state |
| `package:omni_network/advanced.dart` | Everything above, plus transports, stores, adapters, log sinks, `Redactor`, `OfflineQueue`, `CircuitBreaker`, streaming, cURL, the endpoint registry and `BearerAuth` |
| `package:omni_network/testing.dart` | `OmniMock`, `MockResponse`, `MockTransport` |

## Requests and typed responses

```dart
final user  = await api.get<User>('/users/10', decoder: User.fromJson);
final users = await api.getList<User>('/users', decoder: User.fromJson,
    query: {'page': 2, 'tag': ['a', 'b']});          // ?page=2&tag=a&tag=b
final made  = await api.post<User>('/users', body: {'name': 'Ana'},
    decoder: User.fromJson);
await api.delete<void>('/users/10');

// Without a decoder: String gives the text, int/Map/List are cast from
// JSON, and void or a nullable type accepts an empty body.
final count = await api.get<int>('/users/count');

// Every verb takes the same per-call options.
final me = await api.get<User>('/me',
    decoder: User.fromJson,
    query: {'expand': 'roles'},
    headers: {'X-Trace': traceId},
    timeout: const Duration(seconds: 5),
    cancelToken: token,
    retry: RetryPolicy.none,          // or a policy just for this call
    cache: CachePolicy.networkFirst,  // GET only, needs `cache:` on the client
    auth: false);                     // no token (login, public endpoints)

// The full response (status, headers, duration, source):
final res = await api.getResponse<User>('/users/10', decoder: User.fromJson);
print('${res.statusCode} ${res.headers['etag']} ${res.duration} ${res.source}');
// Also: postResponse, putResponse, patchResponse, deleteResponse.
```

JSON envelopes such as `{"data": ..., "meta": ...}` are unwrapped with
`responseAdapter: const EnvelopeResponseAdapter(dataKey: 'data')`. You can set
it for the whole client or pass `adapter:` on a single call.

## Errors

Every failure is a subtype of the sealed `OmniNetworkException`:
`HttpFailure` (non-2xx; the full `response` is kept), `DecodeFailure`,
`TimeoutFailure`, `ConnectionFailure`, `CancelledFailure`, `ClosedFailure`,
`AuthFailure`, `CircuitOpenFailure` and `RequestFailure`. Error messages
never contain bodies, headers, query strings or URL user info.

Quick checks on any failure, no need to know the hierarchy:

```dart
try {
  await api.get<User>('/me', decoder: User.fromJson);
} on OmniNetworkException catch (e) {
  if (e.isOffline) showOfflineBanner();          // connection error or timeout
  else if (e.isUnauthorized) goToLogin();        // 401 or refresh failed
  else if (e.statusCode == 404) showNotFound();  // null when no response
  else showError(e.message);                     // safe: no secrets
}
```

`isTimeout` and `isCancelled` are also available. Or skip try/catch:

```dart
switch (await api.get<User>('/me', decoder: User.fromJson).asResult()) {
  case Ok(:final value): show(value);
  case Err(:final error): showError(error);
}
```

## Logging and redaction

One `true`/`false` switch prints every call in the terminal while you
develop:

```dart
final api = OmniNetwork(baseUrl: url, enableLogging: true);
```

```
┌────────────────────────────────────────────────────────────
│ GET  https://api.example.com/v1/users/10
│ 🔑 token refreshed
├────────────────────────────────────────────────────────────
│ ✔ 200 OK · 142 ms · 1.2 KB
│ {
│   "id": 10,
│   "name": "Ana",
│   "access_token": "***"
│ }
└────────────────────────────────────────────────────────────

┌────────────────────────────────────────────────────────────
│ POST https://api.example.com/v1/orders
│ ⇢ body  {"item":7,"password":"***"}
├────────────────────────────────────────────────────────────
│ ✖ 422 Unprocessable Entity · 88 ms · 29 B
│ {
│   "error": "qty must be ≤ 1"
│ }
└────────────────────────────────────────────────────────────
```

What each block shows:

- **One block per call.** Method, URL, status, time, size and the
  pretty-printed JSON. Request and response are printed together, so
  concurrent calls never mix.
- **Retries and token refresh.** `↻ retry 2/3` and `🔑 token refreshed`
  lines; cache hits are marked `· cache`.
- **Colours.** Green for 2xx, yellow for 4xx, red for 5xx and failures, when
  the terminal supports colours.
- **Secrets.** Always `***`: auth and cookie headers, token, password and
  API-key fields, query values and URL user info. This cannot be turned off,
  only extended with `redactor: Redactor(extraKeys: {...})` from
  `advanced.dart`.
- **Release builds.** Logging is off in release builds even when
  `enableLogging: true`. `logInRelease: true` overrides that, and
  `api.isLogging` tells you whether calls are being logged.

Optional formatting; every field has a default:

```dart
OmniNetwork(
  baseUrl: url,
  enableLogging: true,
  logOptions: const LogOptions(
    headers: true,       // default false
    requestBody: true,   // default true
    responseBody: true,  // default true
    maxLines: 30,        // then "… N more lines"
    colors: null,        // null = auto
  ),
);
```

To send records elsewhere (a file, `package:logger`, a crash reporter, the
Flutter inspector), pass `logSink:` (`LogSink` from `advanced.dart`).

## Auth and interceptors

Every client has a built-in token manager, `api.auth`:

```dart
final api = OmniNetwork(
  baseUrl: url,
  auth: OmniAuth(
    // Runs on a 401, or shortly before the token expires.
    refresh: (tokens, api) async {
      final r = await api.post<Map<String, dynamic>>('/auth/refresh',
          body: {'refresh_token': tokens.refresh});
      return Tokens(access: r['access_token'], refresh: r['refresh_token'],
          expiresIn: Duration(seconds: r['expires_in']));
    },
    onLogout: () => router.go('/login'),
  ),
);

// After your login call:
final r = await api.post<Map<String, dynamic>>('/auth/login',
    body: {'user': u, 'password': p}, auth: false);
await api.auth.login(Tokens(access: r['access_token'], refresh: r['refresh_token']));

api.auth.isLoggedIn;      // true
api.auth.changes;         // Stream<AuthState>, e.g. to redirect in the router
await api.auth.logout();  // clears tokens and cache, calls onLogout
```

What the token manager does:

- **Automatic header.** Every request gets `Authorization: Bearer …`. Pass
  `auth: false` on a call to send it without a token.
- **Refresh on 401.** Ten 401s at once still mean a single refresh, and each
  request is replayed once with the new token.
- **Refresh before expiry.** When `expiresIn`/`expiresAt` is known, the
  token is refreshed shortly before it expires (`refreshBefore`, default
  30 s), so the user never sees a 401.
- **Refresh failure.** If `refresh` returns `null`, throws or times out, the
  tokens are cleared, `onLogout` runs once, and the waiting calls fail with
  `AuthFailure` (`e.isUnauthorized` is true).
- **No refresh configured.** `OmniAuth()` without `refresh` (also the
  default when you pass nothing) just stores and sends the token. A 401 is
  then a normal `HttpFailure`.
- **Storage.** Tokens are kept in memory. To keep users signed in across
  restarts, pass `storage:` (a `TokenStorage` from `advanced.dart`); the
  Flutter package provides secure storage. Tokens are restored from storage
  on the first request.

A token you already manage yourself:

```dart
final api = OmniNetwork(baseUrl: url, token: () => storage.token);
```

Interceptors add your own headers or checks:

```dart
final class AppVersionHeader extends OmniInterceptor {
  @override
  OmniRequest onRequest(OmniRequest r) => r.withHeader('X-App', '1.4.0');
}

OmniNetwork(baseUrl: url, interceptors: [AppVersionHeader()]);
```

For a fully custom setup, `BearerAuth` (from `advanced.dart`) is the
low-level engine behind `OmniAuth`.

## Retry and circuit breaker

```dart
OmniNetwork(
  baseUrl: url,
  retry: const RetryPolicy(maxAttempts: 3),   // off by default
  circuitBreaker: CircuitBreaker(failureThreshold: 5),
);
```

- **Methods.** Only `GET` and `HEAD` are retried. Add `PUT`/`DELETE` through
  `methods:`. `POST`/`PATCH` are retried only when the request carries an
  `Idempotency-Key` header and you set `retryWithIdempotencyKey: true`.
- **What is retried.** Status 408, 429 and 5xx gateway errors, timeouts and
  connection errors. The delay grows exponentially with jitter.
- **`Retry-After`.** The server's `Retry-After` header is honoured. A value
  above `maxRetryAfter` is not waited for; the response is returned instead.
- **Overrides.** Pass `OmniRequest(retry: RetryPolicy.none)` to turn retry off
  for one call.
- **Circuit breaker.** A host that keeps failing is not called for a while.

## Cancellation

```dart
final token = OmniCancelToken();
api.get<User>('/slow', decoder: User.fromJson, cancelToken: token);
token.cancel();                 // fails with CancelledFailure

final screen = appToken.child(); // cancelling the parent cancels children
api.cancelAll();                 // cancels everything, client stays usable
await api.close();               // cancels everything, client closed
```

## Upload and download

```dart
await api.upload<void>('/avatar',
    fields: {'album': 'me'},
    files: [UploadFile.fromBytes('file', bytes, filename: 'me.png',
        contentType: 'image/png')],
    onProgress: (sent, total) {});

final bytes = await api.downloadBytes('/report.pdf', onProgress: (got, total) {});

// IO platforms only (check OmniNetwork.supportsFileDownload).
await api.downloadToFile('/big.zip', '/tmp/big.zip', resume: true);
```

- **Timeouts.** Transfers have no overall deadline unless you pass
  `timeout:`. Instead they fail after `idleTimeout` passes with no progress.
- **Files.** Data is written to `<file>.part` first and renamed when the
  download finishes. With `resume: true` the download continues with an
  HTTP `Range` request.
- **Retry.** Uploads and downloads are never retried automatically.

## Pagination

```dart
final pager = api.paginate<User>('/users',
    decoder: User.fromJson, strategy: const PagePagination(pageSize: 20));
await pager.next();
if (pager.hasMore) await pager.next();
pager.items;          // everything loaded so far
await pager.refresh();
await pager.close();
```

Four strategies are available: `PagePagination`, `OffsetPagination`,
`CursorPagination(nextCursorKey: 'meta.next')` and `LinkHeaderPagination`.
`LinkHeaderPagination` refuses a next link to another origin, so tokens never
leave the API host.

The pager is safe to call from UI code:

- calling `next()` while a page is loading returns the same future;
- a failed page can be retried by calling `next()` again;
- if the server repeats a cursor, paging stops.

## Cache and request de-duplication

```dart
OmniNetwork(baseUrl: url, cache: OmniCache());     // CachePolicy.standard
api.get<User>('/me', decoder: User.fromJson);      // standard HTTP caching
api.get<List<dynamic>>('/feed', cache: CachePolicy.staleWhileRevalidate);
```

- **Standard policy.** Follows RFC 9111: `max-age`, `Age`, `Expires`,
  `no-store`, `no-cache` and `Vary`, plus conditional requests with
  `ETag`/`Last-Modified`. A `304` reply serves the cached body.
- **Other policies.** `cacheFirst`, `staleWhileRevalidate`, `networkFirst`
  (falls back to the cache when offline), `refresh` and `noCache`.
- **Invalidation.** A successful POST, PUT, PATCH or DELETE clears the
  cached entries for that URL.
- **Auth.** Responses to requests with `Authorization` are never cached
  unless you set `cacheAuthenticated: true`. They are then partitioned per
  user through `authScope:`. Call `cache.clear()` on logout.
- **Where a response came from.** `response.source` is `network`, `cache`
  or `revalidated`.
- **De-duplication.** Identical concurrent GETs share one network call; turn
  this off with `deduplicate: false`. Each caller keeps its own timeout and
  cancel token.

## Request state for UIs

```dart
final me = api.watch<User>('/me', decoder: User.fromJson);
me.stream.listen((state) => switch (state) {
  RequestIdle() || RequestLoading(previous: null) => showSpinner(),
  RequestLoading(:final previous?) => showUser(previous, refreshing: true),
  RequestSuccess(:final data) => showUser(data),
  RequestEmpty() => showEmpty(),
  RequestError(:final error) => showError(error),
});
await me.refresh();
await me.close();
```

This is plain Dart. Use it with `StreamBuilder`, Bloc, Riverpod or anything
else.

## Offline queue

Needs `advanced.dart`.

```dart
final queue = OfflineQueue(client: api);          // nothing is queued implicitly
final result = await queue.sendOrQueue(
    const OmniRequest.post('/notes', body: {'text': 'hi'}));
queue.attach(connectivityStream);                 // Stream<bool>, flushes when online
```

Rules:

- **Explicit only.** A request is queued only through `enqueue` or
  `sendOrQueue`, and `sendOrQueue` queues only when the server cannot be
  reached.
- **Not queued.** `GET`, `HEAD` and multipart requests.
- **Destructive requests.** `PUT`, `PATCH` and `DELETE` need
  `allowDestructive: true`.
- **Idempotency.** Every item carries an `Idempotency-Key`, and the same key
  is sent on every replay.
- **Credentials.** `Authorization` and `Cookie` are never stored; auth adds
  a fresh token on replay.
- **Replay order.** `flush()` replays oldest first and stops at the first
  temporary failure.
- **Persistence.** Implement `QueueStore` and save `QueuedRequest.toJson()`.

## Endpoints and cURL

```dart
abstract final class UserApi {
  static final byId = Endpoint.get<User>('/users/{id}', decoder: User.fromJson);
}
final u = await api.call(UserApi.byId, path: {'id': 10});

// advanced.dart: low-level calls and cURL.
final raw = await api.sendRaw(const OmniRequest.get('/health')); // any status, no decoding
print(api.toCurl(const OmniRequest.get('/users'))); // secrets redacted by default
final imported = parseCurl(copiedFromBrowser).request;
```

`omni_network_openapi` generates the `Endpoint`s and models from an OpenAPI
spec.

## Testing with OmniMock

Needs `testing.dart`.

```dart
final mock = OmniMock(basePath: '/v1')
  ..get('/users/{id}', (r) => MockResponse.json({'id': r.pathParams['id']}))
  ..get('/feed', OmniMock.sequence([
      const MockResponse.offline(),
      MockResponse.json([]),
    ]))
  ..scenario('down', (s) => s.any((_) => const MockResponse.status(503)));
final api = OmniNetwork(baseUrl: 'https://api.test/v1', transport: mock);
mock.use('down');
mock.failNext(2);
expect(mock.callsTo(HttpMethod.get, '/users/{id}'), hasLength(1));
```

What else OmniMock gives you:

- `latency` and per-response `delay`;
- `MockResponse.hang()` to test timeouts;
- a seeded `failureRate`;
- upload and download support.

OmniMock is strict by default: a request that matches no route fails with a
message that names it.

## Safe defaults

| Topic | Default |
|---|---|
| Logging | off; redaction always on when enabled |
| Retry | off; when on, GET/HEAD only |
| POST/PATCH retry | only with `Idempotency-Key` and an explicit opt-in |
| Offline queue | explicit only; destructive requests need opt-in |
| Cache | off; authenticated responses not cached |
| Error messages | no bodies, headers, query strings or URL user info |
| Link pagination | same origin only |
| Code generation | never required |
| Redirects | followed by OmniNetwork; credentials dropped on cross-origin hops; no HTTPS → HTTP |
| Large JSON (≥ 256 KB) | parsed off the main isolate on IO platforms |
| Tokens in storage, queue, logs, errors | never stored by the queue, always `***` in logs, never in messages |

## Platforms

| | Android | iOS | macOS | Windows | Linux | Web |
|---|---|---|---|---|---|---|
| Core HTTP, auth, retry, cache, queue | ✅ | ✅ | ✅¹ | ✅ | ✅ | ✅² |
| Upload/download progress | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `downloadToFile` / resume | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ use `downloadBytes` |
| Background transfers (app suspended) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

1. macOS apps need the `com.apple.security.network.client` entitlement.
2. On the Web, the server must send CORS headers. Browsers forbid some
   request headers (`Cookie`, `User-Agent` and others).

## Development

```sh
dart analyze
dart run test/client_test.dart   # see note
```

**Running the tests:** with Dart 3.13 and test_core 0.6.21, `dart test`
crashes in its runner. The runner looks for `vm_platform_strong.dill`, which
the SDK renamed. Until that is fixed, run each file with
`dart run test/<file>_test.dart`.
