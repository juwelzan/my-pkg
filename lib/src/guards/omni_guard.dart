import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Redirect logic built on GoRouter's native `redirect`.
///
/// Return a location to redirect, or `null` to allow. Keep it cheap: read
/// Bloc state (e.g. `context.read<AuthBloc>().state`), never call an API.
///
/// ```dart
/// class AuthGuard extends OmniGuard {
///   @override
///   Stream<Object?> refresh(BuildContext c) => c.read<AuthBloc>().stream;
///
///   @override
///   String? redirect(BuildContext c, GoRouterState s) {
///     final ok = c.read<AuthBloc>().state is Authenticated;
///     if (!ok && s.matchedLocation != '/login') return '/login';
///     if (ok && s.matchedLocation == '/login') return '/';
///     return null;
///   }
/// }
/// ```
abstract class OmniGuard {
  const OmniGuard();

  /// Guard from a function.
  const factory OmniGuard.fn(
    GoRouterRedirect redirect, {
    Stream<Object?>? Function(BuildContext)? refresh,
  }) = _FnGuard;

  FutureOr<String?> redirect(BuildContext context, GoRouterState state);

  /// Stream whose events re-run redirects (e.g. an auth Bloc's stream).
  /// Subscribed once below the global Blocs; cancelled with the app.
  Stream<Object?>? refresh(BuildContext context) => null;
}

class _FnGuard extends OmniGuard {
  const _FnGuard(this._redirect, {this._refresh});
  final GoRouterRedirect _redirect;
  final Stream<Object?>? Function(BuildContext)? _refresh;

  @override
  FutureOr<String?> redirect(BuildContext c, GoRouterState s) =>
      _redirect(c, s);

  @override
  Stream<Object?>? refresh(BuildContext c) => _refresh?.call(c);
}

/// Runs [guards] in order; first non-null redirect wins. A redirect to the
/// current location is ignored (it would loop); longer loops are caught by
/// GoRouter's `redirectLimit` and shown on the error page.
@internal
GoRouterRedirect? composeGuards(
  List<OmniGuard> guards,
  GoRouterRedirect? last,
) {
  if (guards.isEmpty) return last;
  final chain = [...guards.map((g) => g.redirect), ?last];
  // Stays synchronous until a guard returns a Future, so sync guards add no
  // extra frame of delay.
  FutureOr<String?> run(BuildContext context, GoRouterState state, int i) {
    for (; i < chain.length; i++) {
      final r = chain[i](context, state);
      if (r is Future<String?>) {
        final next = i + 1;
        return r.then((to) {
          if (!context.mounted) return null;
          return _accept(to, state) ?? run(context, state, next);
        });
      }
      final to = _accept(r, state);
      if (to != null) return to;
    }
    return null;
  }

  return (context, state) => run(context, state, 0);
}

String? _accept(String? to, GoRouterState state) {
  if (to == null) return null;
  if (_same(to, state.uri)) {
    assert(() {
      debugPrint('OmniRoute: guard redirected $to to itself; ignored.');
      return true;
    }());
    return null;
  }
  return to;
}

bool _same(String to, Uri current) {
  final t = Uri.parse(to);
  return t.path == current.path &&
      (t.query.isEmpty || t.query == current.query);
}

/// Re-runs redirects when a guard's refresh stream emits.
@internal
class GuardRefresh extends StatefulWidget {
  const GuardRefresh({
    super.key,
    required this.guards,
    required this.notifier,
    required this.child,
  });

  final List<OmniGuard> guards;
  final GuardNotifier notifier;
  final Widget child;

  @override
  State<GuardRefresh> createState() => _GuardRefreshState();
}

class _GuardRefreshState extends State<GuardRefresh> {
  List<StreamSubscription<Object?>>? _subs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subs ??= [
      for (final g in widget.guards)
        if (g.refresh(context) case final s?)
          s.listen((_) => widget.notifier.ping()),
    ];
  }

  @override
  void dispose() {
    for (final s in _subs ?? const <StreamSubscription<Object?>>[]) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

@internal
class GuardNotifier extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Removes a trailing slash (`/students/` → `/students`), keeping the query.
/// Runs before user guards so they always see the canonical path.
@internal
class NormalizeUrlGuard extends OmniGuard {
  const NormalizeUrlGuard();

  @override
  String? redirect(BuildContext context, GoRouterState state) {
    final uri = state.uri;
    if (uri.path.length <= 1 || !uri.path.endsWith('/')) return null;
    var path = uri.path;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return uri.replace(path: path).toString();
  }
}
