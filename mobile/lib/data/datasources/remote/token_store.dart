import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the bearer token and the cached user JSON.
abstract interface class TokenStore {
  Future<String?> readToken();
  Future<void> writeToken(String? token);
  Future<String?> readUser();
  Future<void> writeUser(String? userJson);
  Future<void> clear();
}

/// Keychain / Keystore backed store with an in-memory cache.
final class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'ghina.token';
  static const _userKey = 'ghina.user';

  final FlutterSecureStorage _storage;
  String? _token;
  bool _tokenLoaded = false;

  @override
  Future<String?> readToken() async {
    if (!_tokenLoaded) {
      _token = await _storage.read(key: _tokenKey);
      _tokenLoaded = true;
    }
    return _token;
  }

  @override
  Future<void> writeToken(String? token) async {
    _token = token;
    _tokenLoaded = true;
    if (token == null) {
      await _storage.delete(key: _tokenKey);
    } else {
      await _storage.write(key: _tokenKey, value: token);
    }
  }

  @override
  Future<String?> readUser() => _storage.read(key: _userKey);

  @override
  Future<void> writeUser(String? userJson) => userJson == null
      ? _storage.delete(key: _userKey)
      : _storage.write(key: _userKey, value: userJson);

  @override
  Future<void> clear() async {
    await writeToken(null);
    await writeUser(null);
  }
}

/// For tests.
final class MemoryTokenStore implements TokenStore {
  String? token;
  String? user;

  @override
  Future<String?> readToken() async => token;
  @override
  Future<void> writeToken(String? t) async => token = t;
  @override
  Future<String?> readUser() async => user;
  @override
  Future<void> writeUser(String? u) async => user = u;
  @override
  Future<void> clear() async {
    token = null;
    user = null;
  }
}
