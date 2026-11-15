import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../errors/omni_route_exception.dart';
import '../guards/omni_guard.dart';
import '../screens/omni_screen.dart';
import '../screens/omni_screen_host.dart';
import '../core/omni_app_features.dart';
import 'omni_params.dart';
import 'omni_title.dart';

/// Builds a screen from the current route parameters.
typedef OmniScreenBuilder<S extends OmniScreen> = S Function(OmniParams p);

/// Builds the page shown when a screen cannot be built or no route matches.
typedef OmniErrorBuilder =
    Widget Function(BuildContext context, GoRouterState state, Object? error);

/// Creates the [Page] a screen is shown in, which decides its transition.
typedef OmniPageType =
    Page<void> Function(LocalKey key, String? name, Widget child);

/// Built-in page types for `OmniApp(pageType:)` / `OmniPage(pageType:)`.
abstract final class OmniPages {
  /// Default. Uses the theme's transition for the platform: Android
  /// predictive back, iOS/macOS slide with swipe-back, etc.
  static Page<void> material(LocalKey key, String? name, Widget child) =>
      MaterialPage<void>(
        key: key,
        name: name,
        restorationId: _restorationId(key),
        child: child,
      );

  /// Cupertino slide and swipe-back on every platform.
  static Page<void> cupertino(LocalKey key, String? name, Widget child) =>
      CupertinoPage<void>(
        key: key,
        name: name,
        title: name,
        restorationId: _restorationId(key),
        child: child,
      );

  /// No animation (common on web and desktop).
  static Page<void> none(LocalKey key, String? name, Widget child) =>
      NoTransitionPage<void>(
        key: key,
        name: name,
        restorationId: _restorationId(key),
        child: child,
      );

  // go_router page keys are unique, stable ValueKey<String>s per match:
  // reuse them so the Navigator can restore the page stack.
  static String? _restorationId(LocalKey key) =>
      key is ValueKey<String> ? key.value : null;
}

/// A route to an OmniRoute screen. Compiles to a plain [GoRoute].
///
/// ```dart
/// OmniPage('/students', (_) => const StudentScreen(), children: [
///   OmniPage(':id', (p) => StudentDetailScreen(id: p.pathInt('id'))),
/// ])
/// ```
/// Top-level paths start with `/`; child paths are relative.
class OmniPage<S extends OmniScreen> extends GoRoute {
  /// A route at [path] showing the screen built by [screenBuilder].
  ///
  /// [guards] run before this route is shown; [routes] are nested routes.
  /// [metadata] is go_router's route metadata (e.g. `{'title': ..., 'roles':
  /// [...]}`), readable in guards via `state.metadata` and in
  /// [OmniRouteEntry.metadata].
  factory OmniPage(
    String path,
    OmniScreenBuilder<S> screenBuilder, {
    String? name,
    List<RouteBase> routes = const [],
    GlobalKey<NavigatorState>? parentNavigatorKey,
    GoRouterRedirect? redirect,
    List<OmniGuard> guards = const [],
    OmniPageType? pageType,
    Map<String, dynamic>? metadata,
  }) {
    late final OmniPage<S> page;
    page = OmniPage._(
      path,
      screenBuilder,
      (c, s) => page._buildPage(c, s),
      name,
      routes,
      parentNavigatorKey,
      composeGuards(guards, redirect),
      pageType,
      metadata,
      List.unmodifiable(guards),
    );
    return page;
  }

  OmniPage._(
    String path,
    this.screenBuilder,
    GoRouterPageBuilder pageBuilder,
    String? name,
    List<RouteBase> routes,
    GlobalKey<NavigatorState>? parentNavigatorKey,
    GoRouterRedirect? redirect,
    this.pageType,
    Map<String, dynamic>? metadata,
    this.guards,
  ) : super(
        metadata: metadata,
        path: path,
        name: name,
        routes: routes,
        parentNavigatorKey: parentNavigatorKey,
        redirect: redirect,
        pageBuilder: pageBuilder,
      );

  /// Builds the screen from the route parameters.
  final OmniScreenBuilder<S> screenBuilder;

  /// Overrides `OmniApp(pageType:)` for this route.
  final OmniPageType? pageType;

  /// Guards that run before this route is shown. Their `refresh` streams
  /// are listened to by `OmniApp`, like app-wide guards.
  final List<OmniGuard> guards;

  /// The screen type; used by `OmniRoute.to<S>()`.
  Type get screenType => S;

  /// Wraps the screen with its Bloc scope. One Page per route match (keyed
  /// by `pageKey`), so rebuilds keep the same Blocs; unmounting closes them.
  Page<void> _buildPage(BuildContext context, GoRouterState state) {
    final config = OmniPageConfig.of(context);
    Widget child;
    String? name;
    try {
      final screen = screenBuilder(OmniParams(state));
      name = screen.screenName;
      child = OmniRouteStateScope(
        state: state,
        child: hostScreen(
          screen,
          wrap: config.titles
              ? (s) => OmniTitle(title: screen.title, child: s)
              : null,
        ),
      );
    } on OmniRouteException catch (e) {
      child = config.errorBuilder(context, state, e);
    }
    final exitWindow = config.exitWindow;
    if (exitWindow != null && OmniExitGuard.supported) {
      child = OmniExitGuard(
        window: exitWindow,
        onWarning: config.onExitWarning,
        child: child,
      );
    }
    return (pageType ?? config.pageType)(state.pageKey, name, child);
  }
}

/// Per-app page settings, provided by OmniApp above its router so that
/// several OmniApps (multi-window desktop, tests) never share settings.
@internal
class OmniPageConfig extends InheritedWidget {
  /// Provides the settings to [child].
  const OmniPageConfig({
    super.key,
    required this.pageType,
    required this.titles,
    required this.errorBuilder,
    this.exitWindow,
    this.onExitWarning,
    required super.child,
  });

  /// Defaults used when no OmniApp is above (e.g. a bare GoRouter in tests).
  static const fallback = OmniPageConfig(
    pageType: OmniPages.material,
    titles: true,
    errorBuilder: defaultOmniErrorBuilder,
    child: SizedBox(),
  );

  /// Default page type.
  final OmniPageType pageType;

  /// Whether pages set the browser/app-switcher title.
  final bool titles;

  /// Shows invalid-parameter and not-found errors.
  final OmniErrorBuilder errorBuilder;

  /// "Press back again to exit" window on the first page (Android), or null.
  final Duration? exitWindow;

  /// Called on the first back press when [exitWindow] is set.
  final void Function(BuildContext context)? onExitWarning;

  /// The nearest settings, read without subscribing (pages are built by the
  /// router, which already rebuilds them when needed).
  static OmniPageConfig of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<OmniPageConfig>() ?? fallback;

  @override
  bool updateShouldNotify(OmniPageConfig old) =>
      old.pageType != pageType ||
      old.titles != titles ||
      old.errorBuilder != errorBuilder ||
      old.exitWindow != exitWindow ||
      old.onExitWarning != onExitWarning;
}

/// Default error page: details in debug, a generic message in release.
Widget defaultOmniErrorBuilder(
  BuildContext context,
  GoRouterState state,
  Object? error,
) => Scaffold(
  body: Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Page not found', style: TextStyle(fontSize: 24)),
          const SizedBox(height: 8),
          Text(
            kDebugMode ? '${state.uri}\n$error' : state.uri.path,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  ),
);
