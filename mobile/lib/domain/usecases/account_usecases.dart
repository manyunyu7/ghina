/// Auth/session and sync use cases.
library;

import '../../core/failure.dart';
import '../../core/result.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'validation.dart';

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String _email(String v) {
  final e = v.trim().toLowerCase();
  if (!_emailRe.hasMatch(e)) {
    throw const ValidationFailure('Email tidak valid', field: 'email');
  }
  return e;
}

/// Cached user if a session exists (offline-friendly), else null.
final class RestoreSession {
  const RestoreSession(this._auth);
  final AuthRepository _auth;

  Future<AppUser?> call() => _auth.restoreSession();
}

final class SignIn {
  const SignIn(this._auth);
  final AuthRepository _auth;

  Future<Result<AppUser>> call({
    required String email,
    required String password,
  }) => guard(() {
    if (password.isEmpty) {
      throw const ValidationFailure('Password wajib diisi', field: 'password');
    }
    return _auth.signIn(email: _email(email), password: password);
  });
}

final class Register {
  const Register(this._auth);
  final AuthRepository _auth;

  Future<Result<AppUser>> call({
    required String name,
    required String email,
    required String password,
  }) => guard(() {
    if (password.length < 8) {
      throw const ValidationFailure(
        'Password minimal 8 karakter',
        field: 'password',
      );
    }
    return _auth.register(
      name: requireName(name),
      email: _email(email),
      password: password,
    );
  });
}

/// Signs in with a Google ID token obtained by the screen via `google_sign_in`.
final class SignInWithGoogle {
  const SignInWithGoogle(this._auth);
  final AuthRepository _auth;

  Future<Result<AppUser>> call(String idToken) => guard(() {
    if (idToken.isEmpty) {
      throw const UnauthorizedFailure('Login Google dibatalkan');
    }
    return _auth.signInWithGoogle(idToken);
  });
}

/// Clears the session and wipes local data.
final class SignOut {
  const SignOut(this._auth, this._sync);
  final AuthRepository _auth;
  final SyncService _sync;

  Future<Result<void>> call() => guard(() async {
    _sync.stop();
    await _auth.signOut();
  });
}

final class RefreshProfile {
  const RefreshProfile(this._auth);
  final AuthRepository _auth;

  Future<Result<AppUser>> call() => guard(_auth.refreshProfile);
}

/// Updates name and/or currency (requires connectivity).
final class UpdateProfile {
  const UpdateProfile(this._auth);
  final AuthRepository _auth;

  Future<Result<AppUser>> call({String? name, String? currency}) => guard(
    () => _auth.updateProfile(
      name: name == null ? null : requireName(name),
      currency: currency == null ? null : requireCurrency(currency),
    ),
  );
}

final class WatchSessionExpired {
  const WatchSessionExpired(this._auth);
  final AuthRepository _auth;

  Stream<void> call() => _auth.sessionExpired;
}

final class StartSync {
  const StartSync(this._sync);
  final SyncService _sync;

  void call() => _sync.start();
}

final class StopSync {
  const StopSync(this._sync);
  final SyncService _sync;

  void call() => _sync.stop();
}

/// Pull-to-refresh / "Sinkronkan sekarang".
final class SyncNow {
  const SyncNow(this._sync);
  final SyncService _sync;

  Future<Result<void>> call() => guard(_sync.syncNow);
}

final class WatchSyncStatus {
  const WatchSyncStatus(this._sync);
  final SyncService _sync;

  Stream<SyncStatus> call() => _sync.watchStatus();
}

/// Settings → "Reset data lokal": wipe local data (incl. unsynced changes) and re-download.
final class ResetLocalData {
  const ResetLocalData(this._sync);
  final SyncService _sync;

  Future<Result<void>> call() => guard(_sync.resetLocalData);
}
