import Link from "next/link";
import {
  Wallet as WalletIcon,
  TrendingUp,
  TrendingDown,
  Scale,
  Plus,
  ArrowRight,
  PieChart as PieChartIcon,
  Receipt,
  Sparkles,
  type LucideIcon,
} from "lucide-react";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { getNetWorth } from "@/lib/investments-server";
import {
  getMonthlyTotals,
  getSpendingByCategory,
  getRecentTransactions,
  getWallets,
  monthRange,
  currentMonth,
} from "@/lib/queries";
import { formatDate, MONTHS, cn } from "@/lib/utils";
import { walletIconFor, COLOR_PALETTE } from "@/lib/constants";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge, Progress, EmptyState } from "@/components/ui/misc";
import { CategoryIcon } from "@/components/icon";
import { PhotoBadge } from "@/components/photo-viewer";
import { parsePhotos } from "@/lib/photos";
import { SpendingDonut, IncomeExpenseBars, type MonthlyBar } from "./dashboard-charts";
import { ADJUSTMENT_LABEL } from "@/lib/adjustment";
import { getFireTasks } from "../tasks/data";
import { FireTodayCard } from "../tasks/fire-today-card";
import { getTodayContentPosts } from "../content/data";
import { ContentTodayCard } from "../content/today-card";
import { HabitsTodayCard } from "../habits/today-card";
import { LinkPendingIcon } from "@/components/link-pending";
import { Money } from "@/components/money/money";

