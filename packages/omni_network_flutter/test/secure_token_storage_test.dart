import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_network/omni_network.dart';
import 'package:omni_network/testing.dart';
import 'package:omni_network_flutter/omni_network_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('round trip; null clears', () async {
    final s = SecureTokenStorage();
    expect(await s.read(), isNull);
    final t = Tokens(access: 'A', refresh: 'R', expiresAt: DateTime.utc(2030));
    await s.write(t);
    final back = await s.read();
    expect(
      (back!.access, back.refresh, back.expiresAt),
      ('A', 'R', DateTime.utc(2030)),
    );
    await s.write(null);
    expect(await s.read(), isNull);
  });

  test('separate keys keep separate tokens', () async {
    final a = SecureTokenStorage(key: 'a');
    final b = SecureTokenStorage(key: 'b');
    await a.write(const Tokens(access: 'A'));
    expect(await b.read(), isNull);
    expect((await a.read())!.access, 'A');
  });

  test(
    'corrupted data is cleared, reported without secrets, treated as signed out',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'omni_network.tokens': '{not json SECRET',
      });
      final errors = <Object>[];
      final s = SecureTokenStorage(onError: errors.add);
      expect(await s.read(), isNull);
      expect(errors.single, isA<FormatException>());
      expect('${errors.single}', isNot(contains('SECRET')));
      // The broken entry is gone.
      expect(
        await const FlutterSecureStorage().read(key: 'omni_network.tokens'),
        isNull,
      );
    },
  );

  test('platform errors never crash the app', () async {
    final errors = <Object>[];
    final s = SecureTokenStorage(storage: _Failing(), onError: errors.add);
    expect(await s.read(), isNull);
    await s.write(const Tokens(access: 'A'));
    await s.write(null);
    expect(errors, hasLength(3));
    expect(errors, everyElement(isA<PlatformException>()));
  });

  test('users stay signed in across app restarts', () async {
    final mock = OmniMock()
      ..get(
        '/me',
        (r) => MockResponse.json({'auth': r.headers['authorization']}),
      );
    // First launch: log in.
    final first = OmniNetwork(
      baseUrl: 'https://h.io',
      transport: mock,
      auth: OmniAuth(storage: SecureTokenStorage()),
    );
    await first.auth.login(const Tokens(access: 'SAVED', refresh: 'R'));
    await first.close();
    // "Restart": a new client with a new storage object, same secure store.
    final second = OmniNetwork(
      baseUrl: 'https://h.io',
      transport: mock,
      auth: OmniAuth(storage: SecureTokenStorage()),
    );
    expect(await second.auth.restore(), isTrue);
    expect(await second.get<Map<String, dynamic>>('/me'), {
      'auth': 'Bearer SAVED',
    });
    // Logout removes them from the secure store.
    await second.auth.logout();
    final third = OmniAuth(storage: SecureTokenStorage());
    expect(await third.restore(), isFalse);
    await second.close();
  });
}

final class _Failing extends FlutterSecureStorage {
  _Failing();
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => throw PlatformException(code: 'locked');
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => throw PlatformException(code: 'locked');
  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => throw PlatformException(code: 'locked');
}
