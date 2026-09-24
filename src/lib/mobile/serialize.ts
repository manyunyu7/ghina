import type { User } from "@prisma/client";
import type { SyncEntity } from "@/lib/tombstones";

/** Wire fields per entity (Prisma field names minus userId) — see docs/mobile-sync.md. */
export const ENTITY_FIELDS: Record<SyncEntity, readonly string[]> = {
  wallets: ["id", "name", "type", "balance", "currency", "color", "icon", "archived", "createdAt", "updatedAt"],
  categories: ["id", "name", "type", "color", "icon", "createdAt", "updatedAt"],
  transactions: ["id", "walletId", "toWalletId", "categoryId", "type", "amount", "note", "date", "createdAt", "updatedAt"],
  budgets: ["id", "categoryId", "amount", "month", "year", "createdAt", "updatedAt"],
  subscriptions: [
    "id", "name", "amount", "currency", "cycle", "nextBilling", "categoryId", "walletId",
    "color", "icon", "note", "active", "createdAt", "updatedAt",
  ],
  planned: ["id", "type", "amount", "note", "categoryId", "walletId", "date", "done", "createdAt", "updatedAt"],
  prayers: [
    "id", "date", "prayer", "status", "qobliyah", "badiyah", "rakaat", "prayedAt", "note", "createdAt", "updatedAt",
  ],
  health: ["id", "date", "weight", "systolic", "diastolic", "pulse", "note", "createdAt", "updatedAt"],
  food: ["id", "date", "name", "meal", "calories", "photoUrl", "note", "createdAt", "updatedAt"],
};

/** Pick the wire fields of a row; Dates become ISO strings, missing values null. */
export function serializeRow(entity: SyncEntity, row: object): Record<string, unknown> {
  const src = row as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  for (const f of ENTITY_FIELDS[entity]) {
    const v = src[f];
    out[f] = v instanceof Date ? v.toISOString() : (v ?? null);
  }
  return out;
}

export function serializeUser(u: User) {
  return { id: u.id, name: u.name, email: u.email, image: u.image, currency: u.currency, syncEpoch: u.syncEpoch };
}
