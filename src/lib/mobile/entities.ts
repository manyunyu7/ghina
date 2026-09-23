import { z } from "zod";
import type { Db } from "@/lib/ledger";
import { createLedgerTransaction, updateLedgerTransaction, validateTransactionRefs } from "@/lib/ledger";
import {
  budgetSchema,
  categorySchema,
  foodSchema,
  healthSchema,
  plannedSchema,
  subscriptionSchema,
  transactionSchema,
  walletSchema,
} from "@/lib/schemas";
import type { SyncEntity } from "@/lib/tombstones";
import { PRAYER_IDS } from "@/app/(dashboard)/prayers/constants";

/**
 * Per-entity sync definitions: how to find a row, list changed rows, and apply
 * an upsert from a mobile push (same validation and ownership rules as the web).
 */

/** A mutation that must be answered with `rejected` (the message goes back to the client). */
export class SyncRejection extends Error {}

export type UpsertOutcome = "applied" | "duplicate";

type Row = { id: string; userId: string; updatedAt: Date };

interface EntityDef<R extends Row = Row> {
  find(db: Db, id: string): Promise<R | null>;
  changedSince(db: Db, userId: string, since: Date): Promise<object[]>;
  /** Timestamp compared with `clientUpdatedAt` for last-write-wins. */
  lwwTime(row: R): Date;
  /** Create (existing = null) or update the row with the pushed data. */
  upsert(db: Db, userId: string, id: string, data: unknown, existing: R | null): Promise<UpsertOutcome>;
}

const since = (userId: string, s: Date) => ({ where: { userId, updatedAt: { gte: s } } });

async function assertWallet(db: Db, userId: string, walletId: string | null | undefined) {
  if (!walletId) return;
  const w = await db.wallet.findFirst({ where: { id: walletId, userId }, select: { id: true } });
  if (!w) throw new SyncRejection("Wallet not found");
}

async function assertCategory(db: Db, userId: string, categoryId: string | null | undefined) {
  if (!categoryId) return;
  const c = await db.category.findFirst({ where: { id: categoryId, userId }, select: { id: true } });
  if (!c) throw new SyncRejection("Category not found");
}

const emptyToNull = (v: string | null | undefined) => (v && v.length > 0 ? v : null);

// balance is optional: honored only when the wallet is created.
const mobileWalletSchema = walletSchema.extend({
  balance: z.number().finite().optional(),
  archived: z.boolean().default(false),
});

const wallets: EntityDef<Row & { editedAt: Date }> = {
  find: (db, id) => db.wallet.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.wallet.findMany(since(userId, s)),
  // updatedAt also moves with every balance change; editedAt only with real edits.
  lwwTime: (row) => row.editedAt,
  async upsert(db, userId, id, data, existing) {
    const { balance, ...d } = mobileWalletSchema.parse(data);
    if (existing) {
      await db.wallet.update({ where: { id }, data: { ...d, editedAt: new Date() } });
    } else {
      await db.wallet.create({ data: { id, userId, ...d, balance: balance ?? 0 } });
    }
    return "applied";
  },
};

const categories: EntityDef = {
  find: (db, id) => db.category.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.category.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing) {
    const d = categorySchema.parse(data);
    if (existing) await db.category.update({ where: { id }, data: d });
    else await db.category.create({ data: { id, userId, ...d } });
    return "applied";
  },
};

const transactions: EntityDef<Row & { type: string; amount: number; walletId: string; toWalletId: string | null }> = {
  find: (db, id) => db.transaction.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.transaction.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing) {
    const p = transactionSchema.parse(data);
    let refs;
    try {
      refs = await validateTransactionRefs(db, userId, p);
    } catch (e) {
      throw new SyncRejection(e instanceof Error ? e.message : "Invalid references");
    }
    const input = { ...p, ...refs };
    // Balance effects go through the ledger, like the web.
    if (existing) await updateLedgerTransaction(db, existing, input);
    else await createLedgerTransaction(db, userId, input, id);
    return "applied";
  },
};

const budgets: EntityDef = {
  find: (db, id) => db.budget.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.budget.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing) {
    const d = budgetSchema.parse(data);
    const category = await db.category.findUnique({ where: { id: d.categoryId }, select: { userId: true, type: true } });
    if (!category || category.userId !== userId || category.type !== "expense") {
      throw new SyncRejection("Invalid category");
    }
    const holder = await db.budget.findUnique({
      where: { userId_categoryId_month_year: { userId, categoryId: d.categoryId, month: d.month, year: d.year } },
      select: { id: true },
    });
    if (holder && holder.id !== id) return "duplicate";

    if (existing) await db.budget.update({ where: { id }, data: d });
    else await db.budget.create({ data: { id, userId, ...d } });
    return "applied";
  },
};

const subscriptions: EntityDef = {
  find: (db, id) => db.subscription.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.subscription.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing) {
    const p = subscriptionSchema.parse(data);
    const d = {
      ...p,
      categoryId: emptyToNull(p.categoryId),
      walletId: emptyToNull(p.walletId),
      note: emptyToNull(p.note),
      active: p.active ?? true,
    };
    await assertCategory(db, userId, d.categoryId);
    await assertWallet(db, userId, d.walletId);
    if (existing) await db.subscription.update({ where: { id }, data: d });
    else await db.subscription.create({ data: { id, userId, ...d } });
    return "applied";
  },
};

const mobilePlannedSchema = plannedSchema.extend({ done: z.boolean().default(false) });

const planned: EntityDef = {
  find: (db, id) => db.plannedTransaction.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.plannedTransaction.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing) {
    const p = mobilePlannedSchema.parse(data);
    const d = {
      ...p,
      categoryId: emptyToNull(p.categoryId),
      walletId: emptyToNull(p.walletId),
      note: emptyToNull(p.note),
    };
    await assertCategory(db, userId, d.categoryId);
    await assertWallet(db, userId, d.walletId);
    if (existing) await db.plannedTransaction.update({ where: { id }, data: d });
    else await db.plannedTransaction.create({ data: { id, userId, ...d } });
    return "applied";
  },
};

const prayerSchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Invalid date"),
  prayer: z.string().refine((v) => PRAYER_IDS.includes(v), "Invalid prayer"),
});

const prayers: EntityDef = {
  find: (db, id) => db.prayerEntry.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.prayerEntry.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing) {
    const d = prayerSchema.parse(data);
    const holder = await db.prayerEntry.findUnique({
      where: { userId_date_prayer: { userId, date: d.date, prayer: d.prayer } },
      select: { id: true },
    });
    if (holder && holder.id !== id) return "duplicate";

    if (existing) await db.prayerEntry.update({ where: { id }, data: d });
    else await db.prayerEntry.create({ data: { id, userId, ...d } });
    return "applied";
  },
};

const health: EntityDef = {
  find: (db, id) => db.healthEntry.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.healthEntry.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing) {
    const d = healthSchema.parse(data);
    if (existing) await db.healthEntry.update({ where: { id }, data: d });
    else await db.healthEntry.create({ data: { id, userId, ...d } });
    return "applied";
  },
};

const food: EntityDef = {
  find: (db, id) => db.foodLog.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.foodLog.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing) {
    const d = foodSchema.parse(data);
    if (existing) await db.foodLog.update({ where: { id }, data: d });
    else await db.foodLog.create({ data: { id, userId, ...d } });
    return "applied";
  },
};

export const ENTITY_DEFS: Record<SyncEntity, EntityDef> = {
  wallets: wallets as unknown as EntityDef,
  categories,
  transactions: transactions as unknown as EntityDef,
  budgets,
  subscriptions,
  planned,
  prayers,
  health,
  food,
};
