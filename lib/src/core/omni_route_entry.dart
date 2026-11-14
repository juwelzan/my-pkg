import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:meta/meta.dart';

import '../routing/omni_page.dart';

/// One page in the navigation stack, for debugging, analytics and tools.
@immutable
class OmniRouteEntry {
  /// Creates an entry.
  const OmniRouteEntry({
    required this.location,
    this.name,
    this.path,
    this.screen,
    this.metadata = const {},
  });

  /// Entry for [route] shown at [location].
  factory OmniRouteEntry.fromRoute(GoRoute route, String location) =>
      OmniRouteEntry(
        location: location,
        name: route.name,
        path: route.path,
        screen: route is OmniPage ? route.screenType : null,
        metadata: route.metadata ?? const {},
      );

  /// Where the page is, e.g. `/students/7` (no query).
  final String location;

  /// The route's `name`, if it has one.
  final String? name;

  /// The route pattern as declared, e.g. `:id`.
  final String? path;

  /// The screen type shown, for [OmniPage] routes; `null` for raw GoRoutes.
  final Type? screen;

  /// The route's metadata (`OmniPage(metadata: ...)`).
  final Map<String, dynamic> metadata;

  @override
  bool operator ==(Object other) =>
      other is OmniRouteEntry &&
      other.location == location &&
      other.name == name &&
      other.path == path &&
      other.screen == screen;

  @override
  int get hashCode => Object.hash(location, name, path, screen);

  @override
  String toString() =>
      '$location${screen == null ? '' : ' ($screen)'}${name == null ? '' : ' #$name'}';
}

/// A completed navigation, passed to `OmniApp(onNavigate:)`.
@immutable
class OmniNavigation {
  /// Creates a navigation event.
  const OmniNavigation({
    required this.from,
    required this.to,
    required this.uri,
  });

  /// The top page before, or `null` for the first location.
  final OmniRouteEntry? from;

  /// The top page now.
  final OmniRouteEntry to;

  /// The full new location, including the query.
  final Uri uri;

  @override
  String toString() => '${from ?? '(start)'} → $to';
}

/// Pages from bottom to top, flattening shells and pushed pages.
@internal
List<OmniRouteEntry> entriesOf(RouteMatchList list) {
  final out = <OmniRouteEntry>[];
  void visit(List<RouteMatchBase> matches) {
    for (final m in matches) {
      switch (m) {
        case ShellRouteMatch():
          visit(m.matches);
        case RouteMatch():
          out.add(OmniRouteEntry.fromRoute(m.route, m.matchedLocation));
      }
    }
  }

  visit(list.matches);
  return out;
}
