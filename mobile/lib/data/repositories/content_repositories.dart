import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/usecases/content_rules.dart'
    show recordSponsorPaid, recordStage;
import '../datasources/local/app_database.dart';
import '../models/entity_names.dart';
import '../models/notes_content_mappers.dart';
import '../models/notes_content_wire.dart';
import 'local_store.dart';
import 'notes_repositories.dart' show pendingPhotoPaths, storePendingPhotos;
import 'photo_store.dart';

class DriftSocialAccountRepository implements SocialAccountRepository {
  DriftSocialAccountRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$SocialAccountsTable, SocialAccountRow> get _all =>
      _db.select(_db.socialAccounts)..orderBy([
        (a) => OrderingTerm.asc(a.sortOrder),
        (a) => OrderingTerm.asc(a.createdAt),
      ]);

  @override
  Stream<List<SocialAccount>> watchAll() =>
      _all.watch().map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<SocialAccount>> getAll() async => [
    for (final x in await _all.get()) x.toEntity(),
  ];

  @override
  Stream<SocialAccount?> watchById(String id) =>
      (_db.select(_db.socialAccounts)..where((a) => a.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntity());

  @override
  Future<SocialAccount?> getById(String id) async => (await (_db.select(
    _db.socialAccounts,
  )..where((a) => a.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(SocialAccount account) => _s.write(() async {
    final exists = await getById(account.id) != null;
    await _db
        .into(_db.socialAccounts)
        .insertOnConflictUpdate(account.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.socialAccounts,
      entityId: account.id,
      data: socialAccountToWire(account),
      clientUpdatedAt: account.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.socialAccounts,
    )..where((a) => a.id.equals(id))).go();
    if (n == 0) return;
    await _s.cascades.socialAccountDeleted(id);
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.socialAccounts,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftContentItemRepository implements ContentItemRepository {
  DriftContentItemRepository(this._s, [PhotoStore? media])
    : _media = media ?? InMemoryPhotoStore();
  final LocalStore _s;
  final PhotoStore _media;
  AppDatabase get _db => _s.db;

  @override
  Stream<List<ContentItem>> watchAll() => _db
      .select(_db.contentItems)
      .watch()
      .map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<ContentItem>> getAll() async => [
    for (final x in await _db.select(_db.contentItems).get()) x.toEntity(),
  ];

  @override
  Stream<ContentItem?> watchById(String id) =>
      (_db.select(_db.contentItems)..where((i) => i.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntity());

  @override
  Future<ContentItem?> getById(String id) async => (await (_db.select(
    _db.contentItems,
  )..where((i) => i.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(ContentItem item) async {
    final before = await getById(item.id);
    final oldLocal = pendingPhotoPaths(before?.photos ?? const []);
    final photos = await storePendingPhotos(
      _media,
      item.photos,
      oldLocal,
      item.id,
      MediaFolder.contentPhotos,
    );
    await _s.write(() async {
      final current = await getById(item.id);
      // Device-only stage log: keep what we know, add newly reached stages.
      final log = recordStage(
        {...?current?.stageReachedAt, ...item.stageReachedAt},
        item.stage,
        item.updatedAt,
      );
      final row = item.copyWith(
        photos: photos,
        stageReachedAt: log,
        sponsorPaidAt: recordSponsorPaid(current, item, item.updatedAt),
      );
      await _db
          .into(_db.contentItems)
          .insertOnConflictUpdate(row.toCompanion());
      await _s.outbox.enqueueUpsert(
        entity: SyncEntity.contentItems,
        entityId: row.id,
        data: contentItemToWire(row),
        clientUpdatedAt: row.updatedAt,
        isCreate: current == null,
      );
    });
    for (final path in oldLocal.difference(pendingPhotoPaths(photos))) {
      await _media.delete(path);
    }
  }

  @override
  Future<void> delete(String id) async {
    final existing = await getById(id);
    if (existing == null) return;
    await _s.write(() async {
      final n = await (_db.delete(
        _db.contentItems,
      )..where((i) => i.id.equals(id))).go();
      if (n == 0) return;
      await _s.cascades.contentItemDeleted(id);
      await _s.outbox.enqueueDelete(
        entity: SyncEntity.contentItems,
        entityId: id,
        clientUpdatedAt: _s.clock.now(),
      );
    });
    for (final path in pendingPhotoPaths(existing.photos)) {
      await _media.delete(path);
    }
  }
}

class DriftContentPostRepository implements ContentPostRepository {
  DriftContentPostRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  @override
  Stream<List<ContentPost>> watchAll() => _db
      .select(_db.contentPosts)
      .watch()
      .map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<ContentPost>> getAll({String? contentId}) async {
    final q = _db.select(_db.contentPosts);
    if (contentId != null) q.where((p) => p.contentId.equals(contentId));
    return [for (final x in await q.get()) x.toEntity()];
  }

  @override
  Stream<ContentPost?> watchById(String id) =>
      (_db.select(_db.contentPosts)..where((p) => p.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntity());

  @override
  Future<ContentPost?> getById(String id) async => (await (_db.select(
    _db.contentPosts,
  )..where((p) => p.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(ContentPost post) => _s.write(() async {
    final exists = await getById(post.id) != null;
    await _db.into(_db.contentPosts).insertOnConflictUpdate(post.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.contentPosts,
      entityId: post.id,
      data: contentPostToWire(post),
      clientUpdatedAt: post.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.contentPosts,
    )..where((p) => p.id.equals(id))).go();
    if (n == 0) return;
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.contentPosts,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftContentPillarRepository implements ContentPillarRepository {
  DriftContentPillarRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$ContentPillarsTable, ContentPillarRow> get _all =>
      _db.select(_db.contentPillars)..orderBy([
        (p) => OrderingTerm.asc(p.sortOrder),
        (p) => OrderingTerm.asc(p.name.lower()),
      ]);

  @override
  Stream<List<ContentPillar>> watchAll() =>
      _all.watch().map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<ContentPillar>> getAll() async => [
    for (final x in await _all.get()) x.toEntity(),
  ];

  @override
  Future<ContentPillar?> getById(String id) async => (await (_db.select(
    _db.contentPillars,
  )..where((p) => p.id.equals(id))).getSingleOrNull())?.toEntity();

  /// A rename also renames the pillar on the items (like the server).
  @override
  Future<void> save(ContentPillar pillar) => _s.write(() async {
    final before = await getById(pillar.id);
    final exists = before != null;
    if (before != null) {
      await _s.cascades.pillarRenamed(before.name, pillar.name);
    }
    await _db
        .into(_db.contentPillars)
        .insertOnConflictUpdate(pillar.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.contentPillars,
      entityId: pillar.id,
      data: contentPillarToWire(pillar),
      clientUpdatedAt: pillar.updatedAt,
      isCreate: !exists,
    );
  });

  /// Items with this pillar get `pillar = null` (like the server).
  @override
  Future<void> delete(String id) => _s.write(() async {
    final before = await getById(id);
    if (before == null) return;
    await (_db.delete(_db.contentPillars)..where((p) => p.id.equals(id))).go();
    await _s.cascades.pillarDeleted(before.name);
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.contentPillars,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}
