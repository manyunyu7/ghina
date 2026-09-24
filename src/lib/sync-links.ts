import type { Prisma } from "@prisma/client";
import { parseSponsor } from "@/lib/content";
import { nameKey, parseLabelIds, stripLabel, toJson } from "@/lib/notes";

/**
 * Soft links between synced rows that must be cleared when the target is deleted
 * (docs/mobile-sync.md "Deletes"). Done with updates (not the DB's SetNull) so the
 * changed rows get a fresh `updatedAt` and reach mobile clients on the next pull.
 * `Note.editedAt` (its LWW time) is deliberately not bumped: this isn't a user edit.
 * Every query is scoped to `userId`.
 */

type Db = Prisma.TransactionClient;

/**
 * Transactions `ids` are being deleted: tasks lose `transactionId`, notes lose
 * `linkedTransactionId`, and a content item's `sponsor.transactionId` pointing at one of
 * them becomes null (`paid` stays as it was).
 */
export async function detachTransactions(db: Db, userId: string, ids: readonly string[]) {
  if (ids.length === 0) return;
  const list = [...ids];
  await db.task.updateMany({ where: { userId, transactionId: { in: list } }, data: { transactionId: null } });
  await db.note.updateMany({ where: { userId, linkedTransactionId: { in: list } }, data: { linkedTransactionId: null } });
  const set = new Set(list);
  const items = await db.contentItem.findMany({
    where: { userId, sponsor: { contains: '"transactionId":"' } },
    select: { id: true, sponsor: true },
  });
  for (const it of items) {
    const s = parseSponsor(it.sponsor);
    if (s?.transactionId && set.has(s.transactionId)) {
      await db.contentItem.update({ where: { id: it.id }, data: { sponsor: toJson({ ...s, transactionId: null }) } });
    }
  }
}

/** Tasks `ids` are being deleted: notes lose `linkedTaskId`. */
export async function detachTasks(db: Db, userId: string, ids: readonly string[]) {
  if (ids.length === 0) return;
  await db.note.updateMany({ where: { userId, linkedTaskId: { in: [...ids] } }, data: { linkedTaskId: null } });
}

/** Content item `id` is being deleted: notes lose `linkedContentId`. */
export async function detachContentItem(db: Db, userId: string, id: string) {
  await db.note.updateMany({ where: { userId, linkedContentId: id }, data: { linkedContentId: null } });
}

/** Note `id` is being deleted: content items lose `noteId`. */
export async function detachNote(db: Db, userId: string, id: string) {
  await db.contentItem.updateMany({ where: { userId, noteId: id }, data: { noteId: null } });
}

/** Label `labelId` is being deleted: its id is stripped from every note's `labels`. */
export async function stripLabelFromNotes(db: Db, userId: string, labelId: string) {
  const notes = await db.note.findMany({
    where: { userId, labels: { contains: JSON.stringify(labelId) } },
    select: { id: true, labels: true },
  });
  for (const n of notes) {
    const before = parseLabelIds(n.labels);
    const after = stripLabel(before, labelId);
    if (after.length !== before.length) await db.note.update({ where: { id: n.id }, data: { labels: toJson(after) } });
  }
}

/** Ids of the user's content items whose pillar is `name` (case-insensitive). */
async function itemsWithPillar(db: Db, userId: string, name: string): Promise<string[]> {
  const k = nameKey(name);
  const rows = await db.contentItem.findMany({ where: { userId, pillar: { not: null } }, select: { id: true, pillar: true } });
  return rows.filter((r) => nameKey(r.pillar!) === k).map((r) => r.id);
}

/** Pillar `name` is being deleted: content items with that pillar (case-insensitive) get `pillar = null`. */
export async function clearPillar(db: Db, userId: string, name: string) {
  const ids = await itemsWithPillar(db, userId, name);
  if (ids.length) await db.contentItem.updateMany({ where: { userId, id: { in: ids } }, data: { pillar: null } });
}

/** Pillar renamed `from` → `to`: content items follow (case-insensitive match on `from`). */
export async function renamePillar(db: Db, userId: string, from: string, to: string) {
  if (from === to) return;
  const ids = await itemsWithPillar(db, userId, from);
  if (ids.length) await db.contentItem.updateMany({ where: { userId, id: { in: ids } }, data: { pillar: to } });
}
