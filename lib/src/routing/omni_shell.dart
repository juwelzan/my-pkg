import 'package:go_router/go_router.dart';

import '../bloc/omni_bloc.dart';
import '../bloc/omni_bloc_scope.dart';

/// A [ShellRoute] (shared layout around child routes) with optional Blocs
/// that live as long as the shell is shown.
class OmniShell extends ShellRoute {
  /// A shell around [routes]; [provide] Blocs live as long as the shell.
  OmniShell({
    required ShellRouteBuilder builder,
    required super.routes,
    List<Provide> provide = const [],
    super.navigatorKey,
    super.parentNavigatorKey,
    super.observers,
  }) : super(
         builder: (c, s, child) =>
             OmniBlocScope(provide: provide, child: builder(c, s, child)),
       );
}

/// A [StatefulShellRoute.indexedStack]: each branch keeps its own navigation
/// stack, widget state and screen Blocs while other tabs are shown.
///
/// ```dart
/// OmniStatefulShell(
///   builder: (context, state, shell) => HomeScaffold(shell: shell),
///   branches: [
///     StatefulShellBranch(routes: [OmniPage('/home', (_) => const HomeScreen())]),
///     StatefulShellBranch(routes: [OmniPage('/profile', (_) => const ProfileScreen())]),
///   ],
/// )
/// ```
/// Switch tabs with `shell.goBranch(index)` (go_router API).
class OmniStatefulShell extends StatefulShellRoute {
  /// Tabs from [branches]; [provide] Blocs live as long as the shell.
  OmniStatefulShell({
    required StatefulShellRouteBuilder builder,
    required super.branches,
    List<Provide> provide = const [],
    super.parentNavigatorKey,
    super.restorationScopeId,
  }) : super.indexedStack(
         builder: (c, s, shell) =>
             OmniBlocScope(provide: provide, child: builder(c, s, shell)),
       );
}
