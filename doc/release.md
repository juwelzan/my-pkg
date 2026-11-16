# Release checklist & validation report

## Status at 0.2.0

| Check | Result |
|---|---|
| `flutter analyze` (package, with `public_member_api_docs`) | no issues |
| `flutter analyze` (example) | no issues |
| Package tests (leak tracking on) | 78 passed |
| Example flow test | 1 passed |
| `dart doc` | 0 warnings, 0 errors |
| `dart pub publish --dry-run` | 1 warning: no `homepage`/`repository` |
| Example builds | Android APK, iOS simulator, macOS release, web |
| Live runs | web (browser), iOS simulator (both on 0.1.0; 0.2 changes verified by tests) |

## Spec acceptance criteria

| Criterion | Status |
|---|---|
| GoRouter does all navigation; no new navigation engine | ✅ `OmniPage` is a `GoRoute`; router is a `GoRouter` |
| flutter_bloc does all Bloc management; no new state engine | ✅ `BlocProvider` / `MultiBlocProvider` only |
| OmniStatelessWidget / OmniStatefulWidget, same Bloc API | ✅ |
| Single & multiple Bloc registration | ✅ |
| Global & screen Bloc scope | ✅ |
| Correct Bloc lifecycle, no duplicate creation | ✅ tested (create/close counts) |
| No memory leaks found | ✅ leak tracker on all tests; 2 error-path leaks fixed |
| No added jank | ✅ within noise vs plain go_router (UI thread, profile) — see performance.md for method limits |
| Clean path URLs, back/forward, refresh, deep link | ✅ verified in a browser |
| Nested navigation | ✅ |
| Android & iOS back behaviour | ✅ tests; iOS swipe-back verified in simulator |
| Desktop navigation | ✅ tests (keyboard, mouse back) |
| Automated tests pass | ✅ |
| Example app works | ✅ |
| Documentation complete | ✅ README (24 sections), doc/web.md, doc/platforms.md, doc/performance.md |

## Known gaps (not claimed)

- Android on a real device/emulator; Windows and Linux builds.
- App Links / Universal Links with a real domain.
- Raster-thread frame timing and DevTools heap snapshots on a
  foreground display.
- Desktop deep links need OS registration and a plugin.

## Before publishing

1. Choose the license holder name (LICENSE says "The OmniRoute Authors").
2. Add `repository:` (and optionally `homepage:`, `issue_tracker:`) to
   `pubspec.yaml`.
3. Check the name `omni_route` is free on pub.dev.
4. Remove the `publish_to: none` line.
5. `dart pub publish --dry-run`, then `dart pub publish`.

## Minimum SDK (checked for 0.3.0)

Found by lowering each package's `sdk:` floor and analyzing, plus each
dependency's own `environment`:

| Package | Floor | Why |
|---|---|---|
| `omni_route` | Dart `^3.12.0`, Flutter `>=3.44.0` | `go_router` 18.1.4 requires exactly this; the package's own code needs Dart 3.8 (null-aware elements) |
| `omni_network` | Dart `^3.12.0` | private named parameters (Dart 3.12); also null-aware elements (3.8) |
| `omni_network_ws` | Dart `^3.12.0` | private named parameters |
| `omni_network_flutter` | Dart `^3.12.0` (so Flutter ≥ 3.44) | private named parameters; `flutter_secure_storage` 11.2 alone needs Dart 3.8 / Flutter 3.19 |
| `omni_network_openapi` | Dart `^3.5.0` | no newer language features; 3.5 is the minimum for a pub workspace member |

Going lower for `omni_route` means allowing an older `go_router`; going
lower for the network packages means replacing private named parameters.

## Branches and tags

- `main` is the release branch.
- Every `omni_route` release is tagged `vX.Y.Z` (e.g. `v0.3.0`); every
  sub-package release is tagged `<package>-vX.Y.Z` (e.g.
  `omni_network-v0.1.0`). Users depend on these tags with `git:` + `ref:`.
- The repository is a pub workspace: one `flutter pub get` at the root
  resolves the root package and `packages/*`.
