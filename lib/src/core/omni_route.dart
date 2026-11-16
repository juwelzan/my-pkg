import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:meta/meta.dart';

import '../errors/omni_route_exception.dart';
import 'omni_log.dart';
import 'omni_route_entry.dart';
import '../routing/omni_route_registry.dart';
import '../screens/omni_screen.dart';

/// Navigation helpers for the running [OmniApp]. Each call delegates to its
/// single [GoRouter]; `context.go(...)` from go_router works just as well.
///
/// With several [OmniApp]s mounted at once (e.g. multi-window desktop), these
/// helpers act on the most recently mounted one; navigate the others with
/// `context.go(...)` from inside them.
abstract final class OmniRoute {
  // Mounted apps, oldest first; the helpers use the last one.
  static final List<(GoRouter, OmniRouteRegistry)> _apps = [];

  static GoRouter? get _router => _apps.isEmpty ? null : _apps.last.$1;
  static OmniRouteRegistry? get _registry =>
      _apps.isEmpty ? null : _apps.last.$2;

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

  /// Where OmniRoute's own logs go (`OmniApp(logNavigation: true)`, guard
  /// warnings), via the `logger` package. Debug builds only by default,
  /// one framed block per event with time and level emoji. Replace it to
  /// change the format or send logs elsewhere:
  ///
  /// ```dart
  /// OmniRoute.logger = Logger(printer: SimplePrinter());
  /// ```
  static Logger logger = defaultOmniLogger();

  /// The app's GoRouter, for anything these helpers don't cover.
  static GoRouter get router =>
      _router ??
      (throw const OmniRouteException(
        OmniErrorCode.notInitialized,
        'No OmniApp is mounted.',
        hint: 'Navigate after OmniApp is built, or use context.go(...).',
      ));

  /// Connects the helpers to [r]. Called by OmniApp.
  @internal
  static void attach(GoRouter r, OmniRouteRegistry reg) => _apps.add((r, reg));

  /// Disconnects [r]; the previously mounted app (if any) becomes current.
  @internal
  static void detach(GoRouter r) =>
      _apps.removeWhere((app) => identical(app.$1, r));

  /// Current location, e.g. `/students/101?tab=a`.
  ///
  /// Includes pages added with [push] (go_router's base configuration does
  /// not), so it always matches the page on top.
  static Uri get location => router.state.uri;

  /// go_router's state of the page on top (params, `metadata`, `extra`...).
  static GoRouterState get state => router.state;

  /// The page on top.
  static OmniRouteEntry get current {
    final s = router.state;
    final route = s.topRoute;
    return route == null
        ? OmniRouteEntry(
            location: s.matchedLocation,
            name: s.name,
            path: s.path,
          )
        : OmniRouteEntry.fromRoute(route, s.matchedLocation);
  }

  /// All pages, bottom to top, including pages inside shells and pushed
  /// pages — for debugging tools and tests.
  static List<OmniRouteEntry> get stack =>
      entriesOf(router.routerDelegate.currentConfiguration);

  /// Replace the whole stack with [location] (also the way to "clear and go").
  static void go(String location, {Object? extra}) =>
      router.go(location, extra: extra);

  /// Push [location] on the stack; completes with the value given to [pop].
  static Future<T?> push<T extends Object?>(String location, {Object? extra}) =>
      router.push<T>(location, extra: extra);

  /// Replace the top page.
  static void replace(String location, {Object? extra}) =>
      router.pushReplacement(location, extra: extra);

  /// Pop the top page, completing its [push] future with [result].
  static void pop<T extends Object?>([T? result]) => router.pop<T>(result);

  /// Whether there is a page to pop.
  static bool canPop() => router.canPop();

  /// [pop] if there is a page to pop; returns whether it popped. Safe to
  /// call on the first page, where [pop] would throw.
  static bool maybePop<T extends Object?>([T? result]) {
    if (!router.canPop()) return false;
    router.pop<T>(result);
    return true;
  }

  /// Open [location] without duplicating pages, so apps can navigate with
  /// push (keeping a page behind for back / swipe-back) everywhere:
  ///
  /// - already on top: nothing (a different query on the top page replaces
  ///   it);
  /// - already in the stack: pops back to it;
  /// - otherwise pushes it, unless the stack already holds [maxDepth] pages,
  ///   then [go]es there (resets the stack).
  static Future<T?> open<T extends Object?>(
    String location, {
    Object? extra,
    int maxDepth = 10,
  }) async {
    final target = Uri.parse(location);
    if (OmniRoute.location == target) return null;
    final stack = OmniRoute.stack;
    final index = stack.lastIndexWhere((e) => e.location == target.path);
    if (index >= 0) {
      await _popWhile(() => OmniRoute.location.path != target.path);
      if (OmniRoute.location != target) replace(location, extra: extra);
      return null;
    }
    if (stack.length >= maxDepth) {
      go(location, extra: extra);
      return null;
    }
    return push<T>(location, extra: extra);
  }

  /// [open] for a screen type, like [to]/[pushTo]: builds the location
  /// from [path] and [query] parameters. Completes with the pop result
  /// when it pushed (use [open] with a type for a typed result).
  static Future<Object?> openTo<S extends OmniScreen>({
    Map<String, String> path = const {},
    Map<String, String> query = const {},
    Object? extra,
    int maxDepth = 10,
  }) => open<Object?>(
    locationOf<S>(path: path, query: query),
    extra: extra,
    maxDepth: maxDepth,
  );

  /// Pop pages until [location] (its path; query ignored) is on top, one
  /// page per frame; completes when done.
  /// Returns whether it was found; when it is not in the stack, nothing is
  /// popped. Ignores `PopScope`, like [popToRoot].
  static Future<bool> popUntil(String location) async {
    final path = Uri.parse(location).path;
    if (!stack.any((e) => e.location == path)) return false;
    await _popWhile(() => OmniRoute.location.path != path);
    return OmniRoute.location.path == path;
  }

  /// Pop every page that can be popped, back to the first page (of the
  /// current tab inside a shell).
  ///
  /// Like Flutter's `Navigator.popUntil` and [pop], this ignores
  /// `PopScope(canPop: false)`, which only guards user back actions.
  static Future<void> popToRoot() => _popWhile(() => true);

  // One pop per frame: go_router's navigator only sees the new page list
  // after a rebuild, and a second pop in the same frame would complete the
  // same pushed page twice. Bounded by the stack size, so it always ends.
  static Future<void> _popWhile(bool Function() keepGoing) async {
    for (var i = stack.length; i > 0 && keepGoing() && router.canPop(); i--) {
      router.pop<Object?>();
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// Re-run redirects and guards for the current location, e.g. after
  /// state they read has changed without a guard refresh stream.
  static void refresh() => router.refresh();

  /// Replace the top page with the route named [name].
  static void replaceNamed(
    String name, {
    Map<String, String> path = const {},
    Map<String, dynamic> query = const {},
    Object? extra,
  }) => router.pushReplacementNamed(
    name,
    pathParameters: path,
    queryParameters: query,
    extra: extra,
  );

  /// [go] to the route named [name].
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

  /// [push] the route named [name].
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

  /// [replace] the top page with the route that builds screen [S].
  static void replaceTo<S extends OmniScreen>({
    Map<String, String> path = const {},
    Map<String, String> query = const {},
    Object? extra,
  }) => replace(
    locationOf<S>(path: path, query: query),
    extra: extra,
  );

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
