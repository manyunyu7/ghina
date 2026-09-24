/// Tasks (to-do) — `docs/tasks.md`. Pure value types; the rules (recurrence,
/// focus areas, mepet/overdue, reminders) live in `domain/usecases/task_rules.dart`.
library;

import '../../core/dates.dart';

const _unset = Object();

bool _listEq<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// How urgent a task is. Order everywhere: fire, want, should ([values] order).
enum TaskBucket {
  fire('fire', 'FIRE', '🔥', 'hari ini / besok', 0xFFFF4B4B, 10),
  want('want', 'WANT', '✨', '1–2 minggu', 0xFFCE82FF, 8),
  should('should', 'SHOULD', '📋', 'kapan saja / rutin', 0xFF1CB0F6, 5);

  const TaskBucket(
    this.wire,
    this.label,
    this.emoji,
    this.meaning,
    this.color,
    this.xp,
  );

  /// `fire | want | should`
  final String wire;

  /// `FIRE` — also the notification code part (`[KERJA-FIRE] …`).
  final String label;
  final String emoji;

  /// Short Indonesian hint of the bucket's horizon.
  final String meaning;

  /// ARGB (spec colors `#FF4B4B`, `#CE82FF`, `#1CB0F6`).
  final int color;

  /// XP when a task of this bucket is completed (spec table; the XP engine owns
  /// the actual rule).
  final int xp;

  /// `🔥 FIRE`
  String get display => '$emoji $label';

  /// Unknown values → [want] (the server default).
  static TaskBucket fromWire(String? v) =>
      values.firstWhere((b) => b.wire == v, orElse: () => TaskBucket.want);
}

/// `HH:mm` (00:00–23:59).
final _hmRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

bool isHm(String? s) => s != null && _hmRe.hasMatch(s);

