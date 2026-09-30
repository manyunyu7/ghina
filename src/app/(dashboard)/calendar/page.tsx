import type { Metadata } from "next";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { DEFAULT_TIME_ZONE, localDateKey } from "@/lib/content";
import { addDaysKey } from "@/lib/tasks";
import { isMonthKey, monthGridKeys, monthOf } from "@/lib/calendar";
import { CalendarView, type CalendarEventDTO } from "./calendar-view";

export const metadata: Metadata = { title: "Kalender — Ghina" };

type Search = { m?: string | string[] };

/** Month grid + agenda. `?m=YYYY-MM` picks the month (default: this month, Asia/Jakarta). */
export default async function CalendarPage({ searchParams }: { searchParams: Promise<Search> }) {
  const user = await requireUser();
  const sp = await searchParams;
  const today = localDateKey(new Date(), DEFAULT_TIME_ZONE);
  const month = isMonthKey(sp.m) ? sp.m : monthOf(today);

  // The grid's days, padded by a day on each side so any browser time zone is covered.
  const grid = monthGridKeys(month);
  const from = new Date(`${addDaysKey(grid[0], -1)}T00:00:00.000Z`);
  const to = new Date(`${addDaysKey(grid[grid.length - 1], 2)}T00:00:00.000Z`);

  const rows = await prisma.calendarEvent.findMany({
    where: {
      userId: user.id,
      startAt: { lt: to },
      OR: [{ startAt: { gte: from } }, { endAt: { gte: from } }],
    },
    orderBy: [{ startAt: "asc" }, { createdAt: "asc" }],
  });

  const events: CalendarEventDTO[] = rows.map((e) => ({
    id: e.id,
    title: e.title,
    notes: e.notes,
    startAt: e.startAt.toISOString(),
    endAt: e.endAt?.toISOString() ?? null,
    allDay: e.allDay,
    color: e.color,
    location: e.location,
  }));

  return <CalendarView key={month} month={month} events={events} />;
}
