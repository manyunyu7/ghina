import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { getAssetDetail } from "@/lib/investments-server";
import { AssetDetailView } from "./asset-detail";

export default async function AssetDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const user = await requireUser();
  const [detail, wallets] = await Promise.all([
    // Cached price only; the client refreshes a stale quote after mount.
    getAssetDetail(user.id, id, { refresh: false }),
    prisma.wallet.findMany({
      where: { userId: user.id, archived: false },
      select: { id: true, name: true, type: true, currency: true, balance: true },
      orderBy: { createdAt: "asc" },
    }),
  ]);
  if (!detail) notFound();
  const linked = detail.trades.map((t) => t.cashTransactionId).filter((x): x is string => !!x);
  const txWallets = linked.length
    ? await prisma.transaction.findMany({
        where: { id: { in: linked }, userId: user.id },
        select: { id: true, wallet: { select: { name: true } } },
      })
    : [];
  const cashWallets = Object.fromEntries(txWallets.map((t) => [t.id, t.wallet.name]));
  return <AssetDetailView detail={detail} wallets={wallets} cashWallets={cashWallets} />;
}
