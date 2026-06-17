import { PiggyBank, Wallet as WalletIcon } from "lucide-react";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { getCategories, monthRange, currentMonth } from "@/lib/queries";
import { formatCurrency, cn, MONTHS } from "@/lib/utils";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState, PageHeader, Progress } from "@/components/ui/misc";
import { AddBudgetButton } from "./add-budget-button";
import { MonthSelector } from "./month-selector";
import { BudgetCard, type BudgetTx } from "./budget-card";
import type { BudgetEditData } from "./budget-form";

type SearchParams = { month?: string; year?: string };

function parseIntOr(value: string | undefined, fallback: number): number {
  if (!value) return fallback;
  const n = Number.parseInt(value, 10);
  return Number.isFinite(n) ? n : fallback;
}

export default async function BudgetsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const user = await requireUser();
  const sp = await searchParams;
  const cm = currentMonth();

  let month = parseIntOr(sp.month, cm.month);
  let year = parseIntOr(sp.year, cm.year);
  if (month < 1 || month > 12) month = cm.month;
  if (year < 1970 || year > 9999) year = cm.year;

  const { start, end } = monthRange(year, month);

  const [expenseCategories, budgets, monthTx] = await Promise.all([
    getCategories(user.id, "expense"),
    prisma.budget.findMany({
      where: { userId: user.id, month, year },
      include: { category: true },
    }),
    prisma.transaction.findMany({
      where: {
        userId: user.id,
        type: "expense",
        date: { gte: start, lte: end },
        categoryId: { not: null },
      },
      select: { id: true, note: true, amount: true, date: true, categoryId: true },
      orderBy: [{ date: "desc" }, { createdAt: "desc" }],
    }),
  ]);

  // categoryId -> total spent + the individual transactions making it up
  const spentByCategory = new Map<string, number>();
  const txByCategory = new Map<string, BudgetTx[]>();
  for (const t of monthTx) {
    const cid = t.categoryId as string;
    spentByCategory.set(cid, (spentByCategory.get(cid) ?? 0) + t.amount);
    const list = txByCategory.get(cid) ?? [];
    list.push({ id: t.id, note: t.note, amount: t.amount, date: t.date.toISOString() });
    txByCategory.set(cid, list);
  }

  // Build per-budget view models, sorted by usage (most spent first).
  const rows = budgets
    .map((b) => {
      const spent = spentByCategory.get(b.categoryId) ?? 0;
      const remaining = b.amount - spent;
      const pct = b.amount > 0 ? (spent / b.amount) * 100 : 0;
      return { budget: b, spent, remaining, pct, over: spent > b.amount };
    })
    .sort((a, b) => b.pct - a.pct);

  const totalBudgeted = budgets.reduce((sum, b) => sum + b.amount, 0);
  const totalSpent = rows.reduce((sum, r) => sum + r.spent, 0);
  const totalRemaining = totalBudgeted - totalSpent;
  const totalPct = totalBudgeted > 0 ? (totalSpent / totalBudgeted) * 100 : 0;
  const totalOver = totalSpent > totalBudgeted;

  // Categories that don't yet have a budget this month (for the create form).
  const budgetedIds = new Set(budgets.map((b) => b.categoryId));
  const availableCategories = expenseCategories.filter((c) => !budgetedIds.has(c.id));

  const monthLabel = `${MONTHS[month - 1]} ${year}`;
  const hasExpenseCategories = expenseCategories.length > 0;

  return (
    <div>
      <PageHeader
        title="Budgets"
        description={`Plan and track your spending limits for ${monthLabel}.`}
        action={
          hasExpenseCategories ? (
            <AddBudgetButton
              label="Set Budget"
              month={month}
              year={year}
              availableCategories={availableCategories}
            />
          ) : undefined
        }
      />

      <div className="mb-6">
        <MonthSelector month={month} year={year} currentYear={cm.year} />
      </div>

      {!hasExpenseCategories ? (
        <EmptyState
          icon={PiggyBank}
          title="No expense categories yet"
          description="Budgets are set per expense category. Create some categories first, then come back to plan your spending."
        />
      ) : (
        <>
          {/* Overall summary */}
          <Card className="mb-6">
            <CardContent className="space-y-4">
              <div className="flex flex-wrap items-end justify-between gap-3">
                <div>
                  <p className="text-sm text-muted">Total budgeted</p>
                  <p className="mt-1 text-2xl font-bold text-foreground">
                    {formatCurrency(totalBudgeted, user.currency)}
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-sm text-muted">Spent</p>
                  <p
                    className={cn(
                      "mt-1 text-xl font-bold tabular-nums",
                      totalOver ? "text-expense" : "text-foreground",
                    )}
                  >
                    {formatCurrency(totalSpent, user.currency)}
                  </p>
                </div>
              </div>

              <Progress value={totalPct} />

              <div className="flex items-center justify-between text-sm">
                <span className="text-muted">
                  {totalBudgeted > 0 ? `${Math.round(totalPct)}% used` : "No budgets set"}
                </span>
                <span
                  className={cn(
                    "font-medium tabular-nums",
                    totalRemaining < 0 ? "text-expense" : "text-income",
                  )}
                >
                  {totalRemaining < 0
                    ? `${formatCurrency(Math.abs(totalRemaining), user.currency)} over`
                    : `${formatCurrency(totalRemaining, user.currency)} left`}
                </span>
              </div>
            </CardContent>
          </Card>

          {/* Per-budget rows */}
          {rows.length === 0 ? (
            <EmptyState
              icon={WalletIcon}
              title={`No budgets for ${monthLabel}`}
              description="Set a spending limit for an expense category to start tracking your progress."
              action={
                <AddBudgetButton
                  label="Set Budget"
                  variant="primary"
                  month={month}
                  year={year}
                  availableCategories={availableCategories}
                />
              }
            />
          ) : (
            <div className="space-y-3">
              {rows.map(({ budget, spent, remaining, pct, over }) => {
                const c = budget.category;
                const editData: BudgetEditData = {
                  id: budget.id,
                  categoryId: budget.categoryId,
                  categoryName: c.name,
                  categoryColor: c.color,
                  categoryIcon: c.icon,
                  amount: budget.amount,
                };
                return (
                  <BudgetCard
                    key={budget.id}
                    editData={editData}
                    spent={spent}
                    remaining={remaining}
                    pct={pct}
                    over={over}
                    currency={user.currency}
                    month={month}
                    year={year}
                    transactions={txByCategory.get(budget.categoryId) ?? []}
                  />
                );
              })}
            </div>
          )}
        </>
      )}
    </div>
  );
}
