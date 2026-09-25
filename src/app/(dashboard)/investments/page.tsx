import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { getPortfolio, getPortfolioHistory } from "@/lib/investments-server";
import { PortfolioView } from "./portfolio-view";
import { daysAgoKey, dateKeyWIB } from "./format";
import type { WalletOption } from "./types";

export const metadata = { title: "Investasi" };

export default async function InvestmentsPage() {
  const user = await requireUser();
  // Cached prices only (fast first paint); the client refreshes stale quotes after mount.
  const [portfolio, archivedCount, wallets, history] = await Promise.all([
    getPortfolio(user.id, { refresh: false }),
    prisma.asset.count({ where: { userId: user.id, archived: true } }),
    prisma.wallet.findMany({
      where: { userId: user.id, archived: false },
      select: { id: true, name: true, type: true, currency: true, balance: true },
      orderBy: { createdAt: "asc" },
    }),
    getPortfolioHistory(user.id, { from: daysAgoKey(5 * 366), to: dateKeyWIB() }),
  ]);
  const archived =
    archivedCount > 0
      ? (await getPortfolio(user.id, { refresh: false, includeArchived: true, snapshot: false })).holdings.filter((h) => h.asset.archived)
      : [];

  return (
    <PortfolioView
      portfolio={portfolio}
      archived={archived}
      wallets={wallets satisfies WalletOption[]}
      history={history}
      currency={user.currency}
    />
  );
}
