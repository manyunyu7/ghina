/// JSON wire format (contract "Entities" / "JSON conventions").
///
/// `*ToWire` builds the push `data` (full row minus id/createdAt/updatedAt);
/// `*FromWire` turns a pulled row into a drift companion.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../datasources/local/app_database.dart';
import 'entity_names.dart';
import 'mappers.dart' show encodePhotos, localPhotoPrefix;

typedef Json = Map<String, dynamic>;

/// UTC ISO-8601 with `Z` (what the server expects).
String isoUtc(DateTime d) => d.toUtc().toIso8601String();

DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();
double _num(Object? v) => (v as num).toDouble();
double? _numN(Object? v) => v == null ? null : (v as num).toDouble();
int? _intN(Object? v) => v == null ? null : (v as num).round();
String? _strN(Object? v) => v as String?;

// ---------------------------------------------------------------- to wire

Json walletToWire(Wallet w) => {
  'name': w.name,
  'type': w.type.wire,
  'balance': w.syncedBalance,
  'currency': w.currency,
  'color': w.color,
  'icon': w.icon,
  'archived': w.archived,
};

Json categoryToWire(TxCategory c) => {
  'name': c.name,
  'type': c.type.wire,
  'color': c.color,
  'icon': c.icon,
};

/// `photos` carries only uploaded paths: pending local photos are uploaded by the
/// sync engine first, which then patches the queued upsert.
Json transactionToWire(Transaction t) => {
  'walletId': t.walletId,
  'toWalletId': t.toWalletId,
  'categoryId': t.categoryId,
  'type': t.type.wire,
  'amount': t.amount,
  'note': t.note,
  'date': isoUtc(t.date),
  'photos': wirePhotos(t.photos),
};

/// What the server accepts in `transactions.photos` (what `/api/mobile/upload`
/// returns).
final uploadPathRe = RegExp(r'^/uploads/[A-Za-z0-9-]+\.[a-z]+$');

/// Uploaded photo paths in order, deduplicated, at most [maxTransactionPhotos].
/// Pending local ones — and anything the server would reject, which would get the
/// whole transaction rejected — are left out.
List<String> wirePhotos(List<TransactionPhoto> photos) {
  final out = <String>[];
  for (final p in photos) {
    final url = p.url;
    if (p.isPending || url == null || !uploadPathRe.hasMatch(url)) continue;
    if (!out.contains(url)) out.add(url);
  }
  return out.length > maxTransactionPhotos
      ? out.sublist(0, maxTransactionPhotos)
      : out;
}

Json taskAreaToWire(TaskArea a) => {
  'name': a.name,
  'code': a.code,
  'color': a.color,
  'icon': a.icon,
  'schedule': a.schedule?.toJson(),
  'sortOrder': a.sortOrder,
  'archived': a.archived,
};

Json taskToWire(Task t) => {
  'areaId': t.areaId,
  'title': t.title,
  'note': t.note,
  'bucket': t.bucket.wire,
  'dueDate': t.dueDate,
  'dueTime': t.dueTime,
  'remindBefore': t.remindBefore,
  'recurrence': t.recurrence?.toJson(),
  'seriesId': t.seriesId,
  'done': t.done,
  'doneAt': t.doneAt == null ? null : isoUtc(t.doneAt!),
  'sortOrder': t.sortOrder,
  'amount': t.amount,
  'walletId': t.walletId,
  'categoryId': t.categoryId,
  'transactionId': t.transactionId,
};

Json budgetToWire(Budget b) => {
  'categoryId': b.categoryId,
  'amount': b.amount,
  'month': b.month,
  'year': b.year,
};

Json subscriptionToWire(Subscription s) => {
  'name': s.name,
  'amount': s.amount,
  'currency': s.currency,
  'cycle': s.cycle.wire,
  'nextBilling': isoUtc(s.nextBilling),
  'categoryId': s.categoryId,
  'walletId': s.walletId,
  'color': s.color,
  'icon': s.icon,
  'note': s.note,
  'active': s.active,
};

Json plannedToWire(PlannedTransaction p) => {
  'type': p.type.wire,
  'amount': p.amount,
  'note': p.note,
  'categoryId': p.categoryId,
  'walletId': p.walletId,
  'date': isoUtc(p.date),
  'done': p.done,
};

Json prayerToWire(PrayerEntry p) => {
  'date': p.date,
  'prayer': p.prayer.wire,
  'status': p.status.wire,
  'qobliyah': p.qobliyah,
  'badiyah': p.badiyah,
  'rakaat': p.rakaat,
  'prayedAt': p.prayedAt == null ? null : isoUtc(p.prayedAt!),
  'note': p.note,
};

Json healthToWire(HealthEntry h) => {
  'date': isoUtc(h.date),
  'weight': h.weight,
  'systolic': h.systolic,
  'diastolic': h.diastolic,
  'pulse': h.pulse,
  'note': h.note,
};

/// `localPhotoPath` is device-only and never sent.
Json foodToWire(FoodLog f) => {
  'date': isoUtc(f.date),
  'name': f.name,
  'meal': f.meal?.wire,
  'calories': f.calories,
  'photoUrl': f.photoUrl,
  'note': f.note,
};

