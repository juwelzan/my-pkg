## 0.2.3

No API changes; purely additive. Every new `OmniApp` parameter is optional
and off by default, so existing apps behave exactly as before.

- New `OmniApp(lifecycle:)`: app-wide `OmniLifecycle` hooks (resume, pause,
  memory pressure, ...) whose context can read global Blocs.
- New `OmniApp(onInit:, splash:)`: async startup work before the first
  page; guards see the loaded state. Errors are reported and the app opens.
- New `OmniApp(dismissKeyboardOnTap:)`: close the keyboard on outside taps.
- New `OmniApp(doubleBackToExit:, onExitWarning:)`: Android "press back
  again to exit" on the first page; other pages and platforms unchanged.
- New `OmniApp(orientations:)`: preferred orientations, reset on dispose.
- New `OmniApp(minTextScale:, maxTextScale:)`: clamp the system text scale.
- New `OmniApp(blocObserver:)`: installs `Bloc.observer`, restored on dispose.
- New `OmniApp(onError:)`: receives Flutter and platform errors (previous
  handlers still run; default reporting is kept); restored on dispose.

## 0.2.2

No API changes; purely additive.

- New: `OmniLifecycle` mixin — lifecycle hooks for both screen types without
  `WidgetsBindingObserver` boilerplate. Opt in with `with OmniLifecycle` on
  an `OmniStatelessWidget` or an `OmniState`; registration and cleanup are
  automatic. Hooks: `onAppLifecycleChanged`, `onAppResumed`,
  `onAppInactive`, `onAppHidden`, `onAppPaused`, `onAppDetached`,
  `onScreenVisible`, `onScreenHidden` (push/pop/tab), `onMemoryPressure`,
  `onMetricsChanged`, `onBrightnessChanged`, `onLocalesChanged`,
  `onTextScaleChanged`. Screens without the mixin are unaffected.

## 0.2.1

No API changes; all 0.2.0 code keeps compiling and behaving the same,
except for the two bug fixes below.

- Fix: guards passed to `OmniPage(guards:)` now re-run when their `refresh`
  stream emits (only `OmniApp(guards:)` were listened to). A guard object
  shared by several routes is subscribed once.
- Fix: `onNavigate` now reports a new page at the same location (pushing
  the same URL twice, popping back to it). Re-going to the current page
  still reports nothing.
- New: `OmniParams.queryBool`, `queryDouble`, `queryEnum`.
- New: `OmniRoute.maybePop`, `refresh`, `replaceTo<S>`, `replaceNamed`.
- Better error: `missingRoute` explains the `List<OmniPage>` type-inference
  trap that hides a route's screen type.

## 0.2.0

- Fix: a stateless screen shown outside a route now creates its own
  `provide` Blocs (it failed with `ProviderNotFoundException`).
- New: `OmniScreenHost` for stateful screens shown outside a route; a clear
  `OmniErrorCode.screenNotHosted` error is reported otherwise.
- Fix: duplicate route `name`s are rejected at startup in release builds too
  (previously only a go_router debug assert).
- New: `OmniRouteGroup` — route scope. Blocs shared by a group of routes,
  created on entering the group and closed on leaving it; `scopeKey`
  recreates them when e.g. the `:id` changes. Built on go_router `ShellRoute`.
- New: `OmniParams.of(context)` — read route parameters without subscribing,
  safe in Bloc `create` callbacks and `initState`.
- Example: student detail and edit share Blocs through `OmniRouteGroup`.
- Fix: page type, title setting and not-found page are now per `OmniApp`
  (were package-level variables: a second `OmniApp` overwrote the first's).
- `OmniRoute` helpers with several mounted apps act on the most recent one
  and fall back to the previous one when it is disposed.
- New: `OmniApp(restorationScopeId:)`; built-in page types set a stable
  `restorationId`, so the route stack, pushed pages, shell tabs and
  `Restorable*` widget state survive a restart. Blocs are recreated.
- Fix: `OmniRoute.location` ignored pages added with `push` and returned the
  location underneath them.
- New: `OmniPage(metadata:)` (go_router route metadata; readable in guards
  via `state.metadata`).
- New: `OmniRoute.current`, `OmniRoute.stack` (pages bottom→top through
  shells and pushes), `OmniRoute.state`; `OmniRouteEntry` type.
- New: `OmniApp(onNavigate:)` hook (`OmniNavigation` from/to/uri, no
  duplicate events) and `OmniApp(logNavigation: true)` (debug builds only).
- Docs: architecture, lifecycle & Bloc ownership guide (`doc/architecture.md`),
  migration guide (`doc/migration.md`), README sections for all new APIs.

## 0.1.0

First release.

### Development history

- Phase 2: `OmniStatelessWidget`, `OmniStatefulWidget`, `OmniState`, `OmniScreenMetadata`, `OmniRouteException`, route path validation.
- Phase 3: `OmniBloc` factory registry (global/screen), `Provide` / `Provide.create` / `Provide.value`, `OmniGlobalBlocScope`, `OmniBlocScope`, `provide` on screens.
- Phase 4: `OmniApp` (single GoRouter), `OmniPage` (compiles to GoRoute, wraps screen Bloc scope), `OmniParams`, `OmniRoute` navigation helpers incl. typed `to<S>()`, route validation at startup, not-found/invalid-param error page.
- Phase 5: `OmniShell`, `OmniStatefulShell` (with shell-scoped Blocs), `OmniGuard` (app-wide + per-route, sync/async, Bloc-stream refresh, self-redirect ignored, loops caught by GoRouter), deep-link test.
- Phase 6: `OmniRoute.usePathUrls()`, trailing-slash normalization, browser title from screen `title` (follows pop and tab switches), `OmniApp(setTitles:)`, web hosting docs (`doc/web.md`), example app.
- Phase 7: leak tracking on all tests (2 error-path leaks fixed), long-session/rebuild/tab-switch/large-registry tests, profile benchmark vs raw GoRouter (`example/benchmark`), report in `doc/performance.md`.
- Phase 8: `OmniApp(pageType:)` / `OmniPage(pageType:)` with `OmniPages.material|cupertino|none`, desktop back (Alt+←, Cmd+[, mouse back, optional Escape), per-platform tests, platform guide (`doc/platforms.md`).
- Phase 9: README, complete example + flow test, API docs for all public members, LICENSE (MIT).
