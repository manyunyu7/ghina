import { Flame, CalendarCheck, Percent } from "lucide-react";
import { subDays, endOfMonth } from "date-fns";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { Card, CardContent } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/misc";
import { MONTHS } from "@/lib/utils";
import { dateKey, todayKey, PRAYERS } from "./constants";
import { PrayerToggles } from "./prayer-toggles";
import { PrayerCalendar } from "./prayer-calendar";

type SearchParams = { month?: string; year?: string };

function parseIntOr(v: string | undefined, fallback: number) {
  if (!v) return fallback;
  const n = Number.parseInt(v, 10);
  return Number.isFinite(n) ? n : fallback;
}

export default async function PrayersPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const user = await requireUser();
  const sp = await searchParams;

  const now = new Date();
  let month = parseIntOr(sp.month, now.getMonth() + 1);
  let year = parseIntOr(sp.year, now.getFullYear());
  if (month < 1 || month > 12) month = now.getMonth() + 1;
  if (year < 1970 || year > 9999) year = now.getFullYear();

  const tKey = todayKey();
  const monthStartKey = dateKey(new Date(year, month - 1, 1));
  const monthEndKey = dateKey(endOfMonth(new Date(year, month - 1, 1)));

  // Entries for the selected month (for the calendar + month %) and a 45-day window (for streak).
  const [monthEntries, recentEntries] = await Promise.all([
    prisma.prayerEntry.findMany({
      where: { userId: user.id, date: { gte: monthStartKey, lte: monthEndKey } },
      select: { date: true, prayer: true },
    }),
    prisma.prayerEntry.findMany({
      where: { userId: user.id, date: { gte: dateKey(subDays(now, 45)), lte: tKey } },
      select: { date: true },
    }),
  ]);

  // date -> list of done prayers
  const data: Record<string, string[]> = {};
  for (const e of monthEntries) {
    (data[e.date] ??= []).push(e.prayer);
  }

  const todayDone = data[tKey] ?? [];

  // This month completion %
  const isCurrentMonth = month === now.getMonth() + 1 && year === now.getFullYear();
  const isPastMonth = year < now.getFullYear() || (year === now.getFullYear() && month < now.getMonth() + 1);
  const daysInMonth = endOfMonth(new Date(year, month - 1, 1)).getDate();
  const elapsedDays = isCurrentMonth ? now.getDate() : isPastMonth ? daysInMonth : 0;
  const doneSoFar = monthEntries.filter((e) => e.date <= tKey || isPastMonth).length;
  const possible = elapsedDays * PRAYERS.length;
  const monthPct = possible > 0 ? Math.round((doneSoFar / possible) * 100) : 0;

  // Current streak of full (5/5) days
  const countByDate: Record<string, number> = {};
  for (const e of recentEntries) countByDate[e.date] = (countByDate[e.date] ?? 0) + 1;
  let streak = 0;
  const cursor = new Date(now);
  if ((countByDate[dateKey(cursor)] ?? 0) < PRAYERS.length) cursor.setDate(cursor.getDate() - 1); // today still in progress
  while ((countByDate[dateKey(cursor)] ?? 0) >= PRAYERS.length) {
    streak++;
    cursor.setDate(cursor.getDate() - 1);
  }

  const monthLabel = `${MONTHS[month - 1]} ${year}`;

  return (
    <div>
      <PageHeader title="Prayers" description="Track your five daily prayers and keep your streak going." />

      {/* Today */}
      <Card className="mb-6">
        <CardContent>
          <div className="mb-4 flex items-center justify-between">
            <div>
              <p className="text-sm text-muted">Today</p>
              <p className="font-semibold text-foreground">
                {new Intl.DateTimeFormat("en-US", { weekday: "long", day: "numeric", month: "long" }).format(now)}
              </p>
            </div>
            <span className="rounded-full bg-primary-soft px-3 py-1 text-sm font-semibold text-primary tabular-nums">
              {todayDone.length}/{PRAYERS.length}
            </span>
          </div>
          <PrayerToggles dateKey={tKey} initialDone={todayDone} size="lg" />
        </CardContent>
      </Card>

      {/* Stats */}
      <div className="mb-6 grid gap-3 sm:grid-cols-3">
        <StatTile icon={<Flame className="h-5 w-5" />} label="Current streak" value={`${streak} ${streak === 1 ? "day" : "days"}`} tint="bg-expense-soft text-expense" />
        <StatTile icon={<CalendarCheck className="h-5 w-5" />} label="Today" value={`${todayDone.length} of ${PRAYERS.length}`} tint="bg-income-soft text-income" />
        <StatTile icon={<Percent className="h-5 w-5" />} label={`${monthLabel} completion`} value={`${monthPct}%`} tint="bg-primary-soft text-primary" />
      </div>

      {/* Calendar with dots */}
      <PrayerCalendar year={year} month={month} data={data} />
    </div>
  );
}

function StatTile({ icon, label, value, tint }: { icon: React.ReactNode; label: string; value: string; tint: string }) {
  return (
    <Card className="p-4">
      <div className={`mb-3 flex h-9 w-9 items-center justify-center rounded-lg ${tint}`}>{icon}</div>
      <p className="text-sm text-muted">{label}</p>
      <p className="text-xl font-bold text-foreground">{value}</p>
    </Card>
  );
}
