# Release checklist & validation report

## Status at 0.1.0

| Check | Result |
|---|---|
| `flutter analyze` (package, with `public_member_api_docs`) | no issues |
| `flutter analyze` (example) | no issues |
| Package tests (leak tracking on) | 56 passed |
| Example flow test | 1 passed |
| `dart doc` | 0 warnings, 0 errors |
| `dart pub publish --dry-run` | 1 warning: no `homepage`/`repository` |
| Example builds | Android APK, iOS simulator, macOS release, web |
| Live runs | web (browser), iOS simulator |

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
