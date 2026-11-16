import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// How a page can be closed by an edge swipe; see `OmniPages.transition`,
/// `OmniPages.custom` and `OmniApp(swipeBack:)`.
enum OmniSwipeBack {
  /// No swipe gesture (default).
  none,

  /// The page follows the finger horizontally (iOS-like).
  slide,

  /// The page shrinks, moves with the finger, rounds its corners and fades
  /// out near the end. The page below is shown as-is.
  zoom,
}

/// A screen edge a swipe-back may start from.
enum OmniSwipeEdge {
  /// The left screen edge (closes by moving right in LTR).
  left,

  /// The right screen edge (closes by moving left in LTR).
  right,
}

/// Tuning for the swipe-back gesture and its visuals.
@immutable
class OmniSwipeBackStyle {
  /// All values have defaults tuned for phones.
  const OmniSwipeBackStyle({
    this.minScale = 0.82,
    this.maxRadius = 28,
    this.slideFactor = 0.45,
    this.edgeWidth = 28,
    this.closeThreshold = 0.5,
    this.flingVelocity = 1.0,
    this.edges = const {OmniSwipeEdge.left, OmniSwipeEdge.right},
    this.springCurve = Curves.easeOutBack,
    this.closeCurve = Curves.easeOutCubic,
    this.settleDuration = const Duration(milliseconds: 300),
  }) : assert(minScale > 0 && minScale <= 1),
       assert(closeThreshold > 0 && closeThreshold < 1);

  /// Zoom: page scale at a full drag.
  final double minScale;

  /// Zoom: corner radius at a full drag, in logical pixels.
  final double maxRadius;

  /// Zoom: how far the page moves, as a fraction of the drag distance.
  final double slideFactor;

  /// Width of the edge strip a swipe starts in (the safe-area inset is used
  /// when larger).
  final double edgeWidth;

  /// Release past this fraction of the screen width closes the page.
  final double closeThreshold;

  /// A flick faster than this (screen widths per second) toward closing
  /// closes the page even under [closeThreshold].
  final double flingVelocity;

  /// Edges a swipe may start from.
  final Set<OmniSwipeEdge> edges;

  /// Curve used to spring back when the page is not closed.
  final Curve springCurve;

  /// Curve used to finish closing.
  final Curve closeCurve;

  /// Time to settle from a full drag; shorter for smaller distances.
  final Duration settleDuration;
}

/// The [CustomTransitionPage] behind `OmniPages.transition`/`custom`; adds
/// an optional swipe-back layer on top of [transitionsBuilder].
class OmniSwipeBackPage<T> extends CustomTransitionPage<T> {
  /// Same parameters as [CustomTransitionPage], plus the swipe settings
  /// (null = the `OmniApp` default).
  const OmniSwipeBackPage({
    required super.child,
    required super.transitionsBuilder,
    super.transitionDuration,
    super.reverseTransitionDuration,
    super.opaque,
    super.barrierDismissible,
    super.barrierColor,
    super.fullscreenDialog,
    super.key,
    super.name,
    super.restorationId,
    this.swipeBack,
    this.swipeBackStyle,
  });

  /// Swipe style for this page; null uses the app default.
  final OmniSwipeBack? swipeBack;

  /// Swipe tuning for this page; null uses the app default.
  final OmniSwipeBackStyle? swipeBackStyle;

  @override
  Route<T> createRoute(BuildContext context) => _OmniSwipeBackRoute<T>(this);
}

/// App-wide swipe-back defaults (provided by `OmniApp`).
@internal
class OmniSwipeBackDefaults extends InheritedWidget {
  /// Provides [mode] and [style] to the pages below.
  const OmniSwipeBackDefaults({
    super.key,
    required this.mode,
    required this.style,
    required super.child,
  });

  /// Default swipe style.
  final OmniSwipeBack mode;

  /// Default tuning.
  final OmniSwipeBackStyle style;

