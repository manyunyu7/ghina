"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import type { Prisma } from "@prisma/client";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { deleteSynced } from "@/lib/sync-deletes";
import { assertId, assertObject, pick, runAction, UserError, type ActionResult } from "@/lib/action-utils";
import { reminderSchema, type ReminderRecurrence } from "@/lib/schemas";
import { nextReminderDue, safeTimeZone } from "@/lib/reminders";

/**
 * Server actions of the web Reminders page. Plain-object arguments, results
 * `{ ok: true, … } | { ok: false, error }`. Validation is shared with mobile sync
 * (`reminderSchema` in src/lib/schemas.ts); deletes are tombstoned.
 */

export type ReminderInput = {
  title: string;
  notes?: string | null;
  /** ISO instant (the browser converts its local date/time). */
  dueAt: string;
  recurrence?: ReminderRecurrence | "none" | null;
};

const KEYS = ["title", "notes", "dueAt", "recurrence"] as const;
const NOT_FOUND = "Pengingat tidak ditemukan";

type Row = Prisma.ReminderGetPayload<object>;

function revalidate() {
  revalidatePath("/reminders");
}

/** A stored row in the `reminderSchema` input shape. */
function rowToInput(r: Row) {
  return {
    title: r.title,
    notes: r.notes,
    dueAt: r.dueAt.toISOString(),
    recurrence: r.recurrence,
    done: r.done,
    doneAt: r.doneAt?.toISOString() ?? null,
  };
}

async function own(userId: string, id: unknown): Promise<Row> {
  assertId(id, NOT_FOUND);
  const r = await prisma.reminder.findFirst({ where: { id, userId } });
  if (!r) throw new UserError(NOT_FOUND);
  return r;
}

export async function createReminder(input: ReminderInput): Promise<ActionResult<{ id: string }>> {
  const user = await requireUser(); // outside runAction: it redirects
  return runAction("reminders", async () => {
    assertObject(input);
    const data = reminderSchema.parse({ ...pick(input, KEYS), done: false });
    const id = randomUUID();
    await prisma.reminder.create({ data: { id, userId: user.id, ...data } });
    revalidate();
    return { id };
  });
}

export async function updateReminder(id: string, patch: Partial<ReminderInput>): Promise<ActionResult> {
  const user = await requireUser();
  return runAction("reminders", async () => {
    assertObject(patch);
    const r = await own(user.id, id);
    const data = reminderSchema.parse({ ...rowToInput(r), ...pick(patch, KEYS) });
    await prisma.reminder.update({ where: { id: r.id }, data });
    revalidate();
    return {};
  });
}

/**
 * Complete a reminder. One-off: done. Repeating: `dueAt` moves to the next occurrence after
 * now (in the browser's `timeZone`), done stays false and doneAt records this completion.
 */
export async function completeReminder(id: string, timeZone?: string): Promise<ActionResult<{ nextDueAt: string | null }>> {
  const user = await requireUser();
  return runAction("reminders", async () => {
    const r = await own(user.id, id);
    const now = new Date();
    const rule = reminderSchema.parse(rowToInput(r)).recurrence;
    if (rule) {
      const next = nextReminderDue(r.dueAt, rule, now, safeTimeZone(timeZone));
      await prisma.reminder.update({ where: { id: r.id }, data: { dueAt: next, done: false, doneAt: now } });
      revalidate();
      return { nextDueAt: next.toISOString() };
    }
    await prisma.reminder.update({ where: { id: r.id }, data: { done: true, doneAt: now } });
    revalidate();
    return { nextDueAt: null };
  });
}

/** Undo "done" on a one-off reminder. */
export async function reopenReminder(id: string): Promise<ActionResult> {
  const user = await requireUser();
  return runAction("reminders", async () => {
    const r = await own(user.id, id);
    await prisma.reminder.update({ where: { id: r.id }, data: { done: false, doneAt: null } });
    revalidate();
    return {};
  });
}

export async function deleteReminder(id: string): Promise<ActionResult> {
  const user = await requireUser();
  return runAction("reminders", async () => {
    const r = await own(user.id, id);
    await deleteSynced(user.id, "reminders", r.id);
    revalidate();
    return {};
  });
}
