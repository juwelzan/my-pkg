/// OmniRoute: screens, routes and Bloc scoping on top of go_router and
/// flutter_bloc.
library;

export 'src/bloc/omni_bloc.dart'
    show AnyBloc, OmniBloc, OmniBlocCreate, OmniBlocRegistry, Provide;
export 'src/bloc/omni_bloc_scope.dart' hide hostedScreenAbove;
export 'src/core/omni_app.dart';
export 'src/core/omni_route.dart';
export 'src/core/omni_route_entry.dart' show OmniNavigation, OmniRouteEntry;
export 'src/errors/omni_route_exception.dart';
export 'src/guards/omni_guard.dart' show OmniGuard;
export 'src/routing/omni_page.dart'
    show
        OmniPage,
        OmniPages,
        OmniPageType,
        OmniScreenBuilder,
        OmniErrorBuilder,
        defaultOmniErrorBuilder;
export 'src/routing/omni_params.dart' hide OmniRouteStateScope;
export 'src/routing/omni_route_group.dart';
export 'src/routing/omni_shell.dart';
export 'src/screens/omni_screen.dart' show OmniScreen, OmniScreenMetadata;
export 'src/screens/omni_screen_host.dart' show OmniScreenHost;
export 'src/screens/omni_stateful_widget.dart';
export 'src/screens/omni_stateless_widget.dart';
