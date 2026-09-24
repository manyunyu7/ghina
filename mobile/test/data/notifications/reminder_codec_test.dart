import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/notifications/notifications.dart';

void main() {
  group('reminderNotificationId', () {
    test('is stable (FNV-1a, not String.hashCode)', () {
      expect(reminderNotificationId('abc'), 440920331);
      expect(reminderNotificationId(''), 18652612);
      expect(reminderNotificationId('task-1'), 137425991);
    });

    test('stays within 31 bits and spreads', () {
      final ids = <int>{};
      for (var i = 0; i < 5000; i++) {
        final id = reminderNotificationId('0190c3b2-7e1d-7a00-9b1c-$i');
        expect(id, inInclusiveRange(0, kMaxNotificationId));
        ids.add(id);
      }
      expect(ids.length, 5000);
    });
  });

  group('assignReminderIds', () {
    // Known collision of the 31-bit hash.
    const a = 'task-130386', b = 'task-626259';

    test('probes on collision, independent of input order', () {
      expect(reminderNotificationId(a), reminderNotificationId(b));
      final ids1 = assignReminderIds([a, b]);
      final ids2 = assignReminderIds([b, a]);
      expect(ids1, ids2);
      expect(ids1[a], reminderNotificationId(a));
      expect(ids1[b], reminderNotificationId(a) + 1);
    });

    test('dedupes keys', () {
      expect(assignReminderIds(['x', 'x', 'y']).length, 2);
    });
  });

  group('ReminderPayload', () {
    test('round-trips', () {
      const p = ReminderPayload(
        key: 't1',
        route: '/tasks/t1',
        fireAt: '2026-09-25T09:50:00.000',
        exact: true,
      );
      final d = ReminderPayload.tryDecode(p.encode())!;
      expect(
        [d.key, d.route, d.fireAt, d.exact],
        [p.key, p.route, p.fireAt, p.exact],
      );
    });

    test('ignores foreign payloads', () {
      for (final raw in [null, '', 'item x', '{"kind":"other"}', '[1]']) {
        expect(ReminderPayload.tryDecode(raw), isNull, reason: '$raw');
      }
    });
  });
}
