import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../bloc/omni_bloc.dart';
import '../bloc/omni_bloc_scope.dart';
import '../guards/omni_guard.dart';
import '../routing/omni_page.dart';
import '../routing/omni_route_registry.dart';
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

  @override
  State<OmniApp> createState() => _OmniAppState();
}

class _OmniAppState extends State<OmniApp> {
  late final OmniBlocRegistry _blocs;
  GoRouter? _router;
  Object? _configError;
  final GuardNotifier _guardRefresh = GuardNotifier();

  @override
  void initState() {
    super.initState();
    try {
      _blocs = OmniBlocRegistry(widget.blocs);
      final registry = OmniRouteRegistry(widget.routes);
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

  void _navigated() {
    final router = _router!;
    final state = router.state;
    if (state.uri == _lastUri) return;
    final top = state.topRoute;
    final to = top == null
        ? OmniRouteEntry(location: state.matchedLocation, name: state.name)
        : OmniRouteEntry.fromRoute(top, state.matchedLocation);
    final event = OmniNavigation(from: _last, to: to, uri: state.uri);
    _last = to;
    _lastUri = state.uri;
    if (widget.logNavigation && kDebugMode) debugPrint('[OmniRoute] $event');
    widget.onNavigate?.call(event);
  }

  @override
  void dispose() {
    final router = _router;
    if (router != null) {
      router.routerDelegate.removeListener(_navigated);
      OmniRoute.detach(router);
      router.dispose();
    }
    _guardRefresh.dispose();
    super.dispose();
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
      child: OmniGlobalBlocScope(
        registry: _blocs,
        child: GuardRefresh(
          guards: widget.guards,
          notifier: _guardRefresh,
          child: Builder(
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
    );
  }
}
