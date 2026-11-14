# omni_network_flutter

Flutter tools for [`omni_network`](../omni_network):

- **Secure token storage.** Users stay signed in after the app restarts.
- **In-app network inspector.** See every call from inside the app.

## Stay signed in: `SecureTokenStorage`

```dart
final api = OmniNetwork(
  baseUrl: 'https://api.example.com',
  auth: OmniAuth(
    storage: SecureTokenStorage(),   // that's all
    refresh: (tokens, api) async { /* see omni_network README */ },
  ),
);

await api.auth.login(Tokens(access: a, refresh: r)); // saved securely
// Next app start: the user is still signed in.
await api.auth.logout();                              // removed from the store
```

| Platform | Where tokens are kept |
|---|---|
| iOS / macOS | Keychain (macOS: add the Keychain Sharing entitlement) |
| Android | Keystore-encrypted storage |
| Windows / Linux | Credential Manager / libsecret |
| Web | WebCrypto-encrypted `localStorage`. A browser can't fully protect it, so use short-lived access tokens |

Failure handling:

- **Corrupted data** is deleted and treated as signed out, so the app never
  gets stuck.
- **Platform errors** never crash the app. They are reported through
  `onError` (the default prints only the error type, never a token).
- **Several clients.** Use a different `key:` for each client so they keep
  separate tokens.

## Network inspector

```dart
final inspector = OmniInspector();         // disabled in release builds
final api = OmniNetwork(
  baseUrl: 'https://api.example.com',
  enableLogging: inspector.enabled,
  logSink: inspector.sink('api'),          // one label per client
);

MaterialApp(
  builder: (context, child) =>
      OmniInspectorLauncher(inspector: inspector, child: child!),
  home: const HomePage(),
);
```

`OmniInspectorLauncher` adds a small floating button that opens a
full-screen panel. The panel has:

- the request list, with a filter and status colours;
- a detail view with request and response headers and bodies;
- "Copy as cURL".

You can also show `OmniInspectorView(inspector: inspector)` anywhere.

What the inspector sees and keeps:

- **Only redacted data.** It receives records after the client's
  `Redactor` has run, so tokens, cookies and passwords never reach the UI or
  the clipboard.
- **Bounded.** It keeps at most `maxEntries` entries.
- **Forwarding.** `forwardTo: PrettyLogSink()` also prints every call in the terminal.

## Example

`example/` has an app that uses `RequestController` with a fake backend.
To run it, first add platform folders:

```sh
cd example
flutter create --platforms=android,ios,macos,web .
flutter run
```

`flutter test` in `example/` runs its smoke test.

## Development

`flutter test` runs with leak tracking enabled for every test
(`test/flutter_test_config.dart`), the same setup as `omni_route`.
