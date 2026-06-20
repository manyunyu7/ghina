import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import {
  getWallets,
  getCategories,
  getCategoryMonthlyAverages,
  monthRange,
  currentMonth,
} from "@/lib/queries";
import { PageHeader } from "@/components/ui/misc";
import { MONTHS } from "@/lib/utils";
import { occurrencesInMonth } from "./logic";
import { AddPlannedButton } from "./add-planned-button";
import { ForecastView } from "./forecast-view";
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

  // Tier 3 — user-entered planned items.
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

  // Tier 1 — subscription occurrences that fall in this month.
  const subItems = subscriptions
    .flatMap((s) =>
      occurrencesInMonth(s.nextBilling, s.cycle, start, end).map((date) => ({
        id: `${s.id}-${date.getTime()}`,
        name: s.name,
        amount: s.amount,
        currency: s.currency,
        color: s.color,
        icon: s.icon,
        date: date.toISOString(),
      })),
    )
    .sort((a, b) => a.date.localeCompare(b.date));

  // Tier 2 — estimated from history.
  const avgItems = averages.map((a) => ({
    id: a.category.id,
    name: a.category.name,
    color: a.category.color,
    icon: a.category.icon,
    avg: a.avg,
  }));

  const monthLabel = `${MONTHS[month - 1]} ${year}`;
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

      <ForecastView
        plannedItems={plannedItems}
        subItems={subItems}
        averages={avgItems}
        wallets={wallets}
        categories={categories}
        currency={currency}
        monthLabel={monthLabel}
        defaultDate={defaultDate}
        historyMonths={HISTORY_MONTHS}
      />
    </div>
  );
}
