import 'omni_network_exception.dart';
import 'omni_response.dart';

/// Transforms a parsed JSON body before it reaches the decoder, e.g. to
/// unwrap an envelope such as `{"data": {...}, "meta": {...}}`.
///
/// Throw [DecodeFailure] when the body does not have the expected shape.
abstract interface class ResponseAdapter {
  /// Returns the JSON value the decoder should receive.
  Object? unwrap(Object? json, OmniRawResponse response);
}

/// Passes the body through unchanged (the default).
final class PlainResponseAdapter implements ResponseAdapter {
  /// Creates the identity adapter.
  const PlainResponseAdapter();

  @override
  Object? unwrap(Object? json, OmniRawResponse response) => json;
}

/// Unwraps `{dataKey: value}` envelopes.
///
/// When [errorKey] is set and present with a non-null value in a 2xx body,
/// a [DecodeFailure] is thrown (some APIs report errors with status 200).
final class EnvelopeResponseAdapter implements ResponseAdapter {
  /// Creates an envelope adapter.
  const EnvelopeResponseAdapter({this.dataKey = 'data', this.errorKey});

  /// Key holding the payload.
  final String dataKey;

  /// Optional key holding an error object.
  final String? errorKey;

  @override
  Object? unwrap(Object? json, OmniRawResponse response) {
    if (json is! Map) {
      throw DecodeFailure(
        'Expected an envelope object with "$dataKey"',
        uri: response.requestUri,
      );
    }
    final err = errorKey;
    if (err != null && json[err] != null) {
      throw DecodeFailure(
        'Response envelope contains "$err"',
        uri: response.requestUri,
      );
    }
    if (!json.containsKey(dataKey)) {
      throw DecodeFailure(
        'Envelope is missing "$dataKey"',
        uri: response.requestUri,
      );
    }
    return json[dataKey];
  }
}
