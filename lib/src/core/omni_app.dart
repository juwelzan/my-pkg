import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/omni_bloc.dart';
import '../bloc/omni_bloc_scope.dart';
import '../guards/omni_guard.dart';
import '../routing/omni_page.dart';
import '../routing/omni_route_registry.dart';
import '../screens/omni_lifecycle.dart';
import 'omni_app_features.dart';
import 'omni_desktop_back.dart';
import 'omni_route_entry.dart';
import 'omni_route.dart';

/// Builds your app widget around the router OmniApp created.
typedef OmniAppBuilder = Widget Function(BuildContext context, GoRouter router);

/// Root of an OmniRoute app. Creates the [GoRouter] once, provides global
/// Blocs above it, and hands the router to [builder]:
///
/// ```dart
/// OmniApp(
///   initialRoute: '/dashboard',
///   blocs: [OmniBloc<AuthBloc>((_) => AuthBloc(), global: true)],
///   routes: [OmniPage('/dashboard', (_) => const DashboardScreen())],
///   builder: (context, router) => MaterialApp.router(routerConfig: router),
/// )
/// ```
///
/// Configuration is read once in `initState`; changing it later (including
/// hot reload) needs a hot restart, the same as a GoRouter kept in state.
class OmniApp extends StatefulWidget {
  /// Creates the root of an OmniRoute app.
  const OmniApp({
    super.key,
    required this.routes,
    required this.builder,
    this.blocs = const [],
    this.initialRoute = '/',
    this.notFound,
    this.guards = const [],
    this.redirect,
    this.redirectLimit = 5,
    this.refreshListenable,
    this.navigatorKey,
    this.observers,
    this.debugLogDiagnostics = false,
    this.setTitles = true,
    this.pageType = OmniPages.material,
    this.desktopBack = true,
    this.escapeGoesBack = false,
    this.restorationScopeId,
    this.onNavigate,
    this.logNavigation = false,
    this.lifecycle,
    this.onInit,
    this.splash,
    this.dismissKeyboardOnTap = false,
    this.doubleBackToExit,
    this.onExitWarning,
    this.orientations,
    this.minTextScale,
    this.maxTextScale,
    this.blocObserver,
    this.onError,
  });

  /// [OmniPage]s and any raw go_router [RouteBase]s.
  final List<RouteBase> routes;

  /// Builds your app widget (e.g. `MaterialApp.router`) around the router.
  final OmniAppBuilder builder;

  /// Bloc factories; entries with `global: true` are created app-wide.
  final List<OmniBloc> blocs;

  /// Location shown first when the platform gives none (e.g. no deep link).
  final String initialRoute;

  /// Page for unknown URLs and invalid route parameters.
  final OmniErrorBuilder? notFound;

  /// App-wide guards, run in order before [redirect] on every navigation.
  final List<OmniGuard> guards;

  /// Extra GoRouter redirect, run after [guards].
  final GoRouterRedirect? redirect;

  /// Maximum redirects per navigation before GoRouter reports a loop.
  final int redirectLimit;

  /// Re-runs redirects when it notifies (in addition to guard streams).
  final Listenable? refreshListenable;

  /// Key of the root navigator.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Observers of the root navigator.
  final List<NavigatorObserver>? observers;

  /// Log GoRouter's route matching (debug builds).
  final bool debugLogDiagnostics;

  /// Set the browser tab title from each screen's `title` (default
  /// `screenName`). Turn off if you manage `Title` yourself.
  final bool setTitles;

  /// Page (transition) used for every [OmniPage] unless it sets its own.
  /// See [OmniPages].
  final OmniPageType pageType;

  /// On Windows/Linux/macOS, Alt+← / Cmd+[ / mouse back button go back.
  final bool desktopBack;

  /// Also go back on Escape (desktop only). Dialogs still close first,
  /// because Flutter handles their Escape before this.
  final bool escapeGoesBack;

  /// Enables state restoration of the route stack (Android process death,
  /// iOS state restoration). Also set `restorationScopeId` on your
  /// `MaterialApp.router`. Restores locations and `Restorable*` widget
  /// state — not Bloc state (Blocs are recreated; persist what you need).
  final String? restorationScopeId;

  /// Called after each navigation that changes the location (go, push, pop,
  /// back, deep link, redirect). Use it for analytics or screen-view
  /// tracking. Runs after the frame is scheduled; keep it cheap.
  final void Function(OmniNavigation navigation)? onNavigate;

  /// Print each navigation (debug builds only).
  final bool logNavigation;

