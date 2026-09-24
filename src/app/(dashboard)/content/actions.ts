"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { deleteLedgerTransaction } from "@/lib/ledger";
import { deleteSynced } from "@/lib/sync-deletes";
import { deleteUnreferencedUploads, deleteUpload, saveMediaUpload } from "@/lib/uploads";
import {
  assertId,
  assertIds,
  assertObject,
  formFiles,
  pick,
  runAction,
  UserError,
  type ActionResult,
} from "@/lib/action-utils";
import {
  CONTENT_PHOTOS_MAX,
  STAGE_IDS,
  type AssetLink,
  type FormatId,
  type Metrics,
  type PlatformId,
  type PostStatus,
  type Sponsor,
  type StageId,
} from "@/lib/content";
import { parseImageList, type ChecklistItem } from "@/lib/notes";
import {
  accountRowToInput,
  applyAutoStage,
  ContentError,
  ensureDefaultContentPillars,
  getContentCalendar,
  getContentReport,
  itemRowToInput,
  markSponsorPaid as markPaid,
  pillarRowToInput,
  postRowToInput,
  saveContentItem,
  saveContentPillar,
  saveContentPost,
  saveSocialAccount,
  type CalendarData,
} from "@/lib/content-server";

/**
 * Server actions for the web Content planner (docs/content.md). Plain-object arguments
 * (photo uploads take FormData), results `{ ok: true, … } | { ok: false, error }` with
 * Indonesian messages. Validation is shared with mobile sync (src/lib/content.ts,
 * src/lib/content-server.ts). Post changes apply the stage auto-advance rule.
 */

export type SocialAccountInput = {
  platform: PlatformId;
  /** Required when platform = "other". */
  platformName?: string | null;
  handle: string;
  /** Default: the platform color. */
  color?: string | null;
  /** null/0 = no target. */
  targetPerWeek?: number | null;
  archived?: boolean;
  /** Default on create: after the last account. */
  sortOrder?: number;
};

export type ContentPillarInput = { name: string; color?: string; sortOrder?: number };

export type ContentItemInput = {
  title: string;
  stage?: StageId;
  format?: FormatId | null;
  /** A pillar name. */
  pillar?: string | null;
  /** Markdown idea / script. */
  idea?: string;
  noteId?: string | null;
  checklist?: ChecklistItem[];
  assetLinks?: AssetLink[];
  /** null removes the sponsor. `paid`/`transactionId` are managed by markSponsorPaid/markSponsorUnpaid. */
  sponsor?: SponsorInput | null;
  /** Reorder / remove photos: subset of the stored list (removed files are deleted). */
  photos?: string[];
};

export type SponsorInput = {
  brand: string;
  /** ≥ 0 (0 = barter). */
  amount: number;
  /** 3-letter code, default IDR. */
  currency?: string;
  /** Local YYYY-MM-DD. */
  due?: string | null;
  /** Only used when creating an item. */
  paid?: boolean;
};

export type ContentPostInput = {
  contentId: string;
  accountId: string;
  caption?: string;
  hashtags?: string;
  /** ISO-8601 with Z/offset, or null. */
  scheduledAt?: string | null;
  remindBefore?: number | null;
  /** Default: "scheduled" when scheduledAt is set, else "draft". */
  status?: PostStatus;
  postedAt?: string | null;
  url?: string | null;
  metrics?: Metrics;
  metricsAt?: string | null;
};

const ACCOUNT_KEYS = ["platform", "platformName", "handle", "color", "targetPerWeek", "archived", "sortOrder"] as const;
const PILLAR_KEYS = ["name", "color", "sortOrder"] as const;
const ITEM_KEYS = ["title", "stage", "format", "pillar", "idea", "noteId", "checklist", "assetLinks"] as const;
const POST_KEYS = [
  "contentId", "accountId", "caption", "hashtags", "scheduledAt", "remindBefore", "status", "postedAt", "url", "metrics", "metricsAt",
] as const;

const ACCOUNT_NOT_FOUND = "Akun tidak ditemukan";
const PILLAR_NOT_FOUND = "Pilar tidak ditemukan";
const ITEM_NOT_FOUND = "Konten tidak ditemukan";
const POST_NOT_FOUND = "Posting tidak ditemukan";

