import { TrendingUp, TrendingDown, PiggyBank, Percent, BarChart3, PieChart } from "lucide-react";
import { requireUser } from "@/lib/auth-helpers";
import {
  getMonthlyTotals,
  getSpendingByCategory,
  monthRange,
  currentMonth,
  type DateRange,
} from "@/lib/queries";
import { formatCurrency, cn, MONTHS } from "@/lib/utils";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EmptyState, PageHeader } from "@/components/ui/misc";
import { CategoryIcon } from "@/components/icon";
import { PeriodSelector } from "./period-selector";
import { IncomeExpenseChart, CategoryDonut, CashflowChart } from "./charts";

const UNCATEGORIZED_COLOR = "#94a3b8";

type SearchParams = {
  range?: string;
  year?: string;
};

/** A single calendar month within the selected reporting window. */
type MonthCell = { year: number; month: number; label: string };

/**
 * Build the list of months (oldest → newest) covered by the selected period,
 * plus the overall start/end range for whole-period queries.
 */
function resolvePeriod(
  range: string,
  yearParam: number,
  now: { year: number; month: number },
): { months: MonthCell[]; full: DateRange; label: string } {
  const cell = (year: number, month: number): MonthCell => ({
    year,
    month,
    label: MONTHS[month - 1].slice(0, 3),
  });

  if (range === "month") {
    const months = [cell(now.year, now.month)];
    return { months, full: monthRange(now.year, now.month), label: "This month" };
  }

  if (range === "year") {
    const months: MonthCell[] = [];
    const max = yearParam === now.year ? now.month : 12;
    for (let m = 1; m <= max; m++) months.push(cell(yearParam, m));
    return {
      months,
      full: {
        start: new Date(yearParam, 0, 1, 0, 0, 0, 0),
        end: new Date(yearParam, 11, 31, 23, 59, 59, 999),
      },
      label: `Year ${yearParam}`,
    };
  }

  // Rolling window: 6m (default) or 12m, inclusive of the current month.
  const count = range === "12m" ? 12 : 6;
  const months: MonthCell[] = [];
  for (let i = count - 1; i >= 0; i--) {
    const d = new Date(now.year, now.month - 1 - i, 1);
    months.push(cell(d.getFullYear(), d.getMonth() + 1));
  }
  const first = months[0];
  const last = months[months.length - 1];
  return {
    months,
    full: {
      start: monthRange(first.year, first.month).start,
      end: monthRange(last.year, last.month).end,
    },
    label: range === "12m" ? "Last 12 months" : "Last 6 months",
  };
}

