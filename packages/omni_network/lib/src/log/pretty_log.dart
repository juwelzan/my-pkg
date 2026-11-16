import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:meta/meta.dart';

import '../cache/omni_cache.dart' show ResponseSource;
import '../core/http_status.dart';
import 'ansi_stub.dart' if (dart.library.io) 'ansi_io.dart';
import 'network_log.dart';

/// How `enableLogging: true` prints calls. All fields have defaults.
@immutable
final class LogOptions {
  /// Creates options.
  const LogOptions({
    this.headers = false,
    this.requestBody = true,
    this.responseBody = true,
    this.maxLines = 30,
    this.colors,
    this.width = 60,
  });

  /// Print request and response headers (redacted).
  final bool headers;

  /// Print the request body (redacted).
  final bool requestBody;

  /// Print the response body (redacted, JSON pretty-printed).
  final bool responseBody;

  /// Body lines shown before `… N more lines`.
  final int maxLines;

  /// ANSI colours; `null` = when the terminal supports them.
  final bool? colors;

  /// Width of the frame lines.
  final int width;
}

/// Prints each call as one block: method and URL, then status, time, size
/// and the pretty-printed body. Request and response are printed together
/// in one log event, so concurrent calls never interleave. Data arrives
/// already redacted.
///
/// By default it logs through the `logger` package in the same format as
/// OmniRoute's own logs: a framed block with time and time since start,
/// and a level emoji per line — 💡 success, ⚠️ 4xx, ⛔ 5xx or failure:
///
/// ```text
/// ┌────────────────────────────────────────────────────────────
/// │ 10:42:07.311 (+0:00:05.402070)
/// ├┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
/// │ 💡 GET  https://api.example.com/users/10
/// │ 💡 ✔ 200 OK · 84 ms · 312 B
/// │ 💡 {
/// │ 💡   "id": 10,
/// │ 💡   "name": "Rahim"
/// │ 💡 }
/// └────────────────────────────────────────────────────────────
/// ```
///
/// Pass [logger] to use your own `Logger` (format, file, crash reporter).
/// Passing [printer] instead prints the classic self-framed text block with
/// `printer` (kept for compatibility).
///
/// This is the default sink for `enableLogging: true`.
final class PrettyLogSink implements LogSink {
  /// Creates the sink.
  PrettyLogSink({
    this.options = const LogOptions(),
    void Function(String)? printer,
    Logger? logger,
  }) : _printer = printer,
       _colors = options.colors ?? terminalSupportsColors(),
       _logger = printer != null ? null : (logger ?? _defaultLogger(options));

  /// Formatting options.
  final LogOptions options;

  final void Function(String)? _printer;
  final Logger? _logger;
  final bool _colors;

