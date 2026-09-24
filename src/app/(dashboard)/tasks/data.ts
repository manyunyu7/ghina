import type { Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { BUCKET_IDS, compareAreas, compareTasks, parseRecurrence, parseSchedule, type BucketId } from "@/lib/tasks";
import { ensureDefaultTaskAreas } from "@/lib/tasks-server";
import type { AreaDTO, BoardData, TaskDTO } from "./types";

/** How many completed tasks the "Selesai" list shows (most recent first). */
const DONE_LIMIT = 200;

type TaskRow = Prisma.TaskGetPayload<object>;
type AreaRow = Prisma.TaskAreaGetPayload<object>;

export function toTaskDTO(t: TaskRow): TaskDTO {
  return {
    id: t.id,
    areaId: t.areaId,
    title: t.title,
    note: t.note,
    bucket: (BUCKET_IDS.includes(t.bucket as BucketId) ? t.bucket : "want") as BucketId,
    dueDate: t.dueDate,
    dueTime: t.dueTime,
    remindBefore: t.remindBefore,
    recurrence: parseRecurrence(t.recurrence),
    seriesId: t.seriesId,
    done: t.done,
    doneAt: t.doneAt?.toISOString() ?? null,
    sortOrder: t.sortOrder,
    amount: t.amount,
    walletId: t.walletId,
    categoryId: t.categoryId,
    transactionId: t.transactionId,
    createdAt: t.createdAt.toISOString(),
  };
}

export function toAreaDTO(a: AreaRow): AreaDTO {
  return {
    id: a.id,
    name: a.name,
    code: a.code,
    color: a.color,
    icon: a.icon,
    schedule: parseSchedule(a.schedule),
    sortOrder: a.sortOrder,
    archived: a.archived,
  };
}

/** Areas (seeding the defaults on first visit), ordered. */
export async function getTaskAreas(userId: string): Promise<AreaDTO[]> {
  await ensureDefaultTaskAreas(prisma, userId);
  const rows = await prisma.taskArea.findMany({ where: { userId } });
  return rows.map(toAreaDTO).sort(compareAreas);
}

export async function getBoardData(userId: string, currency: string): Promise<BoardData> {
  const areas = await getTaskAreas(userId);
  const [open, done, wallets, categories] = await Promise.all([
    prisma.task.findMany({ where: { userId, done: false } }),
    prisma.task.findMany({ where: { userId, done: true }, orderBy: { doneAt: "desc" }, take: DONE_LIMIT }),
    prisma.wallet.findMany({
      where: { userId, archived: false },
      select: { id: true, name: true, currency: true },
      orderBy: { createdAt: "asc" },
    }),
    prisma.category.findMany({
      where: { userId, type: "expense" },
      select: { id: true, name: true, color: true, icon: true },
      orderBy: { name: "asc" },
    }),
  ]);
  return {
    areas,
    tasks: open.map(toTaskDTO).sort(compareTasks),
    doneTasks: done.map(toTaskDTO),
    wallets,
    categories,
    currency,
  };
}

/** Dashboard card: non-archived areas + undone FIRE tasks (focus is picked on the client). */
export async function getFireTasks(userId: string) {
  const [areas, tasks] = await Promise.all([
    prisma.taskArea.findMany({ where: { userId, archived: false } }),
    prisma.task.findMany({ where: { userId, done: false, bucket: "fire" } }),
  ]);
  return { areas: areas.map(toAreaDTO).sort(compareAreas), tasks: tasks.map(toTaskDTO).sort(compareTasks) };
}
