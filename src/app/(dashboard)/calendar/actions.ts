"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { deleteSynced } from "@/lib/sync-deletes";
import { assertId, assertObject, pick, runAction, UserError, type ActionResult } from "@/lib/action-utils";
import { calendarEventSchema } from "@/lib/schemas";

/**
 * Server actions of the web Calendar page. Plain-object arguments, results
 * `{ ok: true, … } | { ok: false, error }`. Validation is shared with mobile sync
 * (`calendarEventSchema` in src/lib/schemas.ts); deletes are tombstoned.
 */

export type CalendarEventInput = {
  title: string;
  notes?: string | null;
  /** ISO instant; all-day: `YYYY-MM-DDT00:00:00.000Z` (the local day). */
  startAt: string;
  endAt?: string | null;
  allDay?: boolean;
  color?: string | null;
  location?: string | null;
};

const KEYS = ["title", "notes", "startAt", "endAt", "allDay", "color", "location"] as const;
const NOT_FOUND = "Acara tidak ditemukan";

function revalidate() {
  revalidatePath("/calendar");
}

async function own(userId: string, id: unknown) {
  assertId(id, NOT_FOUND);
  const e = await prisma.calendarEvent.findFirst({ where: { id, userId } });
  if (!e) throw new UserError(NOT_FOUND);
  return e;
}

export async function createCalendarEvent(input: CalendarEventInput): Promise<ActionResult<{ id: string }>> {
  const user = await requireUser(); // outside runAction: it redirects
  return runAction("calendar", async () => {
    assertObject(input);
    const data = calendarEventSchema.parse(pick(input, KEYS));
    const id = randomUUID();
    await prisma.calendarEvent.create({ data: { id, userId: user.id, ...data } });
    revalidate();
    return { id };
  });
}

export async function updateCalendarEvent(id: string, patch: Partial<CalendarEventInput>): Promise<ActionResult> {
  const user = await requireUser();
  return runAction("calendar", async () => {
    assertObject(patch);
    const e = await own(user.id, id);
    const current = {
      title: e.title,
      notes: e.notes,
      startAt: e.startAt.toISOString(),
      endAt: e.endAt?.toISOString() ?? null,
      allDay: e.allDay,
      color: e.color,
      location: e.location,
    };
    const data = calendarEventSchema.parse({ ...current, ...pick(patch, KEYS) });
    await prisma.calendarEvent.update({ where: { id: e.id }, data });
    revalidate();
    return {};
  });
}

export async function deleteCalendarEvent(id: string): Promise<ActionResult> {
  const user = await requireUser();
  return runAction("calendar", async () => {
    const e = await own(user.id, id);
    await deleteSynced(user.id, "calendarEvents", e.id);
    revalidate();
    return {};
  });
}
