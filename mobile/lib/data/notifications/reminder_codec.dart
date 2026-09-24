import 'dart:convert';

/// Largest id the plugins accept (Android ids are 32-bit signed ints).
const int kMaxNotificationId = 0x7fffffff;

/// Stable notification id for a [Reminder.key]: 32-bit FNV-1a folded to 31 bits.
///
/// Deterministic across runs/isolates/platforms (unlike `String.hashCode`), so a
/// reminder keeps its id between app launches and rescheduling replaces it in place.
/// Collisions (~1 in 2^31 per pair) are resolved by [assignReminderIds].
int reminderNotificationId(String key) {
  var h = 0x811c9dc5;
  for (final unit in utf8.encode(key)) {
    h ^= unit;
    h = (h * 0x01000193) & 0xffffffff;
  }
  // Fold the top bit in instead of dropping it, keeps the distribution uniform.
  return (h ^ (h >>> 31)) & kMaxNotificationId;
}

/// Assigns a unique id to every key: [reminderNotificationId], linearly probed on
/// collision. Keys are processed in sorted order so the result only depends on the
/// set of keys, not on their order.
Map<String, int> assignReminderIds(Iterable<String> keys) {
  final sorted = keys.toSet().toList()..sort();
  final used = <int>{};
  final out = <String, int>{};
  for (final k in sorted) {
    var id = reminderNotificationId(k);
    while (!used.add(id)) {
      id = (id + 1) & kMaxNotificationId;
    }
    out[k] = id;
  }
  return out;
}

/// What we store in the notification payload. The OS only gives back id/title/body/
/// payload for pending notifications, so the payload carries everything needed to
/// (a) recognise our task reminders, (b) diff against the desired set and
/// (c) route on tap.
class ReminderPayload {
  const ReminderPayload({
    required this.key,
    required this.route,
    required this.fireAt,
    required this.exact,
    this.timeZone = '',
  });

  static const _kind = 'task_reminder';

  final String key;
  final String route;

  /// Local wall-clock ISO string (compared verbatim).
  final String fireAt;

  /// Scheduled with an exact alarm (Android). Part of the payload so toggling
  /// "precise reminders" makes every reminder look changed and get rescheduled.
  final bool exact;

  /// Device zone at scheduling time; a zone change makes reminders look changed
  /// so they are re-armed at the new wall-clock instant.
  final String timeZone;

  String encode() => jsonEncode({
    'kind': _kind,
    'k': key,
    'r': route,
    'at': fireAt,
    'x': exact,
    'tz': timeZone,
  });

  /// Null when [raw] is not one of our task reminder payloads.
  static ReminderPayload? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map || m['kind'] != _kind) return null;
      final k = m['k'], r = m['r'], at = m['at'];
      if (k is! String || r is! String || at is! String) return null;
      return ReminderPayload(
        key: k,
        route: r,
        fireAt: at,
        exact: m['x'] == true,
        timeZone: m['tz'] is String ? m['tz'] as String : '',
      );
    } on FormatException {
      return null;
    }
  }
}
