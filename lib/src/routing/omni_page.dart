import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../bloc/omni_bloc_scope.dart';
import '../errors/omni_route_exception.dart';
import '../guards/omni_guard.dart';
import '../screens/omni_screen.dart';
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
      MaterialPage<void>(key: key, name: name, child: child);

  /// Cupertino slide and swipe-back on every platform.
  static Page<void> cupertino(LocalKey key, String? name, Widget child) =>
      CupertinoPage<void>(key: key, name: name, title: name, child: child);

  /// No animation (common on web and desktop).
  static Page<void> none(LocalKey key, String? name, Widget child) =>
      NoTransitionPage<void>(key: key, name: name, child: child);
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
  factory OmniPage(
    String path,
    OmniScreenBuilder<S> screenBuilder, {
    String? name,
    List<RouteBase> routes = const [],
    GlobalKey<NavigatorState>? parentNavigatorKey,
    GoRouterRedirect? redirect,
    List<OmniGuard> guards = const [],
    OmniPageType? pageType,
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
  ) : super(
        path: path,
        name: name,
        routes: routes,
        parentNavigatorKey: parentNavigatorKey,
        redirect: redirect,
        pageBuilder: pageBuilder,
      );

  final OmniScreenBuilder<S> screenBuilder;

  /// Overrides `OmniApp(pageType:)` for this route.
  final OmniPageType? pageType;

  Type get screenType => S;

  /// Wraps the screen with its Bloc scope. One Page per route match (keyed
  /// by `pageKey`), so rebuilds keep the same Blocs; unmounting closes them.
  Page<void> _buildPage(BuildContext context, GoRouterState state) {
    Widget child;
    String? name;
    try {
      final screen = screenBuilder(OmniParams(state));
      name = screen.screenName;
      child = OmniBlocScope(
        provide: screen.provide,
        child: omniTitles
            ? OmniTitle(title: screen.title, child: screen)
            : screen,
      );
    } on OmniRouteException catch (e) {
      child = omniErrorBuilder(context, state, e);
    }
    return (pageType ?? omniPageType)(state.pageKey, name, child);
  }
}

/// Set by OmniApp: default page type.
@internal
OmniPageType omniPageType = OmniPages.material;

/// Set by OmniApp: whether pages set the browser/app-switcher title.
@internal
bool omniTitles = true;

/// Set by OmniApp. Shows invalid-parameter and not-found errors.
@internal
OmniErrorBuilder omniErrorBuilder = defaultOmniErrorBuilder;

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
