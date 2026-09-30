import type { Metadata } from "next";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { reminderStatus } from "@/lib/reminders";
import { ReminderBoard, type ReminderDTO } from "./reminder-board";

export const metadata: Metadata = { title: "Pengingat — Ghina" };

/** Done reminders shown (most recent first). */
const DONE_LIMIT = 50;

export default async function RemindersPage() {
  const user = await requireUser();
  const [open, done] = await Promise.all([
    prisma.reminder.findMany({ where: { userId: user.id, done: false }, orderBy: { dueAt: "asc" } }),
    prisma.reminder.findMany({
      where: { userId: user.id, done: true },
      orderBy: [{ doneAt: "desc" }, { dueAt: "desc" }],
      take: DONE_LIMIT,
    }),
  ]);

  const now = new Date();
  const toDTO = (r: (typeof open)[number]): ReminderDTO => ({
    id: r.id,
    title: r.title,
    notes: r.notes,
    dueAt: r.dueAt.toISOString(),
    recurrence: r.recurrence,
    done: r.done,
    doneAt: r.doneAt?.toISOString() ?? null,
    status: reminderStatus(r, now),
  });

  return (
    <ReminderBoard reminders={[...open, ...done].map(toDTO)} />
  );
}
