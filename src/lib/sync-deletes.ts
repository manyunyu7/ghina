import { randomUUID } from "node:crypto";
import { prisma } from "@/lib/prisma";
import { deleteLedgerTransaction, type Db } from "@/lib/ledger";
import { parsePhotos } from "@/lib/photos";
import { writeTombstones, type SyncEntity } from "@/lib/tombstones";
import { deleteUnreferencedUploads } from "@/lib/uploads";

/**
 * Every delete of a synced row goes through here (or `deleteLedgerTransaction`),
 * so each one leaves a SyncTombstone for mobile clients. An ESLint rule forbids
 * calling `.delete()` / `.deleteMany()` on synced models anywhere else.
 *
 * Cascades mirror docs/mobile-sync.md and are done explicitly (not by the DB's
 * onDelete) so cascaded deletes are tombstoned and nulled rows get a fresh updatedAt.
 *
 * Helpers that run inside a DB transaction return the upload URLs whose files should
 * be removed; callers pass them to `deleteUnreferencedUploads` after the commit.
 */

/**
 * Delete a wallet: its transactions (either side of a transfer) are deleted and
 * tombstoned WITHOUT touching the other wallet's balance (same as the old DB cascade);
 * subscriptions/planned/tasks lose their walletId, tasks linked to a deleted
 * transaction lose their transactionId.
 */
export async function deleteWalletCascade(db: Db, userId: string, walletId: string): Promise<string[]> {
  // Every query is scoped to the user: a foreign id deletes nothing.
  if (!(await db.wallet.findFirst({ where: { id: walletId, userId }, select: { id: true } }))) return [];
  const txs = await db.transaction.findMany({
    where: { userId, OR: [{ walletId }, { toWalletId: walletId }] },
    select: { id: true, photos: true },
  });
  const txIds = txs.map((t) => t.id);
  await db.task.updateMany({ where: { userId, transactionId: { in: txIds } }, data: { transactionId: null } });
  await db.transaction.deleteMany({ where: { userId, id: { in: txIds } } });
  await writeTombstones(db, userId, "transactions", txIds);

  await db.subscription.updateMany({ where: { userId, walletId }, data: { walletId: null } });
  await db.plannedTransaction.updateMany({ where: { userId, walletId }, data: { walletId: null } });
  await db.task.updateMany({ where: { userId, walletId }, data: { walletId: null } });

  await db.wallet.delete({ where: { id: walletId } });
  await writeTombstones(db, userId, "wallets", [walletId]);
  return txs.flatMap((t) => parsePhotos(t.photos));
}

/** Delete a category: rows referencing it lose their categoryId; its budgets are deleted. */
export async function deleteCategoryCascade(db: Db, userId: string, categoryId: string) {
  if (!(await db.category.findFirst({ where: { id: categoryId, userId }, select: { id: true } }))) return;
  await db.transaction.updateMany({ where: { userId, categoryId }, data: { categoryId: null } });
  await db.subscription.updateMany({ where: { userId, categoryId }, data: { categoryId: null } });
  await db.plannedTransaction.updateMany({ where: { userId, categoryId }, data: { categoryId: null } });
  await db.task.updateMany({ where: { userId, categoryId }, data: { categoryId: null } });

  const budgets = await db.budget.findMany({ where: { userId, categoryId }, select: { id: true } });
  const budgetIds = budgets.map((b) => b.id);
  await db.budget.deleteMany({ where: { id: { in: budgetIds } } });
  await writeTombstones(db, userId, "budgets", budgetIds);

  await db.category.delete({ where: { id: categoryId } });
  await writeTombstones(db, userId, "categories", [categoryId]);
}

/** Delete a task area and all its tasks (each tombstoned). */
export async function deleteTaskAreaCascade(db: Db, userId: string, areaId: string) {
  if (!(await db.taskArea.findFirst({ where: { id: areaId, userId }, select: { id: true } }))) return;
  const tasks = await db.task.findMany({ where: { userId, areaId }, select: { id: true } });
  const taskIds = tasks.map((t) => t.id);
  await db.task.deleteMany({ where: { userId, id: { in: taskIds } } });
  await writeTombstones(db, userId, "tasks", taskIds);

  await db.taskArea.delete({ where: { id: areaId } });
  await writeTombstones(db, userId, "taskAreas", [areaId]);
}

