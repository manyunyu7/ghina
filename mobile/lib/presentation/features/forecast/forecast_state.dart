import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dates.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart' show defaultForecastMonth;

/// Month shown on the forecast page (web default: next month). The "new
/// planned item" form starts its date in this month.
final forecastMonthProvider = NotifierProvider<ForecastMonth, YearMonth>(
  ForecastMonth.new,
);

class ForecastMonth extends Notifier<YearMonth> {
  @override
  YearMonth build() => defaultForecastMonth(ref.read(clockProvider).now());

  void set(YearMonth m) => state = m;
}

/// Source toggles (web chips). History is off by default.
final forecastSourcesProvider =
    NotifierProvider<ForecastSourcesState, ForecastSources>(
      ForecastSourcesState.new,
    );

class ForecastSourcesState extends Notifier<ForecastSources> {
  @override
  ForecastSources build() => const ForecastSources();

  void set(ForecastSources s) => state = s;
}

/// One point of the projected balance line.
typedef BalancePoint = ({int day, double balance, bool event});

/// Projects the wallet balance through [f]'s month: starts from
/// [startBalance] and applies planned items and subscription billings on their
/// day, and history averages spread evenly over the month. Day 0 is the start.
List<BalancePoint> projectBalance(
  Forecast f,
  ForecastSources sources,
  double startBalance,
) {
  final days = daysInMonth(f.month.year, f.month.month);
  final delta = List<double>.filled(days + 1, 0);
  final event = List<bool>.filled(days + 1, false);
  if (sources.manual) {
    for (final p in f.planned) {
      final d = p.date.day.clamp(1, days);
      delta[d] += p.type == TxType.income ? p.amount : -p.amount;
      event[d] = true;
    }
  }
  if (sources.subscriptions) {
    for (final s in f.subscriptionItems) {
      final d = s.date.day.clamp(1, days);
      delta[d] -= s.amount;
      event[d] = true;
    }
  }
  final perDay = sources.history ? f.estimatedExpense / days : 0.0;
  final out = <BalancePoint>[(day: 0, balance: startBalance, event: false)];
  var bal = startBalance;
  for (var d = 1; d <= days; d++) {
    bal += delta[d] - perDay;
    out.add((day: d, balance: bal, event: event[d]));
  }
  return out;
}
