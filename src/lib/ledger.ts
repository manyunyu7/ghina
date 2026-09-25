import type { Prisma } from "@prisma/client";
import { writeTombstones } from "@/lib/tombstones";
import { adjustmentNote } from "@/lib/adjustment";
import { parsePhotos } from "@/lib/photos";
import { detachTransactions } from "@/lib/sync-links";

/**
 * The single implementation of how transactions move wallet balances.
 * Used by the web server actions and the mobile sync endpoint — never adjust
 * `wallet.balance` for a transaction anywhere else.
 *
 * income: +amount to wallet · expense: −amount · transfer: −amount from source, +amount to destination
 * · adjustment: +amount (signed) to wallet — a balance correction (docs/balance-adjustment.md)
 * · investment: +amount (signed) to wallet — a trade's cash (buy −, sell +; docs/investments.md).
 * Editing reverses the old effect and applies the new one; deleting reverses it.
 */

export type Db = Prisma.TransactionClient;

export type LedgerTx = { type: string; amount: number; walletId: string; toWalletId: string | null };

export type TransactionInput = LedgerTx & {
  categoryId: string | null;
  note: string | null;
  date: Date;
  /** Serialized photo list (src/lib/photos.ts). Omit on update to keep the stored one. */
  photos?: string;
};

/** Net effect of a transaction on wallet balances, keyed by walletId. */
export function effects(t: LedgerTx): Record<string, number> {
  const e: Record<string, number> = {};
  const add = (id: string, d: number) => {
    e[id] = (e[id] ?? 0) + d;
  };
  if (t.type === "income") add(t.walletId, t.amount);
  else if (t.type === "expense") add(t.walletId, -t.amount);
  else if (t.type === "adjustment" || t.type === "investment") add(t.walletId, t.amount);
  else if (t.type === "transfer" && t.toWalletId) {
    add(t.walletId, -t.amount);
    add(t.toWalletId, t.amount);
  }
  return e;
}

/** Per-wallet balance change for replacing `before` with `after` (either may be null). */
export function ledgerDeltas(before: LedgerTx | null, after: LedgerTx | null): Record<string, number> {
  const out: Record<string, number> = {};
  if (before) for (const [id, d] of Object.entries(effects(before))) out[id] = (out[id] ?? 0) - d;
  if (after) for (const [id, d] of Object.entries(effects(after))) out[id] = (out[id] ?? 0) + d;
  return out;
}

async function applyDeltas(db: Db, deltas: Record<string, number>) {
  for (const [id, d] of Object.entries(deltas)) {
    if (d === 0) continue;
    await db.wallet.update({ where: { id }, data: { balance: { increment: d } } });
  }
}

/**
 * Validate that the referenced wallets/category belong to the user and normalize
 * a transfer's fields (transfers need a different destination and carry no category).
 */
export async function validateTransactionRefs(
  db: Db,
  userId: string,
  p: { type: string; walletId: string; toWalletId: string | null; categoryId: string | null },
): Promise<{ toWalletId: string | null; categoryId: string | null }> {
  const wallet = await db.wallet.findFirst({ where: { id: p.walletId, userId }, select: { id: true } });
  if (!wallet) throw new Error("Wallet not found");

  if (p.type === "transfer") {
    if (!p.toWalletId) throw new Error("Choose a destination wallet");
    if (p.toWalletId === p.walletId) throw new Error("Source and destination must differ");
    const dest = await db.wallet.findFirst({ where: { id: p.toWalletId, userId }, select: { id: true } });
    if (!dest) throw new Error("Destination wallet not found");
    // Transfers carry no category.
    return { toWalletId: p.toWalletId, categoryId: null };
  }

  if (p.type === "adjustment") {
    if (p.toWalletId) throw new Error("A balance adjustment has no destination wallet");
    if (p.categoryId) throw new Error("A balance adjustment has no category");
    return { toWalletId: null, categoryId: null };
  }

  if (p.type === "investment") {
    if (p.toWalletId) throw new Error("An investment transaction has no destination wallet");
    if (p.categoryId) throw new Error("An investment transaction has no category");
    return { toWalletId: null, categoryId: null };
  }

  if (p.categoryId) {
    const category = await db.category.findFirst({ where: { id: p.categoryId, userId }, select: { id: true } });
    if (!category) throw new Error("Category not found");
  }
  return { toWalletId: null, categoryId: p.categoryId };
}

/** Create a transaction and apply its balance effect. Caller validates ownership. */
export async function createLedgerTransaction(db: Db, userId: string, data: TransactionInput, id?: string) {
  const tx = await db.transaction.create({ data: { ...(id ? { id } : {}), userId, ...data } });
  await applyDeltas(db, ledgerDeltas(null, data));
  return tx;
}

/** Update a transaction: reverse the old effect, apply the new one (netted per wallet). */
export async function updateLedgerTransaction(db: Db, existing: LedgerTx & { id: string }, data: TransactionInput) {
  const tx = await db.transaction.update({ where: { id: existing.id }, data });
  await applyDeltas(db, ledgerDeltas(existing, data));
  return tx;
}

/**
 * Delete a transaction, reverse its balance effect, and tombstone it for sync. Tasks
 * linked to it lose their `transactionId` (docs/tasks.md), notes their
 * `linkedTransactionId`, content sponsors their `transactionId` (docs/notes.md, content.md). Returns the transaction's
 * photo URLs — the caller removes the files after the DB transaction commits
 * (`deleteUnreferencedUploads`).
 */
export async function deleteLedgerTransaction(
  db: Db,
  existing: LedgerTx & { id: string; userId: string },
): Promise<string[]> {
  const row = await db.transaction.findUnique({ where: { id: existing.id }, select: { photos: true } });
  await detachTransactions(db, existing.userId, [existing.id]);
  await db.transaction.delete({ where: { id: existing.id } });
  await applyDeltas(db, ledgerDeltas(existing, null));
  await writeTombstones(db, existing.userId, "transactions", [existing.id]);
  return parsePhotos(row?.photos);
}

/** Round to 2 decimals so float noise (0.1 + 0.2) never creates a phantom adjustment. */
export function roundMoney(n: number): number {
  return Math.round(n * 100) / 100;
}

/**
 * Set a wallet's balance to `target` by recording a balance `adjustment` transaction
 * for the difference (docs/balance-adjustment.md). No row when nothing changed.
 * Run inside the same DB transaction as any other wallet edit. Returns the
 * created transaction or null.
 */
export async function adjustWalletBalance(
  db: Db,
  userId: string,
  walletId: string,
  target: number,
  opts: { currency: string; note?: string | null; date?: Date | null },
) {
  const wallet = await db.wallet.findFirst({ where: { id: walletId, userId }, select: { balance: true } });
  if (!wallet) throw new Error("Wallet not found");
  const delta = roundMoney(target - wallet.balance);
  if (delta === 0) return null;
  const auto = adjustmentNote(wallet.balance, target, opts.currency);
  const userNote = opts.note?.trim();
  return createLedgerTransaction(db, userId, {
    type: "adjustment",
    amount: delta,
    walletId,
    toWalletId: null,
    categoryId: null,
    note: userNote ? `${auto} — ${userNote}` : auto,
    date: opts.date ?? new Date(),
  });
}
