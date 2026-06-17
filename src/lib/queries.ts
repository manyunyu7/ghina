import { prisma } from "@/lib/prisma";

export type DateRange = { start: Date; end: Date };

export function monthRange(year: number, month: number): DateRange {
  // month is 1-12
  const start = new Date(year, month - 1, 1, 0, 0, 0, 0);
  const end = new Date(year, month, 0, 23, 59, 59, 999);
  return { start, end };
}

export function currentMonth(): { year: number; month: number } {
  const now = new Date();
  return { year: now.getFullYear(), month: now.getMonth() + 1 };
}

export async function getWallets(userId: string) {
  return prisma.wallet.findMany({
    where: { userId, archived: false },
    orderBy: { createdAt: "asc" },
  });
}

export async function getCategories(userId: string, type?: "income" | "expense") {
  return prisma.category.findMany({
    where: { userId, ...(type ? { type } : {}) },
    orderBy: { name: "asc" },
  });
}

export async function getTotalBalance(userId: string) {
  const wallets = await prisma.wallet.findMany({
    where: { userId, archived: false },
    select: { balance: true },
  });
  return wallets.reduce((sum, w) => sum + w.balance, 0);
}

/** Sum of income & expense for a user within a date range. */
export async function getMonthlyTotals(userId: string, range: DateRange) {
  const rows = await prisma.transaction.groupBy({
    by: ["type"],
    where: { userId, date: { gte: range.start, lte: range.end }, type: { in: ["income", "expense"] } },
    _sum: { amount: true },
  });
  const income = rows.find((r) => r.type === "income")?._sum.amount ?? 0;
  const expense = rows.find((r) => r.type === "expense")?._sum.amount ?? 0;
  return { income, expense, net: income - expense };
}

/** Spending grouped by category within a range (expenses only). */
export async function getSpendingByCategory(userId: string, range: DateRange) {
  const rows = await prisma.transaction.groupBy({
    by: ["categoryId"],
    where: { userId, type: "expense", date: { gte: range.start, lte: range.end } },
    _sum: { amount: true },
  });
  const categories = await getCategories(userId);
  const map = new Map(categories.map((c) => [c.id, c]));
  return rows
    .map((r) => ({
      category: r.categoryId ? map.get(r.categoryId) ?? null : null,
      total: r._sum.amount ?? 0,
    }))
    .sort((a, b) => b.total - a.total);
}

export async function getRecentTransactions(userId: string, take = 8) {
  return prisma.transaction.findMany({
    where: { userId },
    include: { wallet: true, category: true },
    orderBy: [{ date: "desc" }, { createdAt: "desc" }],
    take,
  });
}