// ---------------------------------------------------------------- from wire

Value<DateTime> _created(Json j) => Value(_date(j['createdAt']));
Value<DateTime> _updated(Json j) => Value(
  j['updatedAt'] == null ? _date(j['createdAt']) : _date(j['updatedAt']),
);

WalletsCompanion walletFromWire(Json j) => WalletsCompanion(
  id: Value(j['id'] as String),
  name: Value(j['name'] as String),
  type: Value(j['type'] as String? ?? 'cash'),
  balance: Value(_numN(j['balance']) ?? 0),
  currency: Value(j['currency'] as String? ?? 'IDR'),
  color: Value(j['color'] as String? ?? '#6366f1'),
  icon: Value(j['icon'] as String? ?? 'wallet'),
  archived: Value(j['archived'] as bool? ?? false),
  createdAt: _created(j),
  updatedAt: _updated(j),
);

CategoriesCompanion categoryFromWire(Json j) => CategoriesCompanion(
  id: Value(j['id'] as String),
  name: Value(j['name'] as String),
  type: Value(j['type'] as String? ?? 'expense'),
  color: Value(j['color'] as String? ?? '#6366f1'),
  icon: Value(j['icon'] as String? ?? 'circle'),
  createdAt: _created(j),
  updatedAt: _updated(j),
);

/// An older server sends no `photos`: the stored list is kept (absent value; `[]`
/// on insert). [keepPending] = pending local photos of the local row, appended so
/// a pull never loses a photo that hasn't been uploaded yet.
TransactionsCompanion transactionFromWire(
  Json j, {
  List<TransactionPhoto> keepPending = const [],
}) => TransactionsCompanion(
  id: Value(j['id'] as String),
  walletId: Value(j['walletId'] as String),
  toWalletId: Value(_strN(j['toWalletId'])),
  categoryId: Value(_strN(j['categoryId'])),
  type: Value(j['type'] as String? ?? 'expense'),
  amount: Value(_num(j['amount'])),
  note: Value(_strN(j['note'])),
  date: Value(_date(j['date'])),
  photos: j['photos'] is List
      ? Value(
          encodePhotos([
            for (final x in j['photos'] as List)
              if (x is String &&
                  x.isNotEmpty &&
                  !x.startsWith(localPhotoPrefix))
                TransactionPhoto.remote(x),
            ...keepPending,
          ]),
        )
      : const Value.absent(),
  createdAt: _created(j),
  updatedAt: _updated(j),
);

/// JSON objects on the wire; a JSON string is tolerated too.
Object? _jsonField(Object? v) {
  if (v is String) {
    try {
      return jsonDecode(v);
    } catch (_) {
      return null;
    }
  }
  return v;
}

String? _jsonColumn(Object? parsed, Map<String, Object?>? Function(Object?) f) {
  final m = f(parsed);
  return m == null ? null : jsonEncode(m);
}

TaskAreasCompanion taskAreaFromWire(Json j) => TaskAreasCompanion(
  id: Value(j['id'] as String),
  name: Value(j['name'] as String? ?? ''),
  code: Value(j['code'] as String? ?? ''),
  color: Value(j['color'] as String? ?? '#58CC02'),
  icon: Value(j['icon'] as String? ?? 'briefcase'),
  schedule: Value(
    _jsonColumn(
      _jsonField(j['schedule']),
      (v) => AreaSchedule.tryParse(v)?.toJson(),
    ),
  ),
  sortOrder: Value(_intN(j['sortOrder']) ?? 0),
  archived: Value(j['archived'] as bool? ?? false),
  createdAt: _created(j),
  updatedAt: _updated(j),
);

TasksCompanion taskFromWire(Json j) => TasksCompanion(
  id: Value(j['id'] as String),
  areaId: Value(j['areaId'] as String),
  title: Value(j['title'] as String? ?? ''),
  note: Value(_strN(j['note'])),
  bucket: Value(TaskBucket.fromWire(j['bucket'] as String?).wire),
  dueDate: Value(_strN(j['dueDate'])),
  dueTime: Value(_strN(j['dueTime'])),
  remindBefore: Value(_intN(j['remindBefore'])),
  recurrence: Value(
    _jsonColumn(
      _jsonField(j['recurrence']),
      (v) => Recurrence.tryParse(v)?.toJson(),
    ),
  ),
  seriesId: Value(_strN(j['seriesId'])),
  done: Value(j['done'] as bool? ?? false),
  doneAt: Value(j['doneAt'] == null ? null : _date(j['doneAt'])),
  sortOrder: Value(_numN(j['sortOrder']) ?? 0),
  amount: Value(_numN(j['amount'])),
  walletId: Value(_strN(j['walletId'])),
  categoryId: Value(_strN(j['categoryId'])),
  transactionId: Value(_strN(j['transactionId'])),
  createdAt: _created(j),
  updatedAt: _updated(j),
);

