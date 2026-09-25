"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import type { Prisma } from "@prisma/client";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import type { Db } from "@/lib/ledger";
import { deleteSynced, deleteSyncedRow } from "@/lib/sync-deletes";
import { assertId, assertIds, assertObject, pick, runAction, UserError, type ActionResult } from "@/lib/action-utils";
import { isValidDateKey } from "@/lib/prayer-quality";
import {
  canSkip,
  cleanStreakBefore,
  habitToday,
  MAX_SKIPS_PER_7_DAYS,
  todayKey,
  type HabitKind,
  type HabitLogType,
  type HabitSchedule,
  type HabitTarget,
  type HabitToday,
} from "@/lib/habits";
import {
  getHabitDetail,
  getHabitsOverview,
  habitLike,
  habitLogsLite,
  habitRowToInput,
  HabitError,
  logRowToInput,
  saveHabit,
  saveHabitLog,
  type HabitDetail,
  type HabitOverviewItem,
} from "@/lib/habits-server";

/**
 * Server actions for the web Habits page (docs/habits.md). Plain-object arguments,
 * results `{ ok: true, … } | { ok: false, error }` with Indonesian messages. Validation is
 * shared with mobile sync (src/lib/habits.ts, src/lib/habits-server.ts). Dates are the
 * user's local `YYYY-MM-DD` (the browser sends its own "today").
 */

export type HabitInput = {
  name: string;
  emoji?: string | null;
  color?: string;
  kind?: HabitKind;
  /** Ignored for quit habits (always daily). */
  schedule?: HabitSchedule;
  /** Ignored for quit habits (always check). */
  target?: HabitTarget;
  /** Local HH:mm, ≤ 5. */
  reminders?: string[];
  private?: boolean;
  /** "Alasan berhenti / mulai" (≤ 500), shown on the emergency screen. */
  why?: string | null;
  /** YYYY-MM-DD; default today. Quit: "sudah bersih sejak…". */
  startDate?: string;
  archived?: boolean;
  /** Default on create: after the last habit. */
  sortOrder?: number;
};

export type RelapseInput = {
  date: string;
  /** Times it happened (default 1). */
  count?: number;
  triggers?: string[];
  note?: string | null;
  /** ISO time it happened; default now. */
  at?: string | null;
};

export type UrgeInput = Omit<RelapseInput, "count"> & { count?: number };

const HABIT_KEYS = [
  "name", "emoji", "color", "kind", "schedule", "target", "reminders", "private", "why", "startDate", "archived", "sortOrder",
] as const;

function revalidate() {
  revalidatePath("/habits");
  revalidatePath("/dashboard");
}

function assertDate(date: unknown): asserts date is string {
  if (typeof date !== "string" || !isValidDateKey(date)) throw new UserError("Tanggal tidak valid");
}

async function ownHabit(db: Db, userId: string, id: unknown) {
  assertId(id, "Kebiasaan tidak ditemukan");
  const h = await db.habit.findFirst({ where: { id, userId } });
  if (!h) throw new UserError("Kebiasaan tidak ditemukan");
  return h;
}

type HabitRow = Prisma.HabitGetPayload<object>;
type LogRow = Prisma.HabitLogGetPayload<object>;

/**
 * Create or replace the (habit, date, type) log with `build(existing)` (a partial wire
 * row), validated by the same rules as sync.
 */
async function upsertLog(
  db: Db,
  userId: string,
  habit: HabitRow,
  date: string,
  type: HabitLogType,
  build: (existing: LogRow | null) => Record<string, unknown>,
) {
  const existing = await db.habitLog.findUnique({ where: { habitId_date_type: { habitId: habit.id, date, type } } });
  const base = existing ? logRowToInput(existing) : { habitId: habit.id, date, type, value: null, note: null, triggers: [], at: null };
  const res = await saveHabitLog(db, userId, existing?.id ?? randomUUID(), { ...base, ...build(existing), habitId: habit.id, date, type }, !!existing);
  if (res.outcome === "duplicate") throw new HabitError("Catatan untuk hari ini sudah ada");
  return res.row;
}

