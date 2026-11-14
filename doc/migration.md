# Migrating from 0.1 to 0.2

0.2 adds features and fixes bugs. No public API was removed or renamed, and
most apps need no changes. Read the **behaviour changes** below; each one
was a bug fix, but code may have relied on the old behaviour.

## Behaviour changes

| Change | Was (0.1) | Now (0.2) | What to do |
|---|---|---|---|
| `OmniRoute.location` | ignored pages added with `push`; returned the location underneath | returns the page on top | if you worked around this, remove the workaround |
| Duplicate route `name`s | only a go_router debug assert; release builds silently used one of them | `OmniRouteException(duplicateRoute)` at startup in every build mode | rename the duplicate |
| Stateless screen shown outside a route with `provide` | `ProviderNotFoundException` | creates its own Blocs | nothing; remove manual `OmniBlocScope` wrappers if you like (they still work) |
| Stateful screen shown outside a route with `provide` | `ProviderNotFoundException` | the same, preceded by a clear `screenNotHosted` error | wrap it: `OmniScreenHost(screen: MyScreen())` |
| Two `OmniApp`s at once | the second's page type / titles / not-found page applied to both | each app keeps its own | nothing |
| `OmniRoute.*` after the latest of several apps is disposed | `notInitialized` | falls back to the previous app | nothing |
| Built-in page types | no `restorationId` | `restorationId` = go_router page key | nothing (used only if you enable restoration) |

## Enum addition

`OmniErrorCode.screenNotHosted` is new. A `switch` over `OmniErrorCode`
without a `default`/`_` case needs that case added.

## New APIs (optional)

| API | Use |
|---|---|
| `OmniScreenHost(screen:)` | show a stateful screen with Blocs outside a route |
| `OmniRouteGroup(provide:, scopeKey:, routes:)` | Blocs shared by several routes (route scope) |
| `OmniParams.of(context)` | route params in Bloc factories and `initState` |
| `OmniApp(restorationScopeId:)` | state restoration |
| `OmniPage(metadata:)` | per-route data for guards, analytics, titles |
| `OmniRoute.current` / `.stack` / `.state` | inspect navigation |
| `OmniApp(onNavigate:, logNavigation:)` | analytics hook, debug logging |

## Example: sharing a Bloc between detail and edit

0.1 (each page had its own copy):

```dart
OmniPage(':id', (p) => DetailScreen(id: p.pathInt('id')), routes: [
  OmniPage('edit', (p) => EditScreen(id: p.pathInt('id'))),
]),
// DetailScreen and EditScreen each: provide => [Provide<StudentBloc>.create(...)]
```

0.2 (one shared instance):

```dart
OmniRouteGroup(
  scopeKey: (s) => s.pathParameters['id'],
  provide: [
    Provide<StudentBloc>.create((c) => StudentBloc(OmniParams.of(c).pathInt('id'))),
  ],
  routes: [
    OmniPage(':id', (p) => DetailScreen(id: p.pathInt('id')), routes: [
      OmniPage('edit', (_) => const EditScreen()),
    ]),
  ],
),
// Screens drop the provide entry and use context.read<StudentBloc>().
```
