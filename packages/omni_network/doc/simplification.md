# Making OmniNetwork simpler to use — proposal (awaiting approval)

Status: proposal only. Nothing is implemented yet. The package is still
`0.1.0-dev` and unpublished, so breaking changes cost nothing now.

## 1. What makes it feel big today (measured)

| Area | Today | Problem for an app developer |
|---|---|---|
| One import | `package:omni_network/omni_network.dart` exports **~80 public types** | Autocomplete is flooded (`CancelSignal`, `TransportRequest`, `StreamTarget`, `PageContext`, `QueueEvent`…) even for a simple GET |
| Ways to make a request | 5: `get()`, `send(OmniRequest)`, `sendRaw()`, `call(Endpoint)`, `request().…send()` | It is unclear which one to use |
| Per-request options | `cachePolicy`, `retry`, `skipAuth` exist **only** on `OmniRequest` | Simple calls need the low-level `send(OmniRequest…)` as soon as one option is needed |
| Constructor | 15 parameters | Hard to see what is essential |
| Auth | Even a static token needs `BearerAuth(token:, refresh:)` | Overkill for the common case |
| Errors | 9 failure types | You must know the hierarchy to answer "was it offline?" or "what was the status?" |
| README | One long page that covers every feature | It reads like a reference manual, not a getting-started guide |

The features themselves are fine. The **surface** and the **lack of one
obvious path** are the problem.

## 2. Options

**A. Add a "simple" facade on top** (e.g. `SimpleApi`). Nothing is removed,
but this adds *more* API, and users still meet both layers. ❌

**B. Trim the surface and give one obvious path** (recommended). Same
features, but the default import shows only what apps need. Advanced and
testing APIs move to their own imports. ✅

**C. Rewrite a smaller package and drop features.** This loses tested work
(auth refresh, cache, queue…) that real apps need. ❌

## 3. Recommended changes (option B)

### 3.1 Three imports instead of one

```dart
import 'package:omni_network/omni_network.dart';  // apps: ~20 names
import 'package:omni_network/advanced.dart';      // custom transports, stores, strategies, cURL, low-level types
import 'package:omni_network/testing.dart';       // OmniMock, MockResponse, MockTransport
```

The default import keeps these names:

| Group | Names |
|---|---|
| Client and data | `OmniNetwork`, `OmniResponse` |
| Errors | `OmniNetworkException` (+ subtypes for `switch`), `Result`/`Ok`/`Err` |
| Features | `BearerAuth`, `RetryPolicy`, `CachePolicy`, `OmniCache`, `OmniCancelToken`, `UploadFile` |
| Pagination and state | `PagePagination`/`CursorPagination`/`OffsetPagination`, `OmniPager`, `RequestState` + its 5 states, `RequestController` |
| Endpoints and interceptors | `Endpoint`, `OmniInterceptor`, `OmniRequest` |

### 3.2 One obvious way to call: `get/post/put/patch/delete` with every option

Every common option becomes a named parameter on the five verbs, so
`send(OmniRequest)` is only needed for unusual cases:

```dart
// before: one option forced the low-level form
await api.send<User>(
  const OmniRequest.get('/me', cachePolicy: CachePolicy.networkFirst, retry: RetryPolicy.none),
  decoder: User.fromJson,
);

// after
await api.get<User>('/me', decoder: User.fromJson,
    cache: CachePolicy.networkFirst, retry: RetryPolicy.none);
```

Full response, when needed: `api.getResponse<User>(…)` returns `OmniResponse<User>`
(status, headers). This replaces `send<T>`.

Other changes:

- **Removed:** the fluent builder (`api.request(...)...`). It duplicated the
  verbs.
- **Moved to `advanced.dart`:** `sendRaw` and `OmniRawResponse`.

### 3.3 Simpler setup

```dart
// Static or stored token, no refresh needed:
final api = OmniNetwork(
  baseUrl: 'https://api.example.com',
  token: () => storage.token,          // adds "Authorization: Bearer …"
);

// Refresh needed: same BearerAuth as today.
final api = OmniNetwork(baseUrl: url, auth: BearerAuth(token: …, refresh: …));
```

The constructor docs and the README group the parameters into
*essentials* and *advanced*:

| Group | Parameters |
|---|---|
| Essentials | `baseUrl`, `headers`, `timeout`, `token`/`auth`, `enableLogging` |
| Advanced | `retry`, `cache`, `interceptors`, `circuitBreaker`, `transport`, `redactor`, `logSink`, `deduplicate`, `responseAdapter` |

### 3.4 Errors that answer the usual questions

The exact types stay available for `switch`. Handy getters are added on
the base `OmniNetworkException`:

```dart
try {
  await api.get<User>('/me', decoder: User.fromJson);
} on OmniNetworkException catch (e) {
  if (e.isOffline) showOfflineBanner();          // connection error or timeout
  else if (e.statusCode == 404) showNotFound();  // null when no response
  else showError(e.message);                     // safe, no secrets
}
```

### 3.5 README for humans

**Start here** fits on one screen and covers five tasks:

1. install;
2. create the client;
3. GET a typed object or a list;
4. POST JSON;
5. handle errors.

Then a short **Common tasks** list, with one example each:

- token and refresh;
- upload and download;
- pagination;
- retry and cache;
- testing with `OmniMock`.

Everything else moves to `doc/advanced.md`.

## 4. What does **not** change

- **Features.** Auth refresh, retry safety, cache, the offline queue,
  logging redaction and every other feature stay as they are.
- **Behaviour and safe defaults.** No change.
- **Packages.** `omni_network_ws`, `omni_network_flutter` and
  `omni_network_openapi` only get their imports adjusted.
- **OmniRoute.** Not touched.

## 5. Plan (small steps, tested)

| Step | What | Tests |
|---|---|---|
| S1 | Split exports into `omni_network.dart` / `advanced.dart` / `testing.dart`; update internal imports | Every existing test still passes. A new test checks that the simple import does not expose low-level names |
| S2 | Add per-call options to the verbs; add `getResponse` etc.; remove the builder; move `sendRaw` | Option tests |
| S3 | `token:` shortcut; `isOffline` / `statusCode` / `isTimeout` getters | Unit tests |
| S4 | README rewrite + `doc/advanced.md`; update the examples, generated code and sibling packages | README snippets compiled as before; examples run |

## 6. Questions for you

1. Option B (trim + one obvious path) — OK?
2. Remove the fluent builder `api.request(...)`? (Recommended: yes, it duplicates the verbs.)
3. Rename `send<T>` → `getResponse/postResponse…`? Or keep one `send(OmniRequest)` for the full response?