  // ── App-level conveniences (all optional, off by default) ─────────────

  /// App-wide lifecycle hooks: an object that mixes in [OmniLifecycle]
  /// (`onAppResumed`, `onAppPaused`, `onMemoryPressure`, ...). Its context
  /// can read global Blocs. Replaces a hand-written `WidgetsBindingObserver`.
  final OmniLifecycle? lifecycle;

  /// Startup work run once before the first page is shown (load settings,
  /// restore login, warm caches). The context can read global Blocs.
  /// Guards then see the loaded state. If it throws, the error is reported
  /// and the app opens anyway.
  final Future<void> Function(BuildContext context)? onInit;

  /// Shown while [onInit] runs. Return a complete widget (for example a
  /// `MaterialApp(home: SplashScreen())`). Default: an empty box.
  final WidgetBuilder? splash;

  /// Close the keyboard when the user taps outside a text field.
  final bool dismissKeyboardOnTap;

  /// Android: on the first page, back must be pressed twice within this
  /// time to leave the app. Null (default) = normal back behaviour.
  final Duration? doubleBackToExit;

  /// Called on the first back press when [doubleBackToExit] is set — show a
  /// SnackBar such as "Press back again to exit".
  final void Function(BuildContext context)? onExitWarning;

  /// Allowed device orientations (e.g. portrait only). Restored to "all"
  /// when this OmniApp is disposed.
  final List<DeviceOrientation>? orientations;

  /// Lower bound for the system text scale (accessibility font size).
  final double? minTextScale;

  /// Upper bound for the system text scale, so large accessibility fonts
  /// cannot break layouts.
  final double? maxTextScale;

  /// Installed as `Bloc.observer` while this OmniApp is mounted (before any
  /// Bloc is created); the previous observer is restored on dispose.
  final BlocObserver? blocObserver;

  /// Receives every uncaught error: Flutter framework errors
  /// (`FlutterError.onError`) and async/platform errors
  /// (`PlatformDispatcher.onError`). Previous handlers still run. Use it for
  /// crash reporting. Restored on dispose.
  final void Function(Object error, StackTrace stack)? onError;

  @override
  State<OmniApp> createState() => _OmniAppState();
}

class _OmniAppState extends State<OmniApp> {
  late final OmniBlocRegistry _blocs;
  List<OmniGuard> _refreshGuards = const [];
  GoRouter? _router;
  Object? _configError;
  final GuardNotifier _guardRefresh = GuardNotifier();

