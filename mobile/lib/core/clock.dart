import 'dart:async';

/// Time source abstraction so logic can be tested with a fixed "now".
abstract interface class Clock {
  DateTime now();
}

/// The real wall clock (local time).
final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// A controllable clock for tests.
final class FixedClock implements Clock {
  FixedClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;

  void advance(Duration d) => current = current.add(d);
}

/// Emits [Clock.now] right away and then at every minute boundary (wall clock),
/// so time-based views (focus mode, overdue, reminders) refresh on their own.
Stream<DateTime> minuteTicks(Clock clock) => Stream<DateTime>.multi((c) {
  Timer? timer;
  void schedule() {
    final now = DateTime.now();
    final wait = Duration(
      milliseconds: 60000 - (now.second * 1000 + now.millisecond),
    );
    timer = Timer(wait, () {
      c.add(clock.now());
      schedule();
    });
  }

  c.add(clock.now());
  schedule();
  c.onCancel = () => timer?.cancel();
});
