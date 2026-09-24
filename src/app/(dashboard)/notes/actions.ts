"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { transactionSchema } from "@/lib/schemas";
import { createLedgerTransaction, validateTransactionRefs } from "@/lib/ledger";
import { deleteSynced } from "@/lib/sync-deletes";
import { deleteUnreferencedUploads, deleteUpload, saveMediaUpload } from "@/lib/uploads";
import { MAX_TRANSACTION_PHOTOS, serializePhotos } from "@/lib/photos";
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
  AUDIO_DURATION_MAX,
  bodyExcerpt,
  CHECKLIST_MAX,
  NOTE_AUDIO_MAX,
  NOTE_PHOTOS_MAX,
  noteDisplayTitle,
  parseAmount,
  parseAudio,
  parseImageList,
  type AudioClip,
  type ChecklistItem,
  type NoteColorId,
  type NoteLink,
  type NoteSource,
} from "@/lib/notes";
import {
  ensureDefaultNoteLabel,
  noteRowToInput,
  queueNoteLinkTitles,
  saveNote,
  saveNoteLabel,
} from "@/lib/notes-server";
import { saveTask } from "@/lib/tasks-server";
import { saveContentItem } from "@/lib/content-server";
import type { BucketId, Recurrence } from "@/lib/tasks";
import type { FormatId } from "@/lib/content";

/**
 * Server actions for the web Notes page (docs/notes.md). Plain-object arguments (media
 * uploads take FormData), results `{ ok: true, … } | { ok: false, error }` with
 * Indonesian messages. Validation is shared with mobile sync (src/lib/notes.ts,
 * src/lib/notes-server.ts). Link titles are fetched in the background after a save.
 */

/** Editable note fields (media are managed by uploadNoteMedia / removeNoteMedia). */
export type NoteInput = {
  title?: string | null;
  /** Markdown subset, ≤ 50 000 chars. URLs in it are added to `links` automatically. */
  body?: string;
  checklist?: ChecklistItem[];
  /** Label ids (unknown ids are dropped). */
  labels?: string[];
  color?: NoteColorId | null;
  pinned?: boolean;
  archived?: boolean;
  /** Extra links (e.g. shared URLs); body URLs are merged in. */
  links?: NoteLink[];
  source?: NoteSource | null;
  /** Reorder / remove photos: must be a subset of the stored list (removed files are deleted). */
  photos?: string[];
  /** Reorder / remove clips (by url, subset of the stored list); transcripts may be edited. */
  audio?: AudioClip[];
};

export type NoteLabelInput = { name: string; color?: string; pinnedTab?: boolean; sortOrder?: number };

const NOTE_KEYS = ["title", "body", "checklist", "labels", "color", "pinned", "archived", "links", "source"] as const;
const LABEL_KEYS = ["name", "color", "pinnedTab", "sortOrder"] as const;

const NOTE_NOT_FOUND = "Catatan tidak ditemukan";
const LABEL_NOT_FOUND = "Label tidak ditemukan";

function revalidate(extra: string[] = []) {
  revalidatePath("/notes");
  for (const p of extra) revalidatePath(p);
}

type NoteInputShape = ReturnType<typeof noteRowToInput>;

/**
 * Load note `id` (the user's), let `change` edit its input shape, validate + save it in
 * one DB transaction. After commit: unused files are deleted, link titles queued.
 */
async function mutateNote(
  userId: string,
  id: unknown,
  change: (cur: NoteInputShape) => NoteInputShape | Promise<NoteInputShape>,
) {
  assertId(id, NOTE_NOT_FOUND);
  const saved = await prisma.$transaction(async (db) => {
    const existing = await db.note.findFirst({ where: { id, userId } });
    if (!existing) throw new UserError(NOTE_NOT_FOUND);
    return saveNote(db, userId, id, await change(noteRowToInput(existing)), existing);
  });
  await deleteUnreferencedUploads(saved.removedFiles);
  if (saved.needsTitles) queueNoteLinkTitles(id);
  return saved.row;
}

// ---------- Notes ----------

