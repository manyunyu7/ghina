import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/local/app_database.dart';
import '../datasources/remote/auth_api.dart';
import '../datasources/remote/token_store.dart';
import '../models/api_dto.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required this._api,
    required this._tokens,
    required this._db,
  });

  final AuthApi _api;
  final TokenStore _tokens;
  final AppDatabase _db;
  final _expired = StreamController<void>.broadcast();
  bool _handlingExpiry = false;

  @override
  Stream<void> get sessionExpired => _expired.stream;

  /// Called by the API client on a 401 of an authenticated call.
  Future<void> onUnauthorized() async {
    if (_handlingExpiry) return;
    _handlingExpiry = true;
    try {
      if (await _tokens.readToken() == null) return;
      // Keep local data: the same user can sign in again and push pending changes.
      await _tokens.writeToken(null);
      _expired.add(null);
    } finally {
      _handlingExpiry = false;
    }
  }

  @override
  Future<AppUser?> restoreSession() async {
    if (await _tokens.readToken() == null) return null;
    final raw = await _tokens.readUser();
    if (raw == null) return null;
    try {
      return appUserFromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<AppUser> _establish(AuthResponse res) async {
    final meta = await _db.getMeta();
    if (meta.userId != null && meta.userId != res.user.id) {
      await _db.wipe(includeMeta: true); // someone else's data
    }
    final fresh = await _db.getMeta();
    await _db.updateMeta(
      SyncMetaCompanion(
        userId: Value(res.user.id),
        epoch: fresh.epoch == null && res.user.syncEpoch.isNotEmpty
            ? Value(res.user.syncEpoch)
            : const Value.absent(),
      ),
    );
    await _tokens.writeToken(res.token);
    await _cache(res.user);
    return res.user;
  }

  Future<void> _cache(AppUser u) =>
      _tokens.writeUser(jsonEncode(appUserToJson(u)));

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async => _establish(await _api.login(email, password));

  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
  }) async => _establish(await _api.register(name, email, password));

  @override
  Future<AppUser> signInWithGoogle(String idToken) async =>
      _establish(await _api.google(idToken));

  @override
  Future<AppUser> refreshProfile() async {
    final u = await _api.me();
    await _cache(u);
    return u;
  }

  @override
  Future<AppUser> updateProfile({String? name, String? currency}) async {
    final u = await _api.updateMe(name: name, currency: currency);
    await _cache(u);
    return u;
  }

  @override
  Future<void> signOut() async {
    await _tokens.clear();
    await _db.wipe(includeMeta: true);
  }
}
