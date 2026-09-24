import type { Prisma } from "@prisma/client";

/** Wire names of the entities mobile sync exchanges (see docs/mobile-sync.md). */
export const SYNC_ENTITIES = [
  "wallets",
  "categories",
  "transactions",
  "budgets",
  "subscriptions",
  "planned",
  "prayers",
  "health",
  "food",
  "taskAreas",
  "tasks",
  "noteLabels",
  "notes",
  "socialAccounts",
  "contentPillars",
  "contentItems",
  "contentPosts",
] as const;

export type SyncEntity = (typeof SYNC_ENTITIES)[number];

/**
 * Record deleted rows so mobile clients drop them on their next pull.
 * Only called from src/lib/sync-deletes.ts and src/lib/ledger.ts — every other
 * code path deletes through those helpers (enforced by an ESLint rule).
 */
export async function writeTombstones(db: Prisma.TransactionClient, userId: string, entity: SyncEntity, ids: string[]) {
  if (ids.length === 0) return;
  await db.syncTombstone.createMany({ data: ids.map((entityId) => ({ userId, entity, entityId })) });
}