export async function createNote(input: NoteInput = {}): Promise<ActionResult<{ id: string }>> {
  const user = await requireUser();
  const res = await runAction("notes", async () => {
    assertObject(input);
    const id = randomUUID();
    const saved = await prisma.$transaction((db) => saveNote(db, user.id, id, pick(input, NOTE_KEYS), null));
    if (saved.needsTitles) queueNoteLinkTitles(id);
    return { id };
  });
  if (res.ok) revalidate();
  return res;
}

/** Patch a note (anything omitted keeps its value). */
export async function updateNote(id: string, patch: NoteInput): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("notes", async () => {
    assertObject(patch);
    await mutateNote(user.id, id, (cur) => {
      const next = { ...cur, ...pick(patch, NOTE_KEYS) } as NoteInputShape;
      if (patch.photos !== undefined) {
        if (!Array.isArray(patch.photos) || patch.photos.some((u) => !cur.photos.includes(u)))
          throw new UserError("Foto tidak ditemukan di catatan ini");
        next.photos = patch.photos;
      }
      if (patch.audio !== undefined) {
        if (!Array.isArray(patch.audio) || patch.audio.some((a) => !cur.audio.some((c) => c.url === a?.url)))
          throw new UserError("Rekaman tidak ditemukan di catatan ini");
        next.audio = patch.audio;
      }
      return next;
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

/** Delete a note for good (tombstoned; its photo/audio files are removed). */
export async function deleteNote(id: string): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("notes", async () => {
    assertId(id, NOTE_NOT_FOUND);
    if (!(await prisma.note.findFirst({ where: { id, userId: user.id }, select: { id: true } }))) throw new UserError(NOTE_NOT_FOUND);
    await deleteSynced(user.id, "notes", id);
    return {};
  });
  if (res.ok) revalidate(["/content"]);
  return res;
}

export async function setNotePinned(id: string, pinned: boolean): Promise<ActionResult> {
  return updateNote(id, { pinned: pinned === true });
}

export async function setNoteArchived(id: string, archived: boolean): Promise<ActionResult> {
  return updateNote(id, { archived: archived === true });
}

/** `color`: a NOTE_COLORS id, or null for the default card color. */
export async function setNoteColor(id: string, color: NoteColorId | null): Promise<ActionResult> {
  return updateNote(id, { color });
}

/** Replace a note's labels (label ids; unknown ids are dropped). */
export async function setNoteLabels(id: string, labelIds: string[]): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("notes", async () => {
    assertIds(labelIds, LABEL_NOT_FOUND);
    await mutateNote(user.id, id, (cur) => ({ ...cur, labels: labelIds }));
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

// ---------- Checklist ----------

async function mutateChecklist(id: string, change: (items: ChecklistItem[]) => ChecklistItem[]): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("notes", async () => {
    await mutateNote(user.id, id, (cur) => ({ ...cur, checklist: change(cur.checklist) }));
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

const ITEM_NOT_FOUND = "Item checklist tidak ditemukan";

/** Append an item (or insert at `index`). Returns its id. */
export async function addChecklistItem(
  noteId: string,
  text: string,
  opts: { done?: boolean; index?: number } = {},
): Promise<ActionResult<{ itemId: string }>> {
  const itemId = randomUUID();
  const res = await mutateChecklist(noteId, (items) => {
    if (typeof text !== "string") throw new UserError("Teks item tidak valid");
    if (items.length >= CHECKLIST_MAX) throw new UserError(`Maksimal ${CHECKLIST_MAX} item checklist`);
    const item = { id: itemId, text, done: opts?.done === true };
    const at = typeof opts?.index === "number" && Number.isInteger(opts.index) ? Math.max(0, Math.min(opts.index, items.length)) : items.length;
    return [...items.slice(0, at), item, ...items.slice(at)];
  });
  return res.ok ? { ok: true, itemId } : res;
}

export async function updateChecklistItem(
  noteId: string,
  itemId: string,
  patch: { text?: string; done?: boolean },
): Promise<ActionResult> {
  return mutateChecklist(noteId, (items) => {
    assertObject(patch);
    if (!items.some((i) => i.id === itemId)) throw new UserError(ITEM_NOT_FOUND);
    return items.map((i) =>
      i.id === itemId
        ? { ...i, ...(typeof patch.text === "string" ? { text: patch.text } : {}), ...(typeof patch.done === "boolean" ? { done: patch.done } : {}) }
        : i,
    );
  });
}

export async function toggleChecklistItem(noteId: string, itemId: string): Promise<ActionResult> {
  return mutateChecklist(noteId, (items) => {
    if (!items.some((i) => i.id === itemId)) throw new UserError(ITEM_NOT_FOUND);
    return items.map((i) => (i.id === itemId ? { ...i, done: !i.done } : i));
  });
}

export async function removeChecklistItem(noteId: string, itemId: string): Promise<ActionResult> {
  return mutateChecklist(noteId, (items) => items.filter((i) => i.id !== itemId));
}

/** New order: `orderedIds` must be exactly the note's item ids. */
export async function reorderChecklist(noteId: string, orderedIds: string[]): Promise<ActionResult> {
  return mutateChecklist(noteId, (items) => {
    assertIds(orderedIds, ITEM_NOT_FOUND);
    const byId = new Map(items.map((i) => [i.id, i]));
    if (orderedIds.length !== items.length || new Set(orderedIds).size !== items.length || orderedIds.some((i) => !byId.has(i)))
      throw new UserError(ITEM_NOT_FOUND);
    return orderedIds.map((i) => byId.get(i)!);
  });
}

/** Remove all ticked items. */
export async function clearCheckedItems(noteId: string): Promise<ActionResult> {
  return mutateChecklist(noteId, (items) => items.filter((i) => !i.done));
}

// ---------- Labels ----------

export async function createNoteLabel(input: NoteLabelInput): Promise<ActionResult<{ id: string }>> {
  const user = await requireUser();
  const res = await runAction("notes", async () => {
    assertObject(input);
    const fields = pick(input, LABEL_KEYS);
    if (fields.sortOrder === undefined) {
      const last = await prisma.noteLabel.aggregate({ where: { userId: user.id }, _max: { sortOrder: true } });
      fields.sortOrder = (last._max.sortOrder ?? -1) + 1;
    }
    const id = randomUUID();
    const out = await prisma.$transaction((db) => saveNoteLabel(db, user.id, id, fields, false));
    if (out === "duplicate") throw new UserError("Nama label sudah dipakai");
    return { id };
  });
  if (res.ok) revalidate();
  return res;
}

/** Patch a label (rename, color, pinned tab, order). Notes keep it (they store its id). */
export async function updateNoteLabel(id: string, patch: Partial<NoteLabelInput>): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("notes", async () => {
    assertId(id, LABEL_NOT_FOUND);
    assertObject(patch);
    await prisma.$transaction(async (db) => {
      const l = await db.noteLabel.findFirst({ where: { id, userId: user.id } });
      if (!l) throw new UserError(LABEL_NOT_FOUND);
      const merged = { name: l.name, color: l.color, pinnedTab: l.pinnedTab, sortOrder: l.sortOrder, ...pick(patch, LABEL_KEYS) };
      if ((await saveNoteLabel(db, user.id, id, merged, true)) === "duplicate") throw new UserError("Nama label sudah dipakai");
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

export async function setLabelPinnedTab(id: string, pinnedTab: boolean): Promise<ActionResult> {
  return updateNoteLabel(id, { pinnedTab: pinnedTab === true });
}

/** Delete a label; it is removed from every note (which re-syncs). */
export async function deleteNoteLabel(id: string): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("notes", async () => {
    assertId(id, LABEL_NOT_FOUND);
    if (!(await prisma.noteLabel.findFirst({ where: { id, userId: user.id }, select: { id: true } }))) throw new UserError(LABEL_NOT_FOUND);
    await deleteSynced(user.id, "noteLabels", id);
    return {};
  });
  if (res.ok) revalidate(["/content"]);
  return res;
}

/** Label order: sortOrder = index in `orderedIds` (all must be the user's). */
export async function reorderNoteLabels(orderedIds: string[]): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("notes", async () => {
    assertIds(orderedIds, LABEL_NOT_FOUND);
    const ids = [...new Set(orderedIds)];
    await prisma.$transaction(async (db) => {
      if ((await db.noteLabel.count({ where: { id: { in: ids }, userId: user.id } })) !== ids.length) throw new UserError(LABEL_NOT_FOUND);
      for (const [i, id] of ids.entries()) await db.noteLabel.update({ where: { id }, data: { sortOrder: i } });
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

/** Seed `Ide Konten` if missing (idempotent; pages may call `getNoteLabels` instead). */
export async function ensureDefaultLabel(): Promise<ActionResult<{ created: number }>> {
  const user = await requireUser();
  return runAction("notes", async () => ({ created: await ensureDefaultNoteLabel(prisma, user.id) }));
}

// ---------- Photos / voice notes ----------

/**
 * Attach media to a note. FormData fields: `noteId`; `photos` (image files, ≤ 5 MB each);
 * `audio` (audio files, ≤ 20 MB each) with, per audio file in the same order,
 * `audioDuration` (seconds, required) and `audioTranscript` (optional). Limits: 10
 * photos, 5 clips per note. Types are detected from the bytes. Returns the new lists.
 */
export async function uploadNoteMedia(
  formData: FormData,
): Promise<ActionResult<{ photos: string[]; audio: AudioClip[] }>> {
  const user = await requireUser();
  const written: string[] = [];
  const res = await runAction("notes", async () => {
    if (!(formData instanceof FormData)) throw new UserError("Data tidak valid");
    const noteId = formData.get("noteId");
    assertId(noteId, NOTE_NOT_FOUND);
    const photoFiles = formFiles(formData, "photos");
    const audioFiles = formFiles(formData, "audio");
    const durations = formData.getAll("audioDuration").map((v) => Number(v));
    const transcripts = formData.getAll("audioTranscript").map((v) => (typeof v === "string" ? v : ""));
    if (!photoFiles.length && !audioFiles.length) throw new UserError("Pilih foto atau rekaman");
    if (durations.length < audioFiles.length || durations.some((d) => !Number.isFinite(d) || d < 0 || d > AUDIO_DURATION_MAX))
      throw new UserError("Durasi rekaman tidak valid (maks 10 menit)");
    const cur = await prisma.note.findFirst({ where: { id: noteId, userId: user.id }, select: { id: true, photos: true, audio: true } });
    if (!cur) throw new UserError(NOTE_NOT_FOUND);
    const stored = { photos: parseImageList(cur.photos), audio: parseAudio(cur.audio) };
    if (stored.photos.length + photoFiles.length > NOTE_PHOTOS_MAX) throw new UserError(`Maksimal ${NOTE_PHOTOS_MAX} foto per catatan`);
    if (stored.audio.length + audioFiles.length > NOTE_AUDIO_MAX) throw new UserError(`Maksimal ${NOTE_AUDIO_MAX} rekaman per catatan`);
    const newPhotos: string[] = [];
    const newAudio: AudioClip[] = [];
    // saveMediaUpload's errors (type / size) are user-facing.
    const save = (f: File, kind: "image" | "audio") =>
      saveMediaUpload(f, [kind]).catch((e: unknown) => {
        throw new UserError(e instanceof Error ? e.message : "Unggah gagal");
      });
    for (const f of photoFiles) {
      const { url } = await save(f, "image");
      written.push(url);
      newPhotos.push(url);
    }
    for (const [i, f] of audioFiles.entries()) {
      const { url } = await save(f, "audio");
      written.push(url);
      newAudio.push({ url, durationSec: durations[i], transcript: transcripts[i]?.trim() || null });
    }
    const row = await mutateNote(user.id, noteId, (n) => ({ ...n, photos: [...n.photos, ...newPhotos], audio: [...n.audio, ...newAudio] }));
    const out = noteRowToInput(row);
    return { photos: out.photos, audio: out.audio };
  });
  if (!res.ok) await Promise.all(written.map((u) => deleteUpload(u)));
  else revalidate();
  return res;
}

/** Remove a photo or voice clip (by url) from a note; the file is deleted if unused elsewhere. */
export async function removeNoteMedia(noteId: string, url: string): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("notes", async () => {
    if (typeof url !== "string") throw new UserError("File tidak ditemukan");
    await mutateNote(user.id, noteId, (n) => {
      if (!n.photos.includes(url) && !n.audio.some((a) => a.url === url)) throw new UserError("File tidak ditemukan di catatan ini");
      return { ...n, photos: n.photos.filter((u) => u !== url), audio: n.audio.filter((a) => a.url !== url) };
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

/** Set (or clear with null/"") a voice clip's transcript. */
export async function setAudioTranscript(noteId: string, url: string, transcript: string | null): Promise<ActionResult> {
  const user = await requireUser();
  const res = await runAction("notes", async () => {
    if (transcript != null && typeof transcript !== "string") throw new UserError("Transkrip tidak valid");
    await mutateNote(user.id, noteId, (n) => {
      if (!n.audio.some((a) => a.url === url)) throw new UserError("Rekaman tidak ditemukan di catatan ini");
      return { ...n, audio: n.audio.map((a) => (a.url === url ? { ...a, transcript: transcript || null } : a)) };
    });
    return {};
  });
  if (res.ok) revalidate();
  return res;
}

// ---------- Convert to action ----------

export type NoteConversionPrefill = {
  task: { title: string; note: string | null };
  content: { title: string; idea: string };
  transaction: {
    /** Parsed from the note when a single `Rp …`/number is found, else null. */
    amount: number | null;
    note: string;
    /** First 5 note photos (a transaction holds ≤ 5). */
    photos: string[];
  };
  linkedTaskId: string | null;
  linkedContentId: string | null;
  linkedTransactionId: string | null;
};

/** Prefill values for the three convert dialogs. */
export async function getNoteConversion(noteId: string): Promise<ActionResult<NoteConversionPrefill>> {
  const user = await requireUser();
  return runAction("notes", async () => {
    assertId(noteId, NOTE_NOT_FOUND);
    const row = await prisma.note.findFirst({ where: { id: noteId, userId: user.id } });
    if (!row) throw new UserError(NOTE_NOT_FOUND);
    const n = noteRowToInput(row);
    const title = noteDisplayTitle(n);
    const text = [n.title ?? "", n.body, ...n.checklist.map((c) => c.text)].join("\n");
    return {
      task: { title, note: bodyExcerpt(n.body, 2000) || null },
      content: { title, idea: n.body },
      transaction: { amount: parseAmount(text), note: title.slice(0, 200), photos: n.photos.slice(0, MAX_TRANSACTION_PHOTOS) },
      linkedTaskId: n.linkedTaskId,
      linkedContentId: n.linkedContentId,
      linkedTransactionId: n.linkedTransactionId,
    };
  });
}

export type NoteToTaskInput = {
  areaId: string;
  bucket?: BucketId;
  /** Default: note title / first line. */
  title?: string;
  /** Default: body excerpt. */
  note?: string | null;
  dueDate?: string | null;
  dueTime?: string | null;
  remindBefore?: number | null;
  recurrence?: Recurrence | null;
  amount?: number | null;
  walletId?: string | null;
  categoryId?: string | null;
};

/** → Tugas: create a task from the note and set the note's `linkedTaskId`. */
export async function convertNoteToTask(noteId: string, input: NoteToTaskInput): Promise<ActionResult<{ taskId: string }>> {
  const user = await requireUser();
  const res = await runAction("notes", async () => {
    assertObject(input);
    assertId(noteId, NOTE_NOT_FOUND);
    const taskId = randomUUID();
    const saved = await prisma.$transaction(async (db) => {
      const row = await db.note.findFirst({ where: { id: noteId, userId: user.id } });
      if (!row) throw new UserError(NOTE_NOT_FOUND);
      const n = noteRowToInput(row);
      const fields = pick(input, ["areaId", "bucket", "title", "note", "dueDate", "dueTime", "remindBefore", "recurrence", "amount", "walletId", "categoryId"]);
      const last = await db.task.aggregate({
        where: { userId: user.id, areaId: typeof fields.areaId === "string" ? fields.areaId : "", bucket: fields.bucket ?? "want", done: false },
        _max: { sortOrder: true },
      });
      await saveTask(
        db,
        user.id,
        taskId,
        {
          title: noteDisplayTitle(n),
          note: bodyExcerpt(n.body, 2000) || null,
          ...fields,
          sortOrder: (last._max.sortOrder ?? -1) + 1,
          done: false,
        },
        false,
      );
      return saveNote(db, user.id, noteId, { ...n, linkedTaskId: taskId }, row);
    });
    if (saved.needsTitles) queueNoteLinkTitles(noteId);
    return { taskId };
  });
  if (res.ok) revalidate(["/tasks", "/dashboard"]);
  return res;
}

export type NoteToContentInput = { title?: string; format?: FormatId | null; pillar?: string | null };

/**
 * → Konten: create a ContentItem at stage `ide` with the note as its idea (title, body,
 * checklist and photos copied; `noteId` = the note) and set the note's `linkedContentId`.
 */
export async function convertNoteToContent(
  noteId: string,
  input: NoteToContentInput = {},
): Promise<ActionResult<{ contentId: string }>> {
  const user = await requireUser();
  const res = await runAction("notes", async () => {
    assertObject(input);
    assertId(noteId, NOTE_NOT_FOUND);
    const contentId = randomUUID();
    const saved = await prisma.$transaction(async (db) => {
      const row = await db.note.findFirst({ where: { id: noteId, userId: user.id } });
      if (!row) throw new UserError(NOTE_NOT_FOUND);
      const n = noteRowToInput(row);
      await saveContentItem(
        db,
        user.id,
        contentId,
        {
          title: noteDisplayTitle(n),
          idea: n.body,
          checklist: n.checklist,
          photos: n.photos,
          ...pick(input, ["title", "format", "pillar"]),
          stage: "ide",
          noteId,
        },
        null,
      );
      return saveNote(db, user.id, noteId, { ...n, linkedContentId: contentId }, row);
    });
    if (saved.needsTitles) queueNoteLinkTitles(noteId);
    return { contentId };
  });
  if (res.ok) revalidate(["/content"]);
  return res;
}

export type NoteToTransactionInput = {
  type: "expense" | "income";
  amount: number;
  walletId: string;
  categoryId?: string | null;
  /** Default: note title. */
  note?: string | null;
  /** YYYY-MM-DD or ISO; default now. */
  date?: string;
  /** Note photos to attach (subset of the note's, ≤ 5). Default: the first 5. */
  photos?: string[];
};

/** → Transaksi: record a transaction (ledger) from the note and set `linkedTransactionId`. */
export async function createTransactionFromNote(
  noteId: string,
  input: NoteToTransactionInput,
): Promise<ActionResult<{ transactionId: string }>> {
  const user = await requireUser();
  const res = await runAction("notes", async () => {
    assertObject(input);
    assertId(noteId, NOTE_NOT_FOUND);
    if (input.type !== "expense" && input.type !== "income") throw new UserError("Jenis transaksi tidak valid");
    const out = await prisma.$transaction(async (db) => {
      const row = await db.note.findFirst({ where: { id: noteId, userId: user.id } });
      if (!row) throw new UserError(NOTE_NOT_FOUND);
      const n = noteRowToInput(row);
      const photos = input.photos === undefined ? n.photos.slice(0, MAX_TRANSACTION_PHOTOS) : input.photos;
      if (!Array.isArray(photos) || photos.some((u) => !n.photos.includes(u))) throw new UserError("Foto tidak ditemukan di catatan ini");
      if (photos.length > MAX_TRANSACTION_PHOTOS) throw new UserError(`Maksimal ${MAX_TRANSACTION_PHOTOS} foto per transaksi`);
      const p = transactionSchema.parse({
        type: input.type,
        amount: input.amount,
        walletId: input.walletId,
        categoryId: input.categoryId ?? null,
        note: input.note === undefined ? noteDisplayTitle(n) : input.note,
        date: input.date ?? new Date(),
      });
      const refs = await validateTransactionRefs(db, user.id, p).catch((e: unknown) => {
        throw new UserError(e instanceof Error && e.message === "Wallet not found" ? "Dompet tidak ditemukan" : "Kategori tidak ditemukan");
      });
      if (refs.categoryId) {
        const cat = await db.category.findFirst({ where: { id: refs.categoryId, userId: user.id }, select: { type: true } });
        if (cat?.type !== p.type) throw new UserError(p.type === "income" ? "Kategori harus kategori pemasukan" : "Kategori harus kategori pengeluaran");
      }
      const tx = await createLedgerTransaction(db, user.id, { ...p, ...refs, photos: serializePhotos([...new Set(photos)]) });
      const saved = await saveNote(db, user.id, noteId, { ...n, linkedTransactionId: tx.id }, row);
      return { transactionId: tx.id, saved };
    });
    if (out.saved.needsTitles) queueNoteLinkTitles(noteId);
    return { transactionId: out.transactionId };
  });
  if (res.ok) revalidate(["/transactions", "/wallets", "/dashboard"]);
  return res;
}
