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
