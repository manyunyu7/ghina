import { randomUUID } from "node:crypto";
import { prisma } from "@/lib/prisma";
import { deleteLedgerTransaction, type Db } from "@/lib/ledger";
import { parsePhotos } from "@/lib/photos";
import { writeTombstones, type SyncEntity } from "@/lib/tombstones";
import { deleteUnreferencedUploads } from "@/lib/uploads";
import { parseAudio, parseImageList } from "@/lib/notes";
import {
  clearPillar,
  detachContentItem,
  detachNote,
  detachTasks,
  detachTransactions,
  stripLabelFromNotes,
} from "@/lib/sync-links";

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
 * subscriptions/planned/tasks/assets lose their walletId, tasks linked to a deleted
 * transaction lose their transactionId, trades their cashTransactionId (holdings unchanged).
 */
export async function deleteWalletCascade(db: Db, userId: string, walletId: string): Promise<string[]> {
  // Every query is scoped to the user: a foreign id deletes nothing.
  if (!(await db.wallet.findFirst({ where: { id: walletId, userId }, select: { id: true } }))) return [];
  const txs = await db.transaction.findMany({
    where: { userId, OR: [{ walletId }, { toWalletId: walletId }] },
    select: { id: true, photos: true },
  });
  const txIds = txs.map((t) => t.id);
  await detachTransactions(db, userId, txIds);
  await db.transaction.deleteMany({ where: { userId, id: { in: txIds } } });
  await writeTombstones(db, userId, "transactions", txIds);

  await db.subscription.updateMany({ where: { userId, walletId }, data: { walletId: null } });
  await db.plannedTransaction.updateMany({ where: { userId, walletId }, data: { walletId: null } });
  await db.task.updateMany({ where: { userId, walletId }, data: { walletId: null } });
  await db.asset.updateMany({ where: { userId, walletId }, data: { walletId: null } });

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
  await detachTasks(db, userId, taskIds);
  await db.task.deleteMany({ where: { userId, id: { in: taskIds } } });
  await writeTombstones(db, userId, "tasks", taskIds);

  await db.taskArea.delete({ where: { id: areaId } });
  await writeTombstones(db, userId, "taskAreas", [areaId]);
}

/** Delete a note label; its id is stripped from every note's `labels` (notes re-sync). */
export async function deleteNoteLabelCascade(db: Db, userId: string, labelId: string) {
  if (!(await db.noteLabel.findFirst({ where: { id: labelId, userId }, select: { id: true } }))) return;
  await stripLabelFromNotes(db, userId, labelId);
  await db.noteLabel.delete({ where: { id: labelId } });
  await writeTombstones(db, userId, "noteLabels", [labelId]);
}

/** Delete a note: content items lose `noteId`. Returns its photo + audio URLs (file cleanup). */
export async function deleteNoteCascade(db: Db, userId: string, noteId: string): Promise<string[]> {
  const note = await db.note.findFirst({ where: { id: noteId, userId }, select: { photos: true, audio: true } });
  if (!note) return [];
  await detachNote(db, userId, noteId);
  await db.note.delete({ where: { id: noteId } });
  await writeTombstones(db, userId, "notes", [noteId]);
  return [...parseImageList(note.photos), ...parseAudio(note.audio).map((a) => a.url)];
}

/** Delete posts `ids` of the user (tombstoned). */
async function deletePosts(db: Db, userId: string, where: { contentId?: string; accountId?: string }) {
  const posts = await db.contentPost.findMany({ where: { userId, ...where }, select: { id: true } });
  const ids = posts.map((p) => p.id);
  await db.contentPost.deleteMany({ where: { userId, id: { in: ids } } });
  await writeTombstones(db, userId, "contentPosts", ids);
}

/** Delete a social account and all its posts (each tombstoned). */
export async function deleteSocialAccountCascade(db: Db, userId: string, accountId: string) {
  if (!(await db.socialAccount.findFirst({ where: { id: accountId, userId }, select: { id: true } }))) return;
  await deletePosts(db, userId, { accountId });
  await db.socialAccount.delete({ where: { id: accountId } });
  await writeTombstones(db, userId, "socialAccounts", [accountId]);
}

/**
 * Delete a content item: its posts are deleted (tombstoned), notes lose
 * `linkedContentId`. Returns its photo URLs (file cleanup).
 */
export async function deleteContentItemCascade(db: Db, userId: string, itemId: string): Promise<string[]> {
  const item = await db.contentItem.findFirst({ where: { id: itemId, userId }, select: { photos: true } });
  if (!item) return [];
  await deletePosts(db, userId, { contentId: itemId });
  await detachContentItem(db, userId, itemId);
  await db.contentItem.delete({ where: { id: itemId } });
  await writeTombstones(db, userId, "contentItems", [itemId]);
  return parseImageList(item.photos);
}

