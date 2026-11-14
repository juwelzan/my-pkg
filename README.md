# OmniRoute

Simple screens, routes and Bloc scoping for Flutter — built **on**
[go_router](https://pub.dev/packages/go_router) and
[flutter_bloc](https://pub.dev/packages/flutter_bloc), not instead of them.

OmniRoute has no navigation engine and no state management of its own.
`OmniPage` *is* a `GoRoute`, the router *is* a `GoRouter`, and Blocs live in
plain `BlocProvider`s. OmniRoute removes the wiring between them.

Architecture, lifecycle and Bloc ownership: [doc/architecture.md](doc/architecture.md).
Upgrading from 0.1: [doc/migration.md](doc/migration.md).

## 1. Introduction

```dart
class StudentScreen extends OmniStatelessWidget {
  const StudentScreen({super.key});

  @override
  String get screenName => 'Students';

  @override
  List<Provide> get provide => const [Provide<StudentBloc>()];

  @override
  Widget build(BuildContext context) => const StudentList();
}
```

The `StudentBloc` is created when the page opens, kept across rebuilds and
pushes, and closed when the page is popped or replaced.

## 2. Features

- `OmniStatelessWidget` / `OmniStatefulWidget` with the same API
- One `OmniApp` creating a single `GoRouter`
- Global, route-group, shell, page and screen-scoped Blocs — single or multiple, or existing instances
- Typed navigation (`OmniRoute.to<StudentDetailScreen>(...)`) plus all go_router navigation
- Typed route parameters, nested routes, shell and stateful shell routes
- Guards (sync or async, app-wide or per route) that re-run when a Bloc changes
- Clean web URLs, browser titles, trailing-slash cleanup
- Desktop back shortcuts and mouse back button
- State restoration of the route stack
- Route metadata, `OmniRoute.current` / `.stack`, `onNavigate` hook, debug logging
- Validated configuration with clear errors
- Leak-tracked tests; profile-mode benchmark against plain go_router

## 3. Installation

```yaml
dependencies:
  omni_route: ^0.2.0
  flutter_bloc: ^9.1.1   # for context.read / BlocBuilder in your code
  go_router: ^18.1.4     # only if you use go_router types directly
```

Requires Dart ≥ 3.12 and Flutter ≥ 3.44 (go_router 18's minimum).

## 4. Quick start

```dart
import 'package:flutter/material.dart';
import 'package:omni_route/omni_route.dart';

void main() {
  OmniRoute.usePathUrls(); // web: /students instead of /#/students
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => OmniApp(
        initialRoute: '/students',
        blocs: [
          OmniBloc<AuthBloc>((_) => AuthBloc(), global: true),
          OmniBloc<StudentBloc>((ctx) => StudentBloc(ctx.read<StudentRepo>())),
        ],
        routes: [
          OmniPage('/students', (_) => const StudentScreen(), routes: [
            OmniPage(':id', (p) => StudentDetailScreen(id: p.pathInt('id'))),
          ]),
        ],
        builder: (context, router) => MaterialApp.router(routerConfig: router),
      );
}
```

## 5. Screen creation

A screen is a widget with a `screenName` (required, used for logs and the
browser title) and optionally a list of Blocs. Its URL is **not** part of
the screen: it is declared once, in the route table (§8). That way screens
that need constructor arguments (`StudentDetailScreen(id: 101)`) work the
same way as screens that don't.

| Member | Required | Meaning |
|---|---|---|
| `screenName` | yes | Human-readable name; must not be empty |
| `title` | no | Browser/app-switcher title, defaults to `screenName` |
| `provide` | no | Blocs for this screen (§10–12) |
| `name` | — | Runtime class name, for debugging only (not stable under obfuscation) |
| `metadata` | — | `OmniScreenMetadata` (identity is the Dart `Type`) |

**Screens outside routes.** A screen can also be placed directly in a
layout (master–detail pane, dialog). Stateless screens then create their own
`provide` Blocs; wrap stateful ones in `OmniScreenHost`:

```dart
Row(children: [
  const Expanded(child: StudentListScreen()),                 // stateless: automatic
  Expanded(child: OmniScreenHost(screen: DashboardScreen())), // stateful: wrap
])
```

## 6. Stateless screen

```dart
class ProfileScreen extends OmniStatelessWidget {
  const ProfileScreen({super.key});

  @override
  String get screenName => 'Profile';

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(screenName)));
}
```

## 7. Stateful screen

```dart
class DashboardScreen extends OmniStatefulWidget {
  const DashboardScreen({super.key});

  @override
  String get screenName => 'Dashboard';

  @override
  State<DashboardScreen> createState() => _DashboardState();
}

class _DashboardState extends OmniState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Screen Blocs already exist here: context.read<StatsBloc>()
  }

  @override
  Widget build(BuildContext context) =>
      Text('${widget.screenName} at ${routeState.uri}');
}
```

`OmniState` is a normal `State`: `initState`, `didChangeDependencies`,
`didUpdateWidget` and `dispose` behave exactly as in Flutter. It adds
`metadata` and `routeState` (the `GoRouterState`).

## 8. Screen registration

```dart
routes: [
  OmniPage('/dashboard', (_) => const DashboardScreen()),
  OmniPage('/students', (_) => const StudentScreen(), name: 'students', routes: [
    OmniPage(':id', (p) => StudentDetailScreen(id: p.pathInt('id'))),
  ]),
  GoRoute(path: '/legacy', builder: (_, _) => const LegacyPage()), // raw go_router works too
]
```

- Top-level paths start with `/`; child paths are relative (`':id'`, `'profile'`).
- Paths must be lowercase and URL-safe, with no `#`, `?`, `//` or trailing `/`.
- Duplicate paths, including `/a/:id` vs `/a/:slug`, are rejected at startup.
- The same screen may be used by several routes.

## 9. Global Bloc

```dart
blocs: [
  OmniBloc<AuthBloc>((_) => AuthBloc(), global: true, lazy: false),
  OmniBloc<ThemeBloc>((_) => ThemeBloc(), global: true),
]
```

Global Blocs are created once above the router, are available everywhere
(including in `builder`, e.g. to switch themes), and are closed only when
`OmniApp` is disposed. A screen cannot `Provide` a global Bloc again; that is
reported as an error.

## 10. Screen Bloc

Register a factory once, then name the type on the screen:

```dart
// OmniApp
blocs: [OmniBloc<StudentBloc>((ctx) => StudentBloc(ctx.read<StudentRepo>()))],

// Screen
@override
List<Provide> get provide => const [Provide<StudentBloc>()];
```

Factories receive a `BuildContext`, so dependencies come from
`RepositoryProvider`s or global Blocs above.

## 11. Single Bloc

```dart
@override
List<Provide> get provide => const [Provide<AuthBloc>()];
```

The type parameter must be a `Bloc`; Cubits and other types do not compile.

## 12. Multiple Blocs

```dart
@override
List<Provide> get provide => [
      Provide<StudentDetailBloc>.create((_) => StudentDetailBloc(id)), // needs a parameter
      const Provide<AttendanceBloc>(),                                 // from the registry
      Provide.value(existingBloc),                                     // not owned
    ];
```

| Form | Created by | Closed by OmniRoute |
|---|---|---|
| `Provide<B>()` | registered `OmniBloc<B>` factory | yes, when the page is removed |
| `Provide<B>.create(fn)` | `fn` | yes |
| `Provide.value(bloc)` | you | **never** |

The same type twice in one list is an error.

## 13. Navigation

```dart
OmniRoute.go('/students/101?tab=info');       // replace the stack (also "clear and go")
OmniRoute.push('/students/101');              // push
final saved = await OmniRoute.push<bool>('/students/101/edit');
OmniRoute.pop(true);                          // pop with a result
OmniRoute.replace('/login');                  // replace the top page
OmniRoute.goNamed('students');
OmniRoute.to<StudentDetailScreen>(path: {'id': '101'}, query: {'tab': 'info'});
OmniRoute.pushTo<StudentDetailScreen, bool>(path: {'id': '101'});
OmniRoute.location;                           // current Uri
OmniRoute.router;                             // the GoRouter, for anything else
```

Inspecting navigation (debug tools, analytics, tests):

```dart
OmniRoute.current;   // OmniRouteEntry: location, name, screen type, metadata
OmniRoute.stack;     // all pages bottom → top, through shells and pushes
OmniRoute.state;     // go_router's GoRouterState of the top page

OmniApp(
  onNavigate: (nav) => analytics.screenView(nav.to.screen.toString(), nav.uri),
  logNavigation: true,   // prints "[OmniRoute] / → /students/7 (StudentDetailScreen)" in debug
  ...
)
```

`context.go(...)`, `context.push(...)` and all other go_router APIs keep working.

## 14. Dynamic routes

```dart
OmniPage('/attendance/daily', (p) => AttendanceScreen(
  classNo: p.queryInt('class'),   // ?class=10
  section: p.query('section'),    // &section=A
));
```

`OmniParams`: `path`, `pathInt`, `query`, `queryInt`, `queryAll`,
`extra<T>()`, `uri`, `state`. Values are already URL-decoded. An invalid
value (e.g. `/students/abc` for `pathInt`) shows the not-found page instead
of crashing.

Inside Bloc factories and `initState`, use `OmniParams.of(context)`; it reads
without subscribing:

```dart
Provide<StudentBloc>.create((c) => StudentBloc(OmniParams.of(c).pathInt('id')))
```

## 15. Nested routes

```dart
OmniPage('/settings', (_) => const SettingsScreen(), routes: [
  OmniPage('profile', (_) => const ProfileScreen()),   // /settings/profile
]),
```

Going to `/settings/profile` builds both pages; back returns to Settings.

**Route groups (route scope).** Nested routes are separate pages, so a child
route can't read its parent page's Blocs. To share Blocs between several
routes, put them in an `OmniRouteGroup`:

```dart
OmniPage('/students', (_) => const StudentListScreen(), routes: [
  OmniRouteGroup(
    scopeKey: (s) => s.pathParameters['id'],   // new Blocs for another student
    provide: [
      Provide<StudentBloc>.create((c) => StudentBloc(OmniParams.of(c).pathInt('id'))),
    ],
    routes: [
      OmniPage(':id', (p) => StudentDetailScreen(id: p.pathInt('id')), routes: [
        OmniPage('edit', (_) => const StudentEditScreen()),
      ]),
    ],
  ),
]),
```

The Blocs are created on entering the group, kept while moving inside it or
while other pages are pushed on top, and closed when the user leaves it.

## 16. Shell routes

```dart
OmniShell(
  provide: const [Provide<InboxBloc>()],             // lives while the shell is shown
  builder: (context, state, child) => AppFrame(child: child),
  routes: [OmniPage('/inbox', (_) => const InboxScreen())],
),

OmniStatefulShell(
  builder: (context, state, shell) => Scaffold(
    body: shell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: shell.goBranch,
      destinations: const [/* ... */],
    ),
  ),
  branches: [
    StatefulShellBranch(routes: [OmniPage('/dashboard', (_) => const DashboardScreen())]),
    StatefulShellBranch(routes: [OmniPage('/students', (_) => const StudentScreen())]),
  ],
),
```

`OmniStatefulShell` uses go_router's `StatefulShellRoute.indexedStack`: each
tab keeps its own stack, widget state and Blocs while other tabs are shown.

## 17. Authentication guard

```dart
class AuthGuard extends OmniGuard {
  const AuthGuard();

  @override
  Stream<Object?> refresh(BuildContext context) =>
      context.read<AuthBloc>().stream;          // re-check when auth changes

  @override
  String? redirect(BuildContext context, GoRouterState state) {
    final loggedIn = context.read<AuthBloc>().state.isLoggedIn;
    final atLogin = state.matchedLocation == '/login';
    if (!loggedIn && !atLogin) {
      return Uri(path: '/login', queryParameters: {'from': state.uri.toString()}).toString();
    }
    if (loggedIn && atLogin) return state.uri.queryParameters['from'] ?? '/';
    return null;
  }
}

OmniApp(guards: const [AuthGuard()], ...);
OmniPage('/admin', (_) => const AdminScreen(),
    guards: [OmniGuard.fn((c, s) => c.read<AuthBloc>().state.isAdmin ? null : '/denied')]);
```

- Guards run in order; the first non-null redirect wins. They may be `async`.
- Sync guards stay synchronous, so they add no extra frame of delay.
- A redirect to the current location is ignored; longer loops are stopped by
  GoRouter's `redirectLimit` and shown on the error page.
- Read state, don't call APIs: guards run on every navigation.
- **Guards are not security.** They control what the UI shows; your backend
  must enforce every permission too.

Route metadata lets one guard cover many routes:

```dart
OmniPage('/admin', (_) => const AdminScreen(), metadata: const {'roles': ['admin']}),

final roleGuard = OmniGuard.fn((c, s) {
  final roles = s.metadata['roles'] as List<String>?;
  if (roles == null || roles.any(c.read<AuthBloc>().state.roles.contains)) return null;
  return '/denied';
});
```

## 18. Web path URLs

```dart
void main() {
  OmniRoute.usePathUrls();
  runApp(const MyApp());
}
```

You get `https://example.com/students/101`, browser back and forward,
refresh, direct access, browser tab titles from `title`, and
`/students/` → `/students`.

**Your server must return `index.html` for unknown paths.** Nginx:

```nginx
location / { try_files $uri $uri/ /index.html; }
```

Apache, Firebase, Netlify, Vercel, GitHub Pages and subdirectory deploys
(`flutter build web --base-href /myapp/`): see [doc/web.md](doc/web.md).

## 19. Deep linking

GoRouter receives links from the OS; OmniRoute's guards run on them like on
any navigation. You need platform setup:

- **Android App Links:** intent-filter with `android:autoVerify="true"` and
  `/.well-known/assetlinks.json`
- **iOS Universal Links:** Associated Domains `applinks:example.com` and
  `/.well-known/apple-app-site-association`

Full steps and test commands: [doc/platforms.md](doc/platforms.md#deep-links).

## 20. Platform configuration

| Platform | Back | Deep links |
|---|---|---|
| Android | system back, `PopScope` | App Links / custom scheme (manifest) |
| iOS | edge swipe-back | Universal Links / custom scheme |
| Web | browser back/forward | any URL + server fallback |
| macOS | Cmd+[, Cmd+←, mouse back | URL scheme (Info.plist) |
| Windows / Linux | Alt+←, mouse back | needs OS registration + plugin |

```dart
OmniApp(
  pageType: OmniPages.material,  // default; or OmniPages.cupertino / OmniPages.none
  desktopBack: true,             // default
  escapeGoesBack: false,         // default
  ...
)
```

What was checked on which platform: [doc/platforms.md](doc/platforms.md).

**State restoration** (Android process death, iOS restoration):

```dart
OmniApp(
  restorationScopeId: 'router',
  builder: (context, router) =>
      MaterialApp.router(restorationScopeId: 'app', routerConfig: router),
  ...
)
```

Restores the route stack, shell tabs and `Restorable*` widget state; Blocs
are created again (persist their data yourself).

## 21. Lifecycle management

| Resource | Owner | Released |
|---|---|---|
| `GoRouter` | `OmniApp` | when `OmniApp` is disposed |
| Global Bloc | app scope | when `OmniApp` is disposed |
| Route-group Bloc | `OmniRouteGroup` | when the user leaves the group or `scopeKey` changes |
| Screen Bloc (`Provide<B>()` / `.create`) | its page | when the page is popped or replaced |
| `Provide.value` Bloc | you | never by OmniRoute |
| Shell Bloc | the shell | when the shell is no longer shown |
| Screen Bloc (screen outside a route) | the screen / `OmniScreenHost` | when it is removed |
| Guard refresh subscriptions | `OmniApp` | when `OmniApp` is disposed |

- A rebuild never recreates a Bloc; a covered page keeps its Blocs.
- Each Bloc is closed exactly once.
- `OmniApp` reads its configuration once. After changing routes or Blocs, do a
  hot **restart**, as with a `GoRouter` held in state.

## 22. Performance considerations

- Startup validation and indexing run once; route matching is go_router's.
- In a profile-mode benchmark against the same app written with plain
  go_router and BlocProvider, the differences were within run-to-run noise
  ([doc/performance.md](doc/performance.md)).
- All tests run with Flutter's leak tracker.
- Keep guards cheap; put data needed after a web refresh in the URL, not in
  `extra`.

## 23. Troubleshooting

| Message / symptom | Fix |
|---|---|
| `missingBlocFactory: No factory registered for X` | add `OmniBloc<X>(...)` to `OmniApp(blocs:)` |
| `unsupportedConfiguration: X is global` | remove `Provide<X>()`; use `context.read<X>()` |
| `invalidRoutePath ... must be lowercase` | use lowercase path segments |
| `duplicateRoute` | two routes match the same URLs |
| `notInitialized: No OmniApp is mounted` | navigate after `OmniApp` is built, or use `context.go` |
| `X is used by several routes` | navigate by path or `goNamed` |
| 404 after refreshing on the web | configure the server fallback (§18) |
| No page transition on a raw `GoRoute` | use `OmniPage` or give it a `pageBuilder` |
| Route changes ignored after hot reload | hot restart |
| `screenNotHosted` | wrap the stateful screen in `OmniScreenHost` |
| `Route name "x" is used by both ...` | route names must be unique |
| Child route can't find its parent's Bloc | share it with `OmniRouteGroup` |

## 24. Complete example

[`example/lib/main.dart`](example/lib/main.dart) is a full app: login with an
auth guard, dashboard, student list, student details (multiple Blocs, one
built from a route parameter, shared with an edit page through
`OmniRouteGroup`), settings with nested profile, global auth and
theme Blocs, a bottom-tab stateful shell, and path URLs.

```bash
cd example
flutter run -d chrome   # or macos, an iOS simulator, an Android device
flutter test            # full flow test
```

## License

MIT — see [LICENSE](LICENSE).
