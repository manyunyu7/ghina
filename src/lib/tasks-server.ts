import { Prisma } from "@prisma/client";
import type { Db } from "@/lib/ledger";
import {
  defaultAreas,
  nextOccurrence,
  parseRecurrence,
  SERIES_ID_RE,
  taskSchema,
  toJsonColumn,
  type TaskAreaData,
  type TaskData,
} from "@/lib/tasks";

/**
 * DB-side task helpers shared by the mobile sync endpoint and the web server actions
 * (docs/tasks.md). Pure rules live in src/lib/tasks.ts; deletes live in
 * src/lib/sync-deletes.ts (tombstones).
 */

/** A validation failure whose message is safe to show the user / return to a client. */
export class TaskError extends Error {}

type TaskRow = Prisma.TaskGetPayload<object>;

/** DB column values for validated area data (schedule as JSON text). */
export function areaToDb(a: TaskAreaData) {
  return { ...a, schedule: toJsonColumn(a.schedule) };
}

/** DB column values for validated task data (recurrence as JSON text). */
export function taskToDb(t: TaskData) {
  return { ...t, recurrence: toJsonColumn(t.recurrence) };
}

/** A task row in the wire/`taskSchema` input shape (JSON columns parsed, doneAt ISO). */
export function taskRowToInput(row: TaskRow) {
  return {
    areaId: row.areaId,
    title: row.title,
    note: row.note,
    bucket: row.bucket,
    dueDate: row.dueDate,
    dueTime: row.dueTime,
    remindBefore: row.remindBefore,
    recurrence: parseRecurrence(row.recurrence),
    seriesId: row.seriesId,
    done: row.done,
    doneAt: row.doneAt?.toISOString() ?? null,
    sortOrder: row.sortOrder,
    amount: row.amount,
    walletId: row.walletId,
    categoryId: row.categoryId,
    transactionId: row.transactionId,
  };
}

/**
 * Ownership / type checks for a task's references: the area, wallet, expense category
 * and linked transaction must all be the user's. Throws TaskError.
 */
export async function validateTaskRefs(db: Db, userId: string, t: TaskData) {
  const area = await db.taskArea.findFirst({ where: { id: t.areaId, userId }, select: { id: true } });
  if (!area) throw new TaskError("Area not found");
  if (t.walletId) {
    const w = await db.wallet.findFirst({ where: { id: t.walletId, userId }, select: { id: true } });
    if (!w) throw new TaskError("Wallet not found");
  }
  if (t.categoryId) {
    const c = await db.category.findFirst({ where: { id: t.categoryId, userId }, select: { type: true } });
    if (!c) throw new TaskError("Category not found");
    if (c.type !== "expense") throw new TaskError("A task's category must be an expense category");
  }
  if (t.transactionId) {
    const tx = await db.transaction.findFirst({ where: { id: t.transactionId, userId }, select: { id: true } });
    if (!tx) throw new TaskError("Transaction not found");
  }
}

/**
 * Validate (zod + refs) and create or update task `id`. A recurring task without a
 * seriesId starts its own series (seriesId = id). Returns the stored row.
 */
export async function saveTask(db: Db, userId: string, id: string, input: unknown, exists: boolean) {
  const t = taskSchema.parse(input);
  if (t.recurrence && !t.seriesId) {
    if (!SERIES_ID_RE.test(id)) throw new TaskError("Recurring task id is too long (max 55 chars)");
    t.seriesId = id;
  }
  await validateTaskRefs(db, userId, t);
  const data = taskToDb(t);
  return exists
    ? db.task.update({ where: { id }, data })
    : db.task.create({ data: { id, userId, ...data } });
}

/**
 * Create the next occurrence of a just-completed recurring task (deterministic id, so a
 * device that already pushed it doesn't cause a duplicate). An existing row is left as
 * is (it may have been edited); an older tombstone for the id is dropped, like a sync
 * re-create. Returns the next occurrence's id, or null for a one-off task.
 */
export async function createNextOccurrence(db: Db, userId: string, task: TaskRow): Promise<string | null> {
  const next = nextOccurrence({ ...task, recurrence: task.recurrence });
  if (!next) return null;
  const existing = await db.task.findUnique({ where: { id: next.id }, select: { userId: true } });
  if (existing) {
    if (existing.userId !== userId) throw new TaskError("Task id conflict");
    return next.id;
  }
  await db.syncTombstone.deleteMany({ where: { userId, entity: "tasks", entityId: next.id } });
  await db.task.create({ data: { id: next.id, userId, ...taskToDb(next.data) } });
  return next.id;
}

/**
 * Give a user the default areas (Kerjaan, Keseharian) if they have none at all —
 * server side of "seed on first use". Deterministic ids make it idempotent across the
 * server and devices. Returns the number of areas created.
 */
export async function ensureDefaultTaskAreas(db: Db, userId: string): Promise<number> {
  if ((await db.taskArea.count({ where: { userId } })) > 0) return 0;
  let created = 0;
  for (const { id, ...a } of defaultAreas(userId)) {
    try {
      // A re-seed after the user deleted every area: the fresh row must not also be tombstoned.
      await db.syncTombstone.deleteMany({ where: { userId, entity: "taskAreas", entityId: id } });
      await db.taskArea.create({ data: { id, userId, ...areaToDb(a) } });
      created++;
    } catch (e) {
      // Concurrent seed (two requests at once) — the other one won.
      if (!(e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002")) throw e;
    }
  }
  return created;
}