/** Delete a content pillar: items with that pillar name get `pillar = null`. */
export async function deleteContentPillarCascade(db: Db, userId: string, pillarId: string) {
  const pillar = await db.contentPillar.findFirst({ where: { id: pillarId, userId }, select: { name: true } });
  if (!pillar) return;
  await clearPillar(db, userId, pillar.name);
  await db.contentPillar.delete({ where: { id: pillarId } });
  await writeTombstones(db, userId, "contentPillars", [pillarId]);
}

/** Delete a habit and all its logs (each tombstoned). */
export async function deleteHabitCascade(db: Db, userId: string, habitId: string) {
  if (!(await db.habit.findFirst({ where: { id: habitId, userId }, select: { id: true } }))) return;
  const logs = await db.habitLog.findMany({ where: { userId, habitId }, select: { id: true } });
  const ids = logs.map((l) => l.id);
  await db.habitLog.deleteMany({ where: { userId, id: { in: ids } } });
  await writeTombstones(db, userId, "habitLogs", ids);
  await db.habit.delete({ where: { id: habitId } });
  await writeTombstones(db, userId, "habits", [habitId]);
}

/**
 * Delete a trade and its linked cash transaction (investment / dividend income) through
 * the ledger, so the wallet balance is reversed (docs/investments.md). Returns the
 * transaction's photo URLs (file cleanup).
 */
export async function deleteAssetTradeCascade(db: Db, userId: string, tradeId: string): Promise<string[]> {
  const trade = await db.assetTrade.findFirst({ where: { id: tradeId, userId }, select: { cashTransactionId: true } });
  if (!trade) return [];
  let files: string[] = [];
  if (trade.cashTransactionId) {
    const tx = await db.transaction.findFirst({ where: { id: trade.cashTransactionId, userId } });
    if (tx) files = await deleteLedgerTransaction(db, tx);
  }
  await db.assetTrade.delete({ where: { id: tradeId } });
  await writeTombstones(db, userId, "assetTrades", [tradeId]);
  return files;
}

/** Delete an asset: every trade goes too (with its linked cash transaction, balances reversed). */
export async function deleteAssetCascade(db: Db, userId: string, assetId: string): Promise<string[]> {
  if (!(await db.asset.findFirst({ where: { id: assetId, userId }, select: { id: true } }))) return [];
  const trades = await db.assetTrade.findMany({ where: { userId, assetId }, select: { id: true } });
  const files: string[] = [];
  for (const t of trades) files.push(...(await deleteAssetTradeCascade(db, userId, t.id)));
  await db.asset.delete({ where: { id: assetId } });
  await writeTombstones(db, userId, "assets", [assetId]);
  return files;
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
    case "noteLabels":
      return !!(await db.noteLabel.findFirst(q));
    case "notes":
      return !!(await db.note.findFirst(q));
    case "socialAccounts":
      return !!(await db.socialAccount.findFirst(q));
    case "contentPillars":
      return !!(await db.contentPillar.findFirst(q));
    case "contentItems":
      return !!(await db.contentItem.findFirst(q));
    case "contentPosts":
      return !!(await db.contentPost.findFirst(q));
    case "habits":
      return !!(await db.habit.findFirst(q));
    case "habitLogs":
      return !!(await db.habitLog.findFirst(q));
    case "assets":
      return !!(await db.asset.findFirst(q));
    case "assetTrades":
      return !!(await db.assetTrade.findFirst(q));
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
    case "noteLabels":
      await deleteNoteLabelCascade(db, userId, id);
      return [];
    case "notes":
      return deleteNoteCascade(db, userId, id);
    case "socialAccounts":
      await deleteSocialAccountCascade(db, userId, id);
      return [];
    case "contentPillars":
      await deleteContentPillarCascade(db, userId, id);
      return [];
    case "contentItems":
      return deleteContentItemCascade(db, userId, id);
    case "habits":
      await deleteHabitCascade(db, userId, id);
      return [];
    case "habitLogs":
      await db.habitLog.delete({ where: { id } });
      break;
    case "assets":
      return deleteAssetCascade(db, userId, id);
    case "assetTrades":
      return deleteAssetTradeCascade(db, userId, id);
    case "contentPosts":
      await db.contentPost.delete({ where: { id } });
      break;
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
      await detachTasks(db, userId, [id]);
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
 * (prayers, health and food are untouched). Notes and the content planner survive too:
 * notes lose `linkedTransactionId`, sponsors their `transactionId` (paid stays).
 * Habits are untouched. Assets and trades survive (portfolio history is not wallet data):
 * assets lose `walletId`, trades `cashTransactionId`; portfolio snapshots stay.
 * Transaction photo files are removed unless a note/content item still uses them.
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
    await db.asset.updateMany({ where: { userId, walletId: { not: null } }, data: { walletId: null } });
    const txIds = (await db.transaction.findMany({ where: { userId }, select: { id: true } })).map((t) => t.id);
    await detachTransactions(db, userId, txIds);
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
