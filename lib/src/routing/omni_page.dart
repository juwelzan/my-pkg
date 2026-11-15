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

/// Builds a page transition; same signature as Flutter's
/// `PageRouteBuilder.transitionsBuilder`.
typedef OmniTransitionBuilder =
    Widget Function(
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    );

/// Built-in animated transitions; see [OmniPages.transition].
enum OmniTransition {
  /// Cross-fade.
  fade,

  /// Slide in from the end edge (RTL-aware), page below shifts slightly.
  slide,

  /// Slide up from the bottom.
  slideUp,

  /// Zoom in from 92% with a fade.
  scale,

  /// Zoom in from 96% with a fade (subtle).
  fadeScale,

  /// Fade in while moving up slightly.
  fadeSlide,
}

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

  // ── Animated transitions ────────────────────────────────────────────
  //
  // Built for smooth, fast navigation: short durations, an ease-out curve,
  // and only opacity/transform effects (composited by the GPU, no relayout
  // per frame). Animations use `animation.drive(...)`, so nothing is
  // allocated per frame and nothing needs disposing.
  //
  // Custom transitions replace the platform's: iOS swipe-back and Android
  // predictive back need `material` or `cupertino`.

  /// Default open duration of the built-in transitions.
  static const defaultDuration = Duration(milliseconds: 250);

  /// Default close duration of the built-in transitions (closing feels
  /// faster when slightly shorter).
  static const defaultReverseDuration = Duration(milliseconds: 200);

  /// Cross-fade.
  static Page<void> fade(LocalKey key, String? name, Widget child) =>
      _fade(key, name, child);
  static final OmniPageType _fade = transition(OmniTransition.fade);

  /// Slides in from the end edge (right in LTR, left in RTL); the page below
  /// shifts slightly the other way.
  static Page<void> slide(LocalKey key, String? name, Widget child) =>
      _slide(key, name, child);
  static final OmniPageType _slide = transition(OmniTransition.slide);

  /// Slides up from the bottom (sheets, create/edit screens).
  static Page<void> slideUp(LocalKey key, String? name, Widget child) =>
      _slideUp(key, name, child);
  static final OmniPageType _slideUp = transition(OmniTransition.slideUp);

  /// Zooms in from 92% while fading in.
  static Page<void> scale(LocalKey key, String? name, Widget child) =>
      _scale(key, name, child);
  static final OmniPageType _scale = transition(OmniTransition.scale);

  /// Zooms in from 96% with a fade — subtle, good for details/dialogs.
  static Page<void> fadeScale(LocalKey key, String? name, Widget child) =>
      _fadeScale(key, name, child);
  static final OmniPageType _fadeScale = transition(OmniTransition.fadeScale);

  /// Fades in while moving up a few pixels — a light, modern default.
  static Page<void> fadeSlide(LocalKey key, String? name, Widget child) =>
      _fadeSlide(key, name, child);
  static final OmniPageType _fadeSlide = transition(OmniTransition.fadeSlide);

  /// A built-in [kind] with your own [duration], [reverseDuration] and
  /// [curve]:
  ///
  /// ```dart
  /// OmniApp(pageType: OmniPages.transition(
  ///   OmniTransition.slide,
  ///   duration: const Duration(milliseconds: 200),
  /// ))
  /// ```
  static OmniPageType transition(
    OmniTransition kind, {
    Duration duration = defaultDuration,
    Duration reverseDuration = defaultReverseDuration,
    Curve curve = Curves.easeOutCubic,
  }) => custom(
    _builderFor(kind, CurveTween(curve: curve)),
    duration: duration,
    reverseDuration: reverseDuration,
  );

  /// Your own transition. [builder] has the same signature as Flutter's
  /// `transitionsBuilder`:
  ///
  /// ```dart
  /// OmniPages.custom(
  ///   (context, animation, secondaryAnimation, child) => RotationTransition(
  ///     turns: animation.drive(Tween(begin: 0.9, end: 1.0)),
  ///     child: child,
  ///   ),
  ///   duration: const Duration(milliseconds: 300),
  /// )
  /// ```
  ///
  /// [opaque] false + [barrierColor] give a dialog-style page with the
  /// previous page visible behind it.
  static OmniPageType custom(
    OmniTransitionBuilder builder, {
    Duration duration = defaultDuration,
    Duration? reverseDuration,
    bool opaque = true,
    Color? barrierColor,
    bool barrierDismissible = false,
    bool fullscreenDialog = false,
  }) =>
      (key, name, child) => CustomTransitionPage<void>(
        key: key,
        name: name,
        restorationId: _restorationId(key),
        transitionDuration: duration,
        reverseTransitionDuration: reverseDuration ?? duration,
        opaque: opaque,
        barrierColor: barrierColor,
        barrierDismissible: barrierDismissible,
        fullscreenDialog: fullscreenDialog,
        transitionsBuilder: builder,
        child: child,
      );

  static OmniTransitionBuilder _builderFor(OmniTransition kind, CurveTween c) {
    switch (kind) {
      case OmniTransition.fade:
        return (context, a, s, child) =>
            FadeTransition(opacity: a.drive(c), child: child);
      case OmniTransition.slide:
        return (context, a, s, child) {
          final dir = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
          return SlideTransition(
            position: s
                .drive(c)
                .drive(Tween(begin: Offset.zero, end: Offset(-0.25 * dir, 0))),
            child: SlideTransition(
              position: a
                  .drive(c)
                  .drive(Tween(begin: Offset(1.0 * dir, 0), end: Offset.zero)),
              child: child,
            ),
          );
        };
      case OmniTransition.slideUp:
        return (context, a, s, child) => SlideTransition(
          position: a
              .drive(c)
              .drive(Tween(begin: const Offset(0, 1), end: Offset.zero)),
          child: child,
        );
      case OmniTransition.scale:
        return (context, a, s, child) => FadeTransition(
          opacity: a.drive(c),
          child: ScaleTransition(
            scale: a.drive(c).drive(Tween(begin: 0.92, end: 1.0)),
            child: child,
          ),
        );
      case OmniTransition.fadeScale:
        return (context, a, s, child) => FadeTransition(
          opacity: a.drive(c),
          child: ScaleTransition(
            scale: a.drive(c).drive(Tween(begin: 0.96, end: 1.0)),
            child: child,
          ),
        );
      case OmniTransition.fadeSlide:
        return (context, a, s, child) => FadeTransition(
          opacity: a.drive(c),
          child: SlideTransition(
            position: a
                .drive(c)
                .drive(Tween(begin: const Offset(0, 0.04), end: Offset.zero)),
            child: child,
          ),
        );
    }
  }

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