export default async function ReportsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const user = await requireUser();
  const sp = await searchParams;
  const now = currentMonth();

  const range = sp.range ?? "6m";
  const yearParam = (() => {
    const n = Number.parseInt(sp.year ?? "", 10);
    return Number.isFinite(n) ? n : now.year;
  })();

  const { months, full, label } = resolvePeriod(range, yearParam, now);

  // Per-month income/expense (one query per month, run in parallel) +
  // whole-period category spending.
  const [monthlyTotals, spending] = await Promise.all([
    Promise.all(months.map((m) => getMonthlyTotals(user.id, monthRange(m.year, m.month)))),
    getSpendingByCategory(user.id, full),
  ]);

  // Serializable chart data (plain numbers/strings only).
  const incomeExpenseData = months.map((m, i) => ({
    month: m.label,
    income: monthlyTotals[i].income,
    expense: monthlyTotals[i].expense,
  }));
  const cashflowData = months.map((m, i) => ({
    month: m.label,
    net: monthlyTotals[i].net,
  }));

  const totalIncome = monthlyTotals.reduce((s, t) => s + t.income, 0);
  const totalExpense = monthlyTotals.reduce((s, t) => s + t.expense, 0);
  const netSavings = totalIncome - totalExpense;
  const savingsRate = totalIncome > 0 ? (netSavings / totalIncome) * 100 : 0;

  // Category donut + ranked list data.
  const donutData = spending
    .filter((s) => s.total > 0)
    .map((s) => ({
      name: s.category?.name ?? "Uncategorized",
      value: s.total,
      color: s.category?.color ?? UNCATEGORIZED_COLOR,
    }));
  const totalCategorySpend = donutData.reduce((sum, d) => sum + d.value, 0);
  const topCategories = spending
    .filter((s) => s.total > 0)
    .slice(0, 6)
    .map((s) => ({
      name: s.category?.name ?? "Uncategorized",
      icon: s.category?.icon ?? null,
      color: s.category?.color ?? UNCATEGORIZED_COLOR,
      total: s.total,
      pct: totalCategorySpend > 0 ? (s.total / totalCategorySpend) * 100 : 0,
    }));

  const hasData = totalIncome > 0 || totalExpense > 0;

  const stats = [
    {
      label: "Total income",
      value: totalIncome,
      icon: TrendingUp,
      tint: "text-income bg-income-soft",
      valueClass: "text-income",
    },
    {
      label: "Total expense",
      value: totalExpense,
      icon: TrendingDown,
      tint: "text-expense bg-expense-soft",
      valueClass: "text-expense",
    },
    {
      label: "Net savings",
      value: netSavings,
      icon: PiggyBank,
      tint: "text-primary bg-primary-soft",
      valueClass: netSavings >= 0 ? "text-income" : "text-expense",
    },
  ];

  return (
    <div>
      <PageHeader
        title="Reports"
        description="Visualize your income, spending and savings over time."
        action={<PeriodSelector currentYear={now.year} />}
      />

      {!hasData ? (
        <EmptyState
          icon={BarChart3}
          title="No data for this period"
          description={`There are no income or expense transactions in the selected range (${label}). Try a wider period or add some transactions.`}
        />
      ) : (
        <div className="space-y-6">
          {/* Summary stats */}
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {stats.map((s) => (
              <Card key={s.label}>
                <CardContent className="flex items-center justify-between p-4">
                  <div className="min-w-0">
                    <p className="text-sm text-muted">{s.label}</p>
                    <p className={cn("mt-1 truncate text-xl font-bold", s.valueClass)}>
                      {formatCurrency(s.value, user.currency)}
                    </p>
                  </div>
                  <div
                    className={cn(
                      "flex h-10 w-10 shrink-0 items-center justify-center rounded-full",
                      s.tint,
                    )}
                  >
                    <s.icon className="h-5 w-5" />
                  </div>
                </CardContent>
              </Card>
            ))}
            <Card>
              <CardContent className="flex items-center justify-between p-4">
                <div className="min-w-0">
                  <p className="text-sm text-muted">Savings rate</p>
                  <p
                    className={cn(
                      "mt-1 truncate text-xl font-bold",
                      savingsRate >= 0 ? "text-income" : "text-expense",
                    )}
                  >
                    {savingsRate.toFixed(1)}%
                  </p>
                </div>
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-accent text-muted">
                  <Percent className="h-5 w-5" />
                </div>
              </CardContent>
            </Card>
          </div>

          {/* Income vs expense + category donut */}
          <div className="grid grid-cols-1 gap-6 lg:grid-cols-5">
            <Card className="lg:col-span-3">
              <CardHeader>
                <CardTitle>Income vs expense</CardTitle>
                <BarChart3 className="h-5 w-5 text-muted-soft" />
              </CardHeader>
              <CardContent>
                <IncomeExpenseChart data={incomeExpenseData} currency={user.currency} />
              </CardContent>
            </Card>

            <Card className="lg:col-span-2">
              <CardHeader>
                <CardTitle>Spending by category</CardTitle>
                <PieChart className="h-5 w-5 text-muted-soft" />
              </CardHeader>
              <CardContent>
                {donutData.length === 0 ? (
                  <p className="py-12 text-center text-sm text-muted">
                    No expenses recorded in this period.
                  </p>
                ) : (
                  <CategoryDonut data={donutData} currency={user.currency} />
                )}
              </CardContent>
            </Card>
          </div>

          {/* Top categories + cashflow trend */}
          <div className="grid grid-cols-1 gap-6 lg:grid-cols-5">
            <Card className="lg:col-span-2">
              <CardHeader>
                <CardTitle>Top spending categories</CardTitle>
              </CardHeader>
              <CardContent>
                {topCategories.length === 0 ? (
                  <p className="py-8 text-center text-sm text-muted">No spending to rank yet.</p>
                ) : (
                  <ul className="space-y-4">
                    {topCategories.map((c) => (
                      <li key={c.name}>
                        <div className="mb-1.5 flex items-center gap-2.5">
                          <div
                            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full"
                            style={{ background: `${c.color}1a`, color: c.color }}
                          >
                            <CategoryIcon name={c.icon} className="h-4 w-4" />
                          </div>
                          <span className="min-w-0 flex-1 truncate text-sm font-medium text-foreground">
                            {c.name}
                          </span>
                          <span className="shrink-0 text-sm font-semibold tabular-nums text-foreground">
                            {formatCurrency(c.total, user.currency)}
                          </span>
                          <span className="w-10 shrink-0 text-right text-xs tabular-nums text-muted">
                            {c.pct.toFixed(0)}%
                          </span>
                        </div>
                        <div className="h-2 w-full overflow-hidden rounded-full bg-accent">
                          <div
                            className="h-full rounded-full transition-all"
                            style={{ width: `${Math.max(2, c.pct)}%`, background: c.color }}
                          />
                        </div>
                      </li>
                    ))}
                  </ul>
                )}
              </CardContent>
            </Card>

            <Card className="lg:col-span-3">
              <CardHeader>
                <CardTitle>Net cashflow trend</CardTitle>
                <TrendingUp className="h-5 w-5 text-muted-soft" />
              </CardHeader>
              <CardContent>
                <CashflowChart data={cashflowData} currency={user.currency} />
              </CardContent>
            </Card>
          </div>
        </div>
      )}
    </div>
  );
}
