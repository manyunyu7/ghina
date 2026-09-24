import { Prisma } from "@prisma/client";
import { createLedgerTransaction, type Db } from "@/lib/ledger";
import { prisma } from "@/lib/prisma";
import {
  autoStage,
  buildContentReport,
  compareAccounts,
  comparePillars,
  contentItemSchema,
  contentPillarSchema,
  contentPostSchema,
  daysInRange,
  DEFAULT_TIME_ZONE,
  defaultPillars,
  localDateKey,
  parseAssetLinks,
  parseMetrics,
  parseSponsor,
  pillarNameTaken,
  postTime,
  socialAccountSchema,
  sponsorSummary,
  sponsorTransactionNote,
  weekSlots,
  weeksInRange,
  type ContentItemData,
  type ContentReport,
  type Metrics,
  type Sponsor,
  type SponsorSummary,
  type WeekSlot,
} from "@/lib/content";
import { ideaLabelId, parseChecklist, parseImageList, toJson } from "@/lib/notes";
import { renamePillar } from "@/lib/sync-links";
import { toNoteDTO, type NoteDTO } from "@/lib/notes-server";
import { isValidDateKey } from "@/lib/prayer-quality";

/**
 * DB-side content-planner helpers shared by the mobile sync endpoint and the web server
 * actions (docs/content.md). Pure rules live in src/lib/content.ts; deletes in
 * src/lib/sync-deletes.ts.
 */

/** A validation failure whose message is safe to show the user / return to a client. */
export class ContentError extends Error {}

type AccountRow = Prisma.SocialAccountGetPayload<object>;
type PillarRow = Prisma.ContentPillarGetPayload<object>;
type ItemRow = Prisma.ContentItemGetPayload<object>;
type PostRow = Prisma.ContentPostGetPayload<object>;

// ---------- Rows → wire / input shapes ----------

export function accountRowToInput(r: AccountRow) {
  return {
    platform: r.platform,
    platformName: r.platformName,
    handle: r.handle,
    color: r.color,
    targetPerWeek: r.targetPerWeek,
    archived: r.archived,
    sortOrder: r.sortOrder,
  };
}

export function pillarRowToInput(r: PillarRow) {
  return { name: r.name, color: r.color, sortOrder: r.sortOrder };
}

export function itemRowToInput(r: ItemRow) {
  return {
    title: r.title,
    stage: r.stage,
    format: r.format,
    pillar: r.pillar,
    idea: r.idea,
    noteId: r.noteId,
    checklist: parseChecklist(r.checklist),
    photos: parseImageList(r.photos),
    assetLinks: parseAssetLinks(r.assetLinks),
    sponsor: parseSponsor(r.sponsor),
  };
}

export function postRowToInput(r: PostRow) {
  return {
    contentId: r.contentId,
    accountId: r.accountId,
    caption: r.caption,
    hashtags: r.hashtags,
    scheduledAt: r.scheduledAt?.toISOString() ?? null,
    remindBefore: r.remindBefore,
    status: r.status,
    postedAt: r.postedAt?.toISOString() ?? null,
    url: r.url,
    metrics: parseMetrics(r.metrics),
    metricsAt: r.metricsAt?.toISOString() ?? null,
  };
}

// ---------- DTOs (web UI) ----------

const stamps = (r: { id: string; createdAt: Date; updatedAt: Date }) => ({
  id: r.id,
  createdAt: r.createdAt.toISOString(),
  updatedAt: r.updatedAt.toISOString(),
});

export type SocialAccountDTO = ReturnType<typeof toAccountDTO>;
export const toAccountDTO = (r: AccountRow) => ({ ...stamps(r), ...accountRowToInput(r) });
export type ContentPillarDTO = ReturnType<typeof toPillarDTO>;
export const toPillarDTO = (r: PillarRow) => ({ ...stamps(r), ...pillarRowToInput(r) });
export type ContentItemDTO = ReturnType<typeof toItemDTO>;
export const toItemDTO = (r: ItemRow) => ({ ...stamps(r), ...itemRowToInput(r) });
export type ContentPostDTO = ReturnType<typeof toPostDTO>;
export const toPostDTO = (r: PostRow) => ({ ...stamps(r), ...postRowToInput(r) });

