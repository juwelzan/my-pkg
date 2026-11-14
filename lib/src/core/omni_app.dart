import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../bloc/omni_bloc.dart';
import '../bloc/omni_bloc_scope.dart';
import '../guards/omni_guard.dart';
import '../routing/omni_page.dart';
import '../routing/omni_route_registry.dart';
import 'omni_desktop_back.dart';
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
  });

  /// [OmniPage]s and any raw go_router [RouteBase]s.
  final List<RouteBase> routes;
  final OmniAppBuilder builder;
  final List<OmniBloc> blocs;
  final String initialRoute;

  /// Page for unknown URLs and invalid route parameters.
  final OmniErrorBuilder? notFound;

  /// App-wide guards, run in order before [redirect] on every navigation.
  final List<OmniGuard> guards;

  // Passed straight to GoRouter.
  final GoRouterRedirect? redirect;
  final int redirectLimit;
  final Listenable? refreshListenable;
  final GlobalKey<NavigatorState>? navigatorKey;
  final List<NavigatorObserver>? observers;
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
      omniErrorBuilder = onError;
      omniTitles = widget.setTitles;
      omniPageType = widget.pageType;
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
      );
      OmniRoute.attach(router, registry);
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

  @override
  void dispose() {
    final router = _router;
    if (router != null) {
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
    return OmniGlobalBlocScope(
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
    );
  }
}
