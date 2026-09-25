import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { canSkip, todayKey } from "@/lib/habits";
import { getHabitDetail } from "@/lib/habits-server";
import { addDaysKey } from "@/lib/tasks";
import { resolveTimeZone, resolveToday } from "../format";
import { HabitDetailView } from "./habit-detail";

export const metadata: Metadata = { title: "Detail kebiasaan — Ghina" };

type SearchParams = { today?: string; tz?: string; view?: string; m?: string; y?: string };

const pad = (n: number) => String(n).padStart(2, "0");

/** Month (`?m=YYYY-MM`, default this month) or year (`?view=year&y=YYYY`) range. */
function resolveRange(sp: SearchParams, today: string) {
  const [ty, tm] = today.split("-").map(Number);
  if (sp.view === "year") {
    const y = /^\d{4}$/.test(sp.y ?? "") ? Number(sp.y) : ty;
    const year = y >= 2000 && y <= ty + 1 ? y : ty;
    return { view: "year" as const, from: `${year}-01-01`, to: `${year}-12-31`, year, month: 1 };
  }
  const mm = /^(\d{4})-(\d{2})$/.exec(sp.m ?? "");
  let year = ty;
  let month = tm;
  if (mm && Number(mm[2]) >= 1 && Number(mm[2]) <= 12 && Number(mm[1]) >= 2000 && Number(mm[1]) <= ty + 1) {
    year = Number(mm[1]);
    month = Number(mm[2]);
  }
  const last = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return { view: "month" as const, from: `${year}-${pad(month)}-01`, to: `${year}-${pad(month)}-${pad(last)}`, year, month };
}

export default async function HabitDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<SearchParams>;
}) {
  const user = await requireUser();
  const [{ id }, sp] = await Promise.all([params, searchParams]);
  if (!id || id.length > 128) notFound();
  const today = resolveToday(sp.today, todayKey());
  const timeZone = resolveTimeZone(sp.tz);
  const range = resolveRange(sp, today);
  const [detail, skips] = await Promise.all([
    getHabitDetail(user.id, id, { from: range.from, to: range.to, today, timeZone }),
    prisma.habitLog.findMany({
      where: { userId: user.id, habitId: id, type: "skip", date: { gte: addDaysKey(today, -6), lte: addDaysKey(today, 6) } },
      select: { date: true, type: true, value: true },
    }),
  ]);
  if (!detail) notFound();
  return (
    <HabitDetailView
      detail={detail}
      today={today}
      timeZone={timeZone}
      canSkipToday={canSkip(skips, today)}
      range={range}
    />
  );
}
