# OmniRoute — Platforms (Phase 8)

OmniRoute adds no platform code. Back navigation, deep links and transitions
come from Flutter and go_router; OmniRoute only makes the defaults below.

## Support matrix

| Platform | Navigation | Back | Deep links | How it was checked |
|---|---|---|---|---|
| Android | ✅ | system back, `PopScope` | needs manifest setup (below) | widget tests; debug APK built. **Not run on a device/emulator yet.** |
| iOS | ✅ | edge swipe-back, `PopScope` | needs Info.plist / entitlement setup | widget tests; **run in iPhone 17 Pro simulator**: custom-scheme link + auth guard + swipe-back |
| Web | ✅ | browser back/forward | any URL (path strategy) | **run in browser**: direct access, refresh, back/forward, subdirectory deploy ([web.md](web.md)) |
| macOS | ✅ | Cmd+[ , Cmd+←, mouse back | needs URL scheme setup | widget tests; release + profile builds; profile benchmark run |
| Windows | ✅ | Alt+←, mouse back | needs registry/MSIX setup | **widget tests only** (can't build Windows on a Mac) |
| Linux | ✅ | Alt+←, mouse back | needs .desktop setup | **widget tests only** (can't build Linux on a Mac) |

"Widget tests" = the same OmniRoute code run with Flutter's
`TargetPlatformVariant` for that platform (`test/platform_test.dart`).

## Page transitions

```dart
OmniApp(pageType: OmniPages.material, ...)   // default
OmniPage('/x', builder, pageType: OmniPages.none)  // per route
```

| `OmniPages.` | Behaviour |
|---|---|
| `material` (default) | Uses the theme's transition for each platform: Cupertino slide + swipe-back on iOS/macOS, Android's transition (incl. predictive back where Flutter enables it) on Android |
| `cupertino` | iOS slide + swipe-back everywhere |
| `none` | No animation — useful on web/desktop |

Or pass your own: `(key, name, child) => CustomTransitionPage(...)`.

Note: plain `GoRoute(builder:)` routes mixed into `OmniApp.routes` keep
go_router's own page choice, which may be `NoTransitionPage` (see
[performance.md](performance.md)). Use `pageBuilder` on those if you need a
transition.

## State restoration

Android can kill a backgrounded app and restart it; iOS can restore state
after relaunch. To bring the user back to the same screens:

```dart
OmniApp(
  restorationScopeId: 'router',
  builder: (context, router) => MaterialApp.router(
    restorationScopeId: 'app',
    routerConfig: router,
  ),
  ...
)
```

For stateful shells, also set `restorationScopeId` on `OmniStatefulShell`
and on each `StatefulShellBranch` (go_router requires both).

| Restored | Not restored |
|---|---|
| The route stack, including pushed pages | Bloc state: Blocs are created again, as on first open |
| The selected shell tab | `extra` objects |
| `Restorable*` values in your widgets (`RestorationMixin`) | anything only in memory |

Persist Bloc data you need yourself (e.g. local storage or
`hydrated_bloc`). Verified with `restartAndRestore` in
`test/restoration_test.dart`; not yet on a real Android process-death
cycle.

## Back navigation

- **Android / iOS:** handled by Flutter. `PopScope(canPop: false)` blocks
  system back and swipe-back (tested).
- **Desktop:** `OmniApp(desktopBack: true)` (default) adds Alt+← (Windows,
  Linux), Cmd+[ / Cmd+← (macOS) and the mouse back button. They use the same
  path as Android system back, so `PopScope` and nested shell navigators are
  respected. Not active on web (the browser does this) or mobile.
- **Escape:** off by default. `OmniApp(escapeGoesBack: true)` turns it on;
  an open dialog still closes first.

## Deep links

GoRouter handles incoming links once the OS delivers them. OmniRoute's guards
run on them like on any navigation (e.g. a logged-out user is sent to login
and continues to the link afterwards — verified on iOS).

### Android — App Links (https)
`android/app/src/main/AndroidManifest.xml`, inside the main `<activity>`:
```xml
<meta-data android:name="flutter_deeplinking_enabled" android:value="true"/>
<intent-filter android:autoVerify="true">
  <action android:name="android.intent.action.VIEW"/>
  <category android:name="android.intent.category.DEFAULT"/>
  <category android:name="android.intent.category.BROWSABLE"/>
  <data android:scheme="https" android:host="example.com"/>
</intent-filter>
```
Host `https://example.com/.well-known/assetlinks.json` with your app's
package name and signing-certificate SHA-256.
Test: `adb shell am start -a android.intent.action.VIEW -d "https://example.com/students/101"`.

### iOS — Universal Links
1. Xcode → Runner → Signing & Capabilities → Associated Domains →
   `applinks:example.com`.
2. Host `https://example.com/.well-known/apple-app-site-association`
   listing your Team ID + bundle ID and the paths.
3. Flutter deep linking is on by default (Flutter ≥ 3.27); set
   `FlutterDeepLinkingEnabled` = `YES` in Info.plist on older versions.

Test: `xcrun simctl openurl booted "https://example.com/students/101"`.

### Custom scheme (testing, or apps without a domain)
The example registers `omniroute://app/...` on iOS (`CFBundleURLTypes`) and
Android (intent-filter). Only the path and query are used, so
`omniroute://app/students/103?tab=info` opens `/students/103?tab=info`.
iOS asks the user to confirm custom-scheme links; Universal Links do not.

### macOS / Windows / Linux
Need OS-level URL-scheme registration (Info.plist `CFBundleURLTypes` on
macOS; registry or MSIX protocol on Windows; `.desktop` `MimeType` on
Linux) and, on Windows/Linux, a plugin to forward the URL to the running
app. Not automatic — not claimed as supported out of the box.

## Not yet verified
- Android on a real device or emulator (APK builds; behaviour only in tests).
- Windows and Linux builds (need those OSes / CI).
- Universal Links / App Links with a real domain (need a hosted
  association file).
