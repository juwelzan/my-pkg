# OmniRoute

**GoRouter আর flutter_bloc-এর উপর তৈরি — সহজ Screen, Route আর Bloc ব্যবস্থাপনা।**

OmniRoute নিজে কোনো নতুন Navigation Engine বা State Management নয়।
ভিতরে সব কাজ করে [go_router](https://pub.dev/packages/go_router) (navigation)
আর [flutter_bloc](https://pub.dev/packages/flutter_bloc) (Bloc)।
OmniRoute শুধু এদের মধ্যে যে বারবার লেখা "জোড়া লাগানোর কোড" লাগে, সেটা সরিয়ে দেয়।

- `OmniPage` আসলে একটা সাধারণ `GoRoute`
- Router আসলে একটা সাধারণ `GoRouter`
- প্রতিটা Bloc থাকে একটা সাধারণ `BlocProvider`-এ

তাই go_router বা flutter_bloc-এর যেকোনো ফিচার আগের মতোই ব্যবহার করা যায়।

> আরও গভীরে: [doc/architecture.md](doc/architecture.md) (ভিতরের গঠন, lifecycle, Bloc ownership),
> [doc/web.md](doc/web.md) (Web hosting), [doc/platforms.md](doc/platforms.md) (Android/iOS/Desktop),
> [doc/migration.md](doc/migration.md) (পুরনো version থেকে আপগ্রেড)।
> (এই ডকুমেন্টগুলো ইংরেজিতে।)

---

## সূচিপত্র

1. [ইনস্টলেশন](#১-ইনস্টলেশন)
2. [৫ মিনিটে শুরু](#২-৫-মিনিটে-শুরু)
3. [কোন API কী কাজে — এক নজরে](#৩-কোন-api-কী-কাজে--এক-নজরে)
4. [OmniApp — অ্যাপের মূল](#৪-omniapp--অ্যাপের-মূল)
5. [Screen তৈরি](#৫-screen-তৈরি)
6. [Route রেজিস্টার — OmniPage](#৬-route-রেজিস্টার--omnipage)
7. [Route Parameter — OmniParams](#৭-route-parameter--omniparams)
8. [Navigation — OmniRoute](#৮-navigation--omniroute)
9. [Bloc — কোথায় কোনটা](#৯-bloc--কোথায়-কোনটা)
10. [Shell ও Tab — OmniShell / OmniStatefulShell](#১০-shell-ও-tab)
11. [Route Group — কয়েকটা Route একই Bloc ভাগ করে](#১১-route-group)
12. [Guard — Login, Role, Permission](#১২-guard--login-role-permission)
13. [Lifecycle Hook — OmniLifecycle](#১৩-lifecycle-hook--omnilifecycle)
14. [Route-এর বাইরে Screen — OmniScreenHost](#১৪-route-এর-বাইরে-screen--omniscreenhost)
15. [Web — পরিষ্কার URL](#১৫-web--পরিষ্কার-url)
16. [Deep Link](#১৬-deep-link)
17. [Platform সেটিং — Page Transition, Desktop Back, Restoration](#১৭-platform-সেটিং)
18. [Debugging ও Analytics](#১৮-debugging-ও-analytics)
19. [Error ও সমাধান](#১৯-error-ও-সমাধান)
20. [সম্পূর্ণ উদাহরণ](#২০-সম্পূর্ণ-উদাহরণ)

---

## ১. ইনস্টলেশন

```yaml
dependencies:
  omni_route: ^0.2.3
  flutter_bloc: ^9.1.1   # context.read / BlocBuilder ব্যবহারের জন্য
  go_router: ^18.1.4     # go_router-এর type (যেমন GoRouterState) সরাসরি লাগলে
```

প্রয়োজন: Dart ≥ 3.12, Flutter ≥ 3.44।

```dart
import 'package:omni_route/omni_route.dart';
```

---

## ২. ৫ মিনিটে শুরু

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_route/omni_route.dart';

void main() {
  // Web-এ /#/students নয়, পরিষ্কার /students URL দেখাবে।
  // অবশ্যই runApp-এর আগে ডাকতে হবে। Android/iOS-এ এটা কিছুই করে না।
  OmniRoute.usePathUrls();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => OmniApp(
        // অ্যাপ খুললে প্রথমে কোন পেজ দেখাবে।
        initialRoute: '/students',

        // Bloc কীভাবে তৈরি হবে — একবারই এখানে বলে দিন।
        blocs: [
          // global: true → পুরো অ্যাপের জন্য একটাই instance।
          OmniBloc<AuthBloc>((_) => AuthBloc(), global: true),
          // global না → যে screen চাইবে, তার জন্য নতুন instance।
          OmniBloc<StudentBloc>((_) => StudentBloc()),
        ],

        // Route টেবিল: কোন URL-এ কোন screen।
        routes: [
          OmniPage('/students', (_) => const StudentScreen(), routes: [
            // '/students/:id' — child path-এ সামনে '/' থাকে না।
            OmniPage(':id', (p) => StudentDetailScreen(id: p.pathInt('id'))),
          ]),
        ],

        // আপনার MaterialApp — OmniApp শুধু router-টা দেয়।
        builder: (context, router) => MaterialApp.router(routerConfig: router),
      );
}

class StudentScreen extends OmniStatelessWidget {
  const StudentScreen({super.key});

  // বাধ্যতামূলক: মানুষের পড়ার মতো নাম (log আর browser title-এ ব্যবহার হয়)।
  @override
  String get screenName => 'Students';

  // এই screen-এর নিজস্ব Bloc। পেজ খুললে তৈরি, pop করলে বন্ধ — নিজে থেকেই।
  @override
  List<Provide> get provide => const [Provide<StudentBloc>()];

  @override
  Widget build(BuildContext context) {
    final students = context.watch<StudentBloc>().state; // সাধারণ flutter_bloc
    return Scaffold(
      body: ListView(children: [
        for (final s in students)
          ListTile(
            title: Text(s.name),
            // Type দিয়ে navigation — URL string ভুল লেখার ঝুঁকি নেই।
            onTap: () => OmniRoute.to<StudentDetailScreen>(path: {'id': '${s.id}'}),
          ),
      ]),
    );
  }
}
```

---

## ৩. কোন API কী কাজে — এক নজরে

| আপনি যা করতে চান | যেটা ব্যবহার করবেন |
|---|---|
| অ্যাপ সেটআপ (router, Bloc, guard একসাথে) | `OmniApp` |
| সাধারণ (state ছাড়া) screen | `OmniStatelessWidget` |
| state সহ screen (`setState`, controller) | `OmniStatefulWidget` + `OmniState` |
| একটা URL-এ একটা screen | `OmniPage` |
| URL থেকে id, query পড়া | `OmniParams` (`p.pathInt('id')`, `p.query('tab')`) |
| অন্য পেজে যাওয়া / ফেরা | `OmniRoute.go / push / pop / to<Screen>()` |
| Bloc কীভাবে তৈরি হবে বলে দেওয়া | `OmniBloc<B>(...)` (`OmniApp(blocs:)`-এ) |
| পুরো অ্যাপের Bloc (auth, theme) | `OmniBloc<B>(..., global: true)` |
| শুধু এক screen-এর Bloc | screen-এর `provide => [Provide<B>()]` |
| route parameter দিয়ে Bloc বানানো | `Provide<B>.create((c) => B(...))` |
| আগে থেকে তৈরি Bloc দেওয়া (OmniRoute বন্ধ করবে না) | `Provide.value(bloc)` |
| কয়েকটা route একই Bloc ভাগ করবে (detail + edit) | `OmniRouteGroup` |
| সব child route-এর চারপাশে একই layout | `OmniShell` |
| Bottom navigation / tab, প্রতিটা tab নিজের stack রাখবে | `OmniStatefulShell` |
| Login ছাড়া ঢুকতে না দেওয়া, role check | `OmniGuard` |
| App resume/pause, screen দেখা যাচ্ছে কি না | `OmniLifecycle` mixin |
| পুরো অ্যাপের resume/pause, শুরুতে async load, crash reporting | `OmniApp(lifecycle:, onInit:, onError:)` (৪.১) |
| keyboard বন্ধ, দুবার back-এ exit, portrait lock, font সীমা | `OmniApp(dismissKeyboardOnTap:, doubleBackToExit:, orientations:, maxTextScale:)` |
| Route ছাড়া (layout-এর ভিতরে) stateful screen বসানো | `OmniScreenHost` |
| Web-এ `#` ছাড়া URL | `OmniRoute.usePathUrls()` |
| Analytics / screen view tracking | `OmniApp(onNavigate:)` |
| এখন কোন পেজে আছি / পুরো stack | `OmniRoute.current`, `OmniRoute.stack` |

---

## ৪. OmniApp — অ্যাপের মূল

`OmniApp` একবারই `GoRouter` তৈরি করে, global Bloc গুলো সবার উপরে রাখে, আর আপনার
`MaterialApp.router`-কে router-টা দিয়ে দেয়। আপনার `MaterialApp` পুরোপুরি আপনার নিয়ন্ত্রণে থাকে।

```dart
OmniApp(
  // ── বাধ্যতামূলক ─────────────────────────────────────────
  routes: [ /* OmniPage, OmniShell, ... আর সাধারণ GoRoute-ও চলে */ ],
  builder: (context, router) => MaterialApp.router(
    routerConfig: router,      // ← এটা দিতেই হবে
    theme: ThemeData(...),     // বাকি সব আপনার মতো
  ),

  // ── ঐচ্ছিক ───────────────────────────────────────────────
  initialRoute: '/',            // শুরুর পেজ (deep link না থাকলে)
  blocs: [ /* OmniBloc<...> */ ], // Bloc factory আর global Bloc
  guards: [ /* OmniGuard */ ],    // সব route-এ চলবে এমন guard
  notFound: (context, state, error) => const NotFoundScreen(), // ভুল URL-এর পেজ

  pageType: OmniPages.material, // page transition (৯ম অংশে বিস্তারিত)
  setTitles: true,              // browser tab-এ screen-এর title বসাবে
  desktopBack: true,            // Desktop-এ Alt+← / Cmd+[ / mouse back
  escapeGoesBack: false,        // Desktop-এ Esc চাপলে back
  restorationScopeId: null,     // state restoration চালু করতে একটা id দিন

  onNavigate: (nav) {},         // প্রতিটা navigation-এর পর ডাকা হয় (analytics)
  logNavigation: false,         // true দিলে debug build-এ প্রতিটা navigation print হবে

  // অ্যাপ-লেভেল সুবিধা (সব ঐচ্ছিক, default-এ বন্ধ) — বিস্তারিত ৪.১ অংশে:
  lifecycle: null,              // পুরো অ্যাপের resume/pause hook
  onInit: null, splash: null,   // শুরুতে async কাজ + splash
  dismissKeyboardOnTap: false,  // বাইরে tap করলে keyboard বন্ধ
  doubleBackToExit: null,       // Android: দুবার back চাপলে বের হবে
  onExitWarning: null,          // প্রথম back-এ বার্তা দেখানো
  orientations: null,           // portrait / landscape lock
  minTextScale: null, maxTextScale: null, // font size-এর সীমা
  blocObserver: null,           // Bloc.observer
  onError: null,                // সব uncaught error (crash reporting)

  // সরাসরি GoRouter-এ যায় (প্রয়োজন হলে):
  redirect: null, redirectLimit: 5, refreshListenable: null,
  navigatorKey: null, observers: null, debugLogDiagnostics: false,
)
```

> ⚠️ `OmniApp`-এর setting একবারই পড়া হয় (`initState`-এ)। Route বা Bloc বদলালে
> **hot restart** দিন, hot reload যথেষ্ট নয় — `GoRouter` নিজেও এভাবেই কাজ করে।

**ভুল configuration:** কোনো path ভুল হলে, একই route দুবার থাকলে বা একই Bloc দুবার register করলে
অ্যাপ শুরুতেই পরিষ্কার error দেখাবে — পরে কোনো এক অজানা মুহূর্তে crash হবে না।

### ৪.১ অ্যাপ-লেভেল সুবিধা — যেগুলো আগে হাতে লিখতে হতো

নিচের প্রতিটা আগে `main()` বা root widget-এ নিজে লিখতে হতো। এখন `OmniApp`-এ একটা
parameter দিলেই হয়। সব ঐচ্ছিক — না দিলে আগের মতোই চলে।

```dart
// পুরো অ্যাপের lifecycle — WidgetsBindingObserver লিখতে হবে না
class AppLifecycle with OmniLifecycle {
  @override
  void onAppResumed(BuildContext context) =>
      context.read<AuthBloc>().add(TokenCheckRequested()); // global Bloc পড়া যায়

  @override
  void onAppPaused(BuildContext context) =>
      context.read<DraftBloc>().add(DraftSaved());
}

OmniApp(
  // ① অ্যাপ-লেভেল lifecycle hook (১৩তম অংশের সব hook এখানে চলে)
  lifecycle: AppLifecycle(),

  // ② শুরুতে async কাজ (settings load, login restore) — শেষ হলে প্রথম পেজ খোলে।
  //    guard তখন load করা state দেখে, তাই ভুল করে login পেজে যায় না।
  onInit: (context) async {
    await context.read<SettingsBloc>().load();
    context.read<AuthBloc>().add(SessionRestored());
  },
  // onInit চলাকালীন যা দেখাবে (পূর্ণ widget দিন)
  splash: (context) => const MaterialApp(home: SplashScreen()),

  // ③ text field-এর বাইরে tap করলে keyboard বন্ধ
  dismissKeyboardOnTap: true,

  // ④ Android: প্রথম পেজে ২ সেকেন্ডের মধ্যে দুবার back চাপলে অ্যাপ বন্ধ
  doubleBackToExit: const Duration(seconds: 2),
  onExitWarning: (context) => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('বের হতে আবার back চাপুন')),
  ),

  // ⑤ শুধু portrait (OmniApp বন্ধ হলে আবার সব orientation)
  orientations: const [DeviceOrientation.portraitUp],

  // ⑥ বড় accessibility font-এ layout ভাঙবে না
  maxTextScale: 1.3,

  // ⑦ সব Bloc-এর event/state log (Bloc.observer = ... লিখতে হবে না)
  blocObserver: AppBlocObserver(),

  // ⑧ সব uncaught error এক জায়গায় — crash reporting-এর জন্য
  onError: (error, stack) => crashReporter.record(error, stack),
  ...
)
```

| Parameter | আগে হাতে যা লিখতে হতো | নোট |
|---|---|---|
| `lifecycle` | root widget-এ `WidgetsBindingObserver` + `addObserver`/`removeObserver` | context দিয়ে global Bloc পড়া যায় |
| `onInit` + `splash` | `FutureBuilder` + splash screen + guard-এর race condition সামলানো | error হলে report করে অ্যাপ খুলে যায় — splash-এ আটকে থাকে না |
| `dismissKeyboardOnTap` | `GestureDetector(onTap: () => FocusScope.of(context).unfocus())` | text field-এ tap করলে focus থাকে |
| `doubleBackToExit` | `PopScope` + সময় হিসাব + `SystemNavigator.pop()` | শুধু Android, শুধু প্রথম পেজে; বাকি পেজে back আগের মতো |
| `orientations` | `main()`-এ `SystemChrome.setPreferredOrientations` | dispose হলে reset |
| `minTextScale` / `maxTextScale` | `MediaQuery` builder দিয়ে text scale clamp | dialog-সহ পুরো অ্যাপে |
| `blocObserver` | `main()`-এ `Bloc.observer = ...` | আগের observer dispose-এ ফেরত |
| `onError` | `FlutterError.onError` + `PlatformDispatcher.onError` দুটো আলাদা | আগের handler-ও চলে; default reporting বন্ধ হয় না |

---

## ৫. Screen তৈরি

দুই ধরনের screen-এর API একদম একই রকম।

### Stateless Screen

```dart
class ProfileScreen extends OmniStatelessWidget {
  const ProfileScreen({super.key});

  // বাধ্যতামূলক। খালি হলে error।
  @override
  String get screenName => 'Profile';

  // ঐচ্ছিক: browser tab / app switcher-এর title। না দিলে screenName।
  @override
  String get title => 'আমার প্রোফাইল';

  // ঐচ্ছিক: এই screen-এর Bloc (৯ম অংশ)।
  @override
  List<Provide> get provide => const [Provide<ProfileBloc>()];

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Profile'));
}
```

### Stateful Screen

```dart
class DashboardScreen extends OmniStatefulWidget {
  const DashboardScreen({super.key});

  @override
  String get screenName => 'Dashboard';

  @override
  List<Provide> get provide => const [Provide<StatsBloc>()];

  @override
  State<DashboardScreen> createState() => _DashboardState();
}

// State-এর জায়গায় OmniState — বাকি সব সাধারণ Flutter State-এর মতো।
class _DashboardState extends OmniState<DashboardScreen> {
  late final StatsBloc stats;

  @override
  void initState() {
    super.initState();
    // screen-এর Bloc initState-এই পাওয়া যায় — কারণ OmniRoute Bloc গুলো
    // screen-এর উপরে বসায়।
    stats = context.read<StatsBloc>();
  }

  @override
  Widget build(BuildContext context) {
    // metadata   → screen-এর নাম, title, type
    // routeState → GoRouterState (path, query, extra)
    return Text('${widget.screenName} — ${routeState.uri}');
  }
}
```

| Member | কোথায় | কাজ |
|---|---|---|
| `screenName` | দুটোতেই (বাধ্যতামূলক) | screen-এর নাম; log, title-এ ব্যবহার |
| `title` | দুটোতেই | browser tab-এর title (default `screenName`) |
| `provide` | দুটোতেই | এই screen-এর Bloc তালিকা |
| `name` | দুটোতেই | class-এর নাম — **শুধু debug-এর জন্য** (release obfuscation-এ বদলে যায়) |
| `metadata` | দুটোতেই / `OmniState` | `OmniScreenMetadata` (type, screenName, title) |
| `routeState` | `OmniState` | বর্তমান `GoRouterState` |

> Screen-এর ভিতরে URL লেখা থাকে না। URL থাকে route টেবিলে (`OmniPage`)।
> এতে `StudentDetailScreen(id: 101)`-এর মতো argument-ওয়ালা screen-ও সহজে route-এ বসে।

---

## ৬. Route রেজিস্টার — OmniPage

```dart
routes: [
  // সাধারণ route
  OmniPage('/dashboard', (_) => const DashboardScreen()),

  // nested route: /students আর /students/:id
  OmniPage(
    '/students',
    (_) => const StudentScreen(),
    name: 'students',                       // ঐচ্ছিক: নাম দিয়ে navigation (goNamed)
    metadata: const {'section': 'school'},  // ঐচ্ছিক: নিজের তথ্য (guard, analytics)
    routes: [
      OmniPage(':id', (p) => StudentDetailScreen(id: p.pathInt('id'))),
      OmniPage(':id/edit', (p) => StudentEditScreen(id: p.pathInt('id'))),
    ],
  ),

  // শুধু এই route-এর guard (১২তম অংশ)
  OmniPage('/admin', (_) => const AdminScreen(), guards: [adminGuard]),

  // শুধু এই route-এর transition (১৭তম অংশ)
  OmniPage('/popup', (_) => const PopupScreen(), pageType: OmniPages.none),

  // সাধারণ go_router route-ও মিশিয়ে ব্যবহার করা যায়
  GoRoute(path: '/legacy', builder: (_, _) => const LegacyPage()),
]
```

**Path-এর নিয়ম** (ভুল হলে অ্যাপ শুরুতেই error):

| নিয়ম | ঠিক | ভুল |
|---|---|---|
| top-level path `/` দিয়ে শুরু | `/students` | `students` |
| child path `/` ছাড়া | `':id'`, `'edit'` | `'/edit'` |
| ছোট হাতের অক্ষর | `/students` | `/Students` |
| শেষে `/` নয় | `/students` | `/students/` |
| `#`, `?`, `//` নয় | `/a/b` | `/a//b`, `/a?x=1` |
| parameter: `:নাম` | `:id`, `:userId` | `:1d` |
| একই URL দুবার নয় | — | `/a/:id` আর `/a/:slug` একসাথে |
| একই `name` দুবার নয় | — | দুটো route-এর `name: 'x'` |

> ⚠️ **Route list-এর type:** route গুলো `List<OmniPage>` টাইপের ভেরিয়েবলে রাখলে Dart
> screen-এর type হারিয়ে ফেলে, আর `OmniRoute.to<Screen>()` route খুঁজে পায় না।
> `List<RouteBase>` ব্যবহার করুন (অথবা `OmniPage<MyScreen>(...)` লিখুন)।
>
> ```dart
> final List<RouteBase> studentRoutes = [ OmniPage(...), OmniPage(...) ]; // ✅
> ```

---

## ৭. Route Parameter — OmniParams

`OmniPage`-এর builder-এ `p` হলো `OmniParams` — URL থেকে মান পড়ার সহজ উপায়।
সব মান আগে থেকেই decode করা থাকে।

```dart
// URL: /attendance/10?section=A&date=2026-11-15&late=true&sort=newest&tag=x&tag=y
OmniPage('/attendance/:class', (p) => AttendanceScreen(
  classNo:  p.pathInt('class'),             // 10      — path parameter (int)
  section:  p.query('section'),             // 'A'     — query (String?, না থাকলে null)
  page:     p.queryInt('page'),             // null    — query (int?)
  lateOnly: p.queryBool('late'),            // true    — true/false/1/0
  minScore: p.queryDouble('min'),           // null    — query (double?)
  sort:     p.queryEnum('sort', Sort.values), // Sort.newest — enum নাম দিয়ে
  tags:     p.queryAll('tag'),              // ['x','y'] — একই query একাধিকবার
  student:  p.extra<Student>(),             // push-এর সময় পাঠানো object
));
```

| Method | ফেরত দেয় | না থাকলে | ভুল মান হলে |
|---|---|---|---|
| `path(name)` | `String` | error page | — |
| `pathInt(name)` | `int` | error page | error page |
| `query(name)` | `String?` | `null` | — |
| `queryInt / queryDouble / queryBool` | `int? / double? / bool?` | `null` | error page |
| `queryEnum(name, values)` | `T?` | `null` | error page |
| `queryAll(name)` | `List<String>` | `[]` | — |
| `extra<T>()` | `T?` | `null` | error page |
| `uri` / `state` | পুরো `Uri` / `GoRouterState` | — | — |

> ভুল মান (যেমন `/students/abc`-এ `pathInt`) অ্যাপ crash করায় না — not-found পেজ দেখায়।

**Bloc factory বা `initState`-এ parameter লাগলে:** `OmniParams.of(context)`
(এটা subscribe করে না, তাই সেখানে নিরাপদ):

```dart
Provide<StudentBloc>.create(
  (context) => StudentBloc(OmniParams.of(context).pathInt('id')),
)
```

> ⚠️ `extra` URL-এ থাকে না — Web-এ refresh করলে হারিয়ে যায়।
> refresh-এর পরেও যা লাগবে, তা path বা query-তে রাখুন। গোপন তথ্য (token, password) কখনো URL-এ নয়।

---

## ৮. Navigation — OmniRoute

`OmniRoute`-এর সব method সরাসরি অ্যাপের `GoRouter`-এ যায়।
go_router-এর `context.go(...)`, `context.push(...)`-ও আগের মতো চলে।

```dart
// ── URL দিয়ে ─────────────────────────────────────────────
OmniRoute.go('/students/101?tab=info'); // পুরো stack বদলে এখানে যাও ("clear and go")
OmniRoute.push('/students/101');         // উপরে নতুন পেজ (back দিলে আগেরটায় ফিরবে)
OmniRoute.replace('/login');             // উপরের পেজটা বদলে দাও
OmniRoute.pop();                         // উপরের পেজ বন্ধ
OmniRoute.maybePop();                    // pop করা গেলে করবে, না গেলে false (crash নয়)
OmniRoute.canPop();                      // pop করা যাবে কি না

// ── ফলাফল ফেরত পাওয়া ───────────────────────────────────
final saved = await OmniRoute.push<bool>('/students/101/edit');
// edit পেজে: OmniRoute.pop(true);

// ── Screen-এর Type দিয়ে (string ছাড়া, refactor-safe) ────────
OmniRoute.to<StudentDetailScreen>(path: {'id': '101'}, query: {'tab': 'info'}); // go
OmniRoute.pushTo<StudentDetailScreen, bool>(path: {'id': '101'});               // push
OmniRoute.replaceTo<LoginScreen>();                                            // replace
OmniRoute.locationOf<StudentDetailScreen>(path: {'id': '101'}); // '/students/101'

// ── Route-এর নাম দিয়ে ───────────────────────────────────
OmniRoute.goNamed('students');
OmniRoute.pushNamed('student', path: {'id': '101'});
OmniRoute.replaceNamed('login');

// ── অন্যান্য ─────────────────────────────────────────────
OmniRoute.refresh();   // বর্তমান পেজের guard আবার চালাও
OmniRoute.location;    // এখনকার URL (push করা পেজ সহ)
OmniRoute.router;      // আসল GoRouter — বাকি সব কাজের জন্য
```

| কখন কোনটা | |
|---|---|
| Menu / tab থেকে অন্য অংশে যাওয়া | `go` |
| তালিকা থেকে detail খোলা (back-এ ফিরবে) | `push` |
| Login সফল হলে login পেজ সরিয়ে home | `go` বা `replace` |
| Form থেকে ফলাফল নিয়ে ফেরা | `push<T>` + `pop(result)` |
| প্রথম পেজে back বাটন (crash এড়াতে) | `maybePop` |

> একাধিক `OmniApp` একসাথে থাকলে (যেমন desktop-এর কয়েকটা window) `OmniRoute.*` সবশেষে
> চালু হওয়া অ্যাপে কাজ করে। অন্যটার ভিতর থেকে `context.go(...)` ব্যবহার করুন।

---

## ৯. Bloc — কোথায় কোনটা

### ধাপ ১: Factory একবার register করুন

Dart-এ reflection নেই, তাই শুধু type দেখে Bloc বানানো যায় না —
একবার বলে দিতে হয় কীভাবে বানাবে:

```dart
OmniApp(
  blocs: [
    // পুরো অ্যাপের জন্য একটাই (login, theme)
    OmniBloc<AuthBloc>((_) => AuthBloc(), global: true, lazy: false),
    OmniBloc<ThemeBloc>((_) => ThemeBloc(), global: true),

    // screen-গুলোর জন্য factory — dependency context থেকে
    OmniBloc<StudentBloc>((context) => StudentBloc(context.read<StudentRepository>())),
    OmniBloc<AttendanceBloc>((_) => AttendanceBloc()),
  ],
  ...
)
```

- `global: true` → অ্যাপ চালু থাকা পর্যন্ত বাঁচে; সব জায়গা থেকে `context.read<AuthBloc>()`।
- `lazy: false` → প্রথমেই তৈরি হবে (না দিলে প্রথম ব্যবহারের সময়)।
- শুধু `Bloc` চলে (Cubit দিলে compile হবে না)।

### ধাপ ২: Screen-এ শুধু type বলুন

```dart
// একটা Bloc
@override
List<Provide> get provide => const [Provide<StudentBloc>()];

// একাধিক Bloc
@override
List<Provide> get provide => [
  const Provide<StudentBloc>(),                                  // registry থেকে
  Provide<StudentDetailBloc>.create((_) => StudentDetailBloc(id)), // নিজের factory (parameter সহ)
  Provide.value(existingCartBloc),                               // আগে থেকে তৈরি — OmniRoute বন্ধ করবে না
];
```

### কোনটা কতক্ষণ বাঁচে

| ধরন | কোথায় লিখবেন | কখন তৈরি | কখন বন্ধ |
|---|---|---|---|
| Global | `OmniBloc(..., global: true)` | অ্যাপ শুরুতে / প্রথম ব্যবহারে | অ্যাপ বন্ধ হলে |
| Route Group | `OmniRouteGroup(provide:)` | group-এর কোনো route-এ ঢুকলে | group থেকে বেরোলে |
| Shell | `OmniShell(provide:)` | shell দেখালে | shell সরে গেলে |
| Page | screen-এর `provide` | পেজ খুললে | পেজ pop / replace হলে |
| Route-এর বাইরের Screen | screen-এর `provide` | screen বসালে | screen সরালে |
| বাইরের | `Provide.value(bloc)` | আপনি | **কখনো OmniRoute বন্ধ করে না** |

নিশ্চয়তা (সব test দিয়ে যাচাই করা):
- rebuild হলে Bloc আবার তৈরি হয় না
- উপরে নতুন পেজ push করলে নিচের পেজের Bloc বাঁচে
- লুকানো tab-এর Bloc বাঁচে
- প্রতিটা Bloc ঠিক একবার বন্ধ হয়
- global Bloc কোনো screen আবার `Provide` করতে পারে না (করলে error)

---

## ১০. Shell ও Tab

### OmniShell — কয়েকটা route-এর চারপাশে একই layout

```dart
OmniShell(
  // shell যতক্ষণ দেখা যায়, ততক্ষণ এই Bloc বাঁচে
  provide: const [Provide<InboxBloc>()],
  // child = ভিতরের route-এর পেজ
  builder: (context, state, child) => AppFrame(child: child),
  routes: [
    OmniPage('/inbox', (_) => const InboxScreen()),
    OmniPage('/inbox/:id', (p) => MessageScreen(id: p.path('id'))),
  ],
),
```

### OmniStatefulShell — Bottom Navigation (প্রতিটা tab নিজের stack রাখে)

```dart
OmniStatefulShell(
  builder: (context, state, shell) => Scaffold(
    body: shell, // বর্তমান tab
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: shell.goBranch, // tab বদল
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.people), label: 'Students'),
      ],
    ),
  ),
  branches: [
    StatefulShellBranch(routes: [OmniPage('/home', (_) => const HomeScreen())]),
    StatefulShellBranch(routes: [OmniPage('/students', (_) => const StudentScreen())]),
  ],
),
```

tab বদলালে প্রতিটা tab-এর পেজের stack, scroll, `setState`-এর মান আর Bloc — সব থেকে যায়।

---

## ১১. Route Group

Nested route গুলো আলাদা আলাদা পেজ — তাই `/students/7/edit` পেজ তার parent
`/students/7`-এর Bloc পড়তে পারে না। একই Bloc কয়েকটা route-এ ভাগ করতে `OmniRouteGroup`:

```dart
OmniPage('/students', (_) => const StudentListScreen(), routes: [
  OmniRouteGroup(
    // id বদলালে (অন্য student) পুরনো Bloc বন্ধ হয়ে নতুন তৈরি হবে
    scopeKey: (state) => state.pathParameters['id'],
    provide: [
      Provide<StudentBloc>.create(
        (context) => StudentBloc(OmniParams.of(context).pathInt('id')),
      ),
    ],
    routes: [
      OmniPage(':id', (p) => StudentDetailScreen(id: p.pathInt('id')), routes: [
        OmniPage('edit', (_) => const StudentEditScreen()), // একই StudentBloc
      ]),
    ],
  ),
]),
```

- group-এর কোনো route-এ ঢুকলে Bloc তৈরি
- detail ↔ edit যাওয়া-আসায় একই instance
- group-এর বাইরের পেজ উপরে push করলেও বাঁচে
- group থেকে বেরোলে (`go('/students')`, back) বন্ধ

---

## ১২. Guard — Login, Role, Permission

Guard ঠিক করে কোন পেজ দেখানো যাবে। `null` ফেরত = ঢুকতে দাও; একটা path ফেরত = সেখানে পাঠাও।

### Login guard (পুরো অ্যাপে)

```dart
class AuthGuard extends OmniGuard {
  const AuthGuard();

  // AuthBloc-এর state বদলালে (login/logout) guard আবার চলবে
  @override
  Stream<Object?> refresh(BuildContext context) => context.read<AuthBloc>().stream;

  @override
  String? redirect(BuildContext context, GoRouterState state) {
    final loggedIn = context.read<AuthBloc>().state.isLoggedIn;
    final atLogin = state.matchedLocation == '/login';

    // login নেই → login পেজে, আর কোথায় যেতে চেয়েছিল তা মনে রাখো
    if (!loggedIn && !atLogin) {
      return Uri(path: '/login', queryParameters: {'from': state.uri.toString()}).toString();
    }
    // login হয়ে গেছে কিন্তু login পেজে → আগের জায়গায় ফেরত
    if (loggedIn && atLogin) return state.uri.queryParameters['from'] ?? '/';
    return null; // ঢুকতে দাও
  }
}

OmniApp(guards: const [AuthGuard()], ...);
```

### নির্দিষ্ট route-এ guard

```dart
final adminGuard = OmniGuard.fn(
  (context, state) => context.read<AuthBloc>().state.isAdmin ? null : '/denied',
  refresh: (context) => context.read<AuthBloc>().stream, // role বদলালে আবার চেক
);

OmniPage('/admin', (_) => const AdminScreen(), guards: [adminGuard]),
```

### metadata দিয়ে একটা guard-এ অনেক route

```dart
OmniPage('/reports', (_) => const ReportScreen(), metadata: const {'roles': ['admin', 'teacher']}),

final roleGuard = OmniGuard.fn((context, state) {
  final roles = state.metadata['roles'] as List<String>?;
  if (roles == null) return null; // role দরকার নেই
  final mine = context.read<AuthBloc>().state.roles;
  return roles.any(mine.contains) ? null : '/denied';
});
```

নিয়ম:
- guard একের পর এক চলে; প্রথম যেটা path দেয়, সেটাই জেতে
- `async` guard চলে (`Future<String?>`); sync guard-এ কোনো বাড়তি delay নেই
- নিজের জায়গাতেই redirect করলে উপেক্ষা হয়; বড় loop হলে error পেজ (অসীম loop নয়)
- `OmniRoute.refresh()` দিয়ে হাতে guard আবার চালানো যায়
- guard-এ API call করবেন না — আগে থেকে load করা state (Bloc) পড়ুন

> 🔒 **Guard নিরাপত্তা নয়।** Guard শুধু UI-তে কী দেখাবে তা ঠিক করে। প্রতিটা permission
> আপনার backend-এও অবশ্যই যাচাই করতে হবে।

---

## ১৩. Lifecycle Hook — OmniLifecycle

`WidgetsBindingObserver`, `addObserver`, `removeObserver` — কিছুই লিখতে হবে না।
screen-এ `with OmniLifecycle` যোগ করে শুধু দরকারি hook override করুন।
register আর cleanup নিজে থেকেই হয়।

```dart
// Stateless screen-এ
class FeedScreen extends OmniStatelessWidget with OmniLifecycle {
  const FeedScreen({super.key});

  @override
  String get screenName => 'Feed';

  // অ্যাপে ফিরে এলে নতুন data আনো
  @override
  void onAppResumed(BuildContext context) =>
      context.read<FeedBloc>().add(FeedRefreshed());

  @override
  Widget build(BuildContext context) => const FeedList();
}

// Stateful screen-এ — mixin যায় State-এ
class _PlayerState extends OmniState<PlayerScreen> with OmniLifecycle {
  // উপরে অন্য পেজ এলে, tab বদলালে বা pop হলে
  @override
  void onScreenHidden(BuildContext context) => player.pause();

  // আবার দেখা গেলে
  @override
  void onScreenVisible(BuildContext context) => player.resume();

  // অ্যাপ background-এ গেলে
  @override
  void onAppPaused(BuildContext context) => player.pause();

  @override
  Widget build(BuildContext context) => PlayerView(player);
}
```

| Hook | কখন ডাকা হয় | সাধারণ ব্যবহার |
|---|---|---|
| `onAppResumed` | অ্যাপ আবার সামনে এলে | data refresh, token check |
| `onAppInactive` | focus হারালে (call, app switcher) | timer থামানো |
| `onAppHidden` | অ্যাপ দেখা যাচ্ছে না | animation থামানো |
| `onAppPaused` | background-এ গেলে | draft save, media pause |
| `onAppDetached` | engine বন্ধ হওয়ার আগে | শেষ cleanup |
| `onAppLifecycleChanged(state)` | উপরের সবগুলোতে (আগে) | একসাথে সব দেখতে |
| `onScreenVisible` | screen দেখা যেতে শুরু করলে | screen-view analytics, video চালানো |
| `onScreenHidden` | screen ঢাকা পড়লে / tab বদলালে / pop হলে | video থামানো, timer থামানো |
| `onMemoryPressure` | মেমরি কম | cache খালি করা |
| `onMetricsChanged` | size, rotation, keyboard | layout হিসাব |
| `onBrightnessChanged(b)` | light/dark mode বদল | chart-এর রং |
| `onLocalesChanged(l)` | ভাষা বদল | ভাষা-নির্ভর data আবার আনা |
| `onTextScaleChanged` | font size বদল | — |

নিয়ম:
- hook `build`-এর বাইরে চলে — `setState` বা Bloc event পাঠানো নিরাপদ
- screen dispose হওয়ার পর কোনো hook চলে না
- push করলে আগে পুরনো পেজের `onScreenHidden`, তারপর নতুনটার `onScreenVisible`
- app/system hook ঢাকা পড়া পেজ আর লুকানো tab-এও যায়
- যে screen-এ mixin নেই, তার উপর কোনো প্রভাব বা খরচ নেই

---

## ১৪. Route-এর বাইরে Screen — OmniScreenHost

কখনো screen route ছাড়া সরাসরি layout-এ বসে (tablet master–detail, dialog)।

```dart
Row(children: [
  // Stateless: নিজে থেকেই নিজের Bloc তৈরি করে
  const Expanded(child: StudentListScreen()),

  // Stateful: OmniScreenHost দিয়ে মুড়ে দিন
  Expanded(child: OmniScreenHost(screen: DashboardScreen())),
])
```

stateful screen মুড়তে ভুলে গেলে পরিষ্কার `screenNotHosted` error আসে (কী করতে হবে সহ)।

---

## ১৫. Web — পরিষ্কার URL

```dart
void main() {
  OmniRoute.usePathUrls(); // runApp-এর আগে
  runApp(const MyApp());
}
```

পাওয়া যায়: `https://example.com/students/101`, browser back/forward, refresh,
সরাসরি URL খোলা, tab-এ title, আর `/students/` → `/students` নিজে থেকেই।

**⚠️ Server-কে বলতে হবে অজানা path-এ `index.html` দিতে** — নাহলে refresh-এ 404:

```nginx
# Nginx
location / { try_files $uri $uri/ /index.html; }
```

```apache
# Apache (.htaccess)
FallbackResource /index.html
```

Subdirectory-তে (`example.com/myapp/`) deploy করলে:

```bash
flutter build web --base-href /myapp/
```

Firebase, Netlify, Vercel, GitHub Pages-এর setting: [doc/web.md](doc/web.md)।

---

## ১৬. Deep Link

OS থেকে link এলে GoRouter সেটা খোলে, আর আপনার guard-ও চলে
(login না থাকলে login পেজ → login-এর পর linked পেজ)।
এর জন্য platform-এ সেটআপ লাগে:

- **Android App Links:** `AndroidManifest.xml`-এ `autoVerify` intent-filter + `/.well-known/assetlinks.json`
- **iOS Universal Links:** Associated Domains (`applinks:example.com`) + `/.well-known/apple-app-site-association`

পুরো ধাপ আর test command: [doc/platforms.md](doc/platforms.md#deep-links)।

---

## ১৭. Platform সেটিং

### Page transition

```dart
OmniApp(pageType: OmniPages.material, ...)                // default — প্রতিটা platform-এর নিজস্ব animation
OmniApp(pageType: OmniPages.cupertino, ...)               // সব জায়গায় iOS-এর মতো slide + swipe-back
OmniApp(pageType: OmniPages.none, ...)                    // animation নেই (web/desktop-এ ভালো)
OmniPage('/x', builder, pageType: OmniPages.none)         // শুধু একটা route-এ
```

### Back বাটন

| Platform | Back | কে সামলায় |
|---|---|---|
| Android | system back, `PopScope` মানে | Flutter |
| iOS | বাম কিনারা থেকে swipe | Flutter |
| Windows / Linux | Alt+←, mouse back বাটন | OmniRoute (`desktopBack`) |
| macOS | Cmd+[, Cmd+←, mouse back | OmniRoute (`desktopBack`) |
| Web | browser back/forward | browser |

`PopScope(canPop: false)` দিয়ে back আটকানো সব platform-এ কাজ করে।

### State Restoration (Android অ্যাপ মেরে ফেললেও একই জায়গায় ফেরা)

```dart
OmniApp(
  restorationScopeId: 'router',
  builder: (context, router) => MaterialApp.router(
    restorationScopeId: 'app', // এটাও দিতে হবে
    routerConfig: router,
  ),
  ...
)
```

ফিরে আসে: পেজের stack, বেছে নেওয়া tab, `Restorable*` widget state।
ফেরে না: Bloc-এর state (Bloc নতুন করে তৈরি হয় — দরকারি data নিজে save করুন)।

---

## ১৮. Debugging ও Analytics

```dart
OmniRoute.current;  // উপরের পেজ: location, name, screen type, metadata
OmniRoute.stack;    // নিচ থেকে উপর পর্যন্ত সব পেজ (shell, push সহ)
OmniRoute.state;    // go_router-এর GoRouterState

OmniApp(
  // প্রতিটা navigation-এর পর একবার (go, push, pop, back, deep link, redirect)
  onNavigate: (nav) {
    // nav.from → আগের পেজ, nav.to → নতুন পেজ, nav.uri → পুরো URL
    analytics.logScreenView(nav.to.screen.toString(), nav.uri.toString());
  },
  // debug build-এ console-এ: [OmniRoute] / → /students/7 (StudentDetailScreen)
  logNavigation: true,
  ...
)
```

Observer লাগলে: `OmniApp(observers:)` (root), `OmniShell(observers:)`,
`OmniRouteGroup(observers:)`, `StatefulShellBranch(observers:)`।

---

## ১৯. Error ও সমাধান

সব error `OmniRouteException` — এতে `code`, `message` আর সমাধানের `hint` থাকে।

| Error / সমস্যা | কারণ | সমাধান |
|---|---|---|
| `invalidRoutePath ... lowercase` | path-এ বড় হাতের অক্ষর | ছোট হাতের লিখুন |
| `duplicateRoute` | একই URL বা একই `name` দুবার | একটার নাম/path বদলান |
| `emptyScreenName` | `screenName` খালি | নাম দিন |
| `missingBlocFactory` | Bloc register করা হয়নি | `OmniApp(blocs:)`-এ `OmniBloc<X>(...)` যোগ করুন |
| `duplicateBlocRegistration` | একই Bloc দুবার | একটা সরান |
| `unsupportedConfiguration: X is global` | global Bloc screen-এ আবার `Provide` | `Provide` সরিয়ে `context.read<X>()` |
| `screenNotHosted` | route ছাড়া stateful screen | `OmniScreenHost(screen: ...)` |
| `notInitialized` | `OmniApp` তৈরির আগে navigation | পরে navigate করুন বা `context.go` |
| `missingRoute: No OmniPage builds X` | screen-এর route নেই, বা `List<OmniPage>` টাইপ | route যোগ করুন / `List<RouteBase>` |
| `X is used by several routes` | একই screen কয়েকটা route-এ | path বা `goNamed` দিয়ে navigate |
| `invalidParameter` | URL-এ ভুল মান | not-found পেজ দেখায় (crash নয়) |
| Web-এ refresh করলে 404 | server fallback নেই | ১৫তম অংশ |
| child route parent-এর Bloc পায় না | nested route আলাদা পেজ | `OmniRouteGroup` |
| route বদল কাজ করছে না | hot reload | hot restart |

---

## ২০. সম্পূর্ণ উদাহরণ

[`example/lib/main.dart`](example/lib/main.dart)-এ একটা পূর্ণ অ্যাপ আছে:

- Login + Auth guard (login-এর পর আগের পেজে ফেরে)
- Bottom tab (`OmniStatefulShell`) — Dashboard, Students, Settings
- Dashboard: `OmniStatefulWidget` + `OmniLifecycle` (অ্যাপে ফেরা গোনে)
- Student list → detail → edit, একই Bloc ভাগ করে (`OmniRouteGroup`)
- Global Bloc: Auth আর Theme (dark mode)
- Settings → nested Profile
- Web path URL, navigation logging, state restoration

```bash
cd example
flutter run -d chrome   # বা macos, iOS simulator, Android
flutter test            # পুরো flow-এর test
```

---

## License

MIT — [LICENSE](LICENSE) দেখুন।
