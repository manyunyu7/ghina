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
import { parsePhotos, photosSchema, removedPhotos, serializePhotos } from "@/lib/photos";
import { taskAreaSchema } from "@/lib/tasks";
import { areaToDb, saveTask, TaskError } from "@/lib/tasks-server";
import { NoteError, saveNote, saveNoteLabel } from "@/lib/notes-server";
import {
  ContentError,
  saveContentItem,
  saveContentPillar,
  saveContentPost,
  saveSocialAccount,
} from "@/lib/content-server";
import {
  ALL_PRAYER_IDS,
  defaultStatusFor,
  isValidDateKey,
  prayerEntryError,
  type PrayerFields,
} from "@/lib/prayer-quality";

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
  /**
   * Create (existing = null) or update the row with the pushed data. Upload URLs whose
   * files should be removed once the change is committed are pushed onto `cleanup`.
   */
  upsert(db: Db, userId: string, id: string, data: unknown, existing: R | null, cleanup: string[]): Promise<UpsertOutcome>;
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

// `photos` is optional so older app versions keep the stored list on update ([] on create).
const syncPhotosSchema = z.object({ photos: photosSchema.nullish() });

const transactions: EntityDef<
  Row & { type: string; amount: number; walletId: string; toWalletId: string | null; photos: string }
> = {
  find: (db, id) => db.transaction.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.transaction.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing, cleanup) {
    const p = transactionSchema.parse(data);
    const { photos: sent } = syncPhotosSchema.parse(data);
    const before = parsePhotos(existing?.photos);
    const photos = sent === undefined ? before : (sent ?? []);
    let refs;
    try {
      refs = await validateTransactionRefs(db, userId, p);
    } catch (e) {
      throw new SyncRejection(e instanceof Error ? e.message : "Invalid references");
    }
    const input = { ...p, ...refs, photos: serializePhotos(photos) };
    cleanup.push(...removedPhotos(before, photos));
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

// New fields are optional so older app versions (date + prayer only) keep working:
// on create they get defaults (fardhu → "ontime", sunnah → "done"); on update a missing
// field keeps the stored value (an old client never wipes a status it doesn't know about).
const prayerSchema = z.object({
  date: z.string().refine(isValidDateKey, "Invalid date"),
  prayer: z.string().refine((v) => ALL_PRAYER_IDS.includes(v), "Invalid prayer"),
  status: z.string().optional(),
  qobliyah: z.boolean().optional(),
  badiyah: z.boolean().optional(),
  rakaat: z.number().int("Rakaat must be an integer").nullable().optional(),
  prayedAt: z.iso
    .datetime({ offset: true })
    .transform((v) => new Date(v))
    .nullable()
    .optional(),
  note: z
    .string()
    .nullable()
    .optional()
    .transform((v) => (v === undefined ? undefined : v && v.trim().length > 0 ? v.trim() : null)),
});

type PrayerRow = Row & PrayerFields;

const prayers: EntityDef<PrayerRow> = {
  find: (db, id) => db.prayerEntry.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.prayerEntry.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing) {
    const p = prayerSchema.parse(data);
    // Fields carried over from the stored row only if it is the same prayer slot.
    const base = existing && existing.prayer === p.prayer ? existing : null;
    const d: PrayerFields = {
      date: p.date,
      prayer: p.prayer,
      status: p.status ?? base?.status ?? defaultStatusFor(p.prayer),
      qobliyah: p.qobliyah ?? base?.qobliyah ?? false,
      badiyah: p.badiyah ?? base?.badiyah ?? false,
      rakaat: p.rakaat !== undefined ? p.rakaat : (base?.rakaat ?? null),
      prayedAt: p.prayedAt !== undefined ? p.prayedAt : (base?.prayedAt ?? null),
      note: p.note !== undefined ? p.note : (base?.note ?? null),
    };
    const err = prayerEntryError(d);
    if (err) throw new SyncRejection(err);

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

const food: EntityDef<Row & { photoUrl: string | null }> = {
  find: (db, id) => db.foodLog.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.foodLog.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing, cleanup) {
    const d = foodSchema.parse(data);
    // A replaced/removed photo's file is deleted (like the web).
    if (existing?.photoUrl && existing.photoUrl !== d.photoUrl) cleanup.push(existing.photoUrl);
    if (existing) await db.foodLog.update({ where: { id }, data: d });
    else await db.foodLog.create({ data: { id, userId, ...d } });
    return "applied";
  },
};

// Area codes are unique per user: another id holding the code → `duplicate`.
const taskAreas: EntityDef = {
  find: (db, id) => db.taskArea.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.taskArea.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing) {
    const d = areaToDb(taskAreaSchema.parse(data));
    const holder = await db.taskArea.findUnique({
      where: { userId_code: { userId, code: d.code } },
      select: { id: true },
    });
    if (holder && holder.id !== id) return "duplicate";
    if (existing) await db.taskArea.update({ where: { id }, data: d });
    else await db.taskArea.create({ data: { id, userId, ...d } });
    return "applied";
  },
};

