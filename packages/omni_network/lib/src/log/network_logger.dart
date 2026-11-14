import '../core/omni_network_exception.dart';
import '../core/omni_response.dart';
import '../transport/transport.dart';
import 'network_log.dart';
import 'redactor.dart';

/// Formats redacted records and hands them to a [LogSink]. Internal.
final class NetworkLogger {
  /// Creates a logger.
  NetworkLogger(this.sink, this.redactor, {this.logBodies = true});

  /// Destination.
  final LogSink sink;

  /// Redaction rules.
  final Redactor redactor;

  /// Whether request/response bodies are included (redacted).
  final bool logBodies;

  static const _tag = '[OmniNetwork';

  /// Logs an outgoing request.
  void request(int id, TransportRequest r) {
    final url = redactor.uri(r.uri);
    final headers = redactor.headers(r.headers);
    final body = logBodies
        ? redactor.body(r.body, r.headers['content-type'])
        : null;
    _emit(
      NetworkLogRecord(
        kind: NetworkLogKind.request,
        requestId: id,
        method: r.method.verb,
        url: url,
        headers: headers,
        body: body,
        message: [
          '$_tag #$id] --> ${r.method.verb} $url',
          if (headers.isNotEmpty) '  headers: $headers',
          if (body != null) '  body: $body',
        ].join('\n'),
      ),
    );
  }

  /// Logs a received response.
  void response(int id, TransportRequest r, OmniRawResponse res) {
    final url = redactor.uri(r.uri);
    final headers = redactor.headers(res.headers);
    final body = logBodies
        ? redactor.body(res.bodyBytes, res.headers['content-type'])
        : null;
    final ms = res.duration.inMilliseconds;
    _emit(
      NetworkLogRecord(
        kind: NetworkLogKind.response,
        requestId: id,
        method: r.method.verb,
        url: url,
        headers: headers,
        body: body,
        statusCode: res.statusCode,
        duration: res.duration,
        message: [
          '$_tag #$id] <-- ${res.statusCode} ${r.method.verb} $url '
              '($ms ms, ${res.bodyBytes.length} B)',
          if (headers.isNotEmpty) '  headers: $headers',
          if (body != null) '  body: $body',
        ].join('\n'),
      ),
    );
  }

  /// Logs a failure without a response.
  void error(
    int id,
    TransportRequest? r,
    String method,
    OmniNetworkException e,
    Duration elapsed,
  ) {
    final url = r == null ? (e.uri?.toString() ?? '') : redactor.uri(r.uri);
    // OmniNetworkException.toString never contains bodies, headers or query.
    final text = '${e.runtimeType}: ${e.message}';
    _emit(
      NetworkLogRecord(
        kind: NetworkLogKind.error,
        requestId: id,
        method: method,
        url: url,
        duration: elapsed,
        error: text,
        message:
            '$_tag #$id] xx $method $url ($text, '
            '${elapsed.inMilliseconds} ms)',
      ),
    );
  }

  void _emit(NetworkLogRecord record) {
    try {
      sink.log(record);
    } catch (_) {
      // A broken sink must never break a request.
    }
  }
}
