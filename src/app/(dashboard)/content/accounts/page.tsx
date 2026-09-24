import type { Metadata } from "next";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { getContentSetup } from "@/lib/content-server";
import { ContentSettings } from "./settings";

export const metadata: Metadata = { title: "Pengaturan Konten — Ghina" };

export default async function ContentAccountsPage() {
  const user = await requireUser();
  const [setup, postCounts, items] = await Promise.all([
    getContentSetup(user.id),
    prisma.contentPost.groupBy({ by: ["accountId"], where: { userId: user.id }, _count: { _all: true } }),
    prisma.contentItem.findMany({ where: { userId: user.id, pillar: { not: null } }, select: { pillar: true } }),
  ]);
  const pillarUse: Record<string, number> = {};
  for (const i of items) {
    const k = i.pillar!.toLocaleLowerCase("id-ID");
    pillarUse[k] = (pillarUse[k] ?? 0) + 1;
  }
  return (
    <ContentSettings
      accounts={setup.accounts}
      pillars={setup.pillars}
      postCounts={Object.fromEntries(postCounts.map((p) => [p.accountId, p._count._all]))}
      pillarUse={pillarUse}
    />
  );
}