async function removeLog(userId: string, habitId: string, date: string, type: HabitLogType) {
  const row = await prisma.habitLog.findUnique({ where: { habitId_date_type: { habitId, date, type } } });
  if (row && row.userId === userId) await deleteSynced(userId, "habitLogs", row.id);
}

async function todayOf(userId: string, habit: HabitRow, today: string): Promise<HabitToday> {
  return habitToday(habitLike(habit), await habitLogsLite(prisma, userId, habit.id), today);
}

const mergeTriggers = (a: string[], b: string[] | undefined) => [...a, ...(b ?? [])];

// ---------- Habits ----------

export async function createHabit(input: HabitInput): Promise<ActionResult<{ id: string }>> {
  return runAction("habits", async () => {
    assertObject(input);
    const user = await requireUser();
    const last = await prisma.habit.findFirst({ where: { userId: user.id }, orderBy: { sortOrder: "desc" }, select: { sortOrder: true } });
    const data = { startDate: todayKey(), sortOrder: (last?.sortOrder ?? -1) + 1, ...pick(input, HABIT_KEYS) };
    const id = randomUUID();
    await saveHabit(prisma, user.id, id, data, false);
    revalidate();
    return { id };
  });
}

export async function updateHabit(id: string, patch: Partial<HabitInput>): Promise<ActionResult> {
  return runAction("habits", async () => {
    assertObject(patch);
    const user = await requireUser();
    await prisma.$transaction(async (db) => {
      const h = await ownHabit(db, user.id, id);
      await saveHabit(db, user.id, h.id, { ...habitRowToInput(h), ...pick(patch, HABIT_KEYS) }, true);
    });
    revalidate();
    return {};
  });
}

/** Deletes the habit and all its logs (tombstoned). */
export async function deleteHabit(id: string): Promise<ActionResult> {
  return runAction("habits", async () => {
    const user = await requireUser();
    const h = await ownHabit(prisma, user.id, id);
    await deleteSynced(user.id, "habits", h.id);
    revalidate();
    return {};
  });
}

export async function setHabitArchived(id: string, archived: boolean): Promise<ActionResult> {
  return updateHabit(id, { archived: archived === true });
}

/** Manual order: `orderedIds[i]` gets sortOrder i (ids that aren't the user's are ignored). */
export async function reorderHabits(orderedIds: string[]): Promise<ActionResult> {
  return runAction("habits", async () => {
    assertIds(orderedIds, "Kebiasaan tidak ditemukan");
    const user = await requireUser();
    await prisma.$transaction(async (db) => {
      for (const [i, id] of orderedIds.entries())
        await db.habit.updateMany({ where: { id, userId: user.id, sortOrder: { not: i } }, data: { sortOrder: i } });
    });
    revalidate();
    return {};
  });
}

// ---------- Check-ins ----------

/**
 * Record progress for `date` (a `done` row). Build/check and quit ("Hari ini bersih ✅"):
 * value is always 1. Build count/duration: `value` sets the day's progress, `add` adds to
 * it (e.g. +1 gelas); neither → +1. `note` (journal) replaces the row's note when given.
 */
export async function checkInHabit(
  habitId: string,
  input: { date: string; value?: number; add?: number; note?: string | null },
): Promise<ActionResult<{ today: HabitToday }>> {
  return runAction("habits", async () => {
    assertObject(input);
    assertDate(input.date);
    const user = await requireUser();
    const h = await prisma.$transaction(async (db) => {
      const h = await ownHabit(db, user.id, habitId);
      await upsertLog(db, user.id, h, input.date, "done", (ex) => {
        const out: Record<string, unknown> = {};
        if (typeof input.value === "number") out.value = input.value;
        else out.value = (ex?.value ?? 0) + (typeof input.add === "number" ? input.add : 1);
        if (input.note !== undefined) out.note = input.note;
        return out;
      });
      return h;
    });
    revalidate();
    return { today: await todayOf(user.id, h, input.date) };
  });
}