function revalidate(money = false) {
  revalidatePath("/content");
  revalidatePath("/content/accounts");
  revalidatePath("/notes");
  if (money) {
    revalidatePath("/transactions");
    revalidatePath("/wallets");
    revalidatePath("/dashboard");
  }
}

// ---------- Accounts ----------

export async function createSocialAccount(input: SocialAccountInput): Promise<ActionResult<{ id: string }>> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertObject(input);
    const fields = pick(input, ACCOUNT_KEYS);
    if (fields.sortOrder === undefined) {
      const last = await prisma.socialAccount.aggregate({ where: { userId: user.id }, _max: { sortOrder: true } });
      fields.sortOrder = (last._max.sortOrder ?? -1) + 1;
    }
    const id = randomUUID();
    await prisma.$transaction((db) => saveSocialAccount(db, user.id, id, fields, false));
    return { id };
  });
  if (res.ok) revalidate();
  return res;
}

export async function updateSocialAccount(id: string, patch: Partial<SocialAccountInput>): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertId(id, ACCOUNT_NOT_FOUND);
    assertObject(patch);
    await prisma.$transaction(async (db) => {
      const a = await db.socialAccount.findFirst({ where: { id, userId: user.id } });
      if (!a) throw new UserError(ACCOUNT_NOT_FOUND);
      const merged = { ...accountRowToInput(a), ...pick(patch, ACCOUNT_KEYS) };
      // Switching platform without a color resets it to the new platform's default.
      if (patch.platform && patch.platform !== a.platform && patch.color === undefined) merged.color = null;
      await saveSocialAccount(db, user.id, id, merged, true);
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

/** Delete an account and all its posts (tombstoned). */
export async function deleteSocialAccount(id: string): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertId(id, ACCOUNT_NOT_FOUND);
    if (!(await prisma.socialAccount.findFirst({ where: { id, userId: user.id }, select: { id: true } }))) throw new UserError(ACCOUNT_NOT_FOUND);
    const affected = await prisma.contentPost.findMany({ where: { userId: user.id, accountId: id }, select: { contentId: true }, distinct: ["contentId"] });
    await deleteSynced(user.id, "socialAccounts", id);
    // Its posts are gone: the remaining (all posted) variants can complete an item.
    await prisma.$transaction(async (db) => {
      for (const { contentId } of affected) await applyAutoStage(db, user.id, contentId);
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

export async function reorderSocialAccounts(orderedIds: string[]): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertIds(orderedIds, ACCOUNT_NOT_FOUND);
    const ids = [...new Set(orderedIds)];
    await prisma.$transaction(async (db) => {
      if ((await db.socialAccount.count({ where: { id: { in: ids }, userId: user.id } })) !== ids.length) throw new UserError(ACCOUNT_NOT_FOUND);
      for (const [i, id] of ids.entries()) await db.socialAccount.update({ where: { id }, data: { sortOrder: i } });
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

// ---------- Pillars ----------

export async function createContentPillar(input: ContentPillarInput): Promise<ActionResult<{ id: string }>> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertObject(input);
    const fields = pick(input, PILLAR_KEYS);
    if (fields.sortOrder === undefined) {
      const last = await prisma.contentPillar.aggregate({ where: { userId: user.id }, _max: { sortOrder: true } });
      fields.sortOrder = (last._max.sortOrder ?? -1) + 1;
    }
    const id = randomUUID();
    if ((await prisma.$transaction((db) => saveContentPillar(db, user.id, id, fields, null))) === "duplicate")
      throw new UserError("Nama pilar sudah dipakai");
    return { id };
  });
  if (res.ok) revalidate();
  return res;
}

/** Patch a pillar; a rename also renames it on the user's content items. */
export async function updateContentPillar(id: string, patch: Partial<ContentPillarInput>): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertId(id, PILLAR_NOT_FOUND);
    assertObject(patch);
    await prisma.$transaction(async (db) => {
      const p = await db.contentPillar.findFirst({ where: { id, userId: user.id } });
      if (!p) throw new UserError(PILLAR_NOT_FOUND);
      const out = await saveContentPillar(db, user.id, id, { ...pillarRowToInput(p), ...pick(patch, PILLAR_KEYS) }, p);
      if (out === "duplicate") throw new UserError("Nama pilar sudah dipakai");
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

/** Delete a pillar; items with it get `pillar = null`. */
export async function deleteContentPillar(id: string): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertId(id, PILLAR_NOT_FOUND);
    if (!(await prisma.contentPillar.findFirst({ where: { id, userId: user.id }, select: { id: true } }))) throw new UserError(PILLAR_NOT_FOUND);
    await deleteSynced(user.id, "contentPillars", id);
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

export async function reorderContentPillars(orderedIds: string[]): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertIds(orderedIds, PILLAR_NOT_FOUND);
    const ids = [...new Set(orderedIds)];
    await prisma.$transaction(async (db) => {
      if ((await db.contentPillar.count({ where: { id: { in: ids }, userId: user.id } })) !== ids.length) throw new UserError(PILLAR_NOT_FOUND);
      for (const [i, id] of ids.entries()) await db.contentPillar.update({ where: { id }, data: { sortOrder: i } });
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

/** Seed the default pillars once (idempotent; pages may call `getContentSetup` instead). */
export async function ensureDefaultPillars(): Promise<ActionResult<{ created: number }>> {
  const user = await requireUser();
  return runAction("content", async () => ({ created: await ensureDefaultContentPillars(prisma, user.id) }));
}

// ---------- Content items ----------

type ItemShape = ReturnType<typeof itemRowToInput>;

/** Load item `id`, apply `change`, validate + save; after commit delete unused photo files. */
async function mutateItem(userId: string, id: unknown, change: (cur: ItemShape) => ItemShape) {
  assertId(id, ITEM_NOT_FOUND);
  const saved = await prisma.$transaction(async (db) => {
    const existing = await db.contentItem.findFirst({ where: { id, userId } });
    if (!existing) throw new UserError(ITEM_NOT_FOUND);
    return saveContentItem(db, userId, id, change(itemRowToInput(existing)), existing);
  });
  await deleteUnreferencedUploads(saved.removedFiles);
  return saved.row;
}

const SPONSOR_LINKED = "Pemasukan sponsor ini sudah dicatat. Hapus transaksinya dulu sebelum menghapus sponsor.";

/** Keep the stored sponsor's paid/transactionId unless explicitly changed via the sponsor actions. */
function mergeSponsor(cur: Sponsor | null, next: ContentItemInput["sponsor"] | undefined): Sponsor | null | undefined {
  if (next === undefined) return undefined;
  if (next === null) {
    // Removing it would drop the link, and paying a re-added sponsor would record the
    // income a second time.
    if (cur?.transactionId) throw new UserError(SPONSOR_LINKED);
    return null;
  }
  assertObject(next, "Sponsor");
  return {
    currency: "IDR",
    due: null,
    ...pick(next, ["brand", "amount", "currency", "due"]),
    paid: cur?.paid ?? next.paid === true,
    transactionId: cur?.transactionId ?? null,
  } as Sponsor;
}

export async function createContentItem(input: ContentItemInput): Promise<ActionResult<{ id: string }>> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertObject(input);
    const id = randomUUID();
    await prisma.$transaction((db) =>
      saveContentItem(db, user.id, id, { ...pick(input, ITEM_KEYS), sponsor: mergeSponsor(null, input.sponsor) ?? null }, null),
    );
    return { id };
  });
  if (res.ok) revalidate();
  return res;
}

/** Patch an item (anything omitted keeps its value). */
export async function updateContentItem(id: string, patch: Partial<ContentItemInput>): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertObject(patch);
    await mutateItem(user.id, id, (cur) => {
      const next = { ...cur, ...pick(patch, ITEM_KEYS) } as ItemShape;
      const sponsor = mergeSponsor(cur.sponsor, patch.sponsor);
      if (sponsor !== undefined) next.sponsor = sponsor;
      if (patch.photos !== undefined) {
        if (!Array.isArray(patch.photos) || patch.photos.some((u) => !cur.photos.includes(u)))
          throw new UserError("Foto tidak ditemukan di konten ini");
        next.photos = patch.photos;
      }
      return next;
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

/** Board drag & drop: move an item to another stage (any direction). */
export async function moveContentStage(id: string, stage: StageId): Promise<ActionResult> {
  if (!STAGE_IDS.includes(stage)) return { ok: false, error: "Tahap tidak dikenal" };
  return updateContentItem(id, { stage });
}

/** Tick / untick a production checklist item. */
export async function toggleContentChecklistItem(id: string, itemId: string): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    await mutateItem(user.id, id, (cur) => {
      if (!cur.checklist.some((c) => c.id === itemId)) throw new UserError("Item checklist tidak ditemukan");
      return { ...cur, checklist: cur.checklist.map((c) => (c.id === itemId ? { ...c, done: !c.done } : c)) };
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

/** Delete an item and its posts (tombstoned); linked notes lose `linkedContentId`. */
export async function deleteContentItem(id: string): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertId(id, ITEM_NOT_FOUND);
    if (!(await prisma.contentItem.findFirst({ where: { id, userId: user.id }, select: { id: true } }))) throw new UserError(ITEM_NOT_FOUND);
    await deleteSynced(user.id, "contentItems", id);
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

/** Attach photos (FormData: `contentId`, `photos` files ≤ 5 MB each; ≤ 10 per item). */
export async function uploadContentPhotos(formData: FormData): Promise<ActionResult<{ photos: string[] }>> {
  const user = await requireUser();
  const written: string[] = [];
  const res = await runAction("content", async () => {
    if (!(formData instanceof FormData)) throw new UserError("Data tidak valid");
    const id = formData.get("contentId");
    assertId(id, ITEM_NOT_FOUND);
    const files = formFiles(formData, "photos");
    if (!files.length) throw new UserError("Pilih foto");
    const cur = await prisma.contentItem.findFirst({ where: { id, userId: user.id }, select: { photos: true } });
    if (!cur) throw new UserError(ITEM_NOT_FOUND);
    if (parseImageList(cur.photos).length + files.length > CONTENT_PHOTOS_MAX)
      throw new UserError(`Maksimal ${CONTENT_PHOTOS_MAX} foto per konten`);
    for (const f of files) {
      const { url } = await saveMediaUpload(f, ["image"]).catch((e: unknown) => {
        throw new UserError(e instanceof Error ? e.message : "Unggah gagal");
      });
      written.push(url);
    }
    const row = await mutateItem(user.id, id, (c) => ({ ...c, photos: [...c.photos, ...written] }));
    return { photos: parseImageList(row.photos) };
  });
  if (!res.ok) await Promise.all(written.map((u) => deleteUpload(u)));
  else revalidate();
  return res;
}

export async function removeContentPhoto(id: string, url: string): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    await mutateItem(user.id, id, (c) => {
      if (typeof url !== "string" || !c.photos.includes(url)) throw new UserError("Foto tidak ditemukan di konten ini");
      return { ...c, photos: c.photos.filter((u) => u !== url) };
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

// ---------- Sponsorship ----------

/**
 * Mark the item's sponsor paid. With `record` an income transaction is recorded through
 * the ledger (wallet chosen by the user; amount default = sponsor amount; note default
 * "Endorse <brand>") and linked as `sponsor.transactionId` — never twice.
 */
export async function markSponsorPaid(
  id: string,
  record: { walletId: string; amount?: number; categoryId?: string | null; date?: string; note?: string } | null = null,
): Promise<ActionResult<{ transactionId: string | null }>> {
  const user = await requireUser();
  let money = false;
  const res = await runAction("content", async () => {
    assertId(id, ITEM_NOT_FOUND);
    if (record !== null) assertObject(record);
    const date = record?.date ? new Date(record.date) : undefined;
    if (date && Number.isNaN(date.getTime())) throw new UserError("Tanggal tidak valid");
    const out = await prisma.$transaction((db) =>
      markPaid(db, user.id, id, record ? { walletId: record.walletId, amount: record.amount, categoryId: record.categoryId, date, note: record.note } : null),
    );
    money = !!out.transactionId && !!record;
    return { transactionId: out.transactionId };
  });
  if (res.ok) revalidate(money);
  return res;
}

/**
 * Mark the sponsor unpaid. `deleteTransaction: true` also deletes the linked income
 * transaction (reversing its balance effect); otherwise it stays linked, so marking paid
 * again reuses it.
 */
export async function markSponsorUnpaid(id: string, opts: { deleteTransaction?: boolean } = {}): Promise<ActionResult> {
  const user = await requireUser();
  let files: string[] = [];
  const res = await runAction("content", async () => {
    await prisma.$transaction(async (db) => {
      assertId(id, ITEM_NOT_FOUND);
      const item = await db.contentItem.findFirst({ where: { id, userId: user.id } });
      if (!item) throw new UserError(ITEM_NOT_FOUND);
      const s = itemRowToInput(item).sponsor;
      if (!s) throw new ContentError("Konten ini tidak punya sponsor");
      let transactionId = s.transactionId;
      if (opts?.deleteTransaction === true && s.transactionId) {
        const tx = await db.transaction.findFirst({ where: { id: s.transactionId, userId: user.id } });
        if (tx) files = await deleteLedgerTransaction(db, tx);
        transactionId = null;
      }
      // Without deleting, the income stays linked: paying again reuses it (never a second income).
      await db.contentItem.update({ where: { id }, data: { sponsor: JSON.stringify({ ...s, paid: false, transactionId }) } });
    });
    return {};
  });
  if (res.ok) {
    await deleteUnreferencedUploads(files);
    revalidate(opts?.deleteTransaction === true);
  }
  return res;
}

// ---------- Posts ----------

type PostShape = ReturnType<typeof postRowToInput>;

/** Save a post in a transaction and re-apply the item's stage auto-advance. */
async function savePostAndStage(userId: string, id: string, build: (cur: PostShape | null) => unknown, mustExist: boolean) {
  return prisma.$transaction(async (db) => {
    const existing = await db.contentPost.findFirst({ where: { id, userId } });
    if (mustExist && !existing) throw new UserError(POST_NOT_FOUND);
    const row = await saveContentPost(db, userId, id, build(existing ? postRowToInput(existing) : null), !!existing);
    const stage = await applyAutoStage(db, userId, row.contentId);
    if (existing && existing.contentId !== row.contentId) await applyAutoStage(db, userId, existing.contentId);
    return { row, stage };
  });
}

/** Add a post (one per target account; the same account twice on one item is refused). */
export async function createContentPost(input: ContentPostInput): Promise<ActionResult<{ id: string; stage: string | null }>> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertObject(input);
    const fields = pick(input, POST_KEYS);
    if (fields.status === undefined) fields.status = fields.scheduledAt ? "scheduled" : "draft";
    if (typeof fields.contentId === "string" && typeof fields.accountId === "string") {
      const dup = await prisma.contentPost.findFirst({
        where: { userId: user.id, contentId: fields.contentId, accountId: fields.accountId },
        select: { id: true },
      });
      if (dup) throw new UserError("Akun ini sudah ada di konten ini");
    }
    const id = randomUUID();
    const { stage } = await savePostAndStage(user.id, id, () => fields, false);
    return { id, stage };
  });
  if (res.ok) revalidate();
  return res;
}

/** Patch a post (anything omitted keeps its value). Returns the item's new stage if it moved. */
export async function updateContentPost(id: string, patch: Partial<ContentPostInput>): Promise<ActionResult<{ stage: string | null }>> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertId(id, POST_NOT_FOUND);
    assertObject(patch);
    const { stage } = await savePostAndStage(user.id, id, (cur) => ({ ...cur, ...pick(patch, POST_KEYS) }), true);
    return { stage };
  });
  if (res.ok) revalidate();
  return res;
}

/** Calendar drag / schedule dialog: set `scheduledAt` (status → scheduled; null → draft). */
export async function scheduleContentPost(id: string, scheduledAt: string | null): Promise<ActionResult<{ stage: string | null }>> {
  if (scheduledAt !== null && typeof scheduledAt !== "string") return { ok: false, error: "Waktu tidak valid" };
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertId(id, POST_NOT_FOUND);
    const { stage } = await savePostAndStage(
      user.id,
      id,
      (cur) => ({
        ...cur,
        scheduledAt,
        // Rescheduling a posted/skipped post keeps its status.
        status: cur && (cur.status === "posted" || cur.status === "skipped") ? cur.status : scheduledAt ? "scheduled" : "draft",
      }),
      true,
    );
    return { stage };
  });
  if (res.ok) revalidate();
  return res;
}

/** "Sudah tayang": status posted, postedAt (default now), optional live URL. */
export async function markPostPosted(
  id: string,
  opts: { url?: string | null; postedAt?: string } = {},
): Promise<ActionResult<{ stage: string | null }>> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertId(id, POST_NOT_FOUND);
    assertObject(opts);
    const { stage } = await savePostAndStage(
      user.id,
      id,
      (cur) => ({
        ...cur,
        status: "posted",
        postedAt: opts.postedAt ?? new Date().toISOString(),
        ...(opts.url !== undefined ? { url: opts.url } : {}),
      }),
      true,
    );
    return { stage };
  });
  if (res.ok) revalidate();
  return res;
}

