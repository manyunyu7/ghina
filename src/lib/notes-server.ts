import { Prisma } from "@prisma/client";
import type { Db } from "@/lib/ledger";
import { prisma } from "@/lib/prisma";
import { getLinkTitle, type TitleFetchOptions } from "@/lib/link-titles";
import {
  compareLabels,
  compareNotes,
  defaultNoteLabel,
  labelNameTaken,
  mergeLinks,
  noteLabelSchema,
  noteMatches,
  noteSchema,
  parseAudio,
  parseChecklist,
  parseImageList,
  parseLabelIds,
  parseLinks,
  toJson,
  type AudioClip,
  type ChecklistItem,
  type NoteData,
  type NoteLink,
} from "@/lib/notes";

/**
 * DB-side note helpers shared by the mobile sync endpoint and the web server actions
 * (docs/notes.md). Pure rules live in src/lib/notes.ts; deletes in src/lib/sync-deletes.ts.
 */

/** A validation failure whose message is safe to show the user / return to a client. */
export class NoteError extends Error {}

type NoteRow = Prisma.NoteGetPayload<object>;
type LabelRow = Prisma.NoteLabelGetPayload<object>;

/** A note row in the wire / `noteSchema` input shape (JSON columns parsed). */
export function noteRowToInput(row: NoteRow) {
  return {
    title: row.title,
    body: row.body,
    checklist: parseChecklist(row.checklist),
    labels: parseLabelIds(row.labels),
    color: row.color,
    pinned: row.pinned,
    archived: row.archived,
    photos: parseImageList(row.photos),
    audio: parseAudio(row.audio),
    links: parseLinks(row.links),
    source: row.source,
    linkedTaskId: row.linkedTaskId,
    linkedContentId: row.linkedContentId,
    linkedTransactionId: row.linkedTransactionId,
  };
}

export type NoteDTO = ReturnType<typeof noteRowToInput> & { id: string; createdAt: string; updatedAt: string };

export function toNoteDTO(row: NoteRow): NoteDTO {
  return { id: row.id, ...noteRowToInput(row), createdAt: row.createdAt.toISOString(), updatedAt: row.updatedAt.toISOString() };
}

export type NoteLabelDTO = { id: string; name: string; color: string; pinnedTab: boolean; sortOrder: number };

export const toLabelDTO = (l: LabelRow): NoteLabelDTO => ({
  id: l.id,
  name: l.name,
  color: l.color,
  pinnedTab: l.pinnedTab,
  sortOrder: l.sortOrder,
});

function noteToDb(n: NoteData) {
  return {
    ...n,
    checklist: toJson(n.checklist),
    labels: toJson(n.labels),
    photos: toJson(n.photos),
    audio: toJson(n.audio),
    links: toJson(n.links),
  };
}

/**
 * Soft references (links to rows that may have been deleted on another device while
 * this one was offline) are resolved leniently: label ids / link targets that aren't
 * the user's rows are dropped / nulled instead of rejecting the whole note.
 */
async function resolveNoteRefs(db: Db, userId: string, n: NoteData) {
  if (n.labels.length) {
    const own = await db.noteLabel.findMany({ where: { userId, id: { in: n.labels } }, select: { id: true } });
    const ok = new Set(own.map((l) => l.id));
    n.labels = n.labels.filter((id) => ok.has(id));
  }
  if (n.linkedTaskId && !(await db.task.findFirst({ where: { id: n.linkedTaskId, userId }, select: { id: true } })))
    n.linkedTaskId = null;
  if (n.linkedContentId && !(await db.contentItem.findFirst({ where: { id: n.linkedContentId, userId }, select: { id: true } })))
    n.linkedContentId = null;
  if (
    n.linkedTransactionId &&
    !(await db.transaction.findFirst({ where: { id: n.linkedTransactionId, userId }, select: { id: true } }))
  )
    n.linkedTransactionId = null;
}

export type SavedNote = {
  row: NoteRow;
  /** Upload URLs no longer used by this note — delete after commit (`deleteUnreferencedUploads`). */
  removedFiles: string[];
  /** Some link has no title yet — call `queueNoteLinkTitles` after commit. */
  needsTitles: boolean;
};

/**
 * Validate (zod + refs) and create or update note `id` (a user edit: `editedAt` = now).
 * Link titles already stored for the same URL are kept when the input has none.
 */
export async function saveNote(db: Db, userId: string, id: string, input: unknown, existing: NoteRow | null): Promise<SavedNote> {
  const n: NoteData = noteSchema.parse(input);
  if (existing) n.links = mergeLinks(n.links, "", parseLinks(existing.links));
  await resolveNoteRefs(db, userId, n);
  const data = { ...noteToDb(n), editedAt: new Date() };
  const row = existing
    ? await db.note.update({ where: { id }, data })
    : await db.note.create({ data: { id, userId, ...data } });
  const removedFiles = existing
    ? [
        ...parseImageList(existing.photos).filter((u) => !n.photos.includes(u)),
        ...parseAudio(existing.audio)
          .map((a) => a.url)
          .filter((u) => !n.audio.some((a) => a.url === u)),
      ]
    : [];
  return { row, removedFiles, needsTitles: n.links.some((l) => !l.title) };
}