export default async function DashboardPage() {
  const user = await requireUser();
  const cm = currentMonth();
  const range = monthRange(cm.year, cm.month);

  const [netWorth, totals, spending, recent, wallets, fire, contentToday] = await Promise.all([
    // Net worth: wallets + investments (docs/investments.md).
    getNetWorth(user.id),
    getMonthlyTotals(user.id, range),
    getSpendingByCategory(user.id, range),
    getRecentTransactions(user.id, 6),
    getWallets(user.id),
    getFireTasks(user.id),
    getTodayContentPosts(user.id),
  ]);

  // Onboarding: no wallets and no transactions.
  if (wallets.length === 0 && recent.length === 0) {
    return (
      <div className="space-y-6">
        <Greeting name={user.name} />
        <EmptyState
          icon={Sparkles}
          title="Welcome to Ghina"
          description="Let's get you set up. Create a wallet to hold your money, add a few categories, then start logging transactions."
          action={
            <div className="flex flex-wrap items-center justify-center gap-3">
              <Link href="/wallets">
                <Button>
                  <LinkPendingIcon>
                    <WalletIcon className="h-4 w-4" />
                  </LinkPendingIcon>{" "}
                  Create a wallet
                </Button>
              </Link>
              <Link href="/categories">
                <Button variant="outline">
                  <LinkPendingIcon /> Add categories
                </Button>
              </Link>
            </div>
          }
        />
      </div>
    );
  }

  // Income vs Expense over the last 6 months (including the current month).
  const monthsBack: { year: number; month: number }[] = [];
  for (let i = 5; i >= 0; i--) {
    const d = new Date(cm.year, cm.month - 1 - i, 1);
    monthsBack.push({ year: d.getFullYear(), month: d.getMonth() + 1 });
  }
  const monthlySeries = await Promise.all(
    monthsBack.map(async ({ year, month }) => {
      const t = await getMonthlyTotals(user.id, monthRange(year, month));
      return { month: MONTHS[month - 1].slice(0, 3), income: t.income, expense: t.expense };
    }),
  );
  const barData: MonthlyBar[] = monthlySeries;

  // Donut data (top 5 categories + "Other").
  const totalSpent = spending.reduce((s, r) => s + r.total, 0);
  const top = spending.slice(0, 5);
  const rest = spending.slice(5);
  const donutData = top.map((r, i) => ({
    name: r.category?.name ?? "Uncategorized",
    value: r.total,
    color: r.category?.color ?? COLOR_PALETTE[i % COLOR_PALETTE.length],
  }));
  if (rest.length > 0) {
    donutData.push({
      name: "Other",
      value: rest.reduce((s, r) => s + r.total, 0),
      color: "#94a3b8",
    });
  }

  // Budget snapshot for current month.
  const budgets = await prisma.budget.findMany({
    where: { userId: user.id, month: cm.month, year: cm.year },
    include: { category: true },
    orderBy: { amount: "desc" },
  });
  const spentByCategory = new Map(
    spending.map((r) => [r.category?.id, r.total] as const),
  );
  const budgetRows = budgets.slice(0, 4).map((b) => ({
    id: b.id,
    name: b.category.name,
    color: b.category.color,
    icon: b.category.icon,
    amount: b.amount,
    spent: spentByCategory.get(b.categoryId) ?? 0,
  }));

  return (
    <div className="space-y-6">
      <Greeting name={user.name} />

      {/* Stat cards */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <NetWorthCard netWorth={netWorth} currency={user.currency} />
        <StatCard
          label="Income this month"
          value={<Money amount={totals.income} currency={user.currency} />}
          icon={TrendingUp}
          tone="income"
        />
        <StatCard
          label="Expense this month"
          value={<Money amount={totals.expense} currency={user.currency} />}
          icon={TrendingDown}
          tone="expense"
        />
        <StatCard
          label="Net this month"
          value={<Money amount={totals.net} currency={user.currency} />}
          icon={Scale}
          tone={totals.net >= 0 ? "income" : "expense"}
        />
      </div>

      {/* Focus-area FIRE tasks (docs/tasks.md) */}
      {fire.areas.length > 0 && <FireTodayCard areas={fire.areas} tasks={fire.tasks} />}

      {/* Content posts scheduled today (docs/content.md) */}
      {contentToday.length > 0 && <ContentTodayCard posts={contentToday} />}

      {/* Habits due today; private ones masked (docs/habits.md) */}
      <HabitsTodayCard userId={user.id} />

      {/* Charts row */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card className="min-w-0">
          <CardHeader>
            <CardTitle>Spending by category</CardTitle>
            <Badge variant="default">{MONTHS[cm.month - 1]}</Badge>
          </CardHeader>
          <CardContent>
            {donutData.length === 0 ? (
              <div className="flex flex-col items-center justify-center gap-2 py-12 text-center">
                <PieChartIcon className="h-8 w-8 text-muted-soft" />
                <p className="text-sm text-muted">No expenses logged this month yet.</p>
              </div>
            ) : (
              <SpendingDonut data={donutData} currency={user.currency} total={totalSpent} />
            )}
          </CardContent>
        </Card>

        <Card className="min-w-0">
          <CardHeader>
            <CardTitle>Income vs Expense</CardTitle>
            <Badge variant="default">Last 6 months</Badge>
          </CardHeader>
          <CardContent>
            <IncomeExpenseBars data={barData} currency={user.currency} />
          </CardContent>
        </Card>
      </div>

      {/* Wallets + Recent + Budgets */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        {/* Wallets */}
        <Card className="lg:col-span-1">
          <CardHeader>
            <CardTitle>Wallets</CardTitle>
            <ViewAll href="/wallets" />
          </CardHeader>
          <CardContent>
            {wallets.length === 0 ? (
              <p className="py-6 text-center text-sm text-muted">No wallets yet.</p>
            ) : (
              <ul className="space-y-3">
                {wallets.slice(0, 5).map((w) => {
                  const Icon = walletIconFor(w.type);
                  return (
                    <li key={w.id} className="flex items-center gap-3">
                      <div
                        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-white"
                        style={{ background: w.color }}
                      >
                        <Icon className="h-4 w-4" />
                      </div>
                      <span className="min-w-0 flex-1 truncate text-sm font-medium text-foreground">
                        {w.name}
                      </span>
                      <span className="text-sm font-semibold text-foreground">
                        <Money amount={w.balance} currency={w.currency} />
                      </span>
                    </li>
                  );
                })}
              </ul>
            )}
          </CardContent>
        </Card>

        {/* Recent transactions */}
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Recent transactions</CardTitle>
            <ViewAll href="/transactions" />
          </CardHeader>
          <CardContent>
            {recent.length === 0 ? (
              <div className="flex flex-col items-center justify-center gap-2 py-10 text-center">
                <Receipt className="h-8 w-8 text-muted-soft" />
                <p className="text-sm text-muted">No transactions yet.</p>
              </div>
            ) : (
              <ul className="divide-y divide-border">
                {recent.map((t) => {
                  const isIncome = t.type === "income";
                  const isExpense = t.type === "expense";
                  const isAdjustment = t.type === "adjustment";
                  const sign = isIncome ? "+" : isExpense ? "-" : isAdjustment ? (t.amount > 0 ? "+" : "-") : "";
                  return (
                    <li key={t.id} className="flex items-center gap-3 py-3 first:pt-0 last:pb-0">
                      <div
                        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-white"
                        style={{ background: isAdjustment ? "#0284c7" : t.category?.color ?? "#94a3b8" }}
                      >
                        {isAdjustment ? (
                          <Scale className="h-4 w-4" />
                        ) : (
                          <CategoryIcon name={t.category?.icon} className="h-4 w-4" />
                        )}
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium text-foreground">
                          {isAdjustment ? ADJUSTMENT_LABEL : t.note || t.category?.name || "Transaction"}
                        </p>
                        <div className="mt-0.5 flex items-center gap-2">
                          <Badge variant="default">{t.wallet.name}</Badge>
                          <span className="text-xs text-muted">{formatDate(t.date)}</span>
                          <PhotoBadge photos={parsePhotos(t.photos)} />
                        </div>
                      </div>
                      <span
                        className={cn(
                          "shrink-0 text-sm font-semibold",
                          isIncome && "text-income",
                          isExpense && "text-expense",
                          isAdjustment && "text-sky-600",
                          !isIncome && !isExpense && !isAdjustment && "text-foreground",
                        )}
                      >
                        {sign}
                        <Money amount={Math.abs(t.amount)} currency={t.wallet.currency} />
                      </span>
                    </li>
                  );
                })}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Budget snapshot */}
      {budgetRows.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle>Budget snapshot</CardTitle>
            <ViewAll href="/budgets" />
          </CardHeader>
          <CardContent className="grid grid-cols-1 gap-5 sm:grid-cols-2">
            {budgetRows.map((b) => {
              const pct = b.amount > 0 ? (b.spent / b.amount) * 100 : 0;
              const over = b.spent > b.amount;
              return (
                <div key={b.id} className="space-y-2">
                  <div className="flex items-center gap-2">
                    <CategoryIcon name={b.icon} className="h-4 w-4 text-muted" />
                    <span className="flex-1 truncate text-sm font-medium text-foreground">
                      {b.name}
                    </span>
                    <span
                      className={cn("text-xs font-medium", over ? "text-expense" : "text-muted")}
                    >
                      <Money amount={b.spent} currency={user.currency} /> /{" "}
                      <Money amount={b.amount} currency={user.currency} />
                    </span>
                  </div>
                  <Progress value={pct} color={b.color} />
                </div>
              );
            })}
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function Greeting({ name }: { name: string | null }) {
  const first = name?.trim().split(/\s+/)[0] ?? "there";
  return (
    <div className="flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 className="text-2xl font-bold tracking-tight text-foreground">
          Welcome back, {first}
        </h1>
        <p className="mt-1 text-sm text-muted">
          {formatDate(new Date(), { weekday: "long", day: "numeric", month: "long", year: "numeric" })}
        </p>
      </div>
      <Link href="/transactions">
        <Button>
          <LinkPendingIcon>
            <Plus className="h-4 w-4" />
          </LinkPendingIcon>{" "}
          Add Transaction
        </Button>
      </Link>
    </div>
  );
}

function StatCard({
  label,
  value,
  icon: Icon,
  tone,
}: {
  label: string;
  value: React.ReactNode;
  icon: LucideIcon;
  tone: "primary" | "income" | "expense";
}) {
  const toneStyles = {
    primary: "bg-primary-soft text-primary",
    income: "bg-income-soft text-income",
    expense: "bg-expense-soft text-expense",
  };
  return (
    <Card>
      <CardContent className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm text-muted">{label}</p>
          <p className="mt-1 truncate text-xl font-bold tracking-tight text-foreground">{value}</p>
        </div>
        <div
          className={cn(
            "flex h-11 w-11 shrink-0 items-center justify-center rounded-full",
            toneStyles[tone],
          )}
        >
          <Icon className="h-5 w-5" />
        </div>
      </CardContent>
    </Card>
  );
}

function ViewAll({ href }: { href: string }) {
  return (
    <Link
      href={href}
      className="inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline"
    >
      View all{" "}
      <LinkPendingIcon className="h-3.5 w-3.5">
        <ArrowRight className="h-3.5 w-3.5" />
      </LinkPendingIcon>
    </Link>
  );
}

/** Net worth = cash (wallets) + investments (portfolio value), docs/investments.md. */
function NetWorthCard({ netWorth, currency }: { netWorth: { cash: number; investments: number; total: number }; currency: string }) {
  return (
    <Card>
      <CardContent className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm text-muted">Kekayaan bersih</p>
          <p className="mt-1 truncate text-xl font-bold tracking-tight text-foreground" data-testid="net-worth">
            <Money amount={netWorth.total} currency={currency} />
          </p>
          <p className="mt-0.5 truncate text-xs text-muted">
            Kas <Money amount={netWorth.cash} currency={currency} compact /> ·{" "}
            <Link href="/investments" className="font-medium text-primary hover:underline">
              Investasi <Money amount={netWorth.investments} currency={currency} compact />
            </Link>
          </p>
        </div>
        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-primary-soft text-primary">
          <WalletIcon className="h-5 w-5" />
        </div>
      </CardContent>
    </Card>
  );
}