/// `9, 5` → `09:05`.
String formatHm(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// Minutes since midnight of an `HH:mm` string.
int hmToMinutes(String hm) =>
    int.parse(hm.substring(0, 2)) * 60 + int.parse(hm.substring(3, 5));

/// When an area is active (focus mode). ISO weekdays (1 = Monday … 7 = Sunday),
/// local `HH:mm` times with `start < end` (no overnight ranges).
final class AreaSchedule {
  const AreaSchedule({
    required this.days,
    required this.start,
    required this.end,
  });

  /// Mon–Fri 09:00–17:00 (default of the "Kerjaan" area).
  static const workHours = AreaSchedule(
    days: [1, 2, 3, 4, 5],
    start: '09:00',
    end: '17:00',
  );

  /// Sorted, distinct ISO weekdays.
  final List<int> days;
  final String start;
  final String end;

  /// True when [local] falls on one of [days] and `start <= time < end`.
  bool contains(DateTime local) {
    if (!days.contains(local.weekday)) return false;
    final m = local.hour * 60 + local.minute;
    return m >= hmToMinutes(start) && m < hmToMinutes(end);
  }

  Map<String, Object?> toJson() => {'days': days, 'start': start, 'end': end};

  /// Null when [json] isn't a valid schedule.
  static AreaSchedule? tryParse(Object? json) {
    if (json is! Map) return null;
    final days = json['days'];
    final start = json['start'], end = json['end'];
    if (days is! List || !isHm(start as String?) || !isHm(end as String?)) {
      return null;
    }
    final d = <int>{
      for (final x in days)
        if (x is num && x.toInt() >= 1 && x.toInt() <= 7) x.toInt(),
    }.toList()..sort();
    return AreaSchedule(days: d, start: start!, end: end!);
  }

  @override
  bool operator ==(Object other) =>
      other is AreaSchedule &&
      _listEq(other.days, days) &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(Object.hashAll(days), start, end);

  @override
  String toString() => 'AreaSchedule($days $start–$end)';
}

enum RecurrenceFreq {
  daily('daily', 'Harian', 'hari'),
  weekly('weekly', 'Mingguan', 'minggu'),
  monthly('monthly', 'Bulanan', 'bulan');

  const RecurrenceFreq(this.wire, this.label, this.unit);
  final String wire;
  final String label;

  /// `setiap 2 <unit>`
  final String unit;

  static RecurrenceFreq? tryFromWire(String? v) {
    for (final f in values) {
      if (f.wire == v) return f;
    }
    return null;
  }
}

/// Repeat rule of a recurring task. [weekdays] (ISO, weekly only) defaults to the
/// due date's weekday; [monthDay] (monthly only) defaults to the due date's day,
/// clamped to the month's last day.
final class Recurrence {
  const Recurrence({
    required this.freq,
    this.interval = 1,
    this.weekdays,
    this.monthDay,
  });

  const Recurrence.daily([this.interval = 1])
    : freq = RecurrenceFreq.daily,
      weekdays = null,
      monthDay = null;

  const Recurrence.weekly({this.interval = 1, this.weekdays})
    : freq = RecurrenceFreq.weekly,
      monthDay = null;

  const Recurrence.monthly({this.interval = 1, this.monthDay})
    : freq = RecurrenceFreq.monthly,
      weekdays = null;

  final RecurrenceFreq freq;

  /// 1–365.
  final int interval;
  final List<int>? weekdays;
  final int? monthDay;

  /// Indonesian summary, e.g. `Setiap hari`, `Setiap 2 minggu (Sen, Rab)`,
  /// `Setiap bulan tgl 31`.
  String get label {
    final every = interval == 1
        ? 'Setiap ${freq.unit}'
        : 'Setiap $interval ${freq.unit}';
    return switch (freq) {
      RecurrenceFreq.daily => every,
      RecurrenceFreq.weekly =>
        weekdays == null || weekdays!.isEmpty
            ? every
            : '$every (${weekdays!.map((d) => isoWeekdayShort[d - 1]).join(', ')})',
      RecurrenceFreq.monthly =>
        monthDay == null ? every : '$every tgl $monthDay',
    };
  }

  Map<String, Object?> toJson() => {
    'freq': freq.wire,
    'interval': interval,
    if (weekdays != null && freq == RecurrenceFreq.weekly) 'weekdays': weekdays,
    if (monthDay != null && freq == RecurrenceFreq.monthly)
      'monthDay': monthDay,
  };

  /// Null when [json] isn't a valid rule. Out-of-range values are clamped.
  static Recurrence? tryParse(Object? json) {
    if (json is! Map) return null;
    final freq = RecurrenceFreq.tryFromWire(json['freq'] as String?);
    if (freq == null) return null;
    final interval = json['interval'];
    final wd = json['weekdays'];
    final md = json['monthDay'];
    final days = wd is List
        ? (<int>{
            for (final x in wd)
              if (x is num && x.toInt() >= 1 && x.toInt() <= 7) x.toInt(),
          }.toList()..sort())
        : null;
    return Recurrence(
      freq: freq,
      interval: interval is num ? interval.toInt().clamp(1, 365) : 1,
      weekdays: freq == RecurrenceFreq.weekly && days != null && days.isNotEmpty
          ? days
          : null,
      monthDay: freq == RecurrenceFreq.monthly && md is num
          ? md.toInt().clamp(1, 31)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Recurrence &&
      other.freq == freq &&
      other.interval == interval &&
      _listEq(other.weekdays, weekdays) &&
      other.monthDay == monthDay;

  @override
  int get hashCode => Object.hash(
    freq,
    interval,
    weekdays == null ? null : Object.hashAll(weekdays!),
    monthDay,
  );

  @override
  String toString() => 'Recurrence(${toJson()})';
}

/// `Sen … Min` by ISO weekday − 1.
const isoWeekdayShort = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

/// `Senin … Minggu` by ISO weekday − 1.
const isoWeekdayNames = [
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

/// A life context (Kerjaan, Keseharian, Kuliah, …).
final class TaskArea {
  const TaskArea({
    required this.id,
    required this.name,
    required this.code,
    this.color = '#58CC02',
    this.icon = 'briefcase',
    this.schedule,
    this.sortOrder = 0,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// 1–40 chars.
  final String name;

  /// 1–8 chars `A–Z0–9`, uppercase, unique per user (`[KERJA-FIRE] …`).
  final String code;

  /// `#rrggbb`
  final String color;

  /// Same icon set as categories (`categoryIcons`).
  final String icon;

  /// Null = no schedule ("anytime").
  final AreaSchedule? schedule;
  final int sortOrder;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasSchedule => schedule != null;

  TaskArea copyWith({
    String? name,
    String? code,
    String? color,
    String? icon,
    Object? schedule = _unset,
    int? sortOrder,
    bool? archived,
    DateTime? updatedAt,
  }) => TaskArea(
    id: id,
    name: name ?? this.name,
    code: code ?? this.code,
    color: color ?? this.color,
    icon: icon ?? this.icon,
    schedule: identical(schedule, _unset)
        ? this.schedule
        : schedule as AreaSchedule?,
    sortOrder: sortOrder ?? this.sortOrder,
    archived: archived ?? this.archived,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is TaskArea &&
      other.id == id &&
      other.name == name &&
      other.code == code &&
      other.color == color &&
      other.icon == icon &&
      other.schedule == schedule &&
      other.sortOrder == sortOrder &&
      other.archived == archived &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    code,
    color,
    icon,
    schedule,
    sortOrder,
    archived,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'TaskArea($id, $code)';
}

/// One to-do item (one occurrence of a recurring task).
final class Task {
  const Task({
    required this.id,
    required this.areaId,
    required this.title,
    this.note,
    this.bucket = TaskBucket.want,
    this.dueDate,
    this.dueTime,
    this.remindBefore,
    this.recurrence,
    this.seriesId,
    this.done = false,
    this.doneAt,
    this.sortOrder = 0,
    this.amount,
    this.walletId,
    this.categoryId,
    this.transactionId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String areaId;

  /// 1–200 chars.
  final String title;

  /// ≤ 2000 chars.
  final String? note;
  final TaskBucket bucket;

  /// Local date `YYYY-MM-DD` (see [dueDay]).
  final String? dueDate;

  /// Local `HH:mm`, only with [dueDate] (see [dueAt]).
  final String? dueTime;

  /// Minutes before [dueAt] to remind (0 = at due time); null = no reminder.
  final int? remindBefore;

  /// Null = one-off.
  final Recurrence? recurrence;

  /// Id of the first occurrence; the same for every occurrence of a series.
  final String? seriesId;
  final bool done;
  final DateTime? doneAt;

  /// Manual order within (area, bucket), ascending.
  final double sortOrder;

  /// Optional money link (> 0), with optional wallet/category.
  final double? amount;
  final String? walletId;
  final String? categoryId;

  /// Expense recorded when completing (money link accepted).
  final String? transactionId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isRecurring => recurrence != null;
  bool get hasMoneyLink => amount != null && amount! > 0;
  bool get hasReminder =>
      dueDate != null && dueTime != null && remindBefore != null;

  /// Local midnight of [dueDate].
  DateTime? get dueDay =>
      dueDate != null && isDateKey(dueDate!) ? parseDateKey(dueDate!) : null;

  /// Local due instant (needs [dueTime]); null when there's no time.
  DateTime? get dueAt {
    final d = dueDay;
    if (d == null || !isHm(dueTime)) return null;
    final m = hmToMinutes(dueTime!);
    return DateTime(d.year, d.month, d.day, m ~/ 60, m % 60);
  }

  /// When the reminder fires (may be in the past), or null.
  DateTime? get remindAt {
    final at = dueAt;
    if (at == null || remindBefore == null) return null;
    return at.subtract(Duration(minutes: remindBefore!));
  }

  Task copyWith({
    String? areaId,
    String? title,
    Object? note = _unset,
    TaskBucket? bucket,
    Object? dueDate = _unset,
    Object? dueTime = _unset,
    Object? remindBefore = _unset,
    Object? recurrence = _unset,
    Object? seriesId = _unset,
    bool? done,
    Object? doneAt = _unset,
    double? sortOrder,
    Object? amount = _unset,
    Object? walletId = _unset,
    Object? categoryId = _unset,
    Object? transactionId = _unset,
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Task(
    id: id ?? this.id,
    areaId: areaId ?? this.areaId,
    title: title ?? this.title,
    note: identical(note, _unset) ? this.note : note as String?,
    bucket: bucket ?? this.bucket,
    dueDate: identical(dueDate, _unset) ? this.dueDate : dueDate as String?,
    dueTime: identical(dueTime, _unset) ? this.dueTime : dueTime as String?,
    remindBefore: identical(remindBefore, _unset)
        ? this.remindBefore
        : remindBefore as int?,
    recurrence: identical(recurrence, _unset)
        ? this.recurrence
        : recurrence as Recurrence?,
    seriesId: identical(seriesId, _unset) ? this.seriesId : seriesId as String?,
    done: done ?? this.done,
    doneAt: identical(doneAt, _unset) ? this.doneAt : doneAt as DateTime?,
    sortOrder: sortOrder ?? this.sortOrder,
    amount: identical(amount, _unset) ? this.amount : amount as double?,
    walletId: identical(walletId, _unset) ? this.walletId : walletId as String?,
    categoryId: identical(categoryId, _unset)
        ? this.categoryId
        : categoryId as String?,
    transactionId: identical(transactionId, _unset)
        ? this.transactionId
        : transactionId as String?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Task &&
      other.id == id &&
      other.areaId == areaId &&
      other.title == title &&
      other.note == note &&
      other.bucket == bucket &&
      other.dueDate == dueDate &&
      other.dueTime == dueTime &&
      other.remindBefore == remindBefore &&
      other.recurrence == recurrence &&
      other.seriesId == seriesId &&
      other.done == done &&
      other.doneAt == doneAt &&
      other.sortOrder == sortOrder &&
      other.amount == amount &&
      other.walletId == walletId &&
      other.categoryId == categoryId &&
      other.transactionId == transactionId &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll([
    id,
    areaId,
    title,
    note,
    bucket,
    dueDate,
    dueTime,
    remindBefore,
    recurrence,
    seriesId,
    done,
    doneAt,
    sortOrder,
    amount,
    walletId,
    categoryId,
    transactionId,
    createdAt,
    updatedAt,
  ]);

  @override
  String toString() => 'Task($id, ${bucket.wire}, $title, due $dueDate)';
}