  // OmniNetwork already decides whether to log (enableLogging / release
  // builds), so this logger prints everything it is given.
  static Logger _defaultLogger(LogOptions o) => Logger(
    filter: ProductionFilter(),
    printer: PrettyPrinter(
      methodCount: 0, // no Dart stack trace for HTTP calls
      errorMethodCount: 0,
      lineLength: o.width,
      colors: o.colors ?? terminalSupportsColors(),
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    level: Level.trace,
  );
  // Insertion-ordered; bounded so a request whose result is never logged
  // (e.g. a programming error thrown mid-call) cannot grow it forever.
  final Map<int, NetworkLogRecord> _open = {};
  static const _maxOpen = 256;

  /// Requests waiting for their result (diagnostics/tests).
  @visibleForTesting
  int get debugOpenRequests => _open.length;

  @override
  void log(NetworkLogRecord record) {
    switch (record.kind) {
      case NetworkLogKind.request:
        _open[record.requestId] = record;
        while (_open.length > _maxOpen) {
          _open.remove(_open.keys.first);
        }
      case NetworkLogKind.response || NetworkLogKind.error:
        final req = _open.remove(record.requestId);
        if (_printer case final printer?) {
          // Trailing newline: a blank line between blocks.
          printer('${format(req, record)}\n');
        } else {
          _logger!.log(levelOf(record), message(req, record));
        }
    }
  }

  static String _size(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  List<String> _body(String text) {
    var lines = text.split('\n');
    try {
      final parsed = jsonDecode(text);
      if (parsed is Map || parsed is List) {
        lines = const JsonEncoder.withIndent('  ').convert(parsed).split('\n');
      }
    } on FormatException {
      // Not JSON (or truncated): print as is.
    }
    if (lines.length > options.maxLines) {
      final more = lines.length - options.maxLines;
      lines = [
        ...lines.take(options.maxLines),
        '… $more more line${more == 1 ? '' : 's'}',
      ];
    }
    return lines;
  }

  /// Log level for a result: info for success, warning for 4xx, error for
  /// 5xx and failures (timeouts, no connection, …). Visible for tests.
  @visibleForTesting
  static Level levelOf(NetworkLogRecord result) {
    if (result.kind != NetworkLogKind.response) return Level.error;
    final status = result.statusCode ?? 0;
    return status >= 500
        ? Level.error
        : status >= 400
        ? Level.warning
        : Level.info;
  }

  /// The block's text for the `logger` output (the logger draws the frame,
  /// time and colours). Visible for tests.
  @visibleForTesting
  String message(NetworkLogRecord? request, NetworkLogRecord result) =>
      _lines(request, result).join('\n');

  /// Renders one classic self-framed block. Visible for tests.
  @visibleForTesting
  String format(NetworkLogRecord? request, NetworkLogRecord result) {
    final color = _statusColor(result);
    String paint(String s, [String? c]) =>
        _colors ? '\x1B[${c ?? color}m$s\x1B[0m' : s;
    final rule = '─' * options.width;
    final out = <String>[paint('┌$rule')];
    for (final e in _entries(request, result)) {
      if (e == null) {
        out.add(paint('├$rule'));
        continue;
      }
      final (text, c) = e;
      final body = switch (c) {
        null => text,
        'method' => () {
          final method = (request?.method ?? result.method).padRight(4);
          return '${paint(method, '1')}${text.substring(method.length)}';
        }(),
        _ => paint(text, c),
      };
      out.add('${paint('│', color)} $body');
    }
    out.add(paint('└$rule'));
    return out.join('\n');
  }

  List<String> _lines(NetworkLogRecord? request, NetworkLogRecord result) => [
    for (final e in _entries(request, result))
      if (e != null) e.$1,
  ];

  static String _statusColor(NetworkLogRecord result) {
    final status = result.statusCode ?? 0;
    return result.kind != NetworkLogKind.response || status >= 500
        ? '31' // red
        : status >= 400
        ? '33' // yellow
        : '32'; // green
  }

  /// The block's lines as (text, ANSI colour or null); `null` marks the
  /// divider between request and response.
  List<(String, String?)?> _entries(
    NetworkLogRecord? request,
    NetworkLogRecord result,
  ) {
    final ok = result.kind == NetworkLogKind.response;
    final status = result.statusCode ?? 0;
    final color = _statusColor(result);
    final out = <(String, String?)?>[];
    final method = (request?.method ?? result.method).padRight(4);
    // Colour code 'method': the method is bold in the classic format.
    out.add(('$method ${request?.url ?? result.url}', 'method'));
    if (request?.note case final n?) {
      out.add((
        n
            .replaceAll('retry', '↻ retry')
            .replaceAll('token refreshed', '🔑 token refreshed'),
        '36',
      ));
    }
    if (options.headers && request != null && request.headers.isNotEmpty) {
      out.add((
        '⇢ headers  ${request.headers.entries.map((e) => '${e.key}: ${e.value}').join('  ')}',
        '90',
      ));
    }
    final reqBody = options.requestBody ? request?.body : null;
    if (reqBody case final b?) {
      final compact = b.replaceAll(RegExp(r'\s*\n\s*'), ' ');
      out.add((
        '⇢ body  ${compact.length > 200 ? '${compact.substring(0, 200)}…' : compact}',
        '90',
      ));
    }
    out.add(null);
    final ms = '${result.duration?.inMilliseconds ?? 0} ms';
    if (ok) {
      out.add((
        [
          '${status < 400 ? '✔' : '✖'} $status${httpReasonPhrase(status) == null ? '' : ' ${httpReasonPhrase(status)}'}',
          ms,
          if (result.bytes case final n? when n > 0) _size(n),
          if (result.source case final s? when s != ResponseSource.network)
            s.name,
        ].join(' · '),
        color,
      ));
      if (options.headers && result.headers.isNotEmpty) {
        out.add((
          '⇠ headers  ${result.headers.entries.map((e) => '${e.key}: ${e.value}').join('  ')}',
          '90',
        ));
      }
      final resBody = options.responseBody ? result.body : null;
      if (resBody case final b?) {
        for (final l in _body(b)) {
          out.add((l, null));
        }
      }
    } else {
      out.add(('✖ ${result.error ?? 'failed'} · $ms', color));
    }
    return out;
  }
}
