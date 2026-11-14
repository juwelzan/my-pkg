## 0.1.0-dev

- Step 15: `OmniInspector` (a `LogSink` + `ChangeNotifier`; off in release
  builds by default; `sink(label)` per client; bounded `maxEntries`;
  `forwardTo`; only ever sees redacted data), `OmniInspectorView` (list,
  filter, status colours, detail with headers/bodies, copy redacted cURL)
  and `OmniInspectorLauncher` for `MaterialApp.builder` (own `Overlay`,
  floating button, full-screen panel). Widget tests run with leak tracking.