/**
 * Validate and create or update label `id`. Names are unique per user case-insensitively:
 * another label holding the name → "duplicate" (nothing written).
 */
export async function saveNoteLabel(
  db: Db,
  userId: string,
  id: string,
  input: unknown,
  exists: boolean,
): Promise<"applied" | "duplicate"> {
  const d = noteLabelSchema.parse(input);
  const others = await db.noteLabel.findMany({ where: { userId }, select: { id: true, name: true } });
  if (labelNameTaken(others, d.name, id)) return "duplicate";
  if (exists) await db.noteLabel.update({ where: { id }, data: d });
  else await db.noteLabel.create({ data: { id, userId, ...d } });
  return "applied";
}

/**
 * Seed the default `Ide Konten` label (deterministic id `label-ide-konten-<userId>`,
 * pinned tab) unless it exists, was deleted by the user (tombstone), or another label
 * already has that name. Idempotent; returns 1 when created.
 */
export async function ensureDefaultNoteLabel(db: Db, userId: string): Promise<number> {
  const { id, ...d } = defaultNoteLabel(userId);
  if (await db.noteLabel.findUnique({ where: { id }, select: { id: true } })) return 0;
  if (await db.syncTombstone.findFirst({ where: { userId, entity: "noteLabels", entityId: id }, select: { id: true } })) return 0;
  const others = await db.noteLabel.findMany({ where: { userId }, select: { id: true, name: true } });
  if (labelNameTaken(others, d.name)) return 0;
  try {
    await db.noteLabel.create({ data: { id, userId, ...d } });
    return 1;
  } catch (e) {
    // Concurrent seed — the other request won.
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") return 0;
    throw e;
  }
}

// ---------- Link titles (fire-and-forget after a save) ----------

/**
 * Fill missing link titles of note `noteId` (≤ 5 fetches per run, cached per URL). Only
 * `links` changes (and `updatedAt`, so devices pull it) — never `editedAt`, so a device's
 * next edit isn't skipped by last-write-wins. Returns the number of titles filled.
 */
export async function refreshNoteLinkTitles(noteId: string, opts?: TitleFetchOptions): Promise<number> {
  const note = await prisma.note.findUnique({ where: { id: noteId }, select: { links: true } });
  if (!note) return 0;
  const missing = parseLinks(note.links)
    .filter((l) => !l.title)
    .slice(0, 5);
  if (!missing.length) return 0;
  const found = new Map<string, string>();
  for (const l of missing) {
    const t = await getLinkTitle(l.url, opts);
    if (t) found.set(l.url, t);
  }
  if (!found.size) return 0;
  // Re-read inside a transaction: the note may have changed while fetching.
  return prisma.$transaction(async (db) => {
    const cur = await db.note.findUnique({ where: { id: noteId }, select: { links: true } });
    if (!cur) return 0;
    let n = 0;
    const links: NoteLink[] = parseLinks(cur.links).map((l) => {
      const t = !l.title ? found.get(l.url) : undefined;
      if (t) n++;
      return t ? { ...l, title: t } : l;
    });
    if (n) await db.note.update({ where: { id: noteId }, data: { links: toJson(links) } });
    return n;
  });
}

/** Start `refreshNoteLinkTitles` without waiting (never throws, never blocks a save). */
export function queueNoteLinkTitles(noteId: string) {
  void refreshNoteLinkTitles(noteId).catch((e) => console.error("[link titles]", e));
}

// ---------- Queries for the web UI ----------

export type NoteFilter = {
  /** true = only archived, false (default) = only not archived, "all" = both. */
  archived?: boolean | "all";
  /** Only notes with this label. */
  labelId?: string;
  /** Search in title/body/checklist/transcripts/link titles. */
  q?: string;
};

/** The user's labels (seeding `Ide Konten` on first use), ordered. */
export async function getNoteLabels(userId: string): Promise<NoteLabelDTO[]> {
  await ensureDefaultNoteLabel(prisma, userId);
  const rows = await prisma.noteLabel.findMany({ where: { userId } });
  return rows.map(toLabelDTO).sort(compareLabels);
}

/** Notes for the grid: filtered, pinned first, then most recently updated. */
export async function getNotes(userId: string, filter: NoteFilter = {}): Promise<NoteDTO[]> {
  const archived = filter.archived ?? false;
  const rows = await prisma.note.findMany({
    where: {
      userId,
      ...(archived === "all" ? {} : { archived }),
      ...(filter.labelId ? { labels: { contains: JSON.stringify(filter.labelId) } } : {}),
    },
    orderBy: { updatedAt: "desc" },
  });
  let notes = rows.map(toNoteDTO);
  if (filter.labelId) notes = notes.filter((n) => n.labels.includes(filter.labelId!));
  if (filter.q?.trim()) notes = notes.filter((n) => noteMatches(n, filter.q!));
  return notes.sort(compareNotes);
}

export async function getNote(userId: string, id: string): Promise<NoteDTO | null> {
  if (typeof id !== "string" || !id) return null;
  const row = await prisma.note.findFirst({ where: { id, userId } });
  return row ? toNoteDTO(row) : null;
}

export type { AudioClip, ChecklistItem, NoteLink };