/** Skip / un-skip a post for its account (un-skip → scheduled if it has a time, else draft). */
export async function setPostSkipped(id: string, skipped: boolean): Promise<ActionResult<{ stage: string | null }>> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertId(id, POST_NOT_FOUND);
    const { stage } = await savePostAndStage(
      user.id,
      id,
      (cur) => ({ ...cur, status: skipped === true ? "skipped" : cur?.scheduledAt ? "scheduled" : "draft" }),
      true,
    );
    return { stage };
  });
  if (res.ok) revalidate();
  return res;
}

/** Manual metrics entry (replaces the metrics; `metricsAt` = now). */
export async function setPostMetrics(id: string, metrics: Metrics): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertId(id, POST_NOT_FOUND);
    assertObject(metrics, "Metrik");
    await savePostAndStage(user.id, id, (cur) => ({ ...cur, metrics, metricsAt: new Date().toISOString() }), true);
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

export async function deleteContentPost(id: string): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("content", async () => {
    assertId(id, POST_NOT_FOUND);
    const post = await prisma.contentPost.findFirst({ where: { id, userId: user.id }, select: { contentId: true } });
    if (!post) throw new UserError(POST_NOT_FOUND);
    await deleteSynced(user.id, "contentPosts", id);
    // Removing the last unposted variant can complete the item.
    await prisma.$transaction((db) => applyAutoStage(db, user.id, post.contentId));
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

// ---------- Queries (client-side range switching) ----------

/** Calendar data for [from, to] (YYYY-MM-DD, ≤ 62 days) — see `getContentCalendar`. */
export async function fetchContentCalendar(range: { from: string; to: string; timeZone?: string }): Promise<ActionResult<{ calendar: CalendarData }>> {
  const user = await requireUser();
  return runAction("content", async () => {
    assertObject(range);
    if (typeof range.from !== "string" || typeof range.to !== "string") throw new UserError("Rentang tanggal tidak valid");
    const timeZone = typeof range.timeZone === "string" && validTimeZone(range.timeZone) ? range.timeZone : undefined;
    return { calendar: await getContentCalendar(user.id, { from: range.from, to: range.to, timeZone }) };
  });
}

/** Report + sponsor summary for [from, to] — see `getContentReport`. */
export async function fetchContentReport(range: { from: string; to: string; timeZone?: string }) {
  const user = await requireUser();
  return runAction("content", async () => {
    assertObject(range);
    if (typeof range.from !== "string" || typeof range.to !== "string") throw new UserError("Rentang tanggal tidak valid");
    const timeZone = typeof range.timeZone === "string" && validTimeZone(range.timeZone) ? range.timeZone : undefined;
    return getContentReport(user.id, { from: range.from, to: range.to, timeZone });
  });
}

function validTimeZone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat("en", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}
