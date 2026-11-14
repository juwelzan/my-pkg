## 0.1.0-dev

- Step 14: `SseParser` (WHATWG event-stream rules) and `SseConnection`
  (reconnect with `retry:`/backoff, `Last-Event-ID`, stops on 204/4xx,
  `maxReconnects`, runs through `OmniNetwork.openStream` so auth,
  interceptors and logging apply). `OmniWebSocket` (reconnect with
  backoff and jitter except after a normal 1000 close or `close()`,
  per-connect `headers` callback (IO only; browsers forbid handshake
  headers), `onOpen`, `states`, `jsonMessages`, `send` throws while
  disconnected unless `bufferWhileDisconnected` (bounded, ordered)).
