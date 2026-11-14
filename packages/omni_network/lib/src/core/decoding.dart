import 'omni_network_exception.dart';
import 'omni_response.dart';
import 'response_adapter.dart';

/// Builds a `T` from one JSON object, e.g. `User.fromJson`.
typedef JsonDecoder<T> = T Function(Map<String, dynamic> json);

bool _same<A, B>() => <A>[] is List<B> && <B>[] is List<A>;

/// Decodes a 2xx [raw] response into `T`. Internal.
T decodeBody<T>(
  OmniRawResponse raw,
  JsonDecoder<T>? decoder,
  ResponseAdapter adapter,
) {
  final uri = raw.requestUri;
  if (decoder == null) {
    if (raw.bodyBytes.isEmpty) {
      if (null is T) return null as T;
      throw DecodeFailure('Empty body, expected $T', uri: uri);
    }
    if (_same<T, String>()) return raw.text as T;
    // `void`, `dynamic`, `Object?` are indistinguishable at runtime: return
    // parsed JSON, or the text when the body is not JSON (e.g. "OK").
    if (_same<T, Object?>()) {
      try {
        return adapter.unwrap(raw.json, raw) as T;
      } on FormatException {
        return raw.text as T;
      }
    }
  }
  final value = adapter.unwrap(parseJson(raw), raw);
  if (decoder == null) {
    if (value is T) return value;
    throw DecodeFailure('Expected $T, got ${value.runtimeType}', uri: uri);
  }
  return runDecoder(() => decoder(asObject(value, uri)), uri);
}

/// Decodes a 2xx [raw] JSON array of objects into `List<T>`. Internal.
List<T> decodeList<T>(
  OmniRawResponse raw,
  JsonDecoder<T> decoder,
  ResponseAdapter adapter,
) {
  final uri = raw.requestUri;
  final value = adapter.unwrap(parseJson(raw), raw);
  if (value is! List) {
    throw DecodeFailure(
      'Expected a JSON array, got ${value.runtimeType}',
      uri: uri,
    );
  }
  return [
    for (var i = 0; i < value.length; i++)
      runDecoder(() => decoder(asObject(value[i], uri, index: i)), uri),
  ];
}

/// Parses the body as JSON or throws [DecodeFailure].
Object? parseJson(OmniRawResponse raw) {
  if (raw.bodyBytes.isEmpty) {
    throw DecodeFailure('Empty body, expected JSON', uri: raw.requestUri);
  }
  try {
    return raw.json;
  } on FormatException catch (e) {
    // e.source may contain the body; keep only the offset.
    throw DecodeFailure(
      'Body is not valid JSON (at offset ${e.offset})',
      uri: raw.requestUri,
    );
  }
}

/// Casts [value] to a JSON object or throws [DecodeFailure].
Map<String, dynamic> asObject(Object? value, Uri? uri, {int? index}) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  final where = index == null ? '' : ' at index $index';
  throw DecodeFailure(
    'Expected a JSON object$where, got ${value.runtimeType}',
    uri: uri,
  );
}

/// Runs a user decoder, turning any throw into [DecodeFailure].
T runDecoder<T>(T Function() run, Uri? uri) {
  try {
    return run();
  } on DecodeFailure {
    rethrow;
  } catch (e, st) {
    throw DecodeFailure(
      'Decoder threw ${e.runtimeType}',
      uri: uri,
      cause: e,
      stackTrace: st,
    );
  }
}
