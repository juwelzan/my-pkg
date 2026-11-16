import 'package:logger/logger.dart';
import 'package:meta/meta.dart';

import 'omni_route_entry.dart';

/// OmniRoute's default logger: debug builds only, one framed block per
/// event with level emoji, time and time since start, no stack trace.
///
/// ```text
/// ┌───────────────────────────────────────────────────────────────────────
/// │ 10:42:07.311 (+0:00:05.402070)
/// ├┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
/// │ 💡 OmniRoute · navigation
/// │ 💡 from  /settings          SettingsScreen
/// │ 💡 to    /settings/profile  ProfileScreen
/// └───────────────────────────────────────────────────────────────────────
/// ```
@internal
Logger defaultOmniLogger({LogOutput? output}) => Logger(
  filter: DevelopmentFilter(), // nothing is logged in release builds
  printer: PrettyPrinter(
    methodCount: 0, // no stack trace for normal events
    errorMethodCount: 6, // short trace for errors
    lineLength: 72,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
  output: output,
);

/// The log text for one navigation: where from, where to, which screen.
@internal
String navigationMessage(OmniNavigation n) {
  final from = n.from;
  final to = n.to;
  final rows = <(String, String, String)>[
    ('from', from?.location ?? '(app start)', _screen(from)),
    ('to', to.location, _screen(to)),
  ];
  if (n.uri.hasQuery || n.uri.hasFragment) {
    rows.add(('uri', n.uri.toString(), ''));
  }
  final width = rows.map((r) => r.$2.length).reduce((a, b) => a > b ? a : b);
  return [
    'OmniRoute · navigation',
    for (final (label, location, screen) in rows)
      '${label.padRight(4)}  ${location.padRight(width)}  $screen'.trimRight(),
  ].join('\n');
}

String _screen(OmniRouteEntry? e) =>
    e == null ? '' : (e.screen?.toString() ?? e.name ?? '');
