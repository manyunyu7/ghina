import { Prisma } from "@prisma/client";
import type { Db } from "@/lib/ledger";
import { prisma } from "@/lib/prisma";
import {
  compareHabits,
  habitInsights,
  habitLogSchema,
  habitSchema,
  habitToday,
  normalizeHabitLog,
  parseHabitSchedule,
  parseHabitTarget,
  parseReminders,
  parseTriggers,
  type HabitData,
  type HabitInsights,
  type HabitLike,
  type HabitToday,
  type LogLite,
} from "@/lib/habits";
import { toJson } from "@/lib/notes";

/**
 * DB-side habit helpers shared by the mobile sync endpoint and the web server actions
 * (docs/habits.md). Pure rules live in src/lib/habits.ts; deletes in src/lib/sync-deletes.ts.
 */

/** A validation failure whose message (Indonesian) is safe to show the user / return to a client. */
export class HabitError extends Error {}

type HabitRow = Prisma.HabitGetPayload<object>;
type LogRow = Prisma.HabitLogGetPayload<object>;

// ---------- Rows → wire / input shapes ----------

export function habitRowToInput(r: HabitRow) {
  return {
    name: r.name,
    emoji: r.emoji,
    color: r.color,
    kind: r.kind,
    schedule: parseHabitSchedule(r.schedule),
    target: parseHabitTarget(r.target),
    reminders: parseReminders(r.reminders),
    private: r.private,
    why: r.why,
    startDate: r.startDate,
    archived: r.archived,
    sortOrder: r.sortOrder,
  };
}

export function logRowToInput(r: LogRow) {
  return {
    habitId: r.habitId,
    date: r.date,
    type: r.type,
    value: r.value,
    note: r.note,
    triggers: parseTriggers(r.triggers),
    at: r.at?.toISOString() ?? null,
  };
}

const stamps = (r: { id: string; createdAt: Date; updatedAt: Date }) => ({
  id: r.id,
  createdAt: r.createdAt.toISOString(),
  updatedAt: r.updatedAt.toISOString(),
});

export type HabitDTO = ReturnType<typeof toHabitDTO>;
export const toHabitDTO = (r: HabitRow) => ({ ...stamps(r), ...habitRowToInput(r) });
export type HabitLogDTO = ReturnType<typeof toHabitLogDTO>;
export const toHabitLogDTO = (r: LogRow) => ({ ...stamps(r), ...logRowToInput(r) });

/** The pure-module view of a habit row. */
export const habitLike = (r: HabitRow): HabitLike & { kind: string } => ({
  kind: r.kind,
  schedule: parseHabitSchedule(r.schedule),
  target: parseHabitTarget(r.target),
  startDate: r.startDate,
});

export const logLite = (r: LogRow): LogLite => ({
  date: r.date,
  type: r.type,
  value: r.value,
  at: r.at,
  note: r.note,
  triggers: parseTriggers(r.triggers),
});

// ---------- Saves ----------

export function habitToDb(d: HabitData) {
  return { ...d, schedule: toJson(d.schedule), target: toJson(d.target), reminders: toJson(d.reminders) };
}

export async function saveHabit(db: Db, userId: string, id: string, input: unknown, exists: boolean) {
  const data = habitToDb(habitSchema.parse(input));
  return exists ? db.habit.update({ where: { id }, data }) : db.habit.create({ data: { id, userId, ...data } });
}

/**
 * Validate and create or update log `id`: the habit must be the user's, kind/target rules
 * (`normalizeHabitLog`) apply, and (habitId, date, type) is unique — another row holding
 * it → "duplicate" (nothing written).
 */
export async function saveHabitLog(
  db: Db,
  userId: string,
  id: string,
  input: unknown,
  exists: boolean,
): Promise<{ outcome: "applied"; row: LogRow } | { outcome: "duplicate" }> {
  const parsed = habitLogSchema.parse(input);
  const habit = await db.habit.findFirst({ where: { id: parsed.habitId, userId } });
  if (!habit) throw new HabitError("Kebiasaan tidak ditemukan");
  const n = normalizeHabitLog({ kind: habit.kind, target: parseHabitTarget(habit.target) }, parsed);
  if (!n.ok) throw new HabitError(n.error);
  const d = n.log;
  const holder = await db.habitLog.findUnique({
    where: { habitId_date_type: { habitId: d.habitId, date: d.date, type: d.type } },
    select: { id: true },
  });
  if (holder && holder.id !== id) return { outcome: "duplicate" };
  const data = { ...d, triggers: toJson(d.triggers) };
  const row = exists
    ? await db.habitLog.update({ where: { id }, data })
    : await db.habitLog.create({ data: { id, userId, ...data } });
  return { outcome: "applied", row };
}

// ---------- Queries for the web UI ----------

export type HabitOverviewItem = HabitDTO & { today: HabitToday };

async function logsByHabit(userId: string, habitIds: string[]) {
  const logs = habitIds.length
    ? await prisma.habitLog.findMany({ where: { userId, habitId: { in: habitIds } }, orderBy: { date: "asc" } })
    : [];
  const map = new Map<string, LogRow[]>();
  for (const l of logs) {
    const arr = map.get(l.habitId) ?? [];
    arr.push(l);
    map.set(l.habitId, arr);
  }
  return map;
}

/** Every habit (active first, in manual order) with today's status and streak. */
export async function getHabitsOverview(
  userId: string,
  opts: { today: string; includeArchived?: boolean },
): Promise<HabitOverviewItem[]> {
  const habits = (
    await prisma.habit.findMany({ where: { userId, ...(opts.includeArchived ? {} : { archived: false }) } })
  ).sort(compareHabits);
  const logs = await logsByHabit(
    userId,
    habits.map((h) => h.id),
  );
  return habits.map((h) => ({
    ...toHabitDTO(h),
    today: habitToday(habitLike(h), (logs.get(h.id) ?? []).map(logLite), opts.today),
  }));
}

export type HabitDetail = { habit: HabitDTO; insights: HabitInsights; logs: HabitLogDTO[]; today: HabitToday };

/** One habit with insights over [from, to] and its logs in that range. */
export async function getHabitDetail(
  userId: string,
  habitId: string,
  opts: { from: string; to: string; today: string; timeZone?: string },
): Promise<HabitDetail | null> {
  const h = await prisma.habit.findFirst({ where: { id: habitId, userId } });
  if (!h) return null;
  const rows = await prisma.habitLog.findMany({ where: { userId, habitId }, orderBy: [{ date: "asc" }, { type: "asc" }] });
  const lite = rows.map(logLite);
  const like = habitLike(h);
  return {
    habit: toHabitDTO(h),
    insights: habitInsights(like, lite, opts),
    logs: rows.filter((r) => r.date >= opts.from && r.date <= opts.to).map(toHabitLogDTO),
    today: habitToday(like, lite, opts.today),
  };
}

/** Logs of one habit (pure-module shape), all dates. */
export async function habitLogsLite(db: Db, userId: string, habitId: string): Promise<LogLite[]> {
  return (await db.habitLog.findMany({ where: { userId, habitId } })).map(logLite);
}
