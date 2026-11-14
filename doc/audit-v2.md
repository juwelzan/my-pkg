# OmniRoute v0.2 — Architecture Audit & Plan

Date: 2026-11-14 · Baseline: commit `fc0da5e` (0.1.0, branch `phase-9-release-prep`)

## 1. What exists today (and works)

| Area | Current state | Evidence |
|---|---|---|
| Public API | `OmniApp`, `OmniPage`, `OmniShell`, `OmniStatefulShell`, `OmniStatelessWidget`, `OmniStatefulWidget`/`OmniState`, `OmniBloc`, `Provide`, `OmniGuard`, `OmniParams`, `OmniRoute` helpers, `OmniPages`, `OmniRouteException` | `lib/omni_route.dart` |
| GoRouter integration | `OmniPage` **is** a `GoRoute`; one `GoRouter` per `OmniApp`; raw `RouteBase`s mix in | router_test |
| Route identity | path in route table (decision R2), optional `name`, screen identity = Dart `Type` | design doc §1.3 |
| Params | `pathInt`, `query`, `queryInt`, `queryAll`, `extra<T>`; invalid → error page | router_test |
| Bloc scopes | global (app), page (route), shell; `Provide()`, `.create`, `.value`; lazy/eager | bloc_test, advanced_test |
| Ownership | create/close counts balanced over 1000 navigations; `.value` never closed; tab branches retain Blocs | performance_test |
| Guards | ordered, sync/async, per-app/per-route, Bloc-stream refresh, self-redirect ignored, loops → error page | advanced_test |
| Web | path URLs, title, trailing slash, base-href; verified in browser | web_test, doc/web.md |
| Platforms | page types, Android back, iOS swipe, desktop shortcuts | platform_test, iOS simulator run |
| Memory | leak tracker on all 56 tests | flutter_test_config.dart |

Most of this spec (Phases 3, 4, 7, 9, 10, 11, 12) is already covered.
I won't rewrite working code without a real problem; the gaps below were
confirmed by running probe tests.

## 2. Confirmed problems

| # | Problem | Severity | Probe result |
|---|---|---|---|
| **A** | A screen used **outside a route** (embedded in a layout, tablet master–detail, dialog) ignores its `provide` list; `context.read` then fails with a generic `ProviderNotFoundException` | High — spec says both base widgets must support Bloc registration | `ProviderNotFoundException` |
| **B** | Duplicate route `name`s are caught only by a go_router **debug assert**; in release builds the second name silently wins | Medium | `_AssertionError ... duplication fullpaths for name "x"` |
| **C** | No real **route scope**: a child route (`/students/:id/edit`) can't read Blocs from its parent route (`/students/:id`), because each nested route is its own page and not a widget descendant | Medium — spec Phase 5 | `ProviderNotFoundException` |
| **D** | App configuration (error page, page type, titles) lives in package-level variables. Two `OmniApp`s (multi-window desktop, nested apps, parallel tests) overwrite each other | Medium | by inspection: `omni_page.dart` lines 126–134 |
| **E** | **State restoration** isn't wired: `OmniApp` has no `restorationScopeId`, and pages get no `restorationId` | Medium — spec Phases 8, 10, 11 | by inspection |
| **F** | No route **metadata**, no **navigation hooks** (`onNavigate`, screen visits), no **stack inspection**, no optional **logging**. `observers` only reach the root navigator, not shell navigators | Low–Medium — spec Phase 8 | by inspection |

## 3. Requests I recommend not doing (or doing differently)

| Request | Recommendation | Why |
|---|---|---|
| "Unique routeName" on screens | Keep R2: the route's `name` lives on `OmniPage` (now checked for uniqueness, fix **B**); screens keep `screenName` | You chose R2; the new spec also asks to keep screen identity separate from route identity |
| Route groups | Add `OmniRouteGroup` = shell with no layout plus shared Blocs (fixes **C**); plain Dart lists (`...adminRoutes`) cover grouping without new API | built on go_router `ShellRoute`, nothing new reinvented |
| Navigation middleware | Guards already are the middleware; add `onNavigate` hook (**F**) for side effects | avoid two overlapping systems |
| Typed route classes | Keep `OmniRoute.to<S>()` + `OmniParams` + `push<T>` results; no typed route objects | real type-safe routes need code generation (go_router_builder exists for that) |
| Preventing "repeated navigation" (double tap pushes twice) | Document a debounce pattern; no built-in | blocking legitimate repeated pushes would surprise people |
| Low-memory devices | Covered by leak tracking + balanced-count tests; I can't run a low-memory device here | honest limit |
| Guards as security | Docs will state client guards are UX only; enforce on the backend | spec requirement |

## 4. Plan — small phases, each tested and non-breaking

| Phase | Work | Fixes | Tests |
|---|---|---|---|
| **1. Safety fixes** | `OmniScreenHost` (makes `provide` work for embedded stateless **and** stateful screens) + a clear error when a screen's Blocs are missing; duplicate-name check | A, B | regression tests for A, B |
| **2. Route scope & groups** | `OmniRouteGroup(provide:, routes:)`: Blocs shared by a group of routes, closed when the last route of the group is removed | C | create/close counts across group navigation |
| **3. Per-app config** | move error page, page type and titles into the app (looked up from context) | D | two `OmniApp`s with different settings in one test |
| **4. Restoration** | `OmniApp(restorationScopeId:)`, page `restorationId`s | E | `tester.restartAndRestore()` |
| **5. Dev tools** | `OmniPage(meta:)`, `OmniRoute.current` / `.stack`, `OmniApp(onNavigate:)`, optional `OmniApp(logNavigation:)` | F | hook and stack tests |
| **6. Docs** | architecture, lifecycle & ownership guide, migration guide (0.1 → 0.2, no breaking changes), security note on guards, example updates | — | example flow test |

Everything stays additive: no existing API changes signature. If any phase
turns out to need a breaking change, I'll stop and ask first.
