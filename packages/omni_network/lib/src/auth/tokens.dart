import 'dart:async';

import 'package:meta/meta.dart';

/// Access and refresh tokens of a signed-in user.
@immutable
final class Tokens {
  /// Creates tokens. Give [expiresIn] (as most APIs return `expires_in`) or
  /// [expiresAt]; without either the token is refreshed only on 401.
  const Tokens({
    required this.access,
    this.refresh,
    this.expiresAt,
    this.expiresIn,
  });

  /// Access token sent as `Authorization: Bearer …`.
  final String access;

  /// Refresh token, passed back to your refresh callback.
  final String? refresh;

  /// When [access] expires.
  final DateTime? expiresAt;

  /// Lifetime of [access] from when it was saved (converted to
  /// [expiresAt] by `OmniAuth`).
  final Duration? expiresIn;

  /// Copy with [expiresAt] fixed relative to [now] when only [expiresIn]
  /// was given. Internal.
  Tokens fixedAt(DateTime now) => expiresAt != null || expiresIn == null
      ? this
      : Tokens(
          access: access,
          refresh: refresh,
          expiresAt: now.add(expiresIn!),
        );

  /// JSON for storage. Contains secrets: store it securely.
  Map<String, Object?> toJson() => {
    'access': access,
    'refresh': refresh,
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
  };

  /// Restores tokens written by [toJson].
  factory Tokens.fromJson(Map<String, Object?> json) => Tokens(
    access: json['access']! as String,
    refresh: json['refresh'] as String?,
    expiresAt: json['expiresAt'] == null
        ? null
        : DateTime.parse(json['expiresAt']! as String),
  );

  /// Never prints the token values.
  @override
  String toString() =>
      'Tokens(access: ***, refresh: ${refresh == null ? 'none' : '***'}, '
      'expiresAt: $expiresAt)';
}

/// Where `OmniAuth` keeps tokens. Implement for persistence (the Flutter
/// package provides secure storage).
abstract interface class TokenStorage {
  /// Saved tokens, or `null`.
  FutureOr<Tokens?> read();

  /// Saves [tokens]; `null` clears them.
  FutureOr<void> write(Tokens? tokens);
}

/// Keeps tokens in memory (lost on restart). The default.
final class MemoryTokenStorage implements TokenStorage {
  /// Creates storage, optionally pre-filled.
  MemoryTokenStorage([this._tokens]);

  Tokens? _tokens;

  @override
  Tokens? read() => _tokens;

  @override
  void write(Tokens? tokens) => _tokens = tokens;
}
