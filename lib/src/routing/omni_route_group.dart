import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../bloc/omni_bloc.dart';
import '../bloc/omni_bloc_scope.dart';
import 'omni_page.dart';
import 'omni_params.dart';

/// Returns the identity of a group's scope for the current location; when
/// it changes, the group's Blocs are closed and created again.
typedef OmniScopeKey = Object? Function(GoRouterState state);

/// Routes that share Blocs: the **route scope**.
///
/// The Blocs in [provide] are created when the user first enters any route
/// of the group and closed when the user leaves the group (for example with
/// `go` to a route outside it). Moving between routes inside the group, or
/// pushing a route from outside the group on top, keeps them.
///
/// ```dart
/// OmniPage('/students', (_) => const StudentListScreen(), routes: [
///   OmniRouteGroup(
///     scopeKey: (s) => s.pathParameters['id'],   // new Blocs per student
///     provide: [
///       Provide<StudentBloc>.create(
///           (c) => StudentBloc(OmniParams.of(c).pathInt('id'))),
///     ],
///     routes: [
///       OmniPage(':id', (p) => const StudentDetailScreen()),
///       OmniPage(':id/edit', (p) => const StudentEditScreen()),
///     ],
///   ),
/// ])
/// ```
///
/// Built on go_router's [ShellRoute] with no layout of its own: the group's
/// pages live in a nested Navigator, so back navigation inside the group
/// works as usual. Paths inside follow the same rules as where the group is
/// placed (absolute at the top level, relative under an `OmniPage`).
class OmniRouteGroup extends ShellRoute {
  /// Creates a group of [routes] sharing the Blocs in [provide].
  OmniRouteGroup({
    required super.routes,
    required List<Provide> provide,
    OmniScopeKey? scopeKey,
    OmniPageType? pageType,
    super.navigatorKey,
    super.parentNavigatorKey,
    super.observers,
    super.restorationScopeId,
  }) : super(
         pageBuilder: (context, state, child) {
           Widget scoped = OmniRouteStateScope(
             state: state,
             child: OmniBlocScope(provide: provide, child: child),
           );
           if (scopeKey != null) {
             scoped = KeyedSubtree(
               key: ValueKey<Object?>(scopeKey(state)),
               child: scoped,
             );
           }
           return (pageType ?? OmniPageConfig.of(context).pageType)(
             state.pageKey,
             null,
             scoped,
           );
         },
       );
}
