## 0.1.0-dev.1

- Phase 2: `OmniStatelessWidget`, `OmniStatefulWidget`, `OmniState`, `OmniScreenMetadata`, `OmniRouteException`, route path validation.
- Phase 3: `OmniBloc` factory registry (global/screen), `Provide` / `Provide.create` / `Provide.value`, `OmniGlobalBlocScope`, `OmniBlocScope`, `provide` on screens.
- Phase 4: `OmniApp` (single GoRouter), `OmniPage` (compiles to GoRoute, wraps screen Bloc scope), `OmniParams`, `OmniRoute` navigation helpers incl. typed `to<S>()`, route validation at startup, not-found/invalid-param error page.
- Phase 5: `OmniShell`, `OmniStatefulShell` (with shell-scoped Blocs), `OmniGuard` (app-wide + per-route, sync/async, Bloc-stream refresh, self-redirect ignored, loops caught by GoRouter), deep-link test.
- Phase 6: `OmniRoute.usePathUrls()`, trailing-slash normalization, browser title from screen `title` (follows pop and tab switches), `OmniApp(setTitles:)`, web hosting docs (`doc/web.md`), example app.
- Phase 7: leak tracking on all tests (2 error-path leaks fixed), long-session/rebuild/tab-switch/large-registry tests, profile benchmark vs raw GoRouter (`example/benchmark`), report in `doc/performance.md`.
