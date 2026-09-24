// Regressions found by the notes/content end-to-end QA
// (test/data/e2e_notes_content_test.dart): push order vs server cascades, stage
// auto-advance across devices, sponsor income link + XP time.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/models/wire.dart' show Json;
import 'package:ghina/di/game_overrides.dart' show contentActivityEventsFrom;
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/activity.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '../harness.dart';

void main() {
  late Harness h;

  setUp(() => h = Harness());
  tearDown(() => h.close());

  Json row(String entity, String id) => h.server.rows[entity]![id]!;

  Future<String> account(Harness d, String handle) async {
    d.tick();
    return (await d.createAccount(
      SocialAccountInput(platform: SocialPlatform.instagram, handle: handle),
    )).valueOrThrow.id;
  }

  test(
    'push order: edits of rows a server delete cascade touches go before that delete; pillars after items',
    () async {
      final w = await h.newWallet('Dompet', 1000);
      h.tick();
      final label = (await h.createLabel(
        const NoteLabelInput(name: 'Tag'),
      )).valueOrThrow;
      h.tick();
      final pillar = (await h.createPillar(
        const ContentPillarInput(name: 'Edukasi'),
      )).valueOrThrow;
      h.tick();
      final item = (await h.createItem(
        const ContentItemInput(
          title: 'Endorse',
          pillar: 'Edukasi',
          sponsor: SponsorInput(brand: 'B', amount: 100),
        ),
      )).valueOrThrow;
      h.tick();
      final tx = (await h.markSponsorPaid(
        item.id,
        record: SponsorPayment(walletId: w),
      )).valueOrThrow.transaction!;
      await h.engine.syncNow();
      h.server.pushed.clear();

      // Offline: unpaid + delete the income, rename the pillar, delete and
      // re-create the label name.
      h.tick();
      await MarkSponsorUnpaid(h.items, h.clock)(item.id);
      h.tick();
      await h.deleteTx(tx.id);
      h.tick();
      await h.updatePillar(
        pillar.id,
        const ContentPillarInput(name: 'Tutorial'),
      );
      h.tick();
      await h.deleteLabel(label.id);
      h.tick();
      final label2 = (await h.createLabel(
        const NoteLabelInput(name: 'Tag'),
      )).valueOrThrow;
      await h.engine.syncNow();

      final order = [
        for (final m in h.server.pushed)
          '${m.entity}/${m.op.name}/${m.entityId}',
      ];
      int at(String entity, String op, String id) =>
          order.indexOf('$entity/$op/$id');
      expect(
        at(SyncEntity.contentItems, 'upsert', item.id),
        lessThan(at(SyncEntity.transactions, 'delete', tx.id)),
        reason: 'the tx delete would bump the item (sponsor link) first',
      );
      expect(
        at(SyncEntity.contentItems, 'upsert', item.id),
        lessThan(at(SyncEntity.contentPillars, 'upsert', pillar.id)),
        reason: 'the rename would bump the item first',
      );
      expect(
        at(SyncEntity.noteLabels, 'delete', label.id),
        lessThan(at(SyncEntity.noteLabels, 'upsert', label2.id)),
        reason: 'same name: the delete must free it first',
      );
      final s = row(SyncEntity.contentItems, item.id);
      expect(s['sponsor']['paid'], isFalse);
      expect(s['pillar'], 'Tutorial');
      expect(h.server.rejected, isEmpty);
    },
  );

  test('pillar delete + re-create with the same name: delete first', () async {
    h.tick();
    final p = (await h.createPillar(
      const ContentPillarInput(name: 'Promo'),
    )).valueOrThrow;
    await h.engine.syncNow();
    h.server.pushed.clear();
    h.tick();
    await h.deletePillar(p.id);
    h.tick();
    final p2 = (await h.createPillar(
      const ContentPillarInput(name: 'Promo'),
    )).valueOrThrow;
    await h.engine.syncNow();
    expect([for (final m in h.server.pushed) m.entityId], [p.id, p2.id]);
  });

  test('area delete + re-create with the same code: delete first', () async {
    h.tick();
    final a1 = (await h.createArea(
      const TaskAreaInput(name: 'Kuliah', code: 'KUL'),
    )).valueOrThrow;
    await h.engine.syncNow();
    h.server.pushed.clear();
    h.tick();
    await h.deleteArea(a1.id);
    h.tick();
    final a2 = (await h.createArea(
      const TaskAreaInput(name: 'Kuliah baru', code: 'KUL'),
    )).valueOrThrow;
    h.tick();
    final t = (await h.createTask(
      TaskInput(areaId: a2.id, title: 'Skripsi'),
    )).valueOrThrow;
    await h.engine.syncNow();
    expect([for (final m in h.server.pushed) m.entityId].take(2), [
      a1.id,
      a2.id,
    ]);
    expect(h.server.rows[SyncEntity.tasks]![t.id]!['areaId'], a2.id);
    expect(h.server.rejected, isEmpty);
    expect(await h.outboxCount(), 0);
  });

  test(
    'stage auto-advance: two devices posting different accounts offline → tayang on both',
    () async {
      final other = Harness(server: h.server);
      addTearDown(other.close);
      final ig = await account(h, 'ig');
      final tt = await account(h, 'tt');
      h.tick();
      final item = (await h.createItem(
        const ContentItemInput(title: 'Tips'),
      )).valueOrThrow;
      h.tick();
      final p1 = (await h.createPost(
        item.id,
        ContentPostInput(accountId: ig, scheduledAt: DateTime(2026, 9, 25, 19)),
      )).valueOrThrow;
      h.tick();
      final p2 = (await h.createPost(
        item.id,
        ContentPostInput(accountId: tt, scheduledAt: DateTime(2026, 9, 25, 19)),
      )).valueOrThrow;
      await h.engine.syncNow();
      await other.engine.syncNow();
      expect(
        (await other.items.getById(item.id))!.stage,
        ContentStage.terjadwal,
      );

      h.tick();
      await h.markPosted(p1.id);
      other.tick();
      other.tick();
      await other.markPosted(p2.id);
      expect((await h.items.getById(item.id))!.stage, ContentStage.terjadwal);
      await h.engine.syncNow();
      await other.engine.syncNow(); // pulls p1 posted → tayang, queued
      await other.engine.syncNow();
      await h.engine.syncNow();

      expect(row(SyncEntity.contentItems, item.id)['stage'], 'tayang');
      for (final d in [h, other]) {
        final i = (await d.items.getById(item.id))!;
        expect(i.stage, ContentStage.tayang);
        expect(i.stageReachedAt.containsKey(ContentStage.tayang), isTrue);
        expect(await d.outboxCount(), 0);
      }
    },
  );

  test(
    'a full pull never re-advances a stage the user moved back by hand',
    () async {
      final ig = await account(h, 'ig');
      h.tick();
      final item = (await h.createItem(
        const ContentItemInput(title: 'Tips'),
      )).valueOrThrow;
      h.tick();
      final p = (await h.createPost(
        item.id,
        ContentPostInput(accountId: ig),
      )).valueOrThrow;
      h.tick();
      await h.markPosted(p.id);
      h.tick();
      await h.moveStage(item.id, ContentStage.siap);
      await h.engine.syncNow();
      // A new phone downloads everything.
      final other = Harness(server: h.server);
      addTearDown(other.close);
      await other.engine.syncNow();
      expect((await other.items.getById(item.id))!.stage, ContentStage.siap);
      expect(await other.outboxCount(), 0);
    },
  );

  test(
    'sponsor: unpaid keeps the income linked, paid again reuses it; removal refused while linked',
    () async {
      final w = await h.newWallet('Dompet', 0);
      h.tick();
      final item = (await h.createItem(
        const ContentItemInput(
          title: 'Endorse',
          sponsor: SponsorInput(brand: 'B', amount: 100),
        ),
      )).valueOrThrow;
      h.tick();
      final tx = (await h.markSponsorPaid(
        item.id,
        record: SponsorPayment(walletId: w),
      )).valueOrThrow.transaction!;
      h.tick();
      await MarkSponsorUnpaid(h.items, h.clock)(item.id);
      final unpaid = (await h.items.getById(item.id))!.sponsor!;
      expect([unpaid.paid, unpaid.transactionId], [false, tx.id]);
      h.tick();
      final again = (await h.markSponsorPaid(
        item.id,
        record: SponsorPayment(walletId: w),
      )).valueOrThrow;
      expect(again.transaction, isNull);
      expect(again.item.sponsor!.transactionId, tx.id);
      expect(await h.transactions.list(), hasLength(1));

      // Removing the sponsor (either path) is refused while the income is linked.
      h.tick();
      final r1 = await h.setSponsor(item.id, null);
      expect(r1.failureOrNull, isA<ValidationFailure>());
      final r2 = await h.updateItem(
        item.id,
        const ContentItemInput(title: 'Endorse', keepSponsor: false),
      );
      expect(r2.failureOrNull, isA<ValidationFailure>());
      expect((await h.items.getById(item.id))!.sponsor, isNotNull);

      // Once the income is deleted: removable; paying a sponsor again records anew.
      h.tick();
      await h.deleteTx(tx.id);
      expect((await h.items.getById(item.id))!.sponsor!.transactionId, isNull);
      h.tick();
      final paid2 = (await h.markSponsorPaid(
        item.id,
        record: SponsorPayment(walletId: w),
      )).valueOrThrow;
      expect(paid2.transaction, isNotNull);
      h.tick();
      await h.deleteTx(paid2.transaction!.id);
      h.tick();
      expect((await h.setSponsor(item.id, null)).isOk, isTrue);
      expect((await h.items.getById(item.id))!.sponsor, isNull);
    },
  );

  test(
    'sponsor XP time is stable: income date, else when first seen paid — never a later edit',
    () async {
      final w = await h.newWallet('Dompet', 0);
      h.tick();
      final a = (await h.createItem(
        const ContentItemInput(
          title: 'Dengan transaksi',
          sponsor: SponsorInput(brand: 'A', amount: 100),
        ),
      )).valueOrThrow;
      h.tick();
      final b = (await h.createItem(
        const ContentItemInput(
          title: 'Barter',
          sponsor: SponsorInput(brand: 'B', amount: 0),
        ),
      )).valueOrThrow;
      h.tick();
      final txDate = DateTime(2026, 9, 1, 10);
      final tx = (await h.markSponsorPaid(
        a.id,
        record: SponsorPayment(walletId: w, date: txDate),
      )).valueOrThrow.transaction!;
      h.tick();
      await h.markSponsorPaid(b.id);
      final paidAt = h.clock.now();
      expect((await h.items.getById(b.id))!.sponsorPaidAt, paidAt);

      // Days later both items are edited.
      h.clock.advance(const Duration(days: 3));
      for (final id in [a.id, b.id]) {
        await h.moveStage(id, ContentStage.naskah);
      }
      Future<Map<String, DateTime>> times() async => {
        for (final e in contentActivityEventsFrom(
          await h.items.getAll(),
          const [],
          const [],
          transactions: [tx],
        ))
          if (e.contentType == ContentEventType.sponsorPaid) e.id!: e.at,
      };
      expect(await times(), {a.id: txDate, b.id: paidAt});

      // It survives a sync round trip (device-only, never sent) and a pull.
      await h.engine.syncNow();
      expect(
        row(SyncEntity.contentItems, b.id)['sponsor'],
        isNot(contains('sponsorPaidAt')),
      );
      expect((await h.items.getById(b.id))!.sponsorPaidAt, paidAt);
      expect(await times(), {a.id: txDate, b.id: paidAt});

      // Unpaid clears it; paid again stamps the new time.
      h.tick();
      await MarkSponsorUnpaid(h.items, h.clock)(b.id);
      expect((await h.items.getById(b.id))!.sponsorPaidAt, isNull);
      h.tick();
      await h.markSponsorPaid(b.id);
      expect((await h.items.getById(b.id))!.sponsorPaidAt, h.clock.now());

      // Another device first sees it paid through a pull: the row's updatedAt,
      // kept across later edits there.
      final other = Harness(server: h.server);
      addTearDown(other.close);
      await other.engine.syncNow();
      final seen = (await other.items.getById(b.id))!;
      expect(seen.sponsorPaidAt, seen.updatedAt);
      other.clock.advance(const Duration(days: 2));
      await other.moveStage(b.id, ContentStage.siap);
      expect((await other.items.getById(b.id))!.sponsorPaidAt, seen.updatedAt);
    },
  );
}