/** Remove the day's `done` row (un-check / reset progress / undo a clean check-in). */
export async function uncheckHabit(habitId: string, date: string): Promise<ActionResult<{ today: HabitToday }>> {
  return runAction("habits", async () => {
    assertDate(date);
    const user = await requireUser();
    const h = await ownHabit(prisma, user.id, habitId);
    await removeLog(user.id, h.id, date, "done");
    revalidate();
    return { today: await todayOf(user.id, h, date) };
  });
}

/** Mark / unmark a build habit's rest day (max 2 per rolling 7 days). */
export async function setHabitSkip(
  habitId: string,
  date: string,
  skip: boolean,
  note?: string | null,
): Promise<ActionResult<{ today: HabitToday }>> {
  return runAction("habits", async () => {
    assertDate(date);
    const user = await requireUser();
    const h = await ownHabit(prisma, user.id, habitId);
    if (skip === true) {
      await prisma.$transaction(async (db) => {
        if (!canSkip(await habitLogsLite(db, user.id, h.id), date))
          throw new UserError(`Maksimal ${MAX_SKIPS_PER_7_DAYS} hari libur dalam 7 hari`);
        await upsertLog(db, user.id, h, date, "skip", () => (note !== undefined ? { note } : {}));
      });
    } else await removeLog(user.id, h.id, date, "skip");
    revalidate();
    return { today: await todayOf(user.id, h, date) };
  });
}

// ---------- Quit habits: relapse / urge ----------

async function applyRelapse(db: Db, userId: string, h: HabitRow, input: RelapseInput): Promise<number> {
  const previousStreak = cleanStreakBefore({ startDate: h.startDate }, await habitLogsLite(db, userId, h.id), input.date);
  await upsertLog(db, userId, h, input.date, "relapse", (ex) => ({
    value: (ex?.value ?? 0) + (input.count ?? 1),
    triggers: mergeTriggers(ex ? logRowToInput(ex).triggers : [], input.triggers),
    ...(input.note !== undefined ? { note: input.note } : {}),
    at: input.at ?? new Date().toISOString(),
  }));
  return previousStreak;
}

/**
 * Log a relapse (quit habits): adds `count` (default 1) to the day's relapse row, merges
 * triggers, sets the note when given. Returns the clean streak it ended
 * ("Kamu sempat bersih N hari — itu nyata").
 */
export async function logRelapse(habitId: string, input: RelapseInput): Promise<ActionResult<{ previousStreak: number; today: HabitToday }>> {
  return runAction("habits", async () => {
    assertObject(input);
    assertDate(input.date);
    const user = await requireUser();
    const { h, previousStreak } = await prisma.$transaction(async (db) => {
      const h = await ownHabit(db, user.id, habitId);
      return { h, previousStreak: await applyRelapse(db, user.id, h, input) };
    });
    revalidate();
    return { previousStreak, today: await todayOf(user.id, h, input.date) };
  });
}

/** "Lagi pengen, tapi tahan": +`count` (default 1) urges resisted on `date`. */
export async function logUrge(habitId: string, input: UrgeInput): Promise<ActionResult<{ urgesToday: number; today: HabitToday }>> {
  return runAction("habits", async () => {
    assertObject(input);
    assertDate(input.date);
    const user = await requireUser();
    const { h, row } = await prisma.$transaction(async (db) => {
      const h = await ownHabit(db, user.id, habitId);
      const row = await upsertLog(db, user.id, h, input.date, "urge", (ex) => ({
        value: (ex?.value ?? 0) + (input.count ?? 1),
        triggers: mergeTriggers(ex ? logRowToInput(ex).triggers : [], input.triggers),
        ...(input.note !== undefined ? { note: input.note } : {}),
        at: input.at ?? new Date().toISOString(),
      }));
      return { h, row };
    });
    revalidate();
    return { urgesToday: row.value ?? 0, today: await todayOf(user.id, h, input.date) };
  });
}

/**
 * "Aku kalah kali ini" after the emergency screen: the urge just logged becomes a relapse
 * (urge −1 — the row is deleted at 0; relapse +1 with the triggers/note), atomically.
 */
