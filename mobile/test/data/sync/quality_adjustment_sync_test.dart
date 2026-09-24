// Sync of the prayer-quality fields and balance adjustments through the real
// drift database + outbox against the in-memory server.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/models/wire.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '../harness.dart';

void main() {
  late Harness h;

  setUp(() => h = Harness());
  tearDown(() => h.close());

  group('balance adjustments', () {
    test(
      'offline adjustment → displayed balance moves, server matches after push',
      () async {
        final w = await h.newWallet('BCA', 100000);
        await h.engine.syncNow();

        h.server.online = false;
        h.tick();
        final adjust = AdjustWalletBalance(h.wallets, h.transactions, h.clock);
        final t = (await adjust(w, 87500)).valueOrThrow;
        expect(t.amount, -12500);
        expect((await h.wallet(w)).balance, 87500);
        expect((await h.wallet(w)).syncedBalance, 100000);

        // Edit it offline (like any transaction): the pending effect telescopes.
        h.tick();
        await h.updateTx(
          t.id,
          TransactionInput(
            type: TxType.adjustment,
            amount: 2500,
            walletId: w,
            note: t.note,
            date: t.date,
          ),
        );
        expect((await h.wallet(w)).balance, 102500);

        h.server.online = true;
        await h.engine.syncNow();
        final row = h.server.rows[SyncEntity.transactions]![t.id]!;
        expect(row['type'], 'adjustment');
        expect(row['amount'], 2500);
        expect(row['categoryId'], isNull);
        expect(row['toWalletId'], isNull);
        expect(h.server.balanceOf(w), 102500);
        expect((await h.wallet(w)).balance, 102500);
        expect((await h.wallet(w)).syncedBalance, 102500);

        // Delete restores the previous balance.
        h.tick();
        await h.deleteTx(t.id);
        expect((await h.wallet(w)).balance, 100000);
        await h.engine.syncNow();
        expect(h.server.balanceOf(w), 100000);
      },
    );

    test(
      'adjustments pulled from the web are listed and hit no totals',
      () async {
        final w = await h.newWallet('Tunai', 50000);
        await h.engine.syncNow();
        h.server.web(SyncEntity.transactions, 'adj1', {
          'walletId': w,
          'toWalletId': null,
          'categoryId': null,
          'type': 'adjustment',
          'amount': -5000,
          'note': 'Penyesuaian saldo: Rp 50.000 → Rp 45.000',
          'date': isoUtc(h.clock.now()),
        });
        await h.engine.syncNow();
        expect((await h.wallet(w)).balance, 45000);
        final list = await h.transactions.list();
        expect(list.single.type, TxType.adjustment);
        expect(list.single.amount, -5000);
        expect(
          monthlyTotals(list, [YearMonth.of(h.clock.now())]).single.net,
          0,
        );
      },
    );

    test(
      'unknown transaction types from a newer server are skipped, not a crash',
      () async {
        final w = await h.newWallet('Tunai', 50000);
        await h.engine.syncNow();
        h.server.rows[SyncEntity.transactions]!['future1'] = {
          'id': 'future1',
          'walletId': w,
          'toWalletId': null,
          'categoryId': null,
          'type': 'cashback',
          'amount': 7000,
          'note': null,
          'date': isoUtc(h.clock.now()),
          'createdAt': isoUtc(h.clock.now()),
          'updatedAt': isoUtc(h.clock.now().add(const Duration(minutes: 5))),
        };
        // The server already applied its effect to the wallet balance.
        h.server.rows[SyncEntity.wallets]![w]!['balance'] = 57000;
        h.server.rows[SyncEntity.wallets]![w]!['updatedAt'] = isoUtc(
          h.clock.now().add(const Duration(minutes: 5)),
        );
        await h.engine.pullOnly();

        expect(await h.transactions.list(), isEmpty);
        expect(await h.transactions.getById('future1'), isNull);
        expect(await h.transactions.watch(limit: 5).first, isEmpty);
        final wallet = await h.wallet(w);
        expect(
          wallet.balance,
          57000,
          reason: 'server balance, no local effect',
        );
        // The row is kept (a full pull won't fight it) but never shown.
        final raw = await h.db.select(h.db.transactions).get();
        expect(raw.single.type, 'cashback');
      },
    );
  });

  group('prayers', () {
    test('every quality field round-trips through push and pull', () async {
      final day = DateTime(2026, 9, 23);
      h.tick();
      await SetPrayerStatus(h.prayers, h.clock)(
        day,
        Prayer.dzuhur,
        PrayerStatus.late,
      );
      h.tick();
      final at = DateTime(2026, 9, 23, 12, 40);
      final saved = (await SavePrayerDetails(h.prayers, h.clock)(
        day,
        Prayer.dzuhur,
        PrayerDetailsInput(
          status: PrayerStatus.masjid,
          qobliyah: true,
          badiyah: true,
          prayedAt: at,
          note: 'Masjid kantor',
        ),
      )).valueOrThrow;
      h.tick();
      await SetSunnah(h.prayers, h.clock)(
        day,
        Prayer.witir,
        done: true,
        rakaat: 3,
      );

      // One collapsed upsert per row, carrying every field.
      final queued = await h.outbox.all();
      final dz = queued.firstWhere((m) => m.entityId == saved.id);
      expect(jsonDecode(dz.data!), {
        'date': '2026-09-23',
        'prayer': 'dzuhur',
        'status': 'masjid',
        'qobliyah': true,
        'badiyah': true,
        'rakaat': null,
        'prayedAt': at.toUtc().toIso8601String(),
        'note': 'Masjid kantor',
      });
      expect(jsonDecode(dz.data!)['prayedAt'], endsWith('Z'));

      await h.engine.syncNow();
      expect(h.server.rejected, isEmpty);
      final server = h.server.rows[SyncEntity.prayers]!;
      expect(server[saved.id]!['status'], 'masjid');
      final witir = server.values.firstWhere((r) => r['prayer'] == 'witir');
      expect(witir['status'], 'done');
      expect(witir['rakaat'], 3);

      // The web changes it; the pull brings every field back.
      h.server.web(SyncEntity.prayers, saved.id, {
        ...server[saved.id]!,
        'status': 'missed',
        'qobliyah': false,
        'badiyah': false,
        'note': null,
      });
      await h.engine.syncNow();
      final local = (await h.prayers.findByKey('2026-09-23', Prayer.dzuhur))!;
      expect(local.status, PrayerStatus.missed);
      expect(local.rawatibCount, 0);
      expect(local.note, isNull);
      expect(local.prayedAt, at);
    });

    test(
      'rows from an older server (no quality fields) read as ontime',
      () async {
        h.server.web(SyncEntity.prayers, 'old1', {
          'date': '2026-09-22',
          'prayer': 'isya',
        });
        h.server.web(SyncEntity.prayers, 'old2', {
          'date': '2026-09-22',
          'prayer': 'tahajud',
        });
        h.server.web(SyncEntity.prayers, 'odd', {
          'date': '2026-09-22',
          'prayer': 'jumat', // unknown prayer id: stored, never shown
        });
        await h.engine.syncNow();
        final rows = await h.prayers
            .watchRange('2026-09-22', '2026-09-22')
            .first;
        expect(rows, hasLength(2));
        final isya = rows.firstWhere((e) => e.prayer == Prayer.isya);
        expect(isya.status, PrayerStatus.ontime);
        expect(isya.qobliyah || isya.badiyah, isFalse);
        expect(
          rows.firstWhere((e) => e.prayer == Prayer.tahajud).status,
          PrayerStatus.done,
        );
      },
    );

    test(
      'status switch to missed clears rawatib before the push (never rejected)',
      () async {
        final day = DateTime(2026, 9, 23);
        h.tick();
        await SavePrayerDetails(h.prayers, h.clock)(
          day,
          Prayer.subuh,
          const PrayerDetailsInput(status: PrayerStatus.jamaah, qobliyah: true),
        );
        await h.engine.syncNow();
        h.tick();
        await SetPrayerStatus(h.prayers, h.clock)(
          day,
          Prayer.subuh,
          PrayerStatus.missed,
        );
        await h.engine.syncNow();
        expect(h.server.rejected, isEmpty);
        final row = h.server.rows[SyncEntity.prayers]!.values.single;
        expect(row['status'], 'missed');
        expect(row['qobliyah'], isFalse);
      },
    );

    test(
      'wire parse is tolerant; companion keeps unknown statuses as default',
      () {
        final c = prayerFromWire({
          'id': 'p',
          'date': '2026-09-22',
          'prayer': 'subuh',
          'status': 'weird',
          'createdAt': '2026-09-22T00:00:00.000Z',
        });
        expect(c.status.value, 'ontime');
        expect(c.qobliyah.value, isFalse);
        expect(c.rakaat.value, isNull);
        expect(c.prayedAt.value, isNull);
        expect(dateKey(DateTime(2026, 9, 22)), c.date.value);
      },
    );
  });
}
