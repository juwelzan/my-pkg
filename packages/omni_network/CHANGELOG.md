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
