## 0.1.0-dev

- Step 15: `OmniInspector` (a `LogSink` + `ChangeNotifier`; off in release
  builds by default; `sink(label)` per client; bounded `maxEntries`;
  `forwardTo`; only ever sees redacted data), `OmniInspectorView` (list,
  filter, status colours, detail with headers/bodies, copy redacted cURL)
  and `OmniInspectorLauncher` for `MaterialApp.builder` (own `Overlay`,
  floating button, full-screen panel). Widget tests run with leak tracking.
- `SecureTokenStorage` (`flutter_secure_storage` ^11.2.0): `OmniAuth` tokens
  in Keychain/Keystore/Credential Manager/libsecret (WebCrypto on the Web),
  so users stay signed in across restarts. Corrupted entries are cleared;
  platform errors are reported via `onError` without secrets and never
  crash the app.
