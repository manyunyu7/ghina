import '../../core/clock.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/local/app_database.dart';
import '../sync/local_cascades.dart';
import '../sync/outbox.dart';

/// Shared dependencies of the drift repositories.
class LocalStore {
  LocalStore(this.db, this.outbox, this.clock)
    : cascades = LocalCascades(db, outbox);

  final AppDatabase db;
  final Outbox outbox;
  final Clock clock;
  final LocalCascades cascades;

  /// Runs [body] in one DB transaction (row write + outbox enqueue), then pokes sync.
  Future<T> write<T>(Future<T> Function() body) async {
    final r = await db.transaction(body);
    outbox.notifyLocalWrite();
    return r;
  }
}

/// [UnitOfWork] over the drift database (nested repository writes join it).
class DriftUnitOfWork implements UnitOfWork {
  DriftUnitOfWork(this._store);
  final LocalStore _store;

  @override
  Future<T> run<T>(Future<T> Function() action) => _store.write(action);
}
