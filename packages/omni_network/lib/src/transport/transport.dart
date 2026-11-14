import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../core/cancel_signal.dart';
import '../core/omni_request.dart';
import '../core/omni_response.dart';

/// A fully resolved request handed to a [Transport].
@immutable
final class TransportRequest {
  /// Creates a resolved request.
  TransportRequest({
    required this.method,
    required this.uri,
    Map<String, String> headers = const {},
    this.body,
  }) : headers = Map.unmodifiable(headers);

  /// HTTP method.
  final HttpMethod method;

  /// Absolute URL including the query string.
  final Uri uri;

  /// Final headers (lower-case names).
  final Map<String, String> headers;

  /// Encoded body, or `null`.
  final Uint8List? body;

  @override
  String toString() => 'TransportRequest(${method.verb} ${uri.path})';
}

/// Sends [TransportRequest]s over some I/O mechanism.
///
/// Implementations must:
/// * return any HTTP status as an [OmniRawResponse] (never throw for 4xx/5xx);
/// * abort and throw `CancelledFailure` when [CancelSignal] fires;
/// * throw `ConnectionFailure` for network-level errors.
abstract interface class Transport {
  /// Sends [request]; see class docs for the error contract.
  Future<OmniRawResponse> send(TransportRequest request, CancelSignal cancel);

  /// Releases resources. With [force], in-flight requests are aborted.
  Future<void> close({bool force = false});
}
