/// In-memory task/area/wallet/transaction repositories for Beranda tests, so the
/// "Tugas FIRE" card runs the real use cases (`WatchTaskHome`, `CompleteTask`,
/// `CreateTransaction`) without a database. Pass `extra: fx.overrides` to
/// `pageOverrides`.
library;

import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/domain/entities/entities.dart';

import '../../../domain/fakes.dart';
import '../shell/test_utils.dart';

class HomeTaskFixture {
  HomeTaskFixture({DateTime? now}) : now = now ?? testNow;

  final DateTime now;
  final tasks = FakeTaskRepository();
  final areas = FakeTaskAreaRepository();
  final wallets = FakeWalletRepository();
  final transactions = FakeTransactionRepository();
  final categories = FakeCategoryRepository();

  List<Override> get overrides => [
    taskRepositoryProvider.overrideWithValue(tasks),
    // Notes/content sources (game events, merged reminders) in memory.
    contentItemRepositoryProvider.overrideWithValue(
      FakeContentItemRepository(),
    ),
    contentPostRepositoryProvider.overrideWithValue(
      FakeContentPostRepository(),
    ),
    socialAccountRepositoryProvider.overrideWithValue(
      FakeSocialAccountRepository(),
    ),
    taskAreaRepositoryProvider.overrideWithValue(areas),
    walletRepositoryProvider.overrideWithValue(wallets),
    transactionRepositoryProvider.overrideWithValue(transactions),
    categoryRepositoryProvider.overrideWithValue(categories),
    unitOfWorkProvider.overrideWithValue(FakeUnitOfWork()),
    // "Now" once; never closes (like the real minute ticker).
    tickSourceProvider.overrideWithValue(
      () => Stream<DateTime>.multi((c) => c.add(now)),
    ),
  ];

  /// Keseharian (no schedule) — the focus area at [testNow] (Wednesday noon)
  /// unless a scheduled area is active.
  TaskArea life() => area('life', 'Keseharian', 'LIFE');

  TaskArea area(
    String id,
    String name,
    String code, {
    AreaSchedule? schedule,
    int sortOrder = 0,
  }) {
    final a = TaskArea(
      id: id,
      name: name,
      code: code,
      schedule: schedule,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
    unawaited(areas.save(a));
    return a;
  }

  Task task(
    String id,
    String title, {
    String areaId = 'life',
    TaskBucket bucket = TaskBucket.fire,
    String? dueDate,
    double? amount,
    String? walletId,
    bool done = false,
    DateTime? doneAt,
    int sortOrder = 0,
  }) {
    final t = Task(
      id: id,
      areaId: areaId,
      title: title,
      bucket: bucket,
      dueDate: dueDate,
      amount: amount,
      walletId: walletId,
      done: done,
      doneAt: doneAt,
      sortOrder: sortOrder.toDouble(),
      createdAt: now.subtract(const Duration(days: 2)),
      updatedAt: now.subtract(const Duration(days: 2)),
    );
    unawaited(tasks.save(t));
    return t;
  }

  Wallet wallet(String id, String name, double balance) {
    final w = Wallet(
      id: id,
      name: name,
      type: WalletType.cash,
      balance: balance,
      syncedBalance: balance,
      currency: 'IDR',
      color: '#22c55e',
      icon: 'cash',
      archived: false,
      createdAt: now,
      updatedAt: now,
    );
    unawaited(wallets.save(w));
    return w;
  }
}

/// [base] plus the task repositories of [fx] (default: one empty focus area).
List<Override> withTasks(List<Override> base, [HomeTaskFixture? fx]) {
  final f = fx ?? (HomeTaskFixture()..life());
  return [...base, ...f.overrides];
}
