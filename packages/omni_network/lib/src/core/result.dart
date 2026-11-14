import 'omni_network_exception.dart';

/// Outcome of a request as a value instead of an exception.
///
/// ```dart
/// switch (await api.get<User>('/me', decoder: User.fromJson).asResult()) {
///   case Ok(:final value): show(value);
///   case Err(:final error): showError(error);
/// }
/// ```
sealed class Result<T> {
  const Result();

  /// The value, or `null` for an [Err].
  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Err() => null,
  };

  /// Whether this is an [Ok].
  bool get isOk => this is Ok<T>;
}

/// A successful result.
final class Ok<T> extends Result<T> {
  /// Wraps [value].
  const Ok(this.value);

  /// The value.
  final T value;

  @override
  String toString() => 'Ok($value)';
}

/// A failed result.
final class Err<T> extends Result<T> {
  /// Wraps [error].
  const Err(this.error);

  /// The failure.
  final OmniNetworkException error;

  @override
  String toString() => 'Err($error)';
}

/// Converts a request future into a [Result].
extension OmniResultFuture<T> on Future<T> {
  /// Completes with [Ok] or, for an [OmniNetworkException], [Err]. Other
  /// errors (programming bugs) are not caught.
  Future<Result<T>> asResult() async {
    try {
      return Ok(await this);
    } on OmniNetworkException catch (e) {
      return Err(e);
    }
  }
}