/** Whether row `id` of `entity` exists and belongs to `userId`. */
async function ownsRow(db: Db, userId: string, entity: SyncEntity, id: string): Promise<boolean> {
  const q = { where: { id, userId }, select: { id: true } } as const;
  switch (entity) {
    case "wallets":
      return !!(await db.wallet.findFirst(q));
    case "categories":
      return !!(await db.category.findFirst(q));
    case "transactions":
      return !!(await db.transaction.findFirst(q));
    case "budgets":
      return !!(await db.budget.findFirst(q));
    case "subscriptions":
      return !!(await db.subscription.findFirst(q));
    case "planned":
      return !!(await db.plannedTransaction.findFirst(q));
    case "prayers":
      return !!(await db.prayerEntry.findFirst(q));
    case "health":
      return !!(await db.healthEntry.findFirst(q));
    case "food":
      return !!(await db.foodLog.findFirst(q));
    case "taskAreas":
      return !!(await db.taskArea.findFirst(q));
    case "tasks":
      return !!(await db.task.findFirst(q));
  }
}

/**
 * Delete one synced row by wire entity name, applying cascades / ledger reversal.
 * Callers check ownership first; as defense in depth a row that is missing or
 * belongs to another user is left alone (no-op, no tombstone).
 * Returns upload URLs to remove once the DB transaction has committed.
 */
export async function deleteSyncedRow(db: Db, userId: string, entity: SyncEntity, id: string): Promise<string[]> {
  if (!(await ownsRow(db, userId, entity, id))) return [];
  let files: string[] = [];
  switch (entity) {
    case "wallets":
      return deleteWalletCascade(db, userId, id);
    case "categories":
      await deleteCategoryCascade(db, userId, id);
      return [];
    case "transactions": {
      const existing = await db.transaction.findUniqueOrThrow({ where: { id } });
      return deleteLedgerTransaction(db, existing);
    }
    case "taskAreas":
      await deleteTaskAreaCascade(db, userId, id);
      return [];
    case "budgets":
      await db.budget.delete({ where: { id } });
      break;
    case "subscriptions":
      await db.subscription.delete({ where: { id } });
      break;
    case "planned":
      await db.plannedTransaction.delete({ where: { id } });
      break;
    case "prayers":
      await db.prayerEntry.delete({ where: { id } });
      break;
    case "health":
      await db.healthEntry.delete({ where: { id } });
      break;
    case "food": {
      const row = await db.foodLog.delete({ where: { id } });
      if (row.photoUrl) files = [row.photoUrl];
      break;
    }
    case "tasks":
      await db.task.delete({ where: { id } });
      break;
  }
  await writeTombstones(db, userId, entity, [id]);
  return files;
}

/** Convenience: `deleteSyncedRow` in its own DB transaction, then file cleanup. */
export async function deleteSynced(userId: string, entity: SyncEntity, id: string) {
  const files = await prisma.$transaction((db) => deleteSyncedRow(db, userId, entity, id));
  await deleteUnreferencedUploads(files);
}

/**
 * "Reset all data" (web settings): wipes the user's finance data and rotates
 * `syncEpoch`, which makes every mobile client wipe its local copy and re-pull.
 * No tombstones are needed — old ones are dropped too. Subscriptions, planned, tasks
 * and task areas survive with their wallet/category/transaction links nulled
 * (prayers, health and food are untouched). Transaction photo files are removed.
 */
export async function resetFinanceData(userId: string) {
  const files = await prisma.$transaction(async (db) => {
    const txs = await db.transaction.findMany({ where: { userId, photos: { not: "[]" } }, select: { photos: true } });
    await db.subscription.updateMany({ where: { userId }, data: { walletId: null, categoryId: null } });
    await db.plannedTransaction.updateMany({ where: { userId }, data: { walletId: null, categoryId: null } });
    await db.task.updateMany({
      where: { userId, OR: [{ walletId: { not: null } }, { categoryId: { not: null } }, { transactionId: { not: null } }] },
      data: { walletId: null, categoryId: null, transactionId: null },
    });
    await db.budget.deleteMany({ where: { userId } });
    await db.transaction.deleteMany({ where: { userId } });
    await db.category.deleteMany({ where: { userId } });
    await db.wallet.deleteMany({ where: { userId } });
    await db.syncTombstone.deleteMany({ where: { userId } });
    await db.user.update({ where: { id: userId }, data: { syncEpoch: randomUUID() } });
    return txs.flatMap((t) => parsePhotos(t.photos));
  });
  await deleteUnreferencedUploads(files);
}