BudgetsCompanion budgetFromWire(Json j) => BudgetsCompanion(
  id: Value(j['id'] as String),
  categoryId: Value(j['categoryId'] as String),
  amount: Value(_num(j['amount'])),
  month: Value((j['month'] as num).toInt()),
  year: Value((j['year'] as num).toInt()),
  createdAt: _created(j),
  updatedAt: _updated(j),
);

SubscriptionsCompanion subscriptionFromWire(Json j) => SubscriptionsCompanion(
  id: Value(j['id'] as String),
  name: Value(j['name'] as String),
  amount: Value(_num(j['amount'])),
  currency: Value(j['currency'] as String? ?? 'IDR'),
  cycle: Value(j['cycle'] as String? ?? 'monthly'),
  nextBilling: Value(_date(j['nextBilling'])),
  categoryId: Value(_strN(j['categoryId'])),
  walletId: Value(_strN(j['walletId'])),
  color: Value(j['color'] as String? ?? '#6366f1'),
  icon: Value(j['icon'] as String? ?? 'credit-card'),
  note: Value(_strN(j['note'])),
  active: Value(j['active'] as bool? ?? true),
  createdAt: _created(j),
  updatedAt: _updated(j),
);

PlannedCompanion plannedFromWire(Json j) => PlannedCompanion(
  id: Value(j['id'] as String),
  type: Value(j['type'] as String? ?? 'expense'),
  amount: Value(_num(j['amount'])),
  note: Value(_strN(j['note'])),
  categoryId: Value(_strN(j['categoryId'])),
  walletId: Value(_strN(j['walletId'])),
  date: Value(_date(j['date'])),
  done: Value(j['done'] as bool? ?? false),
  createdAt: _created(j),
  updatedAt: _updated(j),
);

/// Older servers send only `date, prayer`: the new fields fall back to the
/// server defaults (`status` ontime — done for sunnah —, no rawatib).
PrayersCompanion prayerFromWire(Json j) {
  final prayer = j['prayer'] as String;
  final p = Prayer.fromWire(prayer);
  final status = p == null
      ? (j['status'] as String? ?? 'ontime')
      : PrayerStatus.forPrayer(p, j['status'] as String?).wire;
  return PrayersCompanion(
    id: Value(j['id'] as String),
    date: Value(j['date'] as String),
    prayer: Value(prayer),
    status: Value(status),
    qobliyah: Value(j['qobliyah'] as bool? ?? false),
    badiyah: Value(j['badiyah'] as bool? ?? false),
    rakaat: Value(_intN(j['rakaat'])),
    prayedAt: Value(j['prayedAt'] == null ? null : _date(j['prayedAt'])),
    note: Value(_strN(j['note'])),
    createdAt: _created(j),
    updatedAt: _updated(j),
  );
}

HealthCompanion healthFromWire(Json j) => HealthCompanion(
  id: Value(j['id'] as String),
  date: Value(_date(j['date'])),
  weight: Value(_numN(j['weight'])),
  systolic: Value(_intN(j['systolic'])),
  diastolic: Value(_intN(j['diastolic'])),
  pulse: Value(_intN(j['pulse'])),
  note: Value(_strN(j['note'])),
  createdAt: _created(j),
  updatedAt: _updated(j),
);

/// Pulled food rows never carry a local photo.
FoodCompanion foodFromWire(Json j) => FoodCompanion(
  id: Value(j['id'] as String),
  date: Value(_date(j['date'])),
  name: Value(j['name'] as String),
  meal: Value(_strN(j['meal'])),
  calories: Value(_intN(j['calories'])),
  photoUrl: Value(_strN(j['photoUrl'])),
  localPhotoPath: const Value(null),
  note: Value(_strN(j['note'])),
  createdAt: _created(j),
  updatedAt: _updated(j),
);

/// Pulled row → companion for [entity].
Insertable<dynamic> companionFromWire(String entity, Json j) =>
    switch (entity) {
      SyncEntity.wallets => walletFromWire(j),
      SyncEntity.categories => categoryFromWire(j),
      SyncEntity.transactions => transactionFromWire(j),
      SyncEntity.budgets => budgetFromWire(j),
      SyncEntity.subscriptions => subscriptionFromWire(j),
      SyncEntity.planned => plannedFromWire(j),
      SyncEntity.prayers => prayerFromWire(j),
      SyncEntity.health => healthFromWire(j),
      SyncEntity.food => foodFromWire(j),
      SyncEntity.taskAreas => taskAreaFromWire(j),
      SyncEntity.tasks => taskFromWire(j),
      _ => throw ArgumentError('Unknown entity $entity'),
    };

/// Balance effects of a transaction given as wire data (null = no row). A type
/// this app doesn't know has no local effect.
Map<String, double> wireTxEffects(Json? data) {
  if (data == null) return const {};
  final type = TxType.tryFromWire(data['type'] as String?);
  if (type == null) return const {};
  return ledgerEffects(
    type: type,
    amount: _num(data['amount']),
    walletId: data['walletId'] as String,
    toWalletId: data['toWalletId'] as String?,
  );
}
