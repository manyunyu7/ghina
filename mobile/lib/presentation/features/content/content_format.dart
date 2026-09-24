/// Pure display helpers for the Konten screens (no widgets, easy to test).
library;

import '../../../core/dates.dart';
import '../../../core/formatters.dart';
import '../../../domain/entities/entities.dart';

/// `Hari ini`, `Besok`, `Kemarin`, `Sen 29/9` or `Sen 29/9/27`.
String contentDayLabel(DateTime day, DateTime now) {
  final diff = daysBetween(day, now);
  if (diff == 0) return 'Hari ini';
  if (diff == 1) return 'Besok';
  if (diff == -1) return 'Kemarin';
  final wd = isoWeekdayShort[day.weekday - 1];
  final year = day.year == now.year ? '' : '/${day.year % 100}';
  return '$wd ${day.day}/${day.month}$year';
}

/// `Hari ini 19.00`, `Sen 29/9 08.30`.
String contentWhenLabel(DateTime at, DateTime now) =>
    '${contentDayLabel(at, now)} ${Fmt.time(at)}';

/// Reminder presets (minutes before; null = none).
const contentRemindOptions = <int?>[null, 0, 10, 30, 60, 180, 1440];

/// `Tanpa pengingat`, `Tepat waktu`, `10 menit`, `1 jam`, `1 hari`.
String remindLabel(int? minutes) {
  if (minutes == null) return 'Tanpa';
  if (minutes == 0) return 'Tepat waktu';
  if (minutes % 1440 == 0) return '${minutes ~/ 1440} hari';
  if (minutes % 60 == 0) return '${minutes ~/ 60} jam';
  return '$minutes menit';
}

/// `12,3 rb`, `1,2 jt`, `950`.
String compactCount(num n) {
  if (n.abs() >= 1000000) {
    return '${_oneDecimal(n / 1000000)} jt';
  }
  if (n.abs() >= 10000) return '${_oneDecimal(n / 1000)} rb';
  return Fmt.number(n);
}

String _oneDecimal(num v) {
  final s = v.toStringAsFixed(1).replaceAll('.', ',');
  return s.endsWith(',0') ? s.substring(0, s.length - 2) : s;
}

/// `4,5%`.
String percentLabel(double? rate) {
  if (rate == null) return '–';
  return '${_oneDecimal(rate * 100)}%';
}

/// Hashtags in a free-text field (`#a #b` → 2).
int hashtagCount(String text) => RegExp(r'#[^\s#]+').allMatches(text).length;

/// `23–29 Sep 2026` (a week range).
String weekRangeLabel(DateTime from, DateTime to) {
  final sameMonth = from.month == to.month && from.year == to.year;
  if (sameMonth) {
    return '${from.day}–${to.day} ${Fmt.monthShort(to.month)} ${to.year}';
  }
  final y = from.year == to.year ? '' : ' ${from.year}';
  return '${from.day} ${Fmt.monthShort(from.month)}$y – '
      '${to.day} ${Fmt.monthShort(to.month)} ${to.year}';
}

/// The next stage after [s], or null for `tayang`.
ContentStage? nextStage(ContentStage s) =>
    s == ContentStage.tayang ? null : ContentStage.values[s.index + 1];

/// XP the item would earn moving [from] → [to] (stages not reached yet on
/// this device; the engine counts each stage once).
int moveXp(ContentItem item, ContentStage to) {
  var xp = 0;
  for (final s in ContentStage.values) {
    if (s.index <= item.stage.index || s.index > to.index) continue;
    if (!item.stageReachedAt.containsKey(s)) xp += s.xp;
  }
  return xp;
}

/// What "Buka `platform`" opens, in order: app deep link, profile page, the
/// web publish page. Empty for an `other` account.
List<String> platformOpenUrls(SocialAccount a) => [
  ?a.appUrl,
  ?a.profileUrl,
  if (a.profileUrl == null) ?a.createUrl,
];

/// `+62 800 1234` style digits → int, blank → null.
int? parseCount(String s) {
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}
