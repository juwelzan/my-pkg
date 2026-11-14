# OmniRoute — Technical Design (Phase 0 + Phase 1)

> Status: **Draft for review.** No implementation code has been written yet.
> Date: 2026-11-13

---

## 0. Phase 0 — Technical Audit

| Item | Found | Decision |
|---|---|---|
| Repository | `/Users/juwel/Developer/my pkg` — empty, not a git repo | Create package `omni_route` here (`flutter create --template=package`) + `example/` |
| Flutter | 3.50.0 stable (Dart 3.13.4) | — |
| `go_router` latest | 18.1.4 (needs Dart ≥3.12, Flutter ≥3.44) | `go_router: ^18.1.4` |
| `flutter_bloc` latest | 9.1.1 (`bloc` 9.2.1) | `flutter_bloc: ^9.1.1` |
| Other deps | — | `flutter_web_plugins` (SDK, for `usePathUrlStrategy`) only. Nothing else. |
| SDK constraint | | `sdk: ^3.12.0`, `flutter: ">=3.44.0"` (inherits go_router's floor) |

**Hard technical constraints discovered (drive the API below):**

1. **No reflection in Flutter** (`dart:mirrors` is unavailable). A `Type` value cannot construct a Bloc, so `provide => AuthBloc` alone cannot work → a factory registry is required.
2. **Instance getters need an instance.** `routeName` declared as an instance getter on a screen can only be read by constructing the screen. A screen with required constructor args (`StudentDetailScreen(id: …)`) cannot be constructed at registration time. This is the single most important design decision — see §1.2.
3. `runtimeType.toString()` is not stable under `--obfuscate` → internal identity uses `Type` objects; `name` is for debugging/logging only.
4. A `Type` literal loses generics: `[StudentBloc, AttendanceBloc]` is `List<Type>`, so the compiler cannot check that the type is a Bloc. Generic descriptors (`Provide<StudentBloc>()`) are checked at compile time.

---

## 1. Deliverable A — Final API Design

### 1.1 Application initialization

**Option A1 — single widget (recommended)**

```dart
void main() {
  runApp(
    OmniApp(
      title: 'School',
      initialRoute: '/dashboard',
      blocs: [
        OmniBloc<AuthBloc>((ctx) => AuthBloc(ctx.read<AuthRepository>())),
        OmniBloc<ThemeBloc>((_) => ThemeBloc()),
        OmniBloc<StudentBloc>((ctx) => StudentBloc(ctx.read())), // factory only
      ],
      globalBlocs: [AuthBloc, ThemeBloc],      // which of the above live app-wide
      routes: [ ... ],                          // §1.3
      guards: [AuthGuard()],                    // §1.7
      notFound: (ctx, state) => const NotFoundScreen(),
      builder: (context, router) => MaterialApp.router(
        routerConfig: router,                   // plain GoRouter, untouched
        theme: ...,
      ),
    ),
  );
}
```

**Option A2 — imperative init + MaterialApp.router**

```dart
final router = OmniRoute.init(routes: [...], blocs: [...]);
runApp(MultiBlocProvider(providers: OmniRoute.globalProviders, child: MaterialApp.router(routerConfig: router)));
```

**Why A1:** A2 makes the developer wire global `MultiBlocProvider` themselves and makes it easy to rebuild the router by accident. `OmniApp` creates the `GoRouter` **once** in its `State`, owns global Bloc providers above it, and hands the plain `GoRouter` to the developer's `MaterialApp.router` / `CupertinoApp.router` — so the app widget stays fully theirs.

> Simplification question for you: merge `blocs` + `globalBlocs` into
> `OmniBloc<AuthBloc>(..., global: true)`. I lean towards this (one list). See §7 Q2.

### 1.2 Screen creation

```dart
class StudentScreen extends OmniStatelessWidget {
  const StudentScreen({super.key});

  @override String get screenName => 'Students';     // required: human name / browser title

  @override
  List<Provide> get provide => const [Provide<StudentBloc>()];   // optional

  @override
  Widget build(BuildContext context) => const Scaffold(body: StudentList());
}

class DashboardScreen extends OmniStatefulWidget {
  const DashboardScreen({super.key});
  @override String get screenName => 'Dashboard';
  @override List<Provide> get provide => const [Provide<StatsBloc>(), Provide<NoticeBloc>()];
  @override State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends OmniState<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    // metadata available: widget.screenName, routeState (path via routeState.matchedLocation) (GoRouterState)
    return Scaffold(appBar: AppBar(title: Text(widget.screenName)));
  }
}
```

- `name` → `runtimeType.toString()` (debug only, never identity).
- `OmniStatelessWidget` / `OmniStatefulWidget` share one mixin (`OmniScreenMeta`) → identical API.
- `OmniState<T>` is just `State<T>` + a `routeState` getter (reads `GoRouterState.of(context)`). No extra lifecycle.

**Bloc declaration — two options compared**

| | B1: `get provide => [StudentBloc, AttendanceBloc]` (spec idea) | B2: `get provide => const [Provide<StudentBloc>(), Provide<AttendanceBloc>()]` (**recommended**) |
|---|---|---|
| Compile-time check it's a Bloc | ❌ any `Type` accepted (`int` compiles) | ✅ `Provide<B extends Bloc>` |
| Single & multiple same syntax | needs `dynamic` return (`Type` or `List<Type>`) | ✅ always a list |
| Existing instance | impossible | ✅ `Provide.value(myBloc)` |
| Per-screen custom factory | impossible | ✅ `Provide<X>.create((ctx) => X(id))` |
| Verbosity | shortest | slightly longer |

B2 also covers the "Bloc that needs a route parameter" case, which B1 cannot.

### 1.3 Screen registration — the key decision

Because of constraint #2, three designs are possible:

**R1 — tear-offs only (spec idea)**
```dart
routes: [DashboardScreen.new, StudentScreen.new]
```
✅ shortest. ❌ Only works for no-arg constructors. Screen must be instantiated once at startup to read `routeName`. Dynamic screens (`/students/:id`) need a second API anyway.

**R2 — path lives in the route table; screen has no `routeName`**
```dart
routes: [OmniPage('/students/:id', (p) => StudentDetailScreen(id: p.int('id')))]
```
✅ works for everything, ✅ one source of truth, ❌ contradicts spec §4 ("routeName mandatory on screen").

**✅ Chosen: R2 — path lives only in the route table** (approved 2026-11-13)
```dart
routes: [
  OmniPage('/dashboard', (_) => const DashboardScreen()),
  OmniPage('/students', (_) => const StudentScreen(), children: [
    OmniPage(':id', (p) => StudentDetailScreen(id: p.pathInt('id'))),   // /students/:id
  ]),
  OmniShell.stateful(
    builder: (ctx, shell) => HomeScaffold(shell: shell),
    branches: [
      [OmniPage('/home', (_) => const DashboardScreen())],
      [OmniPage('/profile', (_) => const ProfileScreen())],
    ],
  ),
  GoRoute(path: '/legacy', builder: ...),   // raw go_router routes accepted as-is
]
```
Screens no longer declare `routeName`; `screenName` stays required (title/logging). Inside a screen the current path is available from `routeState`. The Type registry (for `OmniRoute.to<T>()`) is filled from the builder's generic: `OmniPage<StudentDetailScreen>(...)` is inferred from the return type.

- `OmniPage` compiles to a **plain `GoRoute`** (and `OmniShell` to `ShellRoute` / `StatefulShellRoute`). Raw `RouteBase` mixes freely.
- Registry indexed by `Type` → `{path, name, factory}`; duplicates of path, `name`, or `Type`-with-same-path throw at startup with a clear message.
- One screen may appear at several routes (identity of screen ≠ identity of route).
- Validation: non-empty, starts with `/` (top level), lowercase, no `#`, no trailing `/` (except root), params `:[a-zA-Z_]\w*`.

### 1.4 Navigation

```dart
OmniRoute.go('/students/101?tab=attendance');
OmniRoute.push('/students/101');
final result = await OmniRoute.push<bool>('/students/101/edit');  // navigation result
OmniRoute.pop(true);
OmniRoute.replace('/login');            // GoRouter.pushReplacement
OmniRoute.go('/dashboard');             // == pushAndRemoveUntil (go rebuilds stack from URL)

// Type-based, refactor-safe (resolved via registry, no strings):
OmniRoute.to<StudentDetailScreen>(path: {'id': '101'}, query: {'tab': 'attendance'});
OmniRoute.pushTo<StudentDetailScreen>(path: {'id': '101'}, extra: student);
```

- All static helpers delegate to the single `GoRouter` instance (no `BuildContext` stored).
- `context.go / context.push` from go_router keep working unchanged — we don't hide go_router.
- Called before `OmniApp` mounted / after dispose → `OmniRouteException.notInitialized`.

### 1.5 Dynamic routes & parameters

```dart
OmniPage.params('/attendance/daily', (p) => AttendanceScreen(
  classNo: p.queryInt('class'),          // ?class=10
  section: p.query('section'),           // &section=A
));
// p wraps GoRouterState: path(), pathInt(), query(), queryInt(), queryAll(), extra<T>()
// Invalid int → OmniRouteException.invalidParameter → error screen (debug: detailed)
```

### 1.6 Nested / Shell routes
`children:` on `OmniPage` → nested `GoRoute`. `OmniShell(builder, routes)` → `ShellRoute`; `OmniShell.stateful(builder, branches)` → `StatefulShellRoute.indexedStack` (tab state + per-branch Blocs preserved natively by IndexedStack).

### 1.7 Guards / redirect

```dart
class AuthGuard extends OmniGuard {
  @override
  Listenable? refresh(BuildContext c) => c.read<AuthBloc>().asListenable(); // re-run on auth change

  @override
  FutureOr<String?> redirect(BuildContext c, GoRouterState s) {
    final loggedIn = c.read<AuthBloc>().state is Authenticated;
    if (!loggedIn && s.matchedLocation != '/login') return '/login?from=${Uri.encodeComponent(s.uri.path)}';
    if (loggedIn && s.matchedLocation == '/login') return '/dashboard';
    return null;
  }
}
// per screen:   OmniPage(AdminScreen.new, guards: [RoleGuard('admin')])
```
Guards compose into GoRouter's native `redirect` (global) and `GoRoute.redirect` (per route). Loop prevention = GoRouter `redirectLimit` + a debug check that a guard never redirects to the current location. No API call per navigation: guards read Bloc state only.

### 1.8 Deep links & web URLs
`OmniApp` calls `usePathUrlStrategy()` (configurable: `urlStrategy: OmniUrlStrategy.path | hash`). Deep links / App Links / Universal Links are handled by GoRouter once the platform files are configured (§5). Browser title: default `screenName`, override `String? get title`, implemented with Flutter's `Title` widget.

---

## 2. Deliverable B — Architecture

```
┌──────────────────────── Developer code ────────────────────────┐
│ OmniApp(routes, blocs, guards)   OmniStateless/StatefulWidget   │
│ OmniRoute.go / push / to<T>()    Provide<B>()                   │
└───────────────┬──────────────────────────────┬─────────────────┘
                │ builds once                  │ declares
┌───────────────▼───────── OmniRoute (thin layer) ───────────────┐
│ ScreenRegistry (Type→path,factory)   BlocRegistry (Type→create) │
│ RouteBuilder: OmniPage→GoRoute,      ScreenScope: wraps each    │
│   OmniShell→(Stateful)ShellRoute       page in MultiBlocProvider│
│ GuardComposer → redirect + refreshListenable    Validator/Errors│
└───────┬───────────────────────────────────────┬────────────────┘
        │ plain RouteBase list, redirect         │ BlocProvider(create/value)
┌───────▼──────── go_router ─────────┐   ┌──────▼──── flutter_bloc ───────┐
│ GoRouter: URL parse, stack, pages, │   │ BlocProvider lifecycle, lazy    │
│ redirect, deep link, browser hist. │   │ create, auto-close, context.read│
└───────────────┬────────────────────┘   └──────────────┬─────────────────┘
                └────────── Flutter Navigator / Router / Element tree ─────┘
```

OmniRoute owns **no** navigation stack and **no** state streams.

## 3. Deliverable C — Lifecycle

```
App start
 └ OmniApp.initState
    ├ validate registries (throws early, debug detail)
    ├ GoRouter created ONCE  (owner: OmniApp State; disposed in OmniApp.dispose)
    └ global MultiBlocProvider above MaterialApp  (owner: app scope)

Route match (go/push/deep link/refresh)
 └ GoRoute.pageBuilder → MaterialPage(key: state.pageKey,
       child: MultiBlocProvider(providers from screen.provide, child: screen))
    ├ BlocProvider.create  → owned Bloc, created lazily once per Page element
    └ BlocProvider.value   → external Bloc, never closed by us

Rebuild (setState, resize, parent rebuild) → same Element → NO new Bloc
Push B over A        → A's Page stays in Navigator → A's Blocs alive
Pop B                → B's Page element unmounts → BlocProvider closes B's owned Blocs
Replace / go()       → removed pages unmount → their owned Blocs close
StatefulShell tab    → branch kept in IndexedStack → Blocs kept
App dispose          → global Blocs closed by app-level BlocProvider, router.dispose()
```

| Resource | Owner | Closed by |
|---|---|---|
| GoRouter | `OmniApp` State | `OmniApp.dispose` |
| Global Bloc | app-level `BlocProvider` | flutter_bloc on app dispose |
| Screen Bloc | page-level `BlocProvider.create` | flutter_bloc on page unmount |
| External Bloc | creator | never by OmniRoute (`BlocProvider.value`) |
| Guard refresh listenable | `GuardComposer` | `OmniApp.dispose` |

Note: the screen widget's `provide` getter is evaluated **outside** the screen (in the page builder), so Blocs are available in the screen's own `build`/`initState` via `context.read`. Because the provider sits above the screen, it is never recreated by the screen's rebuilds.

## 4. Deliverable D — Memory & Performance Strategy

- Registries are built once, immutable maps → O(1) `Type` lookup; route matching is go_router's.
- Never store `BuildContext` globally; static helpers hold only the `GoRouter`.
- No per-navigation allocation besides what go_router does + one `MultiBlocProvider` per page.
- Ownership enforced by construction (create vs value); a debug `OmniBlocObserver` counts create/close to detect double-close and leaks.
- **Tests:** widget tests counting Bloc create/close over 1,000 push/pop cycles (must be equal, constant); tab switch 1,000×; rebuild-count probes; `leak_tracker` (Flutter's built-in leak tracking in `flutter_test`) enabled.
- **Benchmarks** (`example/integration_test/`, profile mode, same screens): raw GoRouter vs OmniRoute — startup, registration with 10/100/1,000 routes, push/pop latency, frame build/raster times via `traceAction` + `FrameTiming`; DevTools heap snapshots before/after 500 navigations. Reported numbers will be measured ones only.

## 5. Deliverable E — Platform Strategy

| Platform | Works out of the box | Needs your config |
|---|---|---|
| Android | back button, predictive back (Flutter ≥3.22 + `enableOnBackInvokedCallback`), nested nav | App Links: intent-filter in `AndroidManifest.xml` + `assetlinks.json` on domain |
| iOS | swipe-back (CupertinoPage/MaterialPage), nested nav | Universal Links: Associated Domains entitlement + `apple-app-site-association` |
| Web | path URLs, back/forward, query params | server fallback to `index.html` (Nginx `try_files $uri /index.html;`, Apache `FallbackResource /index.html`, Firebase/Netlify rewrites); `<base href="/myapp/">` for subdirectory deploy |
| Windows/macOS/Linux | mouse back buttons & keyboard via Flutter shortcuts; optional `OmniBackShortcuts` (Esc / Alt+← → `pop`) | deep links need per-OS URL scheme registration — documented, not claimed automatic |

## 6. Deliverable F — Risks & Limitations

1. Resolved by R2: path is declared once, in the route table. Trade-off: a screen does not know its own path statically (use `routeState`).
2. **No reflection** → every Bloc needs one factory registration (`OmniBloc<T>(create)`); missing → clear startup/first-use error.
3. **"Bloc only, no Cubit"**: `Provide<B extends Bloc>` enforces it. Note `flutter_bloc` itself accepts Cubit; we will simply not expose it.
4. **Static `OmniRoute.go()`** implies one router per app (multiple `OmniApp`s in tests need reset). Acceptable; tests use `OmniRoute.resetForTesting()`.
5. **go_router major versions** break often (v14→v18 in ~2 years). Pin `^18.1.4`; CI job against latest.
6. **Web refresh loses `extra`** (not in URL) — documented; use path/query for anything needed after refresh.
7. **Async guards** run on every redirect evaluation; must be cheap (read Bloc state, not network).
8. **Platform validation (Phase 8)**: I can run Web, macOS, and simulators on this Mac; physical Android/iOS deep links and Windows/Linux need your devices/CI.
9. Shell routes: a Bloc provided at a `ShellRoute` builder lives as long as the shell — needs `OmniShell(provide: [...])` support (planned).

## 7. Open questions for your review

1. ~~Registration~~ → **R2 chosen.**
2. **Global blocs:** one list with `global: true` flag, or separate `globalBlocs` list?
3. **Bloc API:** accept B2 `const [Provide<X>()]` instead of `get provide => X`?
4. Package name on pub.dev: `omni_route` (check availability before publish).

After approval → Phase 2 (package skeleton, screen base widgets, validation + tests).