export async function urgeToRelapse(habitId: string, input: RelapseInput): Promise<ActionResult<{ previousStreak: number; today: HabitToday }>> {
  return runAction("habits", async () => {
    assertObject(input);
    assertDate(input.date);
    const user = await requireUser();
    const { h, previousStreak } = await prisma.$transaction(async (db) => {
      const h = await ownHabit(db, user.id, habitId);
      const urge = await db.habitLog.findUnique({ where: { habitId_date_type: { habitId: h.id, date: input.date, type: "urge" } } });
      if (urge && (urge.value ?? 1) <= 1) await deleteSyncedRow(db, user.id, "habitLogs", urge.id);
      else if (urge) await upsertLog(db, user.id, h, input.date, "urge", (ex) => ({ value: (ex?.value ?? 2) - 1 }));
      return { h, previousStreak: await applyRelapse(db, user.id, h, input) };
    });
    revalidate();
    return { previousStreak, today: await todayOf(user.id, h, input.date) };
  });
}

// ---------- Journal ----------

/** Set/clear the journal note of an existing log (done/skip/relapse/urge) of `date`. */
export async function setHabitLogNote(habitId: string, date: string, type: HabitLogType, note: string | null): Promise<ActionResult> {
  return runAction("habits", async () => {
    assertDate(date);
    if (typeof type !== "string") throw new UserError("Jenis catatan tidak valid");
    const user = await requireUser();
    await prisma.$transaction(async (db) => {
      const h = await ownHabit(db, user.id, habitId);
      const ex = await db.habitLog.findUnique({ where: { habitId_date_type: { habitId: h.id, date, type } } });
      if (!ex) throw new UserError("Catat kebiasaan hari itu dulu, baru tulis jurnal");
      await upsertLog(db, user.id, h, date, type, () => ({ note }));
    });
    revalidate();
    return {};
  });
}

export async function deleteHabitLog(logId: string): Promise<ActionResult> {
  return runAction("habits", async () => {
    assertId(logId, "Catatan tidak ditemukan");
    const user = await requireUser();
    const row = await prisma.habitLog.findFirst({ where: { id: logId, userId: user.id }, select: { id: true } });
    if (!row) throw new UserError("Catatan tidak ditemukan");
    await deleteSynced(user.id, "habitLogs", row.id);
    revalidate();
    return {};
  });
}

// ---------- Queries ----------

/** All habits with today's status + streak (active first, manual order). */
export async function fetchHabits(opts: { today: string; includeArchived?: boolean }): Promise<ActionResult<{ habits: HabitOverviewItem[] }>> {
  return runAction("habits", async () => {
    assertObject(opts);
    assertDate(opts.today);
    const user = await requireUser();
    return { habits: await getHabitsOverview(user.id, { today: opts.today, includeArchived: opts.includeArchived === true }) };
  });
}

/** One habit with insights (streaks, completion, heatmap, by weekday/hour, triggers, journal) over [from, to]. */
export async function fetchHabitDetail(
  habitId: string,
  range: { from: string; to: string; today: string; timeZone?: string },
): Promise<ActionResult<{ detail: HabitDetail }>> {
  return runAction("habits", async () => {
    assertId(habitId, "Kebiasaan tidak ditemukan");
    assertObject(range);
    assertDate(range.from);
    assertDate(range.to);
    assertDate(range.today);
    if (range.from > range.to) throw new UserError("Rentang tanggal tidak valid");
    if (Math.abs(Date.parse(range.to) - Date.parse(range.from)) > 800 * 86_400_000)
      throw new UserError("Rentang maksimal ±2 tahun");
    const timeZone = typeof range.timeZone === "string" && range.timeZone.length < 64 ? range.timeZone : undefined;
    if (timeZone) {
      try {
        new Intl.DateTimeFormat("en", { timeZone });
      } catch {
        throw new UserError("Zona waktu tidak valid");
      }
    }
    const user = await requireUser();
    const detail = await getHabitDetail(user.id, habitId, { from: range.from, to: range.to, today: range.today, timeZone });
    if (!detail) throw new UserError("Kebiasaan tidak ditemukan");
    return { detail };
  });
}