// Completing a recurring task: the client pushes the done upsert AND the next occurrence
// (deterministic id `<seriesId>_<YYYYMMDD>`) — both are plain upserts here, so the same
// id pushed from two devices lands on one row (LWW decides which version stays).
const tasks: EntityDef = {
  find: (db, id) => db.task.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.task.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing) {
    try {
      await saveTask(db, userId, id, data, !!existing);
    } catch (e) {
      if (e instanceof TaskError) throw new SyncRejection(e.message);
      throw e;
    }
    return "applied";
  },
};

/** Map a helper's user-facing error to a sync rejection. */
async function asSync<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    if (e instanceof TaskError || e instanceof NoteError || e instanceof ContentError) throw new SyncRejection(e.message);
    throw e;
  }
}

// ---------- Notes (docs/notes.md) ----------

// Label names are unique per user (case-insensitive): another id holding it → `duplicate`.
const noteLabels: EntityDef = {
  find: (db, id) => db.noteLabel.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.noteLabel.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  upsert: (db, userId, id, data, existing) => saveNoteLabel(db, userId, id, data, !!existing),
};

type NoteRow = Row & Awaited<ReturnType<Db["note"]["findUniqueOrThrow"]>>;

// LWW on `editedAt`: `updatedAt` also moves when the server fills link titles or strips a
// deleted label — those must not make a device's later edit lose.
const notes: EntityDef<NoteRow> = {
  find: (db, id) => db.note.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.note.findMany(since(userId, s)),
  lwwTime: (row) => row.editedAt,
  async upsert(db, userId, id, data, existing, cleanup) {
    const saved = await asSync(() => saveNote(db, userId, id, data, existing));
    cleanup.push(...saved.removedFiles);
    return "applied";
  },
};

// ---------- Content planner (docs/content.md) ----------

const socialAccounts: EntityDef = {
  find: (db, id) => db.socialAccount.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.socialAccount.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing) {
    await saveSocialAccount(db, userId, id, data, !!existing);
    return "applied";
  },
};

type PillarRow = Row & { name: string; color: string; sortOrder: number; createdAt: Date };

const contentPillars: EntityDef<PillarRow> = {
  find: (db, id) => db.contentPillar.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.contentPillar.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  upsert: (db, userId, id, data, existing) => saveContentPillar(db, userId, id, data, existing),
};

type ItemRow = Row & Awaited<ReturnType<Db["contentItem"]["findUniqueOrThrow"]>>;

const contentItems: EntityDef<ItemRow> = {
  find: (db, id) => db.contentItem.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.contentItem.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing, cleanup) {
    const saved = await asSync(() => saveContentItem(db, userId, id, data, existing));
    cleanup.push(...saved.removedFiles);
    return "applied";
  },
};

// Stage auto-advance (docs/content.md) is applied by the client that changes the posts;
// the server stores what it is sent.
const contentPosts: EntityDef = {
  find: (db, id) => db.contentPost.findUnique({ where: { id } }),
  changedSince: (db, userId, s) => db.contentPost.findMany(since(userId, s)),
  lwwTime: (row) => row.updatedAt,
  async upsert(db, userId, id, data, existing) {
    await asSync(() => saveContentPost(db, userId, id, data, !!existing));
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
  prayers: prayers as unknown as EntityDef,
  health,
  food: food as unknown as EntityDef,
  taskAreas,
  tasks,
  noteLabels,
  notes: notes as unknown as EntityDef,
  socialAccounts,
  contentPillars: contentPillars as unknown as EntityDef,
  contentItems: contentItems as unknown as EntityDef,
  contentPosts,
};
