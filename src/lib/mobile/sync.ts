import type { User } from "@prisma/client";
import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { deleteSyncedRow } from "@/lib/sync-deletes";
import { SYNC_ENTITIES, type SyncEntity } from "@/lib/tombstones";
import { deleteUnreferencedUploads } from "@/lib/uploads";
import { ensureDefaultTaskAreas } from "@/lib/tasks-server";
import { ensureDefaultNoteLabel, queueNoteLinkTitles } from "@/lib/notes-server";
import { ensureDefaultContentPillars } from "@/lib/content-server";
import { ensureDividendCategoryForPull } from "@/lib/investments-server";
import { ENTITY_DEFS, SyncRejection } from "@/lib/mobile/entities";
import { serializeRow } from "@/lib/mobile/serialize";

/**
 * Mobile sync: pull (changes since a cursor) and push (ordered outbox mutations).
 * Protocol: docs/mobile-sync.md.
 */

/** Cursor handed back to the client: slightly in the past so in-flight writes aren't missed. */
const cursorFor = (start: number) => start - 5000;

export async function pull(user: User, sinceMs: number) {
  const start = Date.now();
  const since = new Date(sinceMs);

  // Default task areas on first sync (deterministic ids → idempotent; docs/tasks.md).
  await ensureDefaultTaskAreas(prisma, user.id);
  // Default `Ide Konten` label and content pillars (seeded once; docs/notes.md, content.md).
  await ensureDefaultNoteLabel(prisma, user.id);
  await ensureDefaultContentPillars(prisma, user.id);
  // "Dividen" income category for users with assets (seeded once; docs/investments.md).
  await ensureDividendCategoryForPull(prisma, user.id);

  const changes = {} as Record<SyncEntity, Record<string, unknown>[]>;
  for (const entity of SYNC_ENTITIES) {
    const rows = await ENTITY_DEFS[entity].changedSince(prisma, user.id, since);
    changes[entity] = rows.map((r) => serializeRow(entity, r));
  }

  // A full pull (since = 0) starts from an empty local DB — tombstones are useless there.
  const tombstones =
    sinceMs > 0
      ? await prisma.syncTombstone.findMany({
          where: { userId: user.id, deletedAt: { gte: since } },
          orderBy: { deletedAt: "asc" },
        })
      : [];

  return {
    serverTime: cursorFor(start),
    epoch: user.syncEpoch,
    changes,
    deleted: tombstones.map((t) => ({ entity: t.entity, id: t.entityId, deletedAt: t.deletedAt.toISOString() })),
  };
}

export const pushBodySchema = z.object({
  // Optional: the epoch the client's local data belongs to. A mismatch means the
  // user reset their data — nothing is applied and the client must wipe + full pull.
  epoch: z.string().optional(),
  mutations: z.array(z.unknown()).max(1000, "Too many mutations in one push (max 1000)"),
});

const mutationSchema = z.object({
  id: z.string().min(1).max(100),
  entity: z.enum(SYNC_ENTITIES),
  op: z.enum(["upsert", "delete"]),
  entityId: z.string().regex(/^[A-Za-z0-9_-]{1,64}$/, "Invalid entityId"),
  data: z.record(z.string(), z.unknown()).optional(),
  clientUpdatedAt: z.iso.datetime({ offset: true }).transform((v) => new Date(v)),
});

export type MutationStatus = "applied" | "skipped" | "duplicate" | "rejected";
type MutationResult = { id: string | null; status: MutationStatus; error?: string };

/** Apply one mutation in its own DB transaction. */
async function applyMutation(userId: string, raw: unknown): Promise<MutationResult> {
  const rawId = (raw as { id?: unknown } | null)?.id;
  const parsed = mutationSchema.safeParse(raw);
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    return {
      id: typeof rawId === "string" ? rawId : null,
      status: "rejected",
      error: issue ? `${issue.path.join(".") || "mutation"}: ${issue.message}` : "Invalid mutation",
    };
  }
  const m = parsed.data;
  const def = ENTITY_DEFS[m.entity];
  // Upload files to delete once the mutation is committed (never on rollback).
  const cleanup: string[] = [];

  try {
    const status = await prisma.$transaction(async (db): Promise<MutationStatus> => {
      const existing = await def.find(db, m.entityId);
      if (existing && existing.userId !== userId) throw new SyncRejection("Not found");

      // Last write wins against the live row…
      if (existing && def.lwwTime(existing) > m.clientUpdatedAt) return "skipped";

      if (m.op === "delete") {
        if (!existing) return "applied"; // idempotent
        cleanup.push(...(await deleteSyncedRow(db, userId, m.entity, m.entityId)));
        return "applied";
      }

      if (!m.data) throw new SyncRejection("Missing data");

      // …and against a deletion: a row deleted after this edit stays deleted.
      if (!existing) {
        const tomb = await db.syncTombstone.findFirst({
          where: { userId, entity: m.entity, entityId: m.entityId },
          orderBy: { deletedAt: "desc" },
        });
        if (tomb && tomb.deletedAt > m.clientUpdatedAt) return "skipped";
        // Re-created after an older delete: drop the tombstone so the id isn't in both lists of a pull.
        if (tomb) await db.syncTombstone.deleteMany({ where: { userId, entity: m.entity, entityId: m.entityId } });
      }

      const outcome = await def.upsert(db, userId, m.entityId, m.data, existing, cleanup);
      if (outcome === "duplicate") {
        // Undo the tombstone removal above along with everything else.
        throw new DuplicateSignal();
      }
      return outcome;
    });

    // File cleanup only after the DB change is committed (skipping files still referenced).
    if (status === "applied") await deleteUnreferencedUploads(cleanup);
    // Fill link titles in the background (never blocks the push).
    if (status === "applied" && m.entity === "notes" && m.op === "upsert") queueNoteLinkTitles(m.entityId);
    return { id: m.id, status };
  } catch (err) {
    if (err instanceof DuplicateSignal) return { id: m.id, status: "duplicate" };
    if (err instanceof SyncRejection) return { id: m.id, status: "rejected", error: err.message };
    if (err instanceof z.ZodError) {
      const issue = err.issues[0];
      return { id: m.id, status: "rejected", error: issue?.message ?? "Invalid data" };
    }
    console.error("[mobile sync] mutation failed", m.entity, m.op, m.entityId, err);
    return { id: m.id, status: "rejected", error: "Server error while applying change" };
  }
}

/** Thrown inside the DB transaction to roll it back when the unique key is taken. */
class DuplicateSignal extends Error {}

export async function push(user: User, mutations: unknown[]) {
  const start = Date.now();
  const results: MutationResult[] = [];
  // In order; one failing does not stop the rest.
  for (const raw of mutations) results.push(await applyMutation(user.id, raw));
  return { serverTime: cursorFor(start), results };
}
