import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result.dart';
import '../../di/di.dart';
import '../../domain/entities/entities.dart';

/// Authentication state of the app.
sealed class SessionState {
  const SessionState();
}

/// Restoring the stored session at startup (show a splash).
final class SessionLoading extends SessionState {
  const SessionLoading();
}

/// No session. [expired] = the server rejected the token (show "sesi berakhir").
final class SignedOut extends SessionState {
  const SignedOut({this.expired = false});
  final bool expired;
}

final class SignedIn extends SessionState {
  const SignedIn(this.user);
  final AppUser user;
}

/// Owns the session and starts/stops background sync with it.
///
/// ```dart
/// final session = ref.watch(sessionControllerProvider);   // SessionState
/// final r = await ref.read(sessionControllerProvider.notifier).signIn(email, pw);
/// ```
class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    final sub = ref.read(watchSessionExpiredProvider)().listen((_) {
      ref.read(stopSyncProvider)();
      state = const SignedOut(expired: true);
    });
    ref.onDispose(sub.cancel);
    Future.microtask(_restore);
    return const SessionLoading();
  }

  Future<void> _restore() async {
    final user = await ref.read(restoreSessionProvider)();
    if (!ref.mounted) return;
    if (user == null) {
      state = const SignedOut();
      return;
    }
    _enter(user);
    // Refresh the cached profile in the background (ignored when offline).
    unawaited(refreshProfile());
  }

  void _enter(AppUser user) {
    state = SignedIn(user);
    ref.read(startSyncProvider)();
  }

  Future<Result<AppUser>> _handle(Future<Result<AppUser>> f) async {
    final r = await f;
    if (r case Ok(:final value)) _enter(value);
    return r;
  }

  /// Email + password (primary flow).
  Future<Result<AppUser>> signIn(String email, String password) =>
      _handle(ref.read(signInProvider)(email: email, password: password));

  Future<Result<AppUser>> register(
    String name,
    String email,
    String password,
  ) => _handle(
    ref.read(registerProvider)(name: name, email: email, password: password),
  );

  /// [idToken] from `google_sign_in` (`GoogleSignInAccount.authentication.idToken`).
  Future<Result<AppUser>> signInWithGoogle(String idToken) =>
      _handle(ref.read(signInWithGoogleProvider)(idToken));

  /// Signs out and wipes local data (including unsynced changes).
  Future<void> signOut() async {
    await ref.read(signOutProvider)();
    state = const SignedOut();
  }

  Future<Result<AppUser>> refreshProfile() async {
    final r = await ref.read(refreshProfileProvider)();
    if (r case Ok(:final value) when ref.mounted && state is SignedIn) {
      state = SignedIn(value);
    }
    return r;
  }

  /// Changes name and/or currency on the server (needs connectivity).
  Future<Result<AppUser>> updateProfile({
    String? name,
    String? currency,
  }) async {
    final r = await ref.read(updateProfileProvider)(
      name: name,
      currency: currency,
    );
    if (r case Ok(:final value) when ref.mounted) state = SignedIn(value);
    return r;
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

/// The signed-in user, or null.
final currentUserProvider = Provider<AppUser?>(
  (ref) => switch (ref.watch(sessionControllerProvider)) {
    SignedIn(:final user) => user,
    _ => null,
  },
);

/// The user's currency for money formatting (`IDR` when signed out).
final currencyProvider = Provider<String>(
  (ref) => ref.watch(currentUserProvider)?.currency ?? 'IDR',
);
