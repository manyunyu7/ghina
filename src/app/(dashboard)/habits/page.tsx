import type { Metadata } from "next";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { canSkip, todayKey } from "@/lib/habits";
import { getHabitsOverview } from "@/lib/habits-server";
import { addDaysKey } from "@/lib/tasks";
import { HabitsBoard } from "./habits-board";
import { resolveToday } from "./format";

export const metadata: Metadata = { title: "Kebiasaan — Ghina" };

type SearchParams = { today?: string; arsip?: string };

export default async function HabitsPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const user = await requireUser();
  const sp = await searchParams;
  const today = resolveToday(sp.today, todayKey());
  const showArchived = sp.arsip === "1";
  const [habits, skips] = await Promise.all([
    getHabitsOverview(user.id, { today, includeArchived: showArchived }),
    // Every 7-day window containing today lies within today ± 6.
    prisma.habitLog.findMany({
      where: { userId: user.id, type: "skip", date: { gte: addDaysKey(today, -6), lte: addDaysKey(today, 6) } },
      select: { habitId: true, date: true, type: true, value: true },
    }),
  ]);
  const skipAllowed: Record<string, boolean> = {};
  for (const h of habits) if (h.kind !== "quit") skipAllowed[h.id] = canSkip(skips.filter((s) => s.habitId === h.id), today);
  return <HabitsBoard habits={habits} today={today} canSkip={skipAllowed} showArchived={showArchived} />;
}
