/// Typed failures shared by every layer.
///
/// Repositories and use cases throw these (use cases wrap them in [Result]).
/// The presentation layer maps them to friendly Indonesian copy; [message] is
/// already a human-readable (Indonesian where we author it) description.
sealed class Failure implements Exception {
  const Failure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// No connection / timeout / server unreachable.
final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Tidak ada koneksi internet']);
}

/// Missing/expired token or wrong credentials (HTTP 401).
final class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure([super.message = 'Sesi kamu sudah berakhir']);
}

/// Input failed validation (local rules mirroring the web's zod schemas, or HTTP 400).
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {this.field});

  /// Optional name of the offending input field (e.g. `amount`).
  final String? field;
}

/// Referenced row doesn't exist (locally or on the server, HTTP 404).
final class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'Data tidak ditemukan']);
}

/// Conflict such as "email already taken" (HTTP 409).
final class ConflictFailure extends Failure {
  const ConflictFailure(super.message);
}

/// Anything else. [cause] keeps the original error for logging.
final class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Terjadi kesalahan', this.cause]);

  final Object? cause;
}