// ---------- Saves ----------

export async function saveSocialAccount(db: Db, userId: string, id: string, input: unknown, exists: boolean) {
  const d = socialAccountSchema.parse(input);
  return exists
    ? db.socialAccount.update({ where: { id }, data: d })
    : db.socialAccount.create({ data: { id, userId, ...d } });
}

/**
 * Create or update a pillar. Names are unique per user (case-insensitive): another pillar
 * holding it → "duplicate". A rename also renames the pillar on the user's content items.
 */
export async function saveContentPillar(
  db: Db,
  userId: string,
  id: string,
  input: unknown,
  existing: PillarRow | null,
): Promise<"applied" | "duplicate"> {
  const d = contentPillarSchema.parse(input);
  const others = await db.contentPillar.findMany({ where: { userId }, select: { id: true, name: true } });
  if (pillarNameTaken(others, d.name, id)) return "duplicate";
  if (existing) {
    await db.contentPillar.update({ where: { id }, data: d });
    await renamePillar(db, userId, existing.name, d.name);
  } else {
    await db.contentPillar.create({ data: { id, userId, ...d } });
  }
  return "applied";
}

function itemToDb(d: ContentItemData) {
  return {
    ...d,
    checklist: toJson(d.checklist),
    photos: toJson(d.photos),
    assetLinks: toJson(d.assetLinks),
    sponsor: d.sponsor ? toJson(d.sponsor) : null,
  };
}

/** Whether `id` is one of the user's income transactions (the only kind a sponsor links). */
async function isIncomeTransaction(db: Db, userId: string, id: string): Promise<boolean> {
  return !!(await db.transaction.findFirst({ where: { id, userId, type: "income" }, select: { id: true } }));
}

/**
 * Validate and create or update content item `id`. Soft links are resolved leniently: a
 * `noteId` that isn't the user's note, or a `sponsor.transactionId` that isn't one of the
 * user's income transactions, becomes null (it may have been deleted while a device was
 * offline). Returns the row and the photo URLs it no longer uses (delete after commit).
 */
export async function saveContentItem(db: Db, userId: string, id: string, input: unknown, existing: ItemRow | null) {
  const d = contentItemSchema.parse(input);
  if (d.noteId && !(await db.note.findFirst({ where: { id: d.noteId, userId }, select: { id: true } }))) d.noteId = null;
  if (d.sponsor?.transactionId && !(await isIncomeTransaction(db, userId, d.sponsor.transactionId)))
    d.sponsor = { ...d.sponsor, transactionId: null };
  const data = itemToDb(d);
  const row = existing
    ? await db.contentItem.update({ where: { id }, data })
    : await db.contentItem.create({ data: { id, userId, ...data } });
  const removedFiles = existing ? parseImageList(existing.photos).filter((u) => !d.photos.includes(u)) : [];
  return { row, removedFiles };
}

/** Validate and create or update post `id`; its content item and account must be the user's. */
export async function saveContentPost(db: Db, userId: string, id: string, input: unknown, exists: boolean) {
  const d = contentPostSchema.parse(input);
  const item = await db.contentItem.findFirst({ where: { id: d.contentId, userId }, select: { id: true } });
  if (!item) throw new ContentError("Konten tidak ditemukan");
  const acc = await db.socialAccount.findFirst({ where: { id: d.accountId, userId }, select: { id: true } });
  if (!acc) throw new ContentError("Akun tidak ditemukan");
  const data = { ...d, metrics: toJson(d.metrics) };
  return exists
    ? db.contentPost.update({ where: { id }, data })
    : db.contentPost.create({ data: { id, userId, ...data } });
}

