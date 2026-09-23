import 'failure.dart';

/// Outcome of a mutation use case: either [Ok] with a value or [Err] with a [Failure].
///
/// ```dart
/// switch (await createTransaction(input)) {
///   case Ok(:final value): ...
///   case Err(:final failure): showError(failure.message);
/// }
/// ```
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;

  /// The value, or null on failure.
  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Err() => null,
  };

  /// The failure, or null on success.
  Failure? get failureOrNull => switch (this) {
    Ok() => null,
    Err(:final failure) => failure,
  };

  /// Returns the value or throws the failure.
  T get valueOrThrow => switch (this) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };

  R fold<R>(R Function(T value) onOk, R Function(Failure failure) onErr) =>
      switch (this) {
        Ok(:final value) => onOk(value),
        Err(:final failure) => onErr(failure),
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;

  @override
  String toString() => 'Ok($value)';
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;

  @override
  String toString() => 'Err($failure)';
}

/// Runs [body], converting thrown [Failure]s (and any other error) into [Err].
Future<Result<T>> guard<T>(Future<T> Function() body) async {
  try {
    return Ok(await body());
  } on Failure catch (f) {
    return Err(f);
  } catch (e) {
    return Err(UnknownFailure('Terjadi kesalahan', e));
  }
}
