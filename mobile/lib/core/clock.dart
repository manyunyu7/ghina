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
