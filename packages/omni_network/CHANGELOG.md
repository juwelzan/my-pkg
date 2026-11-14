## 0.1.0-dev

- Step 1: `OmniNetwork` client with `send(OmniRequest)`; GET/POST/PUT/PATCH/
  DELETE/HEAD; base URL + path + query resolution; default and per-request
  headers; overall timeout; `close()` cancels in-flight requests.
- `Transport` interface with `DioTransport` (default) and `MockTransport`.
- `OmniNetworkException` (sealed): timeout, connection, cancelled, closed.
- Step 2: typed calls `get/getList/post/put/patch/delete/head` and
  `send<T>`/`sendList<T>` returning `OmniResponse<T>`; decoders are plain
  functions (`User.fromJson`), no code generation. The raw call is now
  `sendRaw` (returns every status).
- `HttpFailure` (non-2xx, keeps the response, never prints the body) and
  `DecodeFailure` (invalid JSON, wrong shape, decoder threw; body never echoed).
- `ResponseAdapter`: `PlainResponseAdapter` (default) and
  `EnvelopeResponseAdapter(dataKey:, errorKey:)`, per client or per call.
- `Result<T>` (`Ok`/`Err`) via `future.asResult()`; only
  `OmniNetworkException`s are captured.
- Step 3: logging with one switch, `OmniNetwork(enableLogging: true)`
  (default `false`: nothing is formatted, the sink is never called).
  `LogSink` interface (default `PrintLogSink`), structured
  `NetworkLogRecord`s (request/response/error, correlation id, duration).
- `Redactor` (always on, extendable via `extraHeaders`/`extraKeys`): masks
  auth/cookie/API-key headers, secret query values and JSON/form body keys
  (recursively), strips URL user info; binary/multipart/unknown bodies are
  summarised by size; bodies truncated at 2000 chars; `logBodies: false`
  omits them. A throwing sink never breaks a request.
- Step 4: `OmniInterceptor` (onRequest in order; onResponse/onError in
  reverse; transport-independent). `OmniRequest.copyWith/withHeader/header`
  and `skipAuth`.
- `BearerAuth(token:, refresh:, onRefreshFailed:)`: single-flight refresh
  (N concurrent 401s → one refresh, each request replayed once, no loops);
  requests started during a refresh wait for it; requests made inside the
  refresh callback skip auth automatically; refresh failure/throw/timeout →
  callback once and `AuthFailure` for every waiter; later 401s for the same
  stale token fail without refreshing again.
- Step 5: `OmniCancelToken` (`cancelToken:` on every call; shared tokens,
  no listener leaks). `upload<T>` with `MultipartBody`/`UploadFile`
  (bytes or re-openable stream, exact `content-length`, send progress,
  replayable after token refresh). `downloadBytes` and `downloadToFile`
  (IO only; `.part` file renamed on success, `resume:` via `Range`/206,
  restart on 200) with receive progress. Transfers have no overall deadline
  by default but fail after `idleTimeout` without progress.
- `Transport.sendStreamed` + `StreamedResponse` (Dio and Mock implement it).
- Logs summarise streamed/multipart bodies by size only.
- Step 6: `RetryPolicy` (client `retry:` or per request `OmniRequest(retry:)`,
  `RetryPolicy.none`): GET/HEAD only by default; PUT/DELETE opt-in via
  `methods`; POST/PATCH only with an `Idempotency-Key` header **and**
  `retryWithIdempotencyKey: true`. Retries 408/429/5xx-gateway statuses,
  timeouts and connection errors; exponential backoff with cap and 50–100 %
  jitter; honours `Retry-After` (seconds or HTTP date) and does not wait
  beyond `maxRetryAfter`. Backoff waits are cancellable (token, `close`,
  `cancelAll`). Each attempt is logged. Transfers are not auto-retried.
- `CircuitBreaker` per host (`failureThreshold`, `openDuration`,
  `halfOpenTrials`), `CircuitOpenFailure`, `stateOf(host)`.
- `OmniNetwork.cancelAll()` (also requests waiting for a token refresh or a
  retry) and `OmniCancelToken.child()`.
- Fix: `OmniRequest.copyWith`/`withHeader` dropped `cancelToken`, so
  cancelling did nothing for requests passing through `BearerAuth` or a
  header-adding interceptor (Step 5 regression; test added).
- Step 7: `api.paginate<T>()` → `OmniPager<T>` (`next`, `items`,
  `hasMore`, `isLoading`, `refresh`, `reset`, `close`, `lastError`).
  Concurrent `next()` calls share one request; a failed page keeps the state
  so `next()` retries it; `refresh`/`reset` discard stale in-flight pages;
  repeating cursors and `maxPages` stop runaway paging.
- Strategies: `PagePagination` (short page / empty / `totalPagesKey` /
  `hasMoreKey`), `OffsetPagination` (`totalKey`), `CursorPagination`
  (`nextCursorKey` JSON path), `LinkHeaderPagination` (RFC 8288; refuses
  next links to another origin so auth headers never leave the API host).
  `itemsKey` JSON path (`data`, `result.items`) keeps metadata visible.
- Step 8: `OmniCache` for GET (`OmniNetwork(cache:)`, per request
  `OmniRequest(cachePolicy:)`): `standard` (RFC 9111 freshness from
  `max-age`/`Age`/`Expires`+`Date`, `no-store`, `no-cache`, `Vary`,
  conditional `If-None-Match`/`If-Modified-Since`, `304` → cached body),
  `cacheFirst`, `staleWhileRevalidate` (background refresh, errors
  swallowed), `networkFirst` (offline fallback on connection errors and
  timeouts only), `refresh`, `noCache`. Request `Cache-Control` honoured.
  Successful unsafe requests invalidate the URL. Authenticated responses are
  never cached unless `cacheAuthenticated: true`, then partitioned by
  `authScope` (or token hash in memory). `CacheStore` interface +
  `MemoryCacheStore` (LRU, entry and byte limits).
- `OmniRawResponse.source` (`network`/`cache`/`revalidated`), shown in logs.
- In-flight deduplication (`deduplicate: true` by default): identical
  concurrent GETs (same URL and headers) share one network call; each caller
  keeps its own timeout/cancel, and the shared call is cancelled only when
  every caller has left.
