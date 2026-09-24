import { prisma } from "@/lib/prisma";
import { getContentBoard, getIdeaInbox, toAccountDTO } from "@/lib/content-server";
import { getCategories, getWallets } from "@/lib/queries";
import type { PlannerData } from "./types";

/** First-render data for /content (board + inbox + wallet/category pickers). */
export async function getPlannerData(userId: string, currency: string): Promise<PlannerData> {
  const [board, inbox, wallets, cats] = await Promise.all([
    getContentBoard(userId),
    getIdeaInbox(userId),
    getWallets(userId),
    getCategories(userId, "income"),
  ]);
  return {
    ...board,
    inbox,
    wallets: wallets.map((w) => ({ id: w.id, name: w.name, currency: w.currency, balance: w.balance })),
    incomeCategories: cats.map((c) => ({ id: c.id, name: c.name })),
    currency,
  };
}

export type TodayPost = {
  id: string;
  contentId: string;
  title: string;
  status: string;
  /** Calendar time (postedAt for posted posts, else scheduledAt). */
  at: string;
  account: ReturnType<typeof toAccountDTO>;
};

/**
 * Dashboard "Tayang hari ini": non-skipped posts placed within ±36 h of now — the card
 * keeps the ones on the browser's local today.
 */
export async function getTodayContentPosts(userId: string): Promise<TodayPost[]> {
  const now = Date.now();
  const lo = new Date(now - 36 * 3600_000);
  const hi = new Date(now + 36 * 3600_000);
  const posts = await prisma.contentPost.findMany({
    where: {
      userId,
      status: { not: "skipped" },
      OR: [{ scheduledAt: { gte: lo, lt: hi } }, { postedAt: { gte: lo, lt: hi } }],
    },
    orderBy: { scheduledAt: "asc" },
    take: 60,
  });
  if (!posts.length) return [];
  const [items, accounts] = await Promise.all([
    prisma.contentItem.findMany({ where: { userId, id: { in: [...new Set(posts.map((p) => p.contentId))] } }, select: { id: true, title: true } }),
    prisma.socialAccount.findMany({ where: { userId, id: { in: [...new Set(posts.map((p) => p.accountId))] } } }),
  ]);
  const titles = new Map(items.map((i) => [i.id, i.title]));
  const accs = new Map(accounts.map((a) => [a.id, toAccountDTO(a)]));
  return posts.flatMap((p) => {
    const at = p.status === "posted" ? (p.postedAt ?? p.scheduledAt) : p.scheduledAt;
    const account = accs.get(p.accountId);
    if (!at || !account) return [];
    return [{ id: p.id, contentId: p.contentId, title: titles.get(p.contentId) ?? "", status: p.status, at: at.toISOString(), account }];
  });
}
