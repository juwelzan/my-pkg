import 'dart:convert';

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

/// Prints each call as one framed block: method and URL, then status,
/// time, size and the pretty-printed body. Request and response are
/// printed together in a single `print`, so concurrent calls never
/// interleave. Data arrives already redacted.
///
/// This is the default sink for `enableLogging: true`.
final class PrettyLogSink implements LogSink {
  /// Creates the sink; [printer] defaults to `print`.
  PrettyLogSink({
    this.options = const LogOptions(),
    void Function(String)? printer,
  }) : _printer = printer ?? print,
       _colors = options.colors ?? terminalSupportsColors();

  /// Formatting options.
  final LogOptions options;

  final void Function(String) _printer;
  final bool _colors;
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
        // Trailing newline: a blank line between blocks.
        _printer('${format(req, record)}\n');
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

  /// Renders one block. Visible for tests.
  @visibleForTesting
  String format(NetworkLogRecord? request, NetworkLogRecord result) {
    final ok = result.kind == NetworkLogKind.response;
    final status = result.statusCode ?? 0;
    final color = !ok || status >= 500
        ? '31' // red
        : status >= 400
        ? '33' // yellow
        : '32'; // green
    String paint(String s, [String? c]) =>
        _colors ? '\x1B[${c ?? color}m$s\x1B[0m' : s;
    final rule = '─' * options.width;
    final out = <String>[paint('┌$rule')];
    void line(String s, [String? c]) =>
        out.add('${paint('│', color)} ${c == null ? s : paint(s, c)}');

    final method = (request?.method ?? result.method).padRight(4);
    line('${paint(method, '1')} ${request?.url ?? result.url}');
    if (request?.note case final n?) {
      line(
        n
            .replaceAll('retry', '↻ retry')
            .replaceAll('token refreshed', '🔑 token refreshed'),
        '36',
      );
    }
    if (options.headers && request != null && request.headers.isNotEmpty) {
      line(
        '⇢ headers  ${request.headers.entries.map((e) => '${e.key}: ${e.value}').join('  ')}',
        '90',
      );
    }
    final reqBody = options.requestBody ? request?.body : null;
    if (reqBody case final b?) {
      final compact = b.replaceAll(RegExp(r'\s*\n\s*'), ' ');
      line(
        '⇢ body  ${compact.length > 200 ? '${compact.substring(0, 200)}…' : compact}',
        '90',
      );
    }
    out.add(paint('├$rule'));
    final ms = '${result.duration?.inMilliseconds ?? 0} ms';
    if (ok) {
      line(
        [
          '${status < 400 ? '✔' : '✖'} $status${httpReasonPhrase(status) == null ? '' : ' ${httpReasonPhrase(status)}'}',
          ms,
          if (result.bytes case final n? when n > 0) _size(n),
          if (result.source case final s? when s != ResponseSource.network)
            s.name,
        ].join(' · '),
        color,
      );
      if (options.headers && result.headers.isNotEmpty) {
        line(
          '⇠ headers  ${result.headers.entries.map((e) => '${e.key}: ${e.value}').join('  ')}',
          '90',
        );
      }
      final resBody = options.responseBody ? result.body : null;
      if (resBody case final b?) {
        for (final l in _body(b)) {
          line(l);
        }
      }
    } else {
      line('✖ ${result.error ?? 'failed'} · $ms', color);
    }
    out.add(paint('└$rule'));
    return out.join('\n');
  }
}
