import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_network/advanced.dart';

/// Keeps `OmniAuth` tokens in the platform's secure store, so users stay
/// signed in after the app restarts.
///
/// ```dart
/// final api = OmniNetwork(
///   baseUrl: 'https://api.example.com',
///   auth: OmniAuth(storage: SecureTokenStorage(), refresh: ...),
/// );
/// ```
///
/// Where the tokens live:
///
/// | Platform | Store |
/// |---|---|
/// | iOS / macOS | Keychain (macOS needs the Keychain Sharing entitlement) |
/// | Android | Keystore-encrypted storage |
/// | Windows / Linux | Credential Manager / libsecret |
/// | Web | WebCrypto-encrypted `localStorage`. A browser cannot protect it from scripts on your own origin, so prefer short-lived access tokens there. |
///
/// Unreadable or corrupted data is deleted and treated as "signed out", so a
/// broken entry can never lock the app. Errors from the platform store are
/// reported through [onError] (default: `debugPrint` of the error type only,
/// never the tokens) and the app continues signed out.
final class SecureTokenStorage implements TokenStorage {
  /// Creates the storage. [key] lets several clients keep separate tokens.
  SecureTokenStorage({
    this._storage = const FlutterSecureStorage(),
    this.key = 'omni_network.tokens',
    void Function(Object error)? onError,
  }) : _onError = onError ?? _report;

  /// Entry name in the secure store.
  final String key;

  final FlutterSecureStorage _storage;
  final void Function(Object error) _onError;

  static void _report(Object error) =>
      debugPrint('SecureTokenStorage: ${error.runtimeType}');

  @override
  Future<Tokens?> read() async {
    final String? raw;
    try {
      raw = await _storage.read(key: key);
    } catch (e) {
      _onError(e);
      return null;
    }
    if (raw == null) return null;
    try {
      return Tokens.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (e) {
      _onError(const FormatException('Stored tokens are unreadable; cleared'));
      await _delete();
      return null;
    }
  }

  @override
  Future<void> write(Tokens? tokens) async {
    if (tokens == null) return _delete();
    try {
      await _storage.write(key: key, value: jsonEncode(tokens.toJson()));
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> _delete() async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      _onError(e);
    }
  }
}