/**
 * Apply the stage auto-advance rule (`autoStage`) to item `contentId` after its posts
 * changed. Returns the new stage when it moved, else null.
 */
export async function applyAutoStage(db: Db, userId: string, contentId: string): Promise<string | null> {
  const item = await db.contentItem.findFirst({ where: { id: contentId, userId }, select: { stage: true } });
  if (!item) return null;
  const posts = await db.contentPost.findMany({ where: { userId, contentId }, select: { status: true } });
  const next = autoStage(item.stage, posts);
  if (next === item.stage) return null;
  await db.contentItem.update({ where: { id: contentId }, data: { stage: next } });
  return next;
}

/**
 * Seed the default pillars (Edukasi, Hiburan, Promo, Behind the scene, Personal;
 * deterministic ids `pillar-<key>-<userId>`) once: only when the user has no pillars and
 * none of the default ids was ever deleted (tombstone). Returns the number created.
 */
export async function ensureDefaultContentPillars(db: Db, userId: string): Promise<number> {
  if ((await db.contentPillar.count({ where: { userId } })) > 0) return 0;
  const defaults = defaultPillars(userId);
  const tomb = await db.syncTombstone.findFirst({
    where: { userId, entity: "contentPillars", entityId: { in: defaults.map((p) => p.id) } },
    select: { id: true },
  });
  if (tomb) return 0;
  let created = 0;
  for (const { id, ...p } of defaults) {
    try {
      await db.contentPillar.create({ data: { id, userId, ...p } });
      created++;
    } catch (e) {
      if (!(e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002")) throw e;
    }
  }
  return created;
}

// ---------- Sponsorship ----------

export type SponsorPaidInput = {
  walletId: string;
  /** Default: sponsor amount (must be > 0). */
  amount?: number;
  /** Income category (optional). */
  categoryId?: string | null;
  /** Default: now. */
  date?: Date;
  /** Default: "Endorse <brand>". */
  note?: string;
};

/**
 * Mark an item's sponsor paid. With `record`, an **income** transaction is recorded
 * through the ledger (moving the wallet balance) and linked as `sponsor.transactionId`.
 * A sponsor that already has a linked transaction never records a second one.
 */
export async function markSponsorPaid(
  db: Db,
  userId: string,
  itemId: string,
  record: SponsorPaidInput | null,
): Promise<{ sponsor: Sponsor; transactionId: string | null }> {
  const item = await db.contentItem.findFirst({ where: { id: itemId, userId } });
  if (!item) throw new ContentError("Konten tidak ditemukan");
  const s = parseSponsor(item.sponsor);
  if (!s) throw new ContentError("Konten ini tidak punya sponsor");
  // An income recorded earlier (still linked after "unpaid") is reused — never a second one.
  let transactionId = s.transactionId && (await isIncomeTransaction(db, userId, s.transactionId)) ? s.transactionId : null;
  if (record && !transactionId) {
    const amount = record.amount ?? s.amount;
    if (!(typeof amount === "number" && Number.isFinite(amount) && amount > 0))
      throw new ContentError("Nominal harus lebih dari 0");
    if (typeof record.walletId !== "string" || !record.walletId) throw new ContentError("Pilih dompet");
    const wallet = await db.wallet.findFirst({ where: { id: record.walletId, userId }, select: { id: true } });
    if (!wallet) throw new ContentError("Dompet tidak ditemukan");
    let categoryId: string | null = null;
    if (record.categoryId) {
      if (typeof record.categoryId !== "string") throw new ContentError("Kategori tidak ditemukan");
      const cat = await db.category.findFirst({ where: { id: record.categoryId, userId }, select: { type: true } });
      if (!cat) throw new ContentError("Kategori tidak ditemukan");
      if (cat.type !== "income") throw new ContentError("Kategori harus kategori pemasukan");
      categoryId = record.categoryId;
    }
    const date = record.date instanceof Date && !Number.isNaN(record.date.getTime()) ? record.date : new Date();
    const note = (typeof record.note === "string" && record.note.trim()) || sponsorTransactionNote(s.brand);
    const tx = await createLedgerTransaction(db, userId, {
      type: "income",
      amount,
      walletId: record.walletId,
      toWalletId: null,
      categoryId,
      note: note.slice(0, 500),
      date,
    });
    transactionId = tx.id;
  }
  const sponsor: Sponsor = { ...s, paid: true, transactionId };
  await db.contentItem.update({ where: { id: itemId }, data: { sponsor: toJson(sponsor) } });
  return { sponsor, transactionId };
}

// ---------- Queries for the web UI ----------

/** Accounts + pillars (seeding the default pillars on first use), ordered. */
export async function getContentSetup(userId: string) {
  await ensureDefaultContentPillars(prisma, userId);
  const [accounts, pillars] = await Promise.all([
    prisma.socialAccount.findMany({ where: { userId } }),
    prisma.contentPillar.findMany({ where: { userId } }),
  ]);
  return {
    accounts: accounts.map(toAccountDTO).sort(compareAccounts),
    pillars: pillars.map(toPillarDTO).sort(comparePillars),
  };
}

/** Pipeline board: every item with its posts (+ accounts/pillars). */
export async function getContentBoard(userId: string) {
  const setup = await getContentSetup(userId);
  const [items, posts] = await Promise.all([
    prisma.contentItem.findMany({ where: { userId }, orderBy: { updatedAt: "desc" } }),
    prisma.contentPost.findMany({ where: { userId } }),
  ]);
  return { ...setup, items: items.map(toItemDTO), posts: posts.map(toPostDTO) };
}

export type CalendarData = {
  from: string;
  to: string;
  timeZone: string;
  /** Every day in range with its posts (sorted by time), each post with its item title. */
  days: { date: string; posts: (ContentPostDTO & { title: string; stage: string })[] }[];
  /** Per ISO week in range: slots vs each account's target ("IG: 1/3 minggu ini"). */
  weeks: { weekStart: string; slots: WeekSlot[] }[];
  accounts: SocialAccountDTO[];
  /** Non-skipped posts without scheduledAt (to drag onto the calendar). */
  unscheduled: (ContentPostDTO & { title: string; stage: string })[];
};

/**
 * Calendar for the local date range [from, to] (YYYY-MM-DD): posts placed by `postTime`
 * (postedAt for posted posts, else scheduledAt) in `timeZone` (default Asia/Jakarta).
 */
export async function getContentCalendar(
  userId: string,
  range: { from: string; to: string; timeZone?: string },
): Promise<CalendarData> {
  const { from, to } = range;
  const timeZone = range.timeZone ?? DEFAULT_TIME_ZONE;
  if (!isValidDateKey(from) || !isValidDateKey(to) || from > to) throw new ContentError("Rentang tanggal tidak valid");
  if (daysInRange(from, to).length > 62) throw new ContentError("Rentang kalender maksimal 62 hari");
  const weeks = weeksInRange(from, to);
  // Load a margin of ±1 day around the whole weeks: local days vs UTC instants.
  const lo = new Date(`${weeks[0]}T00:00:00Z`);
  lo.setUTCDate(lo.getUTCDate() - 1);
  const hi = new Date(`${to}T00:00:00Z`);
  hi.setUTCDate(hi.getUTCDate() + 8);
  const [accounts, posts, unscheduled] = await Promise.all([
    prisma.socialAccount.findMany({ where: { userId } }),
    prisma.contentPost.findMany({
      where: { userId, OR: [{ scheduledAt: { gte: lo, lt: hi } }, { postedAt: { gte: lo, lt: hi } }] },
    }),
    prisma.contentPost.findMany({ where: { userId, scheduledAt: null, status: { in: ["draft"] } } }),
  ]);
  const itemIds = [...new Set([...posts, ...unscheduled].map((p) => p.contentId))];
  const items = new Map(
    (await prisma.contentItem.findMany({ where: { userId, id: { in: itemIds } }, select: { id: true, title: true, stage: true } })).map(
      (i) => [i.id, i],
    ),
  );
  const withTitle = (p: PostRow) => ({ ...toPostDTO(p), title: items.get(p.contentId)?.title ?? "", stage: items.get(p.contentId)?.stage ?? "ide" });
  const byDay = new Map<string, ReturnType<typeof withTitle>[]>();
  for (const p of posts) {
    const t = postTime(p);
    if (!t) continue;
    const k = localDateKey(t, timeZone);
    if (k < from || k > to) continue;
    byDay.set(k, [...(byDay.get(k) ?? []), withTitle(p)]);
  }
  const time = (p: ContentPostDTO) => postTime(p)?.getTime() ?? 0;
  return {
    from,
    to,
    timeZone,
    days: daysInRange(from, to).map((date) => ({ date, posts: (byDay.get(date) ?? []).sort((a, b) => time(a) - time(b)) })),
    weeks: weeks.map((w) => ({ weekStart: w, slots: weekSlots(accounts, posts, w, timeZone) })),
    accounts: accounts.map(toAccountDTO).sort(compareAccounts),
    unscheduled: unscheduled.map(withTitle),
  };
}

/**
 * Report for [from, to] (see `buildContentReport`) plus the sponsor summary. Accounts
 * include archived ones (they may have posted in the range).
 */
export async function getContentReport(
  userId: string,
  range: { from: string; to: string; timeZone?: string },
): Promise<{ report: ContentReport; sponsors: SponsorSummary; accounts: SocialAccountDTO[] }> {
  const { from, to } = range;
  const timeZone = range.timeZone ?? DEFAULT_TIME_ZONE;
  if (!isValidDateKey(from) || !isValidDateKey(to) || from > to) throw new ContentError("Rentang tanggal tidak valid");
  if (daysInRange(from, to).length > 800) throw new ContentError("Rentang laporan maksimal ±2 tahun");
  const [accounts, items, posts] = await Promise.all([
    prisma.socialAccount.findMany({ where: { userId } }),
    prisma.contentItem.findMany({ where: { userId } }),
    prisma.contentPost.findMany({ where: { userId } }),
  ]);
  const today = localDateKey(new Date(), timeZone);
  const report = buildContentReport({
    from,
    to,
    timeZone,
    today,
    accounts,
    items: items.map((i) => ({ id: i.id, title: i.title, pillar: i.pillar, format: i.format })),
    posts: posts.map((p) => ({ ...p, metrics: parseMetrics(p.metrics) as Metrics })),
  });
  const sponsored = items.map((i) => ({ id: i.id, title: i.title, sponsor: parseSponsor(i.sponsor), createdAt: i.createdAt }));
  const txIds = sponsored.map((i) => i.sponsor?.transactionId).filter((x): x is string => !!x);
  const txs = txIds.length
    ? await prisma.transaction.findMany({ where: { userId, id: { in: txIds } }, select: { id: true, date: true } })
    : [];
  const sponsors = sponsorSummary({
    items: sponsored,
    posts,
    transactionDates: new Map(txs.map((t) => [t.id, t.date])),
    today,
    timeZone,
  });
  return { report, sponsors, accounts: accounts.map(toAccountDTO).sort(compareAccounts) };
}

/**
 * Idea inbox: non-archived notes with the `Ide Konten` label that haven't been turned
 * into content yet (`linkedContentId` null), newest first.
 */
export async function getIdeaInbox(userId: string): Promise<NoteDTO[]> {
  const id = ideaLabelId(userId);
  const rows = await prisma.note.findMany({
    where: { userId, archived: false, linkedContentId: null, labels: { contains: JSON.stringify(id) } },
    orderBy: { updatedAt: "desc" },
  });
  return rows.map(toNoteDTO).filter((n) => n.labels.includes(id));
}
