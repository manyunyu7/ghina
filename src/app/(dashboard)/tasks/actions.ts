"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { transactionSchema } from "@/lib/schemas";
import { createLedgerTransaction, deleteLedgerTransaction, validateTransactionRefs } from "@/lib/ledger";
import { deleteSynced } from "@/lib/sync-deletes";
import { deleteUnreferencedUploads } from "@/lib/uploads";
import {
  BUCKET_IDS,
  parseSchedule,
  taskAreaSchema,
  type AreaSchedule,
  type BucketId,
  type Recurrence,
} from "@/lib/tasks";
import {
  areaToDb,
  createNextOccurrence,
  ensureDefaultTaskAreas,
  saveTask,
  TaskError,
  taskRowToInput,
} from "@/lib/tasks-server";

/**
 * Server actions for the web Tasks board (docs/tasks.md). Every action takes plain
 * objects (not FormData) and returns `{ ok: true, … }` or `{ ok: false, error }`.
 * Validation is the same as mobile sync (src/lib/tasks.ts + src/lib/tasks-server.ts).
 */

export type TaskActionResult<T extends object = object> = ({ ok: true } & T) | { ok: false; error: string };

/** Editable task fields. done/doneAt/seriesId/transactionId are managed by complete/uncomplete. */
export type TaskInput = {
  areaId: string;
  title: string;
  note?: string | null;
  bucket?: BucketId;
  /** Local date YYYY-MM-DD. */
  dueDate?: string | null;
  /** Local HH:mm, needs dueDate. */
  dueTime?: string | null;
  /** Minutes before due; null = no reminder (mobile notifications only). */
  remindBefore?: number | null;
  /** Needs dueDate. Defaults (weekday / day of month) are filled from dueDate on save. */
  recurrence?: Recurrence | null;
  amount?: number | null;
  walletId?: string | null;
  /** Must be an expense category. */
  categoryId?: string | null;
  /** Manual order within (area, bucket). Default on create: after the last task of that cell. */
  sortOrder?: number;
};

export type TaskAreaInput = {
  name: string;
  /** 1–8 of A–Z/0–9; lowercased input is uppercased. Unique per user. */
  code: string;
  color?: string;
  /** One of CATEGORY_ICONS (src/lib/constants.ts). */
  icon?: string;
  /** null = no schedule ("anytime"). */
  schedule?: AreaSchedule | null;
  archived?: boolean;
  /** Default on create: after the last area. */
  sortOrder?: number;
};

/** Expense recorded when completing a task with a money link; defaults come from the task. */
export type CompleteExpenseInput = {
  amount?: number;
  walletId?: string;
  categoryId?: string | null;
  /** YYYY-MM-DD or ISO; default now. */
  date?: string;
  /** Default: the task title. */
  note?: string;
};

const TASK_INPUT_KEYS = [
  "areaId", "title", "note", "bucket", "dueDate", "dueTime", "remindBefore", "recurrence",
  "amount", "walletId", "categoryId", "sortOrder",
] as const;
const AREA_INPUT_KEYS = ["name", "code", "color", "icon", "schedule", "archived", "sortOrder"] as const;

function pick<T extends object>(src: T, keys: readonly string[]): Partial<T> {
  const out: Record<string, unknown> = {};
  for (const k of keys) if (k in src && (src as Record<string, unknown>)[k] !== undefined) out[k] = (src as Record<string, unknown>)[k];
  return out as Partial<T>;
}

function revalidate(money = false) {
  revalidatePath("/tasks");
  revalidatePath("/dashboard");
  if (money) {
    revalidatePath("/transactions");
    revalidatePath("/wallets");
  }
}

/** Map expected failures to `{ok:false,error}`; unexpected ones are logged and generic. */
async function run<T extends object>(fn: () => Promise<T>): Promise<TaskActionResult<T>> {
  try {
    return { ok: true, ...(await fn()) };
  } catch (e) {
    if (e instanceof z.ZodError) return { ok: false, error: e.issues[0]?.message ?? "Invalid data" };
    if (e instanceof TaskError) return { ok: false, error: e.message };
    console.error("[tasks action]", e);
    return { ok: false, error: "Something went wrong" };
  }
}

/**
 * Server-action arguments arrive via React's reply decoding, so a crafted request can
 * pass an object where a string id is expected — which Prisma would read as a filter
 * (`{ id: { not: "" } }`). Reject anything but a plain id string up front.
 */
function assertId(id: unknown, what = "Task"): asserts id is string {
  if (typeof id !== "string" || id.length === 0 || id.length > 128) throw new TaskError(`${what} not found`);
}

function assertIds(ids: unknown, what = "Task"): asserts ids is string[] {
  if (!Array.isArray(ids)) throw new TaskError(`${what} not found`);
  for (const id of ids) assertId(id, what);
}

async function ownTask(userId: string, id: string) {
  assertId(id);
  const task = await prisma.task.findFirst({ where: { id, userId } });
  if (!task) throw new TaskError("Task not found");
  return task;
}