  /// The nearest defaults, or "off".
  static (OmniSwipeBack, OmniSwipeBackStyle) of(BuildContext context) {
    final d = context
        .dependOnInheritedWidgetOfExactType<OmniSwipeBackDefaults>();
    return (
      d?.mode ?? OmniSwipeBack.none,
      d?.style ?? const OmniSwipeBackStyle(),
    );
  }

  @override
  bool updateShouldNotify(OmniSwipeBackDefaults old) =>
      old.mode != mode || old.style != style;
}

class _OmniSwipeBackRoute<T> extends PageRoute<T> {
  _OmniSwipeBackRoute(OmniSwipeBackPage<T> page) : super(settings: page);

  OmniSwipeBackPage<T> get _page => settings as OmniSwipeBackPage<T>;

  @override
  bool get barrierDismissible => _page.barrierDismissible;
  @override
  Color? get barrierColor => _page.barrierColor;
  @override
  String? get barrierLabel => _page.barrierLabel;
  @override
  Duration get transitionDuration => _page.transitionDuration;
  @override
  Duration get reverseTransitionDuration => _page.reverseTransitionDuration;
  @override
  bool get maintainState => _page.maintainState;
  @override
  bool get fullscreenDialog => _page.fullscreenDialog;
  @override
  bool get opaque => _page.opaque;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    child: _page.child,
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final (appMode, appStyle) = OmniSwipeBackDefaults.of(context);
    final mode = _page.swipeBack ?? appMode;
    if (mode == OmniSwipeBack.none) {
      return _page.transitionsBuilder(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    return _SwipeBackLayer(
      route: this,
      mode: mode,
      style: _page.swipeBackStyle ?? appStyle,
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }

  /// Same rules as Flutter's Cupertino back gesture.
  bool get swipeEnabled {
    final nav = navigator;
    return nav != null &&
        isActive &&
        isCurrent &&
        !isFirst &&
        !willHandlePopInternally &&
        popDisposition == RoutePopDisposition.pop &&
        !fullscreenDialog &&
        animation!.status == AnimationStatus.completed &&
        secondaryAnimation!.status == AnimationStatus.dismissed &&
        !nav.userGestureInProgress;
  }

  AnimationController get swipeController => controller!;

  /// Pops through go_router when it owns this page, so its state, the
  /// OmniRoute stack, logs and lifecycle hooks stay correct.
  void swipePop(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    final key = _page.key;
    if (router != null && router.state.pageKey == key) {
      router.pop();
    } else {
      navigator?.pop();
    }
  }
}

class _SwipeBackLayer extends StatefulWidget {
  const _SwipeBackLayer({
    required this.route,
    required this.mode,
    required this.style,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final _OmniSwipeBackRoute<dynamic> route;
  final OmniSwipeBack mode;
  final OmniSwipeBackStyle style;
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  State<_SwipeBackLayer> createState() => _SwipeBackLayerState();
}

class _SwipeBackLayerState extends State<_SwipeBackLayer> {
  late final HorizontalDragGestureRecognizer _drag =
      HorizontalDragGestureRecognizer(debugOwner: this)
        ..onStart = _onStart
        ..onUpdate = _onUpdate
        ..onEnd = _onEnd
        ..onCancel = _onCancel;

  /// True from drag start until the settle animation ends; while true the
  /// page's own transition is held at "fully open" and the swipe visuals
  /// follow the route animation instead.
  bool _active = false;
  NavigatorState? _navigator;

  /// +1: closing moves right; -1: closing moves left.
  double _closeSign = 1;
  double _width = 1;

  @override
  void dispose() {
    _drag.dispose();
    _finishGesture(rebuild: false);
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent e) {
    if (!widget.route.swipeEnabled) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final x = box.globalToLocal(e.position).dx;
    final padding = MediaQuery.paddingOf(context);
    final s = widget.style;
    final OmniSwipeEdge edge;
    if (s.edges.contains(OmniSwipeEdge.left) &&
        x <= math.max(s.edgeWidth, padding.left)) {
      edge = OmniSwipeEdge.left;
    } else if (s.edges.contains(OmniSwipeEdge.right) &&
        x >= box.size.width - math.max(s.edgeWidth, padding.right)) {
      edge = OmniSwipeEdge.right;
    } else {
      return;
    }
    // Closing always moves inward from the starting edge. (An RTL "swap"
    // would make closing move off-screen from the edge, which a finger
    // cannot do; both edges are on by default for LTR and RTL alike.)
    _closeSign = edge == OmniSwipeEdge.left ? 1.0 : -1.0;
    _width = box.size.width;
    _drag.addPointer(e);
  }

  void _onStart(DragStartDetails _) {
    if (!widget.route.swipeEnabled) return;
    _navigator = widget.route.navigator!..didStartUserGesture();
    setState(() => _active = true);
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_navigator == null) return;
    final c = widget.route.swipeController;
    final progress = (1 - c.value + _closeSign * d.primaryDelta! / _width)
        .clamp(0.0, 1.0);
    c.value = 1 - progress;
  }

  void _onEnd(DragEndDetails d) {
    if (_navigator == null) return;
    final s = widget.style;
    final c = widget.route.swipeController;
    final progress = 1 - c.value;
    final velocity = _closeSign * d.velocity.pixelsPerSecond.dx / _width;
    final close =
        progress > 0 &&
        (velocity >= s.flingVelocity ||
            (progress > s.closeThreshold && velocity > -s.flingVelocity));
    if (close) {
      final ms = math.max(
        80,
        (s.settleDuration.inMilliseconds * c.value).round(),
      );
      widget.route.swipePop(context);
      // pop() starts the normal reverse animation; continue from where the
      // finger left instead.
      c
          .animateBack(
            0,
            duration: Duration(milliseconds: ms),
            curve: s.closeCurve,
          )
          .whenCompleteOrCancel(_finishGesture);
    } else {
      _springBack();
    }
  }

  void _onCancel() {
    if (_navigator == null) return;
    _springBack();
  }

  void _springBack() {
    final s = widget.style;
    final c = widget.route.swipeController;
    final ms = math.max(
      80,
      (s.settleDuration.inMilliseconds * (1 - c.value)).round(),
    );
    c
        .animateTo(
          1,
          duration: Duration(milliseconds: ms),
          curve: s.springCurve,
        )
        .whenCompleteOrCancel(_finishGesture);
  }

  void _finishGesture({bool rebuild = true}) {
    final nav = _navigator;
    if (nav == null) return;
    _navigator = null;
    nav.didStopUserGesture();
    if (rebuild && mounted) setState(() => _active = false);
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.route._page;
    final transitioned = RepaintBoundary(
      child: page.transitionsBuilder(
        context,
        _active ? kAlwaysCompleteAnimation : widget.animation,
        widget.secondaryAnimation,
        widget.child,
      ),
    );
    final zoom =
        widget.mode == OmniSwipeBack.zoom &&
        !MediaQuery.disableAnimationsOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      child: AnimatedBuilder(
        animation: widget.animation,
        child: transitioned,
        builder: (context, child) {
          // Same widget shape in every state, so the page is never rebuilt
          // from scratch when a gesture starts or ends.
          final p = _active ? 1 - widget.animation.value : 0.0;
          final s = widget.style;
          final width = _width;
          double scale = 1, dx = 0, radius = 0, opacity = 1;
          if (p > 0) {
            if (zoom) {
              scale = lerpDouble(1, s.minScale, p)!;
              dx = _closeSign * p * width * s.slideFactor;
              radius = s.maxRadius * p;
              opacity = p < 0.75 ? 1 : (1 - (p - 0.75) / 0.25).clamp(0.0, 1.0);
            } else {
              dx = _closeSign * p * width;
            }
          }
          return Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(dx, 0),
              child: Transform.scale(
                scale: scale,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  clipBehavior: radius > 0 ? Clip.antiAlias : Clip.none,
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
