import 'dart:math';

import 'package:meta/meta.dart';

import '../core/omni_network_exception.dart';
import '../core/omni_request.dart';
import '../core/omni_response.dart';

/// When and how often a failed request is sent again.
///
/// Safe by default: only `GET` and `HEAD` are retried. `PUT`/`DELETE`
/// (idempotent per RFC 9110) can be added to [methods]. `POST`/`PATCH` are
/// retried **only** when the request carries an `Idempotency-Key` header
/// **and** [retryWithIdempotencyKey] is `true`.
///
/// Retried outcomes: [statuses] (default 408, 429, 500, 502, 503, 504),
/// [TimeoutFailure] and [ConnectionFailure]. Never retried: cancellation,
/// closed client, request-building errors, [AuthFailure], an open circuit.
///
/// Uploads and downloads are not retried automatically.
@immutable
final class RetryPolicy {
  /// Creates a policy. [maxAttempts] counts the first attempt too.
  const RetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 300),
    this.maxDelay = const Duration(seconds: 10),
    this.multiplier = 2,
    this.jitter = true,
    this.methods = const {HttpMethod.get, HttpMethod.head},
    this.statuses = const {408, 429, 500, 502, 503, 504},
    this.retryOnTimeout = true,
    this.retryOnConnectionError = true,
    this.retryWithIdempotencyKey = false,
    this.respectRetryAfter = true,
    this.maxRetryAfter = const Duration(seconds: 60),
    this.random,
  }) : assert(maxAttempts >= 1);

  /// A policy that never retries (use per request to opt out).
  static const none = RetryPolicy(maxAttempts: 1);

  /// Total attempts including the first.
  final int maxAttempts;

  /// Delay before the first retry.
  final Duration baseDelay;

  /// Upper bound for one backoff delay.
  final Duration maxDelay;

  /// Growth factor per retry.
  final double multiplier;

  /// Randomise each delay to 50–100 % of its value (avoids thundering herds).
  final bool jitter;

  /// Methods that may be retried.
  final Set<HttpMethod> methods;

  /// Status codes that trigger a retry.
  final Set<int> statuses;

  /// Retry after [TimeoutFailure].
  final bool retryOnTimeout;

  /// Retry after [ConnectionFailure].
  final bool retryOnConnectionError;

  /// Allow retrying POST/PATCH that carry an `Idempotency-Key` header.
  final bool retryWithIdempotencyKey;

  /// Use the server's `Retry-After` header as the delay when present.
  final bool respectRetryAfter;

  /// A `Retry-After` longer than this is not waited for; the response is
  /// returned instead.
  final Duration maxRetryAfter;

  /// Random source for jitter (inject for deterministic tests).
  final Random? random;

  static final _defaultRandom = Random();

  /// Whether [request] may be retried at all.
  bool allows(OmniRequest request) {
    if (maxAttempts <= 1) return false;
    if (methods.contains(request.method)) return true;
    return retryWithIdempotencyKey &&
        (request.method == HttpMethod.post ||
            request.method == HttpMethod.patch ||
            request.method == HttpMethod.put ||
            request.method == HttpMethod.delete) &&
        (request.header('idempotency-key')?.isNotEmpty ?? false);
  }

  /// Whether [error] is worth another attempt.
  bool retriesError(OmniNetworkException error) => switch (error) {
    TimeoutFailure() => retryOnTimeout,
    ConnectionFailure() => retryOnConnectionError,
    _ => false,
  };

  /// Backoff before retry number [retry] (1 = first retry), before jitter
  /// is applied when [withJitter] is false.
  Duration backoff(int retry, {bool withJitter = true}) {
    final raw = baseDelay.inMicroseconds * pow(multiplier, retry - 1);
    var micros = min(raw, maxDelay.inMicroseconds.toDouble());
    if (jitter && withJitter) {
      micros *= 0.5 + (random ?? _defaultRandom).nextDouble() * 0.5;
    }
    return Duration(microseconds: micros.round());
  }

  /// Delay before retry [retry] after [response] (or an error when `null`);
  /// `null` means "do not retry" (Retry-After beyond [maxRetryAfter]).
  Duration? delayFor(int retry, OmniRawResponse? response, {DateTime? now}) {
    final header = response?.headers['retry-after'];
    if (respectRetryAfter && header != null) {
      final d = parseRetryAfter(header, now ?? DateTime.now());
      if (d != null) return d > maxRetryAfter ? null : d;
    }
    return backoff(retry);
  }

  static final _date = RegExp(
    r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  );
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Parses a `Retry-After` value: delta seconds or an IMF-fixdate
  /// (`Wed, 21 Oct 2015 07:28:00 GMT`). Past dates give [Duration.zero];
  /// unparsable values give `null`.
  @visibleForTesting
  static Duration? parseRetryAfter(String value, DateTime now) {
    final v = value.trim();
    final secs = int.tryParse(v);
    if (secs != null) return secs < 0 ? null : Duration(seconds: secs);
    final m = _date.firstMatch(v);
    if (m == null) return null;
    final month = _months.indexOf(m[2]!) + 1;
    if (month == 0) return null;
    final at = DateTime.utc(
      int.parse(m[3]!),
      month,
      int.parse(m[1]!),
      int.parse(m[4]!),
      int.parse(m[5]!),
      int.parse(m[6]!),
    );
    final d = at.difference(now.toUtc());
    return d.isNegative ? Duration.zero : d;
  }
}
