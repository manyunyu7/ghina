import { TrendingUp, ArrowDownCircle, ArrowUpCircle, Repeat, History, CalendarClock } from "lucide-react";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import {
  getWallets,
  getCategories,
  getCategoryMonthlyAverages,
  monthRange,
  currentMonth,
} from "@/lib/queries";
import { Card } from "@/components/ui/card";
import { EmptyState, PageHeader } from "@/components/ui/misc";
import { CategoryIcon } from "@/components/icon";
import { formatCurrency, formatDate, cn, MONTHS } from "@/lib/utils";
import { occurrencesInMonth } from "./logic";
import { PlannedList } from "./planned-list";
import { AddPlannedButton } from "./add-planned-button";
// Re-use the budgets month picker — same URL-param contract (?month=&year=).
import { MonthSelector as MonthNav } from "../budgets/month-selector";

type SearchParams = { month?: string; year?: string };

function parseIntOr(value: string | undefined, fallback: number): number {
  if (!value) return fallback;
  const n = Number.parseInt(value, 10);
  return Number.isFinite(n) ? n : fallback;
}

/** The month after the current one — the natural default for a forecast. */
function nextMonth(): { year: number; month: number } {
  const { year, month } = currentMonth();
  return month === 12 ? { year: year + 1, month: 1 } : { year, month: month + 1 };
}

const HISTORY_MONTHS = 3;

export default async function ForecastPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const user = await requireUser();
  const currency = user.currency || "IDR";
  const sp = await searchParams;
  const def = nextMonth();
  const cm = currentMonth();

  let month = parseIntOr(sp.month, def.month);
  let year = parseIntOr(sp.year, def.year);
  if (month < 1 || month > 12) month = def.month;
  if (year < 1970 || year > 9999) year = def.year;

  const { start, end } = monthRange(year, month);

  const [planned, subscriptions, averages, wallets, categories] = await Promise.all([
    prisma.plannedTransaction.findMany({
      where: { userId: user.id, date: { gte: start, lte: end } },
      orderBy: [{ done: "asc" }, { date: "asc" }],
    }),
    prisma.subscription.findMany({ where: { userId: user.id, active: true } }),
    getCategoryMonthlyAverages(user.id, HISTORY_MONTHS),
    getWallets(user.id),
    getCategories(user.id),
  ]);

  // ---- Tier 3: user-entered planned items ----
  const plannedItems = planned.map((p) => ({
    id: p.id,
    type: p.type,
    amount: p.amount,
    note: p.note,
    date: p.date.toISOString(),
    categoryId: p.categoryId,
    walletId: p.walletId,
    done: p.done,
  }));
  const plannedExpense = planned.filter((p) => p.type === "expense").reduce((s, p) => s + p.amount, 0);
  const plannedIncome = planned.filter((p) => p.type === "income").reduce((s, p) => s + p.amount, 0);

  // ---- Tier 1: subscriptions billing this month ----
  const subItems = subscriptions
    .flatMap((s) =>
      occurrencesInMonth(s.nextBilling, s.cycle, start, end).map((date) => ({
        id: `${s.id}-${date.getTime()}`,
        name: s.name,
        amount: s.amount,
        currency: s.currency,
        color: s.color,
        icon: s.icon,
        date,
      })),
    )
    .sort((a, b) => a.date.getTime() - b.date.getTime());
  const subsExpense = subItems.reduce((sum, s) => sum + s.amount, 0);

  // ---- Tier 2: estimated from history ----
  const estExpense = averages.reduce((sum, a) => sum + a.avg, 0);

  const projectedExpense = plannedExpense + subsExpense + estExpense;
  const projectedIncome = plannedIncome;
  const net = projectedIncome - projectedExpense;

  const monthLabel = `${MONTHS[month - 1]} ${year}`;
  const isEmpty = plannedItems.length === 0 && subItems.length === 0 && averages.length === 0;
  const defaultDate = `${year}-${String(month).padStart(2, "0")}-01`;

  return (
    <div>
      <PageHeader
        title="Forecast"
        description={`A look ahead at what ${monthLabel} might cost you — and what you can expect to come in.`}
        action={<AddPlannedButton wallets={wallets} categories={categories} defaultDate={defaultDate} />}
      />

      <div className="mb-6">
        <MonthNav month={month} year={year} currentYear={cm.year} />
      </div>

      {/* Summary */}
      <div className="mb-6 grid gap-3 sm:grid-cols-3">
        <StatTile
          icon={<ArrowDownCircle className="h-5 w-5" />}
          label="Projected out"
          value={formatCurrency(projectedExpense, currency)}
          tint="bg-expense-soft text-expense"
        />
        <StatTile
          icon={<ArrowUpCircle className="h-5 w-5" />}
          label="Projected in"
          value={formatCurrency(projectedIncome, currency)}
          tint="bg-income-soft text-income"
        />
        <StatTile
          icon={<TrendingUp className="h-5 w-5" />}
          label="Projected net"
          value={`${net < 0 ? "-" : "+"}${formatCurrency(Math.abs(net), currency)}`}
          tint={net < 0 ? "bg-expense-soft text-expense" : "bg-primary-soft text-primary"}
        />
      </div>

      {isEmpty ? (
        <EmptyState
          icon={CalendarClock}
          title={`Nothing forecast for ${monthLabel} yet`}
          description="Add an expected bill, your salary, or a one-off you know is coming. Active subscriptions and your spending history will show up here automatically."
          action={<AddPlannedButton wallets={wallets} categories={categories} defaultDate={defaultDate} variant="primary" />}
        />
      ) : (
        <div className="space-y-8">
          {/* Tier 3 — your planned items */}
          <Section
            title="Your planned items"
            hint="Things you've noted down. These don't affect your wallet balances."
          >
            {plannedItems.length > 0 ? (
              <PlannedList items={plannedItems} wallets={wallets} categories={categories} currency={currency} />
            ) : (
              <Card className="p-4 text-sm text-muted">
                No planned items for {monthLabel} yet. Use “Add planned item” to jot one down.
              </Card>
            )}
          </Section>

          {/* Tier 1 — subscriptions */}
          {subItems.length > 0 && (
            <Section
              title="From your subscriptions"
              hint="Recurring payments that fall in this month, based on their billing cycle."
              icon={<Repeat className="h-4 w-4" />}
            >
              <Card className="divide-y divide-border-soft p-0">
                {subItems.map((s) => (
                  <ReadonlyRow
                    key={s.id}
                    color={s.color}
                    icon={s.icon}
                    title={s.name}
                    date={formatDate(s.date)}
                    amount={`-${formatCurrency(s.amount, s.currency || currency)}`}
                  />
                ))}
              </Card>
            </Section>
          )}

          {/* Tier 2 — estimated from history */}
          {averages.length > 0 && (
            <Section
              title="Estimated from history"
              hint={`Typical spend per category, averaged over the last ${HISTORY_MONTHS} months. A rough guide, not a commitment.`}
              icon={<History className="h-4 w-4" />}
            >
              <Card className="divide-y divide-border-soft p-0">
                {averages.map((a) => (
                  <ReadonlyRow
                    key={a.category.id}
                    color={a.category.color}
                    icon={a.category.icon}
                    title={a.category.name}
                    date={`avg / month`}
                    amount={`~${formatCurrency(a.avg, currency)}`}
                  />
                ))}
              </Card>
            </Section>
          )}
        </div>
      )}
    </div>
  );
}

