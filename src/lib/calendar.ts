import { localDateKey } from "@/lib/content";
import { addDaysKey, daysInMonth, isoWeekday } from "@/lib/tasks";

/**
 * Calendar events — pure helpers shared by the web page (mirrored by the mobile app,
 * docs/mobile-sync.md "Calendar events"). No DB access.
 */

export const DEFAULT_EVENT_COLOR = "#6366f1";
export const EVENT_COLORS = ["#6366f1", "#1CB0F6", "#58CC02", "#FF9600", "#FF4B4B", "#CE82FF", "#64748b"] as const;

/** Longest span listed day by day (longer events are cut off in the grid). */
const MAX_SPAN_DAYS = 366;

export type EventLike = { startAt: string | Date; endAt: string | Date | null; allDay: boolean };

/** Stored instant of an all-day date: UTC midnight of the local day `YYYY-MM-DD`. */
export const allDayIso = (dateKey: string) => `${dateKey}T00:00:00.000Z`;

/** Local day keys an event covers: all-day → the ISO date parts; timed → days in `timeZone`. */
export function eventDayKeys(e: EventLike, timeZone: string): string[] {
  const key = (d: string | Date) =>
    e.allDay ? new Date(d).toISOString().slice(0, 10) : localDateKey(d, timeZone);
  const first = key(e.startAt);
  let last = first;
  if (e.endAt) {
    const end = new Date(e.endAt);
    // A timed event ending exactly at midnight does not occupy the next day (hence −1 ms).
    const lastKey = e.allDay ? key(end) : key(new Date(Math.max(end.getTime() - 1, new Date(e.startAt).getTime())));
    if (lastKey > first) last = lastKey;
  }
  const out: string[] = [];
  for (let d = first; d <= last && out.length < MAX_SPAN_DAYS; d = addDaysKey(d, 1)) out.push(d);
  return out;
}

/** `YYYY-MM` of a date key. */
export const monthOf = (dateKey: string) => dateKey.slice(0, 7);

export function isMonthKey(v: unknown): v is string {
  if (typeof v !== "string" || !/^\d{4}-(0[1-9]|1[0-2])$/.test(v)) return false;
  const y = Number(v.slice(0, 4));
  return y >= 1970 && y <= 9999;
}

export function shiftMonth(monthKey: string, n: number): string {
  const [y, m] = monthKey.split("-").map(Number);
  const idx = y * 12 + (m - 1) + n;
  return `${Math.floor(idx / 12)}-${String((idx % 12) + 1).padStart(2, "0")}`;
}

/** First and last day keys of a month. */
export function monthRange(monthKey: string): { first: string; last: string } {
  const [y, m] = monthKey.split("-").map(Number);
  return { first: `${monthKey}-01`, last: `${monthKey}-${String(daysInMonth(y, m)).padStart(2, "0")}` };
}

/** The 6×7 day keys of a month grid, weeks starting Monday. */
export function monthGridKeys(monthKey: string): string[] {
  const { first } = monthRange(monthKey);
  const start = addDaysKey(first, -(isoWeekday(first) - 1));
  return Array.from({ length: 42 }, (_, i) => addDaysKey(start, i));
}
