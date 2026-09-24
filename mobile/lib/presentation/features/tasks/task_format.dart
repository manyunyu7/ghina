/// Pure display helpers for the Tugas screens (no widgets, easy to test).
library;

import '../../../core/dates.dart';
import '../../../domain/entities/entities.dart';
import '../../shared/tasks/complete_task_flow.dart' show taskShortDate;

/// `09:05` → `09.05` (Indonesian time style).
String hmDisplay(String hm) => hm.replaceAll(':', '.');

/// Relative due label: `Hari ini 14.00`, `Besok`, `Kemarin`, `Sen 29/9`,
/// `Sen 29/9/27` (another year). Null when there's no due date.
String? dueLabel(Task t, DateTime now) {
  final day = t.dueDay;
  if (day == null) return null;
  final time = isHm(t.dueTime) ? ' ${hmDisplay(t.dueTime!)}' : '';
  return '${dayLabel(day, now)}$time';
}

/// `Hari ini`, `Besok`, `Kemarin`, `Sen 29/9` or `Sen 29/9/27`.
String dayLabel(DateTime day, DateTime now) {
  final diff = daysBetween(day, now);
  if (diff == 0) return 'Hari ini';
  if (diff == 1) return 'Besok';
  if (diff == -1) return 'Kemarin';
  final wd = isoWeekdayShort[day.weekday - 1];
  final year = day.year == now.year ? '' : '/${day.year % 100}';
  return '$wd ${day.day}/${day.month}$year';
}

/// `Kam, 2 Okt` — the "Berikutnya: …" toast after a recurring task.
String shortDate(DateTime d) => taskShortDate(d);

/// `Sen, Rab & Jum`.
String weekdayList(List<int> days) {
  final names = [
    for (final d in [...days]..sort()) isoWeekdayShort[d - 1],
  ];
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  return '${names.sublist(0, names.length - 1).join(', ')} & ${names.last}';
}

/// Human summary: `Tiap hari`, `Tiap 3 hari`, `Tiap 2 minggu, Sen & Kam`,
/// `Tiap bulan, tgl 15`. [dueDay] fills the defaults the use case would pick.
String recurrenceSummary(Recurrence r, {DateTime? dueDay}) {
  final every = r.interval == 1
      ? 'Tiap ${r.freq.unit}'
      : 'Tiap ${r.interval} ${r.freq.unit}';
  switch (r.freq) {
    case RecurrenceFreq.daily:
      return every;
    case RecurrenceFreq.weekly:
      final days = (r.weekdays == null || r.weekdays!.isEmpty)
          ? [if (dueDay != null) dueDay.weekday]
          : r.weekdays!;
      if (days.length == 7) return '$every, setiap hari';
      return days.isEmpty ? every : '$every, ${weekdayList(days)}';
    case RecurrenceFreq.monthly:
      final md = r.monthDay ?? dueDay?.day;
      return md == null ? every : '$every, tgl $md';
  }
}

/// `Tepat waktu`, `10 menit sebelum`, `1 jam sebelum`, `2 hari sebelum`.
String remindLabel(int minutes) {
  if (minutes == 0) return 'Tepat waktu';
  if (minutes % 1440 == 0) return '${minutes ~/ 1440} hari sebelum';
  if (minutes % 60 == 0) return '${minutes ~/ 60} jam sebelum';
  return '$minutes menit sebelum';
}

/// Short chip label: `Tepat`, `10 mnt`, `1 jam`.
String remindChip(int minutes) {
  if (minutes == 0) return 'Tepat';
  if (minutes % 1440 == 0) return '${minutes ~/ 1440} hari';
  if (minutes % 60 == 0) return '${minutes ~/ 60} jam';
  return '$minutes mnt';
}

/// Area code from free text: uppercase A–Z/0–9 only, max 8.
String sanitizeAreaCode(String s) {
  final up = s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return up.length > 8 ? up.substring(0, 8) : up;
}

/// Suggests a code from an area name (`Kuliah S2` → `KULIAHS2`).
String suggestAreaCode(String name) => sanitizeAreaCode(name);

/// `Sen–Jum · 09.00–17.00`, `Sen, Rab & Jum · 08.00–12.00`, `Kapan saja`.
String scheduleSummary(AreaSchedule? s) {
  if (s == null) return 'Kapan saja';
  final d = [...s.days]..sort();
  String days;
  if (d.length == 7) {
    days = 'Tiap hari';
  } else if (d.length >= 3 && d.last - d.first == d.length - 1) {
    days = '${isoWeekdayShort[d.first - 1]}–${isoWeekdayShort[d.last - 1]}';
  } else {
    days = weekdayList(d);
  }
  return '$days · ${hmDisplay(s.start)}–${hmDisplay(s.end)}';
}

/// The notification title preview `[KERJA-FIRE] Contoh tugas`.
String notificationPreview(String code, TaskBucket bucket, String title) =>
    '[${code.isEmpty ? 'KODE' : code}-${bucket.label}] $title';
