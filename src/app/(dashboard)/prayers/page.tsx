import Link from "next/link";
import { Flame, CalendarCheck, Gauge, ChevronLeft, ChevronRight, BarChart3 } from "lucide-react";
import { endOfMonth } from "date-fns";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/ui/misc";
import { MONTHS, cn } from "@/lib/utils";
import {
  FARDHU,
  addDays,
  computeReport,
  currentStreak,
  dateKey,
  isValidDateKey,
  parseDateKey,
} from "@/lib/prayer-quality";
import { todayKey } from "./constants";
import { PrayerDayEditor } from "./prayer-day-editor";
import { PrayerCalendar } from "./prayer-calendar";
import { PRAYER_SELECT, byDate, formatLong, toDTO } from "./types";
import { LinkPending, LinkPendingIcon } from "@/components/link-pending";

type SearchParams = { month?: string; year?: string; date?: string };

function parseIntOr(v: string | undefined, fallback: number) {
  if (!v) return fallback;
  const n = Number.parseInt(v, 10);
  return Number.isFinite(n) ? n : fallback;
}

export default async function PrayersPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const user = await requireUser();
  const sp = await searchParams;

  const tKey = todayKey();
  // Day being edited (?date=), never in the future.
  const day = sp.date && isValidDateKey(sp.date) && sp.date <= tKey ? sp.date : tKey;
  const dayDate = parseDateKey(day);

  const now = new Date();
  let month = parseIntOr(sp.month, dayDate.getMonth() + 1);
  let year = parseIntOr(sp.year, dayDate.getFullYear());
  if (month < 1 || month > 12) month = now.getMonth() + 1;
  if (year < 1970 || year > 9999) year = now.getFullYear();

  const monthStartKey = dateKey(new Date(year, month - 1, 1));
  const monthEndKey = dateKey(endOfMonth(new Date(year, month - 1, 1)));
  const streakFrom = addDays(tKey, -400);

  const [monthRows, dayRows, streakRows] = await Promise.all([
    prisma.prayerEntry.findMany({
      where: { userId: user.id, date: { gte: monthStartKey, lte: monthEndKey } },
      select: PRAYER_SELECT,
    }),
    prisma.prayerEntry.findMany({ where: { userId: user.id, date: day }, select: PRAYER_SELECT }),
    prisma.prayerEntry.findMany({
      where: { userId: user.id, date: { gte: streakFrom, lte: tKey } },
      select: { date: true, prayer: true, status: true, qobliyah: true, badiyah: true },
    }),
  ]);

  const monthEntries = monthRows.map(toDTO);
  const data = byDate(monthEntries);
  const dayEntries = byDate(dayRows.map(toDTO))[day] ?? {};

  const streak = currentStreak(streakRows, tKey);
  const monthReport = computeReport(monthEntries, monthStartKey, monthEndKey, tKey);
  const dayReport = computeReport(dayRows.map(toDTO), day, day, tKey);
  const dayRecorded = FARDHU.filter((p) => dayEntries[p.id]).length;

  const monthLabel = `${MONTHS[month - 1]} ${year}`;
  const isToday = day === tKey;
  const dayHref = (d: string) => `/prayers?date=${d}`;

  return (
    <div>
      <PageHeader
        title="Prayers"
        description="Catat kualitas shalat fardhu, rawatib, dan sunnah harian."
        action={
          <Link href="/prayers/report">
            <Button variant="outline">
              <LinkPendingIcon>
                <BarChart3 className="h-4 w-4" />
              </LinkPendingIcon>{" "}
              Laporan
            </Button>
          </Link>
        }
      />

      {/* Day editor with date navigation */}
      <Card className="mb-6">
        <CardContent>
          <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
            <div>
              <p className="text-sm text-muted">{isToday ? "Hari ini" : "Tanggal"}</p>
              <p className="font-semibold text-foreground">{formatLong(day)}</p>
            </div>
            <div className="flex items-center gap-1">
              <Link
                href={dayHref(addDays(day, -1))}
                className="rounded-lg p-1.5 text-muted hover:bg-accent"
                aria-label="Hari sebelumnya"
                scroll={false}
              >
                <LinkPendingIcon className="h-5 w-5">
                  <ChevronLeft className="h-5 w-5" />
                </LinkPendingIcon>
              </Link>
              {!isToday && (
                <Link href="/prayers" scroll={false} className="rounded-lg px-2 py-1 text-sm font-medium text-primary hover:bg-primary-soft">
                  Hari ini
                  <LinkPending spinner={false} />
                </Link>
              )}
              <Link
                href={dayHref(addDays(day, 1))}
                className={cn("rounded-lg p-1.5 text-muted hover:bg-accent", isToday && "pointer-events-none opacity-30")}
                aria-label="Hari berikutnya"
                aria-disabled={isToday}
                scroll={false}
              >
                <LinkPendingIcon className="h-5 w-5">
                  <ChevronRight className="h-5 w-5" />
                </LinkPendingIcon>
              </Link>
              <span className="ml-2 rounded-full bg-primary-soft px-3 py-1 text-sm font-semibold text-primary tabular-nums">
                {dayRecorded}/{FARDHU.length}
              </span>
            </div>
          </div>
          {/* Remount on fresh server data so edits made elsewhere (calendar, mobile sync) show up. */}
          <PrayerDayEditor key={`${day}:${JSON.stringify(dayEntries)}`} dateKey={day} initial={dayEntries} />
        </CardContent>
      </Card>

      {/* Stats */}
      <div className="mb-6 grid gap-3 sm:grid-cols-3">
        <StatTile
          icon={<Flame className="h-5 w-5" />}
          label="Streak hari lengkap"
          value={`${streak} hari`}
          tint="bg-expense-soft text-expense"
        />
        <StatTile
          icon={<CalendarCheck className="h-5 w-5" />}
          label={isToday ? "Skor hari ini" : "Skor hari itu"}
          value={dayReport.score == null ? "–" : `${dayReport.score}`}
          tint="bg-income-soft text-income"
        />
        <StatTile
          icon={<Gauge className="h-5 w-5" />}
          label={`Skor kualitas ${monthLabel}`}
          value={monthReport.score == null ? "–" : `${monthReport.score}`}
          tint="bg-primary-soft text-primary"
        />
      </div>

      {/* Calendar colored by status */}
      <PrayerCalendar year={year} month={month} data={data} today={tKey} />
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