async function ownArea(userId: string, id: string) {
  assertId(id, "Area");
  const area = await prisma.taskArea.findFirst({ where: { id, userId } });
  if (!area) throw new TaskError("Area not found");
  return area;
}

// ---------- Tasks ----------

export async function createTask(input: TaskInput): Promise<TaskActionResult<{ id: string }>> {
  const user = await requireUser();
  const res = await run(async () => {
    const id = randomUUID();
    const fields = pick(input, TASK_INPUT_KEYS);
    await prisma.$transaction(async (db) => {
      let sortOrder = fields.sortOrder;
      if (sortOrder === undefined) {
        const last = await db.task.aggregate({
          where: { userId: user.id, areaId: fields.areaId, bucket: fields.bucket ?? "want", done: false },
          _max: { sortOrder: true },
        });
        sortOrder = (last._max.sortOrder ?? -1) + 1;
      }
      await saveTask(db, user.id, id, { ...fields, sortOrder, done: false }, false);
    });
    return { id };
  });
  if (res.ok) revalidate();
  return res;
}

/** Patch a task's editable fields (anything omitted keeps its value). */
export async function updateTask(id: string, patch: Partial<TaskInput>): Promise<TaskActionResult> {
  const user = await requireUser();
  const res = await run(async () => {
    assertId(id);
    await prisma.$transaction(async (db) => {
      const existing = await db.task.findFirst({ where: { id, userId: user.id } });
      if (!existing) throw new TaskError("Task not found");
      await saveTask(db, user.id, id, { ...taskRowToInput(existing), ...pick(patch, TASK_INPUT_KEYS) }, true);
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

export async function deleteTask(id: string): Promise<TaskActionResult> {
  const user = await requireUser();
  const res = await run(async () => {
    await ownTask(user.id, id);
    await deleteSynced(user.id, "tasks", id);
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

/**
 * Mark a task done. A recurring task also gets its next occurrence (deterministic id
 * `<seriesId>_<YYYYMMDD>`; returned as `nextId`). With `recordExpense` (true = task's
 * amount/wallet/category, or overrides) an expense is recorded through the ledger and
 * linked as `transactionId` — unless the task already has one. Completing an already
 * done task only records a requested, not-yet-linked expense.
 */
export async function completeTask(
  id: string,
  opts: { recordExpense?: boolean | CompleteExpenseInput } = {},
): Promise<TaskActionResult<{ nextId: string | null; transactionId: string | null }>> {
  const user = await requireUser();
  let money = false;
  const res = await run(() => {
    assertId(id);
    return prisma.$transaction(async (db) => {
      const task = await db.task.findFirst({ where: { id, userId: user.id } });
      if (!task) throw new TaskError("Task not found");

      let transactionId = task.transactionId;
      const exp = opts.recordExpense === true ? {} : opts.recordExpense || null;
      if (exp && !transactionId) {
        const p = transactionSchema.parse({
          type: "expense",
          amount: exp.amount ?? task.amount ?? undefined,
          walletId: exp.walletId ?? task.walletId ?? "",
          categoryId: exp.categoryId !== undefined ? exp.categoryId : task.categoryId,
          note: exp.note ?? task.title,
          date: exp.date ?? new Date(),
        });
        const refs = await validateTransactionRefs(db, user.id, p).catch((err: unknown) => {
          throw new TaskError(err instanceof Error ? err.message : "Invalid wallet/category");
        });
        // validateTransactionRefs only checks ownership; an override must still be an expense category.
        if (refs.categoryId) {
          const cat = await db.category.findFirst({ where: { id: refs.categoryId, userId: user.id }, select: { type: true } });
          if (cat?.type !== "expense") throw new TaskError("A task's category must be an expense category");
        }
        const tx = await createLedgerTransaction(db, user.id, { ...p, ...refs });
        transactionId = tx.id;
        money = true;
      }

      let nextId: string | null = null;
      if (!task.done) {
        await db.task.update({ where: { id }, data: { done: true, doneAt: new Date(), transactionId } });
        nextId = await createNextOccurrence(db, user.id, task);
      } else if (transactionId !== task.transactionId) {
        await db.task.update({ where: { id }, data: { transactionId } });
      }
      return { nextId, transactionId };
    });
  });
  if (res.ok) revalidate(money);
  return res;
}

/**
 * Mark a task not done. The next occurrence of a recurring task is NOT deleted.
 * `deleteExpense: true` also deletes the linked expense (reversing its balance effect).
 */
export async function uncompleteTask(id: string, opts: { deleteExpense?: boolean } = {}): Promise<TaskActionResult> {
  const user = await requireUser();
  let files: string[] = [];
  const res = await run(async () => {
    assertId(id);
    await prisma.$transaction(async (db) => {
      const task = await db.task.findFirst({ where: { id, userId: user.id } });
      if (!task) throw new TaskError("Task not found");
      if (opts.deleteExpense && task.transactionId) {
        const tx = await db.transaction.findFirst({ where: { id: task.transactionId, userId: user.id } });
        if (tx) files = await deleteLedgerTransaction(db, tx); // also nulls task.transactionId
      }
      await db.task.update({ where: { id }, data: { done: false, doneAt: null } });
    });
    return {};
  });
  if (res.ok) {
    await deleteUnreferencedUploads(files);
    revalidate(!!opts.deleteExpense);
  }
  return res;
}

/**
 * Drag & drop: put `orderedIds` (all the user's tasks) into the cell (area, bucket) in
 * that order (sortOrder = index). Tasks moved from another cell change area/bucket.
 */
export async function reorderTasks(
  cell: { areaId: string; bucket: BucketId },
  orderedIds: string[],
): Promise<TaskActionResult> {
  const user = await requireUser();
  const res = await run(async () => {
    if (!BUCKET_IDS.includes(cell.bucket)) throw new TaskError("Invalid bucket");
    assertId(cell.areaId, "Area");
    assertIds(orderedIds);
    const ids = [...new Set(orderedIds)];
    await prisma.$transaction(async (db) => {
      const area = await db.taskArea.findFirst({ where: { id: cell.areaId, userId: user.id }, select: { id: true } });
      if (!area) throw new TaskError("Area not found");
      const owned = await db.task.count({ where: { id: { in: ids }, userId: user.id } });
      if (owned !== ids.length) throw new TaskError("Task not found");
      for (const [i, id] of ids.entries()) {
        await db.task.update({ where: { id }, data: { areaId: cell.areaId, bucket: cell.bucket, sortOrder: i } });
      }
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

/** Move one task to another area and/or bucket (and optionally a sortOrder, see `sortOrderBetween`). */
export async function moveTask(
  id: string,
  to: { areaId?: string; bucket?: BucketId; sortOrder?: number },
): Promise<TaskActionResult> {
  return updateTask(id, pick(to, ["areaId", "bucket", "sortOrder"]));
}

// ---------- Areas ----------

export async function createTaskArea(input: TaskAreaInput): Promise<TaskActionResult<{ id: string }>> {
  const user = await requireUser();
  const res = await run(async () => {
    const fields = pick(input, AREA_INPUT_KEYS);
    if (fields.sortOrder === undefined) {
      const last = await prisma.taskArea.aggregate({ where: { userId: user.id }, _max: { sortOrder: true } });
      fields.sortOrder = (last._max.sortOrder ?? -1) + 1;
    }
    const data = areaToDb(taskAreaSchema.parse(fields));
    const clash = await prisma.taskArea.findFirst({ where: { userId: user.id, code: data.code }, select: { id: true } });
    if (clash) throw new TaskError(`Code ${data.code} is already used by another area`);
    const id = randomUUID();
    await prisma.taskArea.create({ data: { id, userId: user.id, ...data } });
    return { id };
  });
  if (res.ok) revalidate();
  return res;
}

/** Patch an area (name, code, color, icon, schedule, archived, sortOrder). */
export async function updateTaskArea(id: string, patch: Partial<TaskAreaInput>): Promise<TaskActionResult> {
  const user = await requireUser();
  const res = await run(async () => {
    const area = await ownArea(user.id, id);
    const merged = {
      name: area.name,
      code: area.code,
      color: area.color,
      icon: area.icon,
      schedule: parseSchedule(area.schedule),
      archived: area.archived,
      sortOrder: area.sortOrder,
      ...pick(patch, AREA_INPUT_KEYS),
    };
    const data = areaToDb(taskAreaSchema.parse(merged));
    const clash = await prisma.taskArea.findFirst({
      where: { userId: user.id, code: data.code, id: { not: id } },
      select: { id: true },
    });
    if (clash) throw new TaskError(`Code ${data.code} is already used by another area`);
    await prisma.taskArea.update({ where: { id }, data });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

/** Delete an area and all its tasks (tombstoned for sync). */
export async function deleteTaskArea(id: string): Promise<TaskActionResult> {
  const user = await requireUser();
  const res = await run(async () => {
    await ownArea(user.id, id);
    await deleteSynced(user.id, "taskAreas", id);
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

/** Set area order: sortOrder = index in `orderedIds` (all must be the user's). */
export async function reorderTaskAreas(orderedIds: string[]): Promise<TaskActionResult> {
  const user = await requireUser();
  const res = await run(async () => {
    assertIds(orderedIds, "Area");
    const ids = [...new Set(orderedIds)];
    await prisma.$transaction(async (db) => {
      const owned = await db.taskArea.count({ where: { id: { in: ids }, userId: user.id } });
      if (owned !== ids.length) throw new TaskError("Area not found");
      for (const [i, id] of ids.entries()) await db.taskArea.update({ where: { id }, data: { sortOrder: i } });
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

/**
 * Seed Kerjaan + Keseharian if the user has no areas (idempotent). Pages can also call
 * `ensureDefaultTaskAreas(prisma, userId)` from src/lib/tasks-server.ts directly while rendering.
 */
export async function ensureDefaultAreas(): Promise<TaskActionResult<{ created: number }>> {
  const user = await requireUser();
  const res = await run(async () => ({ created: await ensureDefaultTaskAreas(prisma, user.id) }));
  if (res.ok && res.created > 0) revalidate();
  return res;
}
