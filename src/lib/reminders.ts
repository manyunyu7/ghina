import { DEFAULT_TIME_ZONE } from "@/lib/content";
import { daysInMonth } from "@/lib/tasks";
import type { ReminderRecurrence } from "@/lib/schemas";

/**
 * Reminders — pure rules shared by the web actions and mirrored by the mobile app
 * (docs/mobile-sync.md "Reminders"). No DB access.
 */

export const RECURRENCE_LABELS: Record<ReminderRecurrence | "none", string> = {
  none: "Sekali",
  daily: "Setiap hari",
  weekly: "Setiap minggu",
  monthly: "Setiap bulan",
  yearly: "Setiap tahun",
};

type Wall = { y: number; m: number; d: number; h: number; mi: number; s: number; ms: number };

/** Wall-clock parts of instant `t` in `timeZone`. */
function wallParts(t: number, timeZone: string): Wall {
  const p = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    })
      .formatToParts(new Date(t))
      .map((x) => [x.type, x.value]),
  );
  return { y: +p.year, m: +p.month, d: +p.day, h: +p.hour, mi: +p.minute, s: +p.second, ms: ((t % 1000) + 1000) % 1000 };
}

const wallAsUtc = (w: Wall) => Date.UTC(w.y, w.m - 1, w.d, w.h, w.mi, w.s, w.ms);

/** The instant whose wall clock in `timeZone` is `w` (DST gaps resolve forward). */
function wallToInstant(w: Wall, timeZone: string): number {
  const guess = wallAsUtc(w);
  const offsetAt = (t: number) => wallAsUtc(wallParts(t, timeZone)) - t;
  // Offset at the guess, then re-read at the corrected instant (handles a DST change in between).
  return guess - offsetAt(guess - offsetAt(guess));
}

/** One step of `rule` in local wall-clock time; monthly/yearly clamp to the month's last day. */
function step(w: Wall, rule: ReminderRecurrence, anchorDay: number): Wall {
  switch (rule) {
    case "daily":
    case "weekly": {
      const d = new Date(Date.UTC(w.y, w.m - 1, w.d + (rule === "daily" ? 1 : 7)));
      return { ...w, y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, d: d.getUTCDate() };
    }
    case "monthly": {
      const idx = w.y * 12 + (w.m - 1) + 1;
      const y = Math.floor(idx / 12);
      const m = (idx % 12) + 1;
      return { ...w, y, m, d: Math.min(anchorDay, daysInMonth(y, m)) };
    }
    case "yearly": {
      const y = w.y + 1;
      return { ...w, y, d: Math.min(anchorDay, daysInMonth(y, w.m)) };
    }
  }
}

/**
 * The next due time of a repeating reminder after completing it: step `dueAt` by `rule`
 * (local wall clock in `timeZone`, so 07:00 stays 07:00) until it is after `now`. Monthly /
 * yearly keep `dueAt`'s day of month, clamped to shorter months (31 → 28 in February).
 */
export function nextReminderDue(
  dueAt: Date,
  rule: ReminderRecurrence,
  now: Date = new Date(),
  timeZone: string = DEFAULT_TIME_ZONE,
): Date {
  const start = wallParts(dueAt.getTime(), timeZone);
  let w = start;
  let t = dueAt.getTime();
  // Bounded: at most ~100 years of daily steps.
  for (let i = 0; i < 40_000 && (i === 0 || t <= now.getTime()); i++) {
    w = step(w, rule, start.d);
    t = wallToInstant(w, timeZone);
  }
  return new Date(t);
}

export type ReminderStatus = "overdue" | "upcoming" | "done";

/** Overdue = not done and due before `now`. */
export function reminderStatus(r: { done: boolean; dueAt: Date | string }, now: Date = new Date()): ReminderStatus {
  if (r.done) return "done";
  return new Date(r.dueAt).getTime() < now.getTime() ? "overdue" : "upcoming";
}

/** A valid IANA zone from a client, else the default. */
export function safeTimeZone(tz: unknown): string {
  if (typeof tz !== "string" || tz.length === 0 || tz.length > 64) return DEFAULT_TIME_ZONE;
  try {
    new Intl.DateTimeFormat("en", { timeZone: tz });
    return tz;
  } catch {
    return DEFAULT_TIME_ZONE;
  }
}
