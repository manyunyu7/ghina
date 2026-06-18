import { ArrowDownLeft, ArrowUpRight, Receipt, ArrowLeftRight } from "lucide-react";
import type { Prisma } from "@prisma/client";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { getWallets, getCategories, getMonthlyTotals, monthRange, currentMonth } from "@/lib/queries";
import { formatCurrency, formatDate, cn } from "@/lib/utils";
import { Card, CardContent } from "@/components/ui/card";
import { Badge, EmptyState, PageHeader } from "@/components/ui/misc";
import { CategoryIcon } from "@/components/icon";
import { AddTransactionButton } from "./add-transaction-button";
import { TransactionFilters } from "./transaction-filters";
import { TransactionActions } from "./transaction-actions";
import type { TransactionFormData } from "./transaction-form";

type SearchParams = {
  type?: string;
  walletId?: string;
  categoryId?: string;
  month?: string;
  year?: string;
  q?: string;
};

function parseIntOr(value: string | undefined, fallback: number | null): number | null {
  if (!value) return fallback;
  const n = Number.parseInt(value, 10);
  return Number.isFinite(n) ? n : fallback;
}

export default async function TransactionsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const user = await requireUser();
  const sp = await searchParams;

  const [wallets, categories] = await Promise.all([
    getWallets(user.id),
    getCategories(user.id),
  ]);

  // Summary always reflects the current calendar month.
  const cm = currentMonth();
  const totals = await getMonthlyTotals(user.id, monthRange(cm.year, cm.month));

  // Build the filtered query.
  const where: Prisma.TransactionWhereInput = { userId: user.id };

  if (sp.type === "income" || sp.type === "expense" || sp.type === "transfer") {
    where.type = sp.type;
  }
  if (sp.walletId) where.walletId = sp.walletId;
  if (sp.categoryId) where.categoryId = sp.categoryId;
  if (sp.q) where.note = { contains: sp.q };

  // Month/year filter. If only a month is given, default the year to current.
  const month = parseIntOr(sp.month, null);
  const year = parseIntOr(sp.year, null);
  if (month && year) {
    const r = monthRange(year, month);
    where.date = { gte: r.start, lte: r.end };
  } else if (month) {
    const r = monthRange(cm.year, month);
    where.date = { gte: r.start, lte: r.end };
  } else if (year) {
    where.date = { gte: new Date(year, 0, 1, 0, 0, 0, 0), lte: new Date(year, 11, 31, 23, 59, 59, 999) };
  }

  const transactions = await prisma.transaction.findMany({
    where,
    include: { wallet: true, toWallet: true, category: true },
    orderBy: [{ date: "desc" }, { createdAt: "desc" }],
  });

  // Group by calendar day (newest first; findMany already sorted).
  const groups = new Map<string, typeof transactions>();
  for (const t of transactions) {
    const key = formatDate(t.date, { day: "numeric", month: "long", year: "numeric" });
    const arr = groups.get(key);
    if (arr) arr.push(t);
    else groups.set(key, [t]);
  }

  const summary = [
    { label: "Income", value: totals.income, className: "text-income", icon: ArrowDownLeft },
    { label: "Expense", value: totals.expense, className: "text-expense", icon: ArrowUpRight },
    {
      label: "Net",
      value: totals.net,
      className: totals.net >= 0 ? "text-income" : "text-expense",
      icon: Receipt,
    },
  ];

  return (
    <div>
      <PageHeader
        title="Transactions"
        description="Track every income and expense across your wallets."
        action={<AddTransactionButton wallets={wallets} categories={categories} />}
      />

      {/* Summary strip — current month */}
      <div className="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-3">
        {summary.map((s) => (
          <Card key={s.label}>
            <CardContent className="flex items-center justify-between p-4">
              <div>
                <p className="text-sm text-muted">{s.label} this month</p>
                <p className={cn("mt-1 text-xl font-bold", s.className)}>
                  {formatCurrency(s.value, user.currency)}
                </p>
              </div>
              <div className={cn("flex h-10 w-10 items-center justify-center rounded-full bg-accent", s.className)}>
                <s.icon className="h-5 w-5" />
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      <TransactionFilters wallets={wallets} categories={categories} currentYear={cm.year} />

      {wallets.length === 0 ? (
        <EmptyState
          icon={Receipt}
          title="No wallets yet"
          description="Create a wallet first, then you can start recording transactions."
        />
      ) : transactions.length === 0 ? (
        <EmptyState
          icon={Receipt}
          title="No transactions found"
          description="Try adjusting your filters, or add your first transaction to get started."
          action={<AddTransactionButton wallets={wallets} categories={categories} />}
        />
      ) : (
        <div className="space-y-6">
          {Array.from(groups.entries()).map(([day, items]) => (
            <div key={day}>
              <h2 className="mb-2 px-1 text-xs font-semibold uppercase tracking-wide text-muted">{day}</h2>
              <Card>
                <CardContent className="divide-y divide-border p-0">
                  {items.map((t) => {
                    const isIncome = t.type === "income";
                    const isExpense = t.type === "expense";
                    const isTransfer = t.type === "transfer";
                    const tint = isTransfer ? "#6366f1" : t.category?.color ?? "#6366f1";
                    const formData: TransactionFormData = {
                      id: t.id,
                      type: t.type,
                      amount: t.amount,
                      walletId: t.walletId,
                      toWalletId: t.toWalletId,
                      categoryId: t.categoryId,
                      note: t.note,
                      date: t.date,
                    };
                    const title = t.note || t.category?.name || (isIncome ? "Income" : isExpense ? "Expense" : "Transfer");
                    return (
                      <div key={t.id} className="flex items-center gap-3 p-3 sm:p-4">
                        <div
                          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full"
                          style={{ backgroundColor: `${tint}1a`, color: tint }}
                        >
                          {isTransfer ? (
                            <ArrowLeftRight className="h-5 w-5" />
                          ) : (
                            <CategoryIcon name={t.category?.icon} className="h-5 w-5" />
                          )}
                        </div>

                        <div className="min-w-0 flex-1">
                          <p className="truncate text-sm font-medium text-foreground">{title}</p>
                          <div className="mt-0.5 flex flex-wrap items-center gap-2">
                            {t.category && t.note ? (
                              <span className="text-xs text-muted">{t.category.name}</span>
                            ) : null}
                            {isTransfer ? (
                              <Badge>
                                {t.wallet.name} → {t.toWallet?.name ?? "—"}
                              </Badge>
                            ) : (
                              <Badge>{t.wallet.name}</Badge>
                            )}
                            <span className="text-xs text-muted-soft">{formatDate(t.date)}</span>
                          </div>
                        </div>

                        <div
                          className={cn(
                            "shrink-0 text-sm font-semibold tabular-nums",
                            isIncome ? "text-income" : isExpense ? "text-expense" : "text-foreground",
                          )}
                        >
                          {isIncome ? "+" : isExpense ? "−" : ""}
                          {formatCurrency(t.amount, t.wallet.currency)}
                        </div>

                        <TransactionActions transaction={formData} wallets={wallets} categories={categories} />
                      </div>
                    );
                  })}
                </CardContent>
              </Card>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
