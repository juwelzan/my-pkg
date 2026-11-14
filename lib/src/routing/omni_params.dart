import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../errors/omni_route_exception.dart';

/// Typed access to the current route's path parameters, query parameters
/// and `extra`. Wraps [GoRouterState]; values are already URL-decoded.
@immutable
class OmniParams {
  /// Wraps [state].
  const OmniParams(this.state);

  /// The underlying go_router state.
  final GoRouterState state;

  /// The full location, including query.
  Uri get uri => state.uri;

  /// Required path parameter, e.g. `id` in `/students/:id`.
  String path(String name) {
    final v = state.pathParameters[name];
    if (v == null) _fail(name, 'missing path parameter');
    return v;
  }

  /// Path parameter parsed as int; an invalid value shows the not-found page.
  int pathInt(String name) => _int(name, path(name));

  /// Optional query parameter (`?class=10`).
  String? query(String name) => state.uri.queryParameters[name];

  /// Optional query parameter parsed as int. Present but not an int → error.
  int? queryInt(String name) {
    final v = query(name);
    return v == null ? null : _int(name, v);
  }

  /// All values of a repeated query parameter (`?tag=a&tag=b`).
  List<String> queryAll(String name) =>
      state.uri.queryParametersAll[name] ?? const [];

  /// `extra` passed with `push`/`go`. Lost on web refresh — never rely on it
  /// for data the page needs after reload.
  T? extra<T>() {
    final e = state.extra;
    if (e == null) return null;
    if (e is T) return e as T;
    _fail('extra', 'expected $T, got ${e.runtimeType}');
  }

  int _int(String name, String v) =>
      int.tryParse(v) ?? _fail(name, '"$v" is not an integer');

  Never _fail(String name, String why) => throw OmniRouteException(
    OmniErrorCode.invalidParameter,
    'Route ${state.uri}: parameter "$name": $why.',
  );
}