function Section({
  title,
  hint,
  icon,
  children,
}: {
  title: string;
  hint?: string;
  icon?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section>
      <div className="mb-3">
        <h2 className="flex items-center gap-2 text-sm font-semibold text-foreground">
          {icon}
          {title}
        </h2>
        {hint && <p className="mt-0.5 text-xs text-muted">{hint}</p>}
      </div>
      {children}
    </section>
  );
}

function ReadonlyRow({
  color,
  icon,
  title,
  date,
  amount,
}: {
  color: string;
  icon: string;
  title: string;
  date: string;
  amount: string;
}) {
  return (
    <div className="flex items-center gap-3 p-3">
      <div
        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-white"
        style={{ background: color }}
      >
        <CategoryIcon name={icon} className="h-4 w-4" />
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium text-foreground">{title}</p>
        <p className="text-xs text-muted">{date}</p>
      </div>
      <p className="shrink-0 text-sm font-medium tabular-nums text-expense">{amount}</p>
    </div>
  );
}

function StatTile({
  icon,
  label,
  value,
  tint,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  tint: string;
}) {
  return (
    <Card className="p-4">
      <div className={cn("mb-3 flex h-9 w-9 items-center justify-center rounded-lg", tint)}>{icon}</div>
      <p className="text-sm text-muted">{label}</p>
      <p className="truncate text-xl font-bold text-foreground">{value}</p>
    </Card>
  );
}
