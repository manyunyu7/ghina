import { ArrowDownLeft, ArrowUpRight, Receipt, ArrowLeftRight, Scale } from "lucide-react";
import type { Prisma } from "@prisma/client";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { getWallets, getCategories, getMonthlyTotals, monthRange, currentMonth } from "@/lib/queries";
import { formatDate, cn } from "@/lib/utils";
import { Card, CardContent } from "@/components/ui/card";
import { Badge, EmptyState, PageHeader } from "@/components/ui/misc";
import { CategoryIcon } from "@/components/icon";
import { AddTransactionButton } from "./add-transaction-button";
import { TransactionFilters } from "./transaction-filters";
import { TransactionActions } from "./transaction-actions";
import type { TransactionFormData } from "./transaction-form";
import { ADJUSTMENT_LABEL } from "@/lib/adjustment";
import { TRANSACTION_TYPES } from "@/lib/schemas";
import { parsePhotos } from "@/lib/photos";
import { PhotoBadge } from "@/components/photo-viewer";
import { Money } from "@/components/money/money";

const ADJUSTMENT_COLOR = "#0284c7";

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

  if ((TRANSACTION_TYPES as readonly string[]).includes(sp.type ?? "")) {
    where.type = sp.type;
  }
  // A wallet's history: everything that moves its balance, incl. transfers into it.
  if (sp.walletId) where.OR = [{ walletId: sp.walletId }, { toWalletId: sp.walletId }];
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
                  <Money amount={s.value} currency={user.currency} />
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
                    const isAdjustment = t.type === "adjustment";
                    const tint = isAdjustment ? ADJUSTMENT_COLOR : isTransfer ? "#6366f1" : t.category?.color ?? "#6366f1";
                    const photos = parsePhotos(t.photos);
                    const formData: TransactionFormData = {
                      id: t.id,
                      type: t.type,
                      amount: t.amount,
                      walletId: t.walletId,
                      toWalletId: t.toWalletId,
                      categoryId: t.categoryId,
                      note: t.note,
                      date: t.date,
                      photos,
                    };
                    const title = isAdjustment
                      ? ADJUSTMENT_LABEL
                      : t.note || t.category?.name || (isIncome ? "Income" : isExpense ? "Expense" : "Transfer");
                    return (
                      <div key={t.id} className="flex items-center gap-3 p-3 sm:p-4">
                        <div
                          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full"
                          style={{ backgroundColor: `${tint}1a`, color: tint }}
                        >
                          {isAdjustment ? (
                            <Scale className="h-5 w-5" />
                          ) : isTransfer ? (
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
                            {isAdjustment && t.note ? (
                              <span className="max-w-full truncate text-xs text-muted">{t.note}</span>
                            ) : null}
                            {isTransfer ? (
                              <Badge>
                                {t.wallet.name} → {t.toWallet?.name ?? "—"}
                              </Badge>
                            ) : (
                              <Badge>{t.wallet.name}</Badge>
                            )}
                            <span className="text-xs text-muted-soft">{formatDate(t.date)}</span>
                            <PhotoBadge photos={photos} />
                          </div>
                        </div>

                        <div
                          className={cn(
                            "shrink-0 text-sm font-semibold tabular-nums",
                            isIncome ? "text-income" : isExpense ? "text-expense" : isAdjustment ? "text-sky-600" : "text-foreground",
                          )}
                        >
                          {isIncome ? "+" : isExpense ? "−" : isAdjustment ? (t.amount > 0 ? "+" : "−") : ""}
                          <Money amount={isAdjustment ? Math.abs(t.amount) : t.amount} currency={t.wallet.currency} />
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
