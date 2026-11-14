import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// An undecoded HTTP response. Any status code is returned as-is (typed
/// decoding and status-based errors arrive in a later step).
@immutable
final class OmniRawResponse {
  /// Creates a response. Header names are stored lower-case.
  OmniRawResponse({
    required this.statusCode,
    Map<String, String> headers = const {},
    Uint8List? bodyBytes,
    this.duration = Duration.zero,
  }) : headers = Map.unmodifiable({
         for (final e in headers.entries) e.key.toLowerCase(): e.value,
       }),
       bodyBytes = bodyBytes ?? Uint8List(0);

  /// HTTP status code.
  final int statusCode;

  /// Response headers, lower-case names; repeated headers joined with `, `.
  final Map<String, String> headers;

  /// Raw body.
  final Uint8List bodyBytes;

  /// Time from sending to receiving the full body.
  final Duration duration;

  /// Whether [statusCode] is 2xx.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// Body decoded as UTF-8 (malformed bytes replaced).
  String get text => utf8.decode(bodyBytes, allowMalformed: true);

  /// Body parsed as JSON; `null` for an empty body.
  /// Throws [FormatException] when the body is not valid JSON.
  Object? get json => bodyBytes.isEmpty ? null : jsonDecode(text);

  /// Copy with a different [duration].
  OmniRawResponse withDuration(Duration duration) => OmniRawResponse(
    statusCode: statusCode,
    headers: headers,
    bodyBytes: bodyBytes,
    duration: duration,
  );

  @override
  String toString() =>
      'OmniRawResponse($statusCode, ${bodyBytes.length} bytes)';
}
