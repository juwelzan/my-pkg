# omni_network_flutter

Flutter tools for [`omni_network`](../omni_network). It currently contains
an in-app network inspector.

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
- **Forwarding.** `forwardTo: const PrintLogSink()` also prints every record.

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
