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
    this.requestUri,
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

  /// URL of the request that produced this response, with user info, query
  /// and fragment removed (safe to log). Set by `OmniNetwork`.
  final Uri? requestUri;

  /// Whether [statusCode] is 2xx.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// Body decoded as UTF-8 (malformed bytes replaced).
  String get text => utf8.decode(bodyBytes, allowMalformed: true);

  /// Body parsed as JSON; `null` for an empty body.
  /// Throws [FormatException] when the body is not valid JSON.
  Object? get json => bodyBytes.isEmpty ? null : jsonDecode(text);

  /// Copy with [duration] and [requestUri] filled in.
  OmniRawResponse finish({required Duration duration, Uri? requestUri}) =>
      OmniRawResponse(
        statusCode: statusCode,
        headers: headers,
        bodyBytes: bodyBytes,
        duration: duration,
        requestUri: requestUri ?? this.requestUri,
      );

  @override
  String toString() =>
      'OmniRawResponse($statusCode, ${bodyBytes.length} bytes)';
}

/// A successful (2xx) response whose body was decoded into [data].
@immutable
final class OmniResponse<T> {
  /// Creates a typed response.
  const OmniResponse(this.data, this.raw);

  /// Decoded body.
  final T data;

  /// The undecoded response.
  final OmniRawResponse raw;

  /// HTTP status code.
  int get statusCode => raw.statusCode;

  /// Response headers (lower-case names).
  Map<String, String> get headers => raw.headers;

  /// Time from sending to receiving the full body.
  Duration get duration => raw.duration;

  @override
  String toString() => 'OmniResponse<$T>($statusCode)';
}
