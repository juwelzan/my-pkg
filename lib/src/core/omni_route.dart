import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:meta/meta.dart';

import '../errors/omni_route_exception.dart';
import '../routing/omni_route_registry.dart';
import '../screens/omni_screen.dart';

/// Navigation helpers for the running [OmniApp]. Each call delegates to its
/// single [GoRouter]; `context.go(...)` from go_router works just as well.
abstract final class OmniRoute {
  static GoRouter? _router;
  static OmniRouteRegistry? _registry;

  /// Use clean path URLs on the web (`/students/101`, not `/#/students/101`).
  /// Call once in `main()` **before** `runApp`. No-op on other platforms.
  ///
  /// ```dart
  /// void main() {
  ///   OmniRoute.usePathUrls();
  ///   runApp(const MyApp());
  /// }
  /// ```
  /// Your server must return `index.html` for unknown paths (see README).
  static void usePathUrls() => usePathUrlStrategy();

  /// The app's GoRouter, for anything these helpers don't cover.
  static GoRouter get router =>
      _router ??
      (throw const OmniRouteException(
        OmniErrorCode.notInitialized,
        'No OmniApp is mounted.',
        hint: 'Navigate after OmniApp is built, or use context.go(...).',
      ));

  @internal
  static void attach(GoRouter r, OmniRouteRegistry reg) {
    _router = r;
    _registry = reg;
  }

  @internal
  static void detach(GoRouter r) {
    if (identical(_router, r)) _router = _registry = null;
  }

  /// Current location, e.g. `/students/101?tab=a`.
  static Uri get location => router.routerDelegate.currentConfiguration.uri;

  /// Replace the whole stack with [location] (also the way to "clear and go").
  static void go(String location, {Object? extra}) =>
      router.go(location, extra: extra);

  /// Push [location] on the stack; completes with the value given to [pop].
  static Future<T?> push<T extends Object?>(String location, {Object? extra}) =>
      router.push<T>(location, extra: extra);

  /// Replace the top page.
  static void replace(String location, {Object? extra}) =>
      router.pushReplacement(location, extra: extra);

  static void pop<T extends Object?>([T? result]) => router.pop<T>(result);

  static bool canPop() => router.canPop();

  static void goNamed(
    String name, {
    Map<String, String> path = const {},
    Map<String, dynamic> query = const {},
    Object? extra,
  }) => router.goNamed(
    name,
    pathParameters: path,
    queryParameters: query,
    extra: extra,
  );

  static Future<T?> pushNamed<T extends Object?>(
    String name, {
    Map<String, String> path = const {},
    Map<String, dynamic> query = const {},
    Object? extra,
  }) => router.pushNamed<T>(
    name,
    pathParameters: path,
    queryParameters: query,
    extra: extra,
  );

  /// URL for screen [S], e.g. `locationOf<StudentDetailScreen>(path: {'id': '101'})`.
  static String locationOf<S extends OmniScreen>({
    Map<String, String> path = const {},
    Map<String, String> query = const {},
  }) {
    router; // throws if not mounted
    return OmniRouteRegistry.location(
      _registry!.pathFor(S),
      params: path,
      query: query,
    );
  }

  /// [go] to the route that builds screen [S].
  static void to<S extends OmniScreen>({
    Map<String, String> path = const {},
    Map<String, String> query = const {},
    Object? extra,
  }) => go(
    locationOf<S>(path: path, query: query),
    extra: extra,
  );

  /// [push] the route that builds screen [S].
  static Future<T?> pushTo<S extends OmniScreen, T extends Object?>({
    Map<String, String> path = const {},
    Map<String, String> query = const {},
    Object? extra,
  }) => push<T>(
    locationOf<S>(path: path, query: query),
    extra: extra,
  );
}
