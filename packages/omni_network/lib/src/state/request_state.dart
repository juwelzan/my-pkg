import 'package:meta/meta.dart';

import '../core/omni_network_exception.dart';

/// The lifecycle of one request, for UI binding (plain Dart, no Flutter).
///
/// ```dart
/// switch (state) {
///   RequestIdle() || RequestLoading(previous: null) => spinner(),
///   RequestLoading(:final previous?) => list(previous, refreshing: true),
///   RequestSuccess(:final data) => list(data),
///   RequestEmpty() => emptyView(),
///   RequestError(:final error) => errorView(error),
/// }
/// ```
@immutable
sealed class RequestState<T> {
  const RequestState();

  /// The latest data available in this state, if any.
  T? get data;

  /// Whether a load is running.
  bool get isLoading => this is RequestLoading<T>;
}

/// Nothing requested yet.
final class RequestIdle<T> extends RequestState<T> {
  /// Creates the idle state.
  const RequestIdle();

  @override
  T? get data => null;

  @override
  String toString() => 'RequestIdle<$T>()';
}

/// A load is running; [previous] is the last successful data (refresh).
final class RequestLoading<T> extends RequestState<T> {
  /// Creates the loading state.
  const RequestLoading({this.previous});

  /// Data shown while refreshing, or `null` on the first load.
  final T? previous;

  @override
  T? get data => previous;

  @override
  String toString() => 'RequestLoading<$T>(previous: $previous)';
}

/// The load succeeded with non-empty [data].
final class RequestSuccess<T> extends RequestState<T> {
  /// Creates the success state.
  const RequestSuccess(this.data);

  @override
  final T data;

  @override
  String toString() => 'RequestSuccess<$T>($data)';
}

/// The load succeeded but returned nothing (`null`, empty list/map/string,
/// or the controller's custom `isEmpty`).
final class RequestEmpty<T> extends RequestState<T> {
  /// Creates the empty state.
  const RequestEmpty([this.data]);

  /// The (empty) value returned, if any.
  @override
  final T? data;

  @override
  String toString() => 'RequestEmpty<$T>()';
}

/// The load failed; [previous] keeps the last successful data.
final class RequestError<T> extends RequestState<T> {
  /// Creates the failure state.
  const RequestError(this.error, {this.previous, this.stackTrace});

  /// What went wrong: usually an [OmniNetworkException].
  final Object error;

  /// Where it was thrown.
  final StackTrace? stackTrace;

  /// Last successful data, if any.
  final T? previous;

  /// [error] as a network failure, or `null` for other errors.
  OmniNetworkException? get networkError =>
      error is OmniNetworkException ? error as OmniNetworkException : null;

  @override
  T? get data => previous;

  @override
  String toString() => 'RequestError<$T>($error)';
}