  @override
  void initState() {
    super.initState();
    _installGlobals();
    try {
      _blocs = OmniBlocRegistry(widget.blocs);
      final registry = OmniRouteRegistry(widget.routes);
      // Route-level guards re-run on their refresh streams too.
      // A guard object shared by several routes is subscribed once.
      _refreshGuards = {...widget.guards, ...registry.routeGuards}.toList();
      final onError = widget.notFound ?? defaultOmniErrorBuilder;
      final router = _router = GoRouter(
        routes: widget.routes,
        initialLocation: widget.initialRoute,
        errorBuilder: (c, s) => onError(c, s, s.error),
        redirect: composeGuards([
          const NormalizeUrlGuard(),
          ...widget.guards,
        ], widget.redirect),
        redirectLimit: widget.redirectLimit,
        refreshListenable: widget.refreshListenable == null
            ? _guardRefresh
            : Listenable.merge([_guardRefresh, widget.refreshListenable]),
        navigatorKey: widget.navigatorKey,
        observers: widget.observers,
        debugLogDiagnostics: widget.debugLogDiagnostics,
        restorationScopeId: widget.restorationScopeId,
      );
      OmniRoute.attach(router, registry);
      if (widget.onNavigate != null || widget.logNavigation) {
        router.routerDelegate.addListener(_navigated);
      }
    } catch (e, stack) {
      // Reported (not rethrown) so the element mounts and disposes cleanly;
      // build() then shows the error.
      _configError = e;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: stack,
          library: 'omni_route',
          context: ErrorDescription('while configuring OmniApp'),
        ),
      );
    }
  }

  OmniRouteEntry? _last;
  Uri? _lastUri;
  LocalKey? _lastPageKey;

  void _navigated() {
    final router = _router!;
    final state = router.state;
    // Same page and same URI = nothing changed. A new page at the same
    // location (pushed twice, or popped back to) has a new pageKey.
    if (state.uri == _lastUri && state.pageKey == _lastPageKey) return;
    final top = state.topRoute;
    final to = top == null
        ? OmniRouteEntry(location: state.matchedLocation, name: state.name)
        : OmniRouteEntry.fromRoute(top, state.matchedLocation);
    final event = OmniNavigation(from: _last, to: to, uri: state.uri);
    _last = to;
    _lastUri = state.uri;
    _lastPageKey = state.pageKey;
    if (widget.logNavigation && kDebugMode) debugPrint('[OmniRoute] $event');
    widget.onNavigate?.call(event);
  }

  // Previous global values, restored in dispose (only if still ours).
  FlutterExceptionHandler? _prevFlutterOnError;
  FlutterExceptionHandler? _ourFlutterOnError;
  bool Function(Object, StackTrace)? _prevPlatformOnError;
  bool Function(Object, StackTrace)? _ourPlatformOnError;
  BlocObserver? _prevBlocObserver;

  void _installGlobals() {
    final onError = widget.onError;
    if (onError != null) {
      _prevFlutterOnError = FlutterError.onError;
      FlutterError.onError = _ourFlutterOnError = (details) {
        onError(details.exception, details.stack ?? StackTrace.empty);
        _prevFlutterOnError?.call(details);
      };
      final dispatcher = PlatformDispatcher.instance;
      _prevPlatformOnError = dispatcher.onError;
      dispatcher.onError = _ourPlatformOnError = (error, stack) {
        onError(error, stack);
        // false = not handled: the engine's default reporting still runs.
        return _prevPlatformOnError?.call(error, stack) ?? false;
      };
    }
    final observer = widget.blocObserver;
    if (observer != null) {
      _prevBlocObserver = Bloc.observer;
      Bloc.observer = observer;
    }
    final orientations = widget.orientations;
    if (orientations != null) {
      SystemChrome.setPreferredOrientations(orientations);
    }
  }

  void _restoreGlobals() {
    if (_ourFlutterOnError != null &&
        identical(FlutterError.onError, _ourFlutterOnError)) {
      FlutterError.onError = _prevFlutterOnError;
    }
    final dispatcher = PlatformDispatcher.instance;
    if (_ourPlatformOnError != null &&
        identical(dispatcher.onError, _ourPlatformOnError)) {
      dispatcher.onError = _prevPlatformOnError;
    }
    final prevObserver = _prevBlocObserver;
    if (prevObserver != null && identical(Bloc.observer, widget.blocObserver)) {
      Bloc.observer = prevObserver;
    }
    if (widget.orientations != null) {
      SystemChrome.setPreferredOrientations(const []); // all orientations
    }
  }

  @override
  void dispose() {
    _restoreGlobals();
    final router = _router;
    if (router != null) {
      router.routerDelegate.removeListener(_navigated);
      OmniRoute.detach(router);
      router.dispose();
    }
    _guardRefresh.dispose();
    super.dispose();
  }

  /// Optional app-level wrappers; each is added only when its setting is on.
  Widget _wrapApp(Widget app) {
    var child = app;
    if (widget.minTextScale != null || widget.maxTextScale != null) {
      child = Builder(
        builder: (context) => MediaQuery.withClampedTextScaling(
          minScaleFactor: widget.minTextScale ?? 0,
          maxScaleFactor: widget.maxTextScale ?? double.infinity,
          child: app,
        ),
      );
    }
    if (widget.dismissKeyboardOnTap) {
      child = OmniKeyboardDismiss(child: child);
    }
    final onInit = widget.onInit;
    if (onInit != null) {
      child = OmniInitGate(onInit: onInit, splash: widget.splash, child: child);
    }
    final lifecycle = widget.lifecycle;
    if (lifecycle != null) {
      child = OmniAppLifecycleScope(lifecycle: lifecycle, child: child);
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    final router = _router;
    if (router == null) {
      return ErrorWidget(_configError ?? 'OmniApp configuration failed');
    }
    return OmniPageConfig(
      pageType: widget.pageType,
      titles: widget.setTitles,
      errorBuilder: widget.notFound ?? defaultOmniErrorBuilder,
      exitWindow: widget.doubleBackToExit,
      onExitWarning: widget.onExitWarning,
      child: OmniGlobalBlocScope(
        registry: _blocs,
        child: GuardRefresh(
          guards: _refreshGuards,
          notifier: _guardRefresh,
          child: _wrapApp(
            Builder(
              builder: (c) => widget.desktopBack
                  ? OmniDesktopBack(
                      router: router,
                      escape: widget.escapeGoesBack,
                      child: widget.builder(c, router),
                    )
                  : widget.builder(c, router),
            ),
          ),
        ),
      ),
    );
  }
}
