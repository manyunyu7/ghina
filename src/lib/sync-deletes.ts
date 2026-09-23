import { randomUUID } from "node:crypto";
import { prisma } from "@/lib/prisma";
import { deleteLedgerTransaction, type Db } from "@/lib/ledger";
import { writeTombstones, type SyncEntity } from "@/lib/tombstones";

/**
 * Every delete of a synced row goes through here (or `deleteLedgerTransaction`),
 * so each one leaves a SyncTombstone for mobile clients. An ESLint rule forbids
 * calling `.delete()` / `.deleteMany()` on synced models anywhere else.
 *
 * Cascades mirror docs/mobile-sync.md and are done explicitly (not by the DB's
 * onDelete) so cascaded deletes are tombstoned and nulled rows get a fresh updatedAt.
 */

/**
 * Delete a wallet: its transactions (either side of a transfer) are deleted and
 * tombstoned WITHOUT touching the other wallet's balance (same as the old DB cascade);
 * subscriptions/planned lose their walletId.
 */
export async function deleteWalletCascade(db: Db, userId: string, walletId: string) {
  const txs = await db.transaction.findMany({
    where: { OR: [{ walletId }, { toWalletId: walletId }] },
    select: { id: true },
  });
  const txIds = txs.map((t) => t.id);
  await db.transaction.deleteMany({ where: { id: { in: txIds } } });
  await writeTombstones(db, userId, "transactions", txIds);

  await db.subscription.updateMany({ where: { walletId }, data: { walletId: null } });
  await db.plannedTransaction.updateMany({ where: { walletId }, data: { walletId: null } });

  await db.wallet.delete({ where: { id: walletId } });
  await writeTombstones(db, userId, "wallets", [walletId]);
}

/** Delete a category: rows referencing it lose their categoryId; its budgets are deleted. */
export async function deleteCategoryCascade(db: Db, userId: string, categoryId: string) {
  await db.transaction.updateMany({ where: { categoryId }, data: { categoryId: null } });
  await db.subscription.updateMany({ where: { categoryId }, data: { categoryId: null } });
  await db.plannedTransaction.updateMany({ where: { categoryId }, data: { categoryId: null } });

  const budgets = await db.budget.findMany({ where: { categoryId }, select: { id: true } });
  const budgetIds = budgets.map((b) => b.id);
  await db.budget.deleteMany({ where: { id: { in: budgetIds } } });
  await writeTombstones(db, userId, "budgets", budgetIds);

  await db.category.delete({ where: { id: categoryId } });
  await writeTombstones(db, userId, "categories", [categoryId]);
}

/**
 * Delete one synced row by wire entity name, applying cascades / ledger reversal.
 * The caller has already verified the row exists and belongs to `userId`.
 */
export async function deleteSyncedRow(db: Db, userId: string, entity: SyncEntity, id: string) {
  switch (entity) {
    case "wallets":
      return deleteWalletCascade(db, userId, id);
    case "categories":
      return deleteCategoryCascade(db, userId, id);
    case "transactions": {
      const existing = await db.transaction.findUniqueOrThrow({ where: { id } });
      return deleteLedgerTransaction(db, existing);
    }
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
    case "food":
      await db.foodLog.delete({ where: { id } });
      break;
  }
  await writeTombstones(db, userId, entity, [id]);
}

/** Convenience: `deleteSyncedRow` in its own DB transaction. */
export function deleteSynced(userId: string, entity: SyncEntity, id: string) {
  return prisma.$transaction((db) => deleteSyncedRow(db, userId, entity, id));
}

/**
 * "Reset all data" (web settings): wipes the user's finance data and rotates
 * `syncEpoch`, which makes every mobile client wipe its local copy and re-pull.
 * No tombstones are needed — old ones are dropped too.
 */
export async function resetFinanceData(userId: string) {
  await prisma.$transaction(async (db) => {
    await db.subscription.updateMany({ where: { userId }, data: { walletId: null, categoryId: null } });
    await db.plannedTransaction.updateMany({ where: { userId }, data: { walletId: null, categoryId: null } });
    await db.budget.deleteMany({ where: { userId } });
    await db.transaction.deleteMany({ where: { userId } });
    await db.category.deleteMany({ where: { userId } });
    await db.wallet.deleteMany({ where: { userId } });
    await db.syncTombstone.deleteMany({ where: { userId } });
    await db.user.update({ where: { id: userId }, data: { syncEpoch: randomUUID() } });
  });
}
