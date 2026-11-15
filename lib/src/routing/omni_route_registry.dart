import 'package:go_router/go_router.dart';
import 'package:meta/meta.dart';

import '../errors/omni_route_exception.dart';
import '../guards/omni_guard.dart';
import 'omni_page.dart';
import 'omni_path.dart';

/// Validates the route tree once at startup and indexes screens by [Type].
@internal
class OmniRouteRegistry {
  OmniRouteRegistry(List<RouteBase> routes) {
    final all = <String>[];
    final names = <String, String>{};
    void walk(List<RouteBase> list, String parent, bool topLevel) {
      for (final r in list) {
        var nextParent = parent;
        var nextTop = topLevel;
        if (r is GoRoute) {
          if (r is OmniPage) validateRoutePath(r.path, topLevel: topLevel);
          final full = topLevel || r.path.startsWith('/')
              ? r.path
              : (parent == '/' ? '/${r.path}' : '$parent/${r.path}');
          all.add(full);
          final name = r.name;
          if (name != null) {
            final previous = names[name];
            if (previous != null) {
              throw OmniRouteException(
                OmniErrorCode.duplicateRoute,
                'Route name "$name" is used by both $previous and $full.',
                hint: 'Route names must be unique; rename one of them.',
              );
            }
            names[name] = full;
          }
          if (r is OmniPage) {
            routeGuards.addAll(r.guards);
            _byType.update(r.screenType, (_) => null, ifAbsent: () => full);
          }
          nextParent = full;
          nextTop = false;
        }
        walk(r.routes, nextParent, nextTop);
      }
    }

    walk(routes, '', true);
    checkDuplicatePaths(all);
    paths = List.unmodifiable(all);
  }

  /// Full path per screen type; `null` value = screen used by several routes.
  final Map<Type, String?> _byType = {};
  late final List<String> paths;

  /// Guards declared on individual routes, in tree order.
  final List<OmniGuard> routeGuards = [];

  String pathFor(Type screen) {
    if (!_byType.containsKey(screen)) {
      throw OmniRouteException(
        OmniErrorCode.missingRoute,
        'No OmniPage builds $screen.',
        hint:
            'Add OmniPage(..., (_) => $screen(...)). If your routes are in a '
            'List<OmniPage>, Dart infers OmniPage<OmniScreen> and loses the '
            'screen type: use List<RouteBase> or write OmniPage<$screen>(...).',
      );
    }
    return _byType[screen] ??
        (throw OmniRouteException(
          OmniErrorCode.unsupportedConfiguration,
          '$screen is used by several routes; navigation by type is ambiguous.',
          hint: 'Navigate by path, or give the route a `name` and use goNamed.',
        ));
  }

  /// Fills `:params` in [path] and appends [query].
  static String location(
    String path, {
    Map<String, String> params = const {},
    Map<String, String> query = const {},
  }) {
    final used = <String>{};
    final filled = path.replaceAllMapped(RegExp(r':(\w+)'), (m) {
      final v = params[m[1]];
      if (v == null || v.isEmpty) {
        throw OmniRouteException(
          OmniErrorCode.invalidParameter,
          'Missing path parameter "${m[1]}" for $path.',
        );
      }
      used.add(m[1]!);
      return Uri.encodeComponent(v);
    });
    final extra = params.keys.toSet().difference(used);
    if (extra.isNotEmpty) {
      throw OmniRouteException(
        OmniErrorCode.invalidParameter,
        'Unknown path parameter(s) $extra for $path.',
      );
    }
    return query.isEmpty
        ? filled
        : Uri(path: filled, queryParameters: query).toString();
  }
}
