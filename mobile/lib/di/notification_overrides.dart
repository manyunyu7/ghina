/// Wires the task reminders (docs/tasks.md → Notifications) into the
/// notification infrastructure's seam `remindersSourceProvider`.
///
/// Pass to the root scope together with the game overrides:
/// `ProviderScope(overrides: [...gameOverrides, ...reminderOverrides], child: …)`.
library;

import 'package:flutter_riverpod/misc.dart' show Override;

import '../presentation/state/notifications/notification_providers.dart'
    show remindersSourceProvider;
import '../presentation/state/session_controller.dart' show currencyProvider;
import 'usecase_providers.dart' show watchRemindersUseCaseProvider;

/// `remindersSourceProvider` ← the tasks' reminders (≤ 60, soonest first,
/// recomputed on task/area changes, every sync pull and every minute; emits only
/// when the set changes).
List<Override> get reminderOverrides => [
  remindersSourceProvider.overrideWith(
    (ref) => ref.watch(watchRemindersUseCaseProvider)(
      currency: ref.watch(currencyProvider),
    ),
  ),
];
