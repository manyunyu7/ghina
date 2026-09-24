import { z } from "zod";
import { AUDIO_UPLOAD_RE, IMAGE_UPLOAD_RE } from "@/lib/media";

/**
 * Notes — pure, shared rules (docs/notes.md). No DB access: used by the web server
 * actions, the mobile sync endpoint and the web UI. The mobile app mirrors these
 * constants and algorithms exactly. Error messages are Indonesian (shown to the user).
 */

// ---------- Limits ----------

export const NOTE_TITLE_MAX = 200;
export const NOTE_BODY_MAX = 50_000;
export const CHECKLIST_MAX = 200;
export const CHECKLIST_TEXT_MAX = 1000;
export const NOTE_LABELS_MAX = 20;
export const NOTE_PHOTOS_MAX = 10;
export const NOTE_AUDIO_MAX = 5;
/** 10 minutes, plus 10 s tolerance for encoder rounding. */
export const AUDIO_DURATION_MAX = 610;
export const AUDIO_RECORD_MAX_SEC = 600;
export const TRANSCRIPT_MAX = 20_000;
export const NOTE_LINKS_MAX = 20;
export const LINK_URL_MAX = 2000;
export const LINK_TITLE_MAX = 300;
export const LABEL_NAME_MAX = 30;
export const ITEM_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
export const HEX_COLOR_RE = /^#[0-9a-fA-F]{6}$/;
export const DEFAULT_LABEL_COLOR = "#58CC02";

/** How a note was captured. Unknown values are stored as null (forward compatible). */
export const NOTE_SOURCES = ["share", "quick", "voice"] as const;
export type NoteSource = (typeof NOTE_SOURCES)[number];

/**
 * Card colors (Keep-like). A note stores the palette `id`; each platform maps it to the
 * light/dark shade. `null` = default card color.
 */
export const NOTE_COLORS = [
  { id: "red", label: "Merah", light: "#FAAFA8", dark: "#77172E" },
  { id: "orange", label: "Oranye", light: "#F39F76", dark: "#692B17" },
  { id: "yellow", label: "Kuning", light: "#FFF8B8", dark: "#7C4A03" },
  { id: "green", label: "Hijau", light: "#E2F6D3", dark: "#264D3B" },
  { id: "teal", label: "Toska", light: "#B4DDD3", dark: "#0C625D" },
  { id: "blue", label: "Biru", light: "#D4E4ED", dark: "#256377" },
  { id: "darkblue", label: "Biru tua", light: "#AECCDC", dark: "#284255" },
  { id: "purple", label: "Ungu", light: "#D3BFDB", dark: "#472E5B" },
  { id: "pink", label: "Merah muda", light: "#F6E2DD", dark: "#6C394F" },
  { id: "brown", label: "Cokelat", light: "#E9E3D4", dark: "#4B443A" },
  { id: "gray", label: "Abu-abu", light: "#EFEFF1", dark: "#232427" },
] as const;
export type NoteColorId = (typeof NOTE_COLORS)[number]["id"];
export const NOTE_COLOR_IDS = NOTE_COLORS.map((c) => c.id) as [NoteColorId, ...NoteColorId[]];

// ---------- Text hygiene ("markdown-safe") ----------

// C0 controls except \t and \n, plus DEL. \r is normalized first.
const CONTROL_RE = /[\u0000-\u0008\u000B-\u001F\u007F]/g;

/** Normalize newlines to \n and drop control characters (keeps tabs/newlines). */
export function cleanText(v: string): string {
  return v.replace(/\r\n?/g, "\n").replace(CONTROL_RE, "");
}

/** One line: newlines/tabs → space, controls dropped, trimmed. */
export function cleanLine(v: string): string {
  return cleanText(v).replace(/[\n\t]+/g, " ").trim();
}

const nullableLine = (max: number, label: string) =>
  z
    .string()
    .nullish()
    .transform((v) => (v == null ? null : cleanLine(v) || null))
    .refine((v) => v == null || v.length <= max, `${label} terlalu panjang (maks ${max})`);

// ---------- URLs ----------

/** An http(s) URL without credentials, ≤ 2000 chars. */
export function isHttpUrl(v: string): boolean {
  if (v.length > LINK_URL_MAX || /\s/.test(v)) return false;
  try {
    const u = new URL(v);
    return (u.protocol === "http:" || u.protocol === "https:") && !!u.hostname && !u.username && !u.password;
  } catch {
    return false;
  }
}

export const httpUrlSchema = z
  .string()
  .trim()
  .refine(isHttpUrl, "URL harus diawali http:// atau https://");

const URL_IN_TEXT_RE = /\bhttps?:\/\/[^\s<>"'`]+/gi;

/**
 * URLs in a note body, in order of first appearance, deduplicated. Trailing punctuation
 * (`.,;:!?'"`) and unbalanced closing brackets — e.g. from `[teks](https://x.id)` or
 * "(lihat https://x.id)" — are not part of the URL.
 */
export function extractUrls(body: string): string[] {
  const out: string[] = [];
  for (const m of body.matchAll(URL_IN_TEXT_RE)) {
    let url = m[0];
    for (;;) {
      const last = url.at(-1)!;
      if (".,;:!?'\"*_~".includes(last)) url = url.slice(0, -1);
      else if (last === ")" && count(url, "(") < count(url, ")")) url = url.slice(0, -1);
      else if (last === "]" && count(url, "[") < count(url, "]")) url = url.slice(0, -1);
      else break;
    }
    if (isHttpUrl(url) && !out.includes(url)) out.push(url);
  }
  return out;
}

const count = (s: string, ch: string) => s.split(ch).length - 1;

// ---------- JSON shapes ----------

export type ChecklistItem = { id: string; text: string; done: boolean };
export type AudioClip = { url: string; durationSec: number; transcript: string | null };
export type NoteLink = { url: string; title: string | null };

export const checklistItemSchema = z.object({
  id: z.string().regex(ITEM_ID_RE, "ID item checklist tidak valid"),
  text: z
    .string()
    .transform(cleanLine)
    .refine((v) => v.length <= CHECKLIST_TEXT_MAX, `Item checklist terlalu panjang (maks ${CHECKLIST_TEXT_MAX})`),
  done: z.boolean().default(false),
});

/** ≤ 200 items `{id, text, done}`; ids unique; empty text allowed (a fresh row). */
export const checklistSchema = z
  .array(checklistItemSchema, { message: "checklist harus berupa array" })
  .max(CHECKLIST_MAX, `Maksimal ${CHECKLIST_MAX} item checklist`)
  .refine((xs) => new Set(xs.map((x) => x.id)).size === xs.length, "ID item checklist duplikat")
  .transform((xs): ChecklistItem[] => xs.map((x) => ({ id: x.id, text: x.text, done: x.done })));

/** Image upload URLs; duplicates dropped (first wins), order kept. */
export const imageListSchema = (max: number) =>
  z
    .array(z.string().regex(IMAGE_UPLOAD_RE, "URL foto tidak valid"), { message: "photos harus berupa array URL" })
    .transform((xs) => [...new Set(xs)])
    .refine((xs) => xs.length <= max, `Maksimal ${max} foto`);

export const notePhotosSchema = imageListSchema(NOTE_PHOTOS_MAX);

export const audioClipSchema = z.object({
  url: z.string().regex(AUDIO_UPLOAD_RE, "URL audio tidak valid"),
  durationSec: z
    .number({ message: "durationSec harus berupa angka" })
    .finite()
    .min(0, "Durasi audio tidak valid")
    .max(AUDIO_DURATION_MAX, "Rekaman maksimal 10 menit"),
  transcript: z
    .string()
    .nullish()
    .transform((v) => (v == null ? null : cleanText(v).trim() || null))
    .refine((v) => v == null || v.length <= TRANSCRIPT_MAX, `Transkrip terlalu panjang (maks ${TRANSCRIPT_MAX})`),
});

/** ≤ 5 clips; a repeated url keeps the first entry. */
export const noteAudioSchema = z
  .array(audioClipSchema, { message: "audio harus berupa array" })
  .transform((xs): AudioClip[] => dedupeBy(xs, (x) => x.url))
  .refine((xs) => xs.length <= NOTE_AUDIO_MAX, `Maksimal ${NOTE_AUDIO_MAX} rekaman suara`);

export const noteLinkSchema = z.object({
  url: httpUrlSchema,
  title: nullableLine(LINK_TITLE_MAX, "Judul tautan"),
});

/** ≤ 20 links; a repeated url keeps the first entry. */
export const noteLinksSchema = z
  .array(noteLinkSchema, { message: "links harus berupa array" })
  .transform((xs): NoteLink[] => dedupeBy(xs, (x) => x.url))
  .refine((xs) => xs.length <= NOTE_LINKS_MAX, `Maksimal ${NOTE_LINKS_MAX} tautan`);

export const labelIdsSchema = z
  .array(z.string().regex(ITEM_ID_RE, "ID label tidak valid"), { message: "labels harus berupa array ID" })
  .transform((xs) => [...new Set(xs)])
  .refine((xs) => xs.length <= NOTE_LABELS_MAX, `Maksimal ${NOTE_LABELS_MAX} label per catatan`);

function dedupeBy<T>(xs: T[], key: (x: T) => string): T[] {
  const seen = new Set<string>();
  return xs.filter((x) => {
    const k = key(x);
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}

/**
 * The note's links: the sent list (deduplicated), plus body URLs not in it appended in
 * order, capped at 20 (sent entries always win the room). A sent link without a title
 * keeps the title already stored for the same url (the server fills titles in the
 * background; a client that hasn't pulled them yet must not wipe them).
 */
export function mergeLinks(sent: NoteLink[], body: string, stored: NoteLink[] = []): NoteLink[] {
  const storedTitle = new Map(stored.filter((l) => l.title).map((l) => [l.url, l.title]));
  const out = sent.map((l) => ({ url: l.url, title: l.title ?? storedTitle.get(l.url) ?? null }));
  for (const url of extractUrls(body)) {
    if (out.length >= NOTE_LINKS_MAX) break;
    if (!out.some((l) => l.url === url)) out.push({ url, title: storedTitle.get(url) ?? null });
  }
  return out;
}

// ---------- Note / label payloads (sync wire format; the web actions build the same shape) ----------

const optionalId = z
  .string()
  .nullish()
  .transform((v) => (v && v.length > 0 ? v : null));

const emptyArray = <T extends z.ZodType>(s: T) => s.nullish().transform((v) => (v ?? []) as z.output<T>);

export const noteSchema = z
  .object({
    title: nullableLine(NOTE_TITLE_MAX, "Judul"),
    body: z
      .string()
      .nullish()
      .transform((v) => cleanText(v ?? ""))
      .refine((v) => v.length <= NOTE_BODY_MAX, `Isi catatan terlalu panjang (maks ${NOTE_BODY_MAX.toLocaleString("id-ID")} karakter)`),
    checklist: emptyArray(checklistSchema),
    labels: emptyArray(labelIdsSchema),
    color: z
      .string()
      .nullish()
      .transform((v) => (v ? v : null))
      .refine((v) => v == null || (NOTE_COLOR_IDS as readonly string[]).includes(v), "Warna catatan tidak valid"),
    pinned: z.boolean().default(false),
    archived: z.boolean().default(false),
    photos: emptyArray(notePhotosSchema),
    audio: emptyArray(noteAudioSchema),
    links: emptyArray(noteLinksSchema),
    // Unknown capture sources become null (forward compatible), like food `meal`.
    source: z
      .string()
      .nullish()
      .transform((v) => (v && (NOTE_SOURCES as readonly string[]).includes(v) ? (v as NoteSource) : null)),
    linkedTaskId: optionalId,
    linkedContentId: optionalId,
    linkedTransactionId: optionalId,
  })
  // Body URLs are always part of `links` (the stored titles are merged in by the server).
  .transform((n) => ({ ...n, links: mergeLinks(n.links, n.body) }));

export type NoteData = z.output<typeof noteSchema>;

/** Case-insensitive uniqueness key of a label / pillar name. */
export const nameKey = (name: string) => cleanLine(name).toLocaleLowerCase("id-ID");

export const noteLabelSchema = z.object({
  name: z
    .string()
    .transform(cleanLine)
    .pipe(z.string().min(1, "Nama label wajib diisi").max(LABEL_NAME_MAX, `Nama label maksimal ${LABEL_NAME_MAX} karakter`)),
  color: z.string().regex(HEX_COLOR_RE, "Warna tidak valid").default(DEFAULT_LABEL_COLOR),
  pinnedTab: z.boolean().default(false),
  sortOrder: z.number().int().min(-1_000_000).max(1_000_000).default(0),
});

export type NoteLabelData = z.output<typeof noteLabelSchema>;

// ---------- Stored columns → values (lenient: bad JSON / entries dropped, never thrown) ----------

function parseArray<T>(raw: unknown, item: z.ZodType<T>): T[] {
  let v = raw;
  if (typeof raw === "string") {
    try {
      v = JSON.parse(raw);
    } catch {
      return [];
    }
  }
  if (!Array.isArray(v)) return [];
  const out: T[] = [];
  for (const x of v) {
    const r = item.safeParse(x);
    if (r.success) out.push(r.data);
  }
  return out;
}

export const parseChecklist = (raw: unknown): ChecklistItem[] =>
  dedupeBy(parseArray(raw, checklistItemSchema), (x) => x.id) as ChecklistItem[];
export const parseLabelIds = (raw: unknown): string[] => [
  ...new Set(parseArray(raw, z.string().regex(ITEM_ID_RE))),
];
export const parseImageList = (raw: unknown): string[] => [
  ...new Set(parseArray(raw, z.string().regex(IMAGE_UPLOAD_RE))),
];
export const parseAudio = (raw: unknown): AudioClip[] => dedupeBy(parseArray(raw, audioClipSchema), (x) => x.url);
export const parseLinks = (raw: unknown): NoteLink[] => dedupeBy(parseArray(raw, noteLinkSchema), (x) => x.url);

/** JSON text for a JSON column. */
export const toJson = (v: unknown): string => JSON.stringify(v);

// ---------- Labels ----------

/** Deleting a label: its id is removed from every note's `labels` (order kept). */
export function stripLabel(labels: readonly string[], labelId: string): string[] {
  return labels.filter((l) => l !== labelId);
}

/**
 * Renaming a label changes nothing on notes (they store label ids) — only the label row.
 * Returns whether `name` would clash with another label (case-insensitive).
 */
export function labelNameTaken(labels: readonly { id: string; name: string }[], name: string, exceptId?: string): boolean {
  const k = nameKey(name);
  return labels.some((l) => l.id !== exceptId && nameKey(l.name) === k);
}

export const IDEA_LABEL_NAME = "Ide Konten";

/** Deterministic id of the default `Ide Konten` label (the Content idea inbox uses it). */
export const ideaLabelId = (userId: string) => `label-ide-konten-${userId}`;

export function defaultNoteLabel(userId: string): NoteLabelData & { id: string } {
  return { id: ideaLabelId(userId), name: IDEA_LABEL_NAME, color: "#CE82FF", pinnedTab: true, sortOrder: 0 };
}

export function compareLabels(a: { sortOrder: number; name: string }, b: { sortOrder: number; name: string }) {
  return a.sortOrder - b.sortOrder || a.name.localeCompare(b.name, "id");
}

// ---------- Listing / search ----------

type ListNote = { pinned: boolean; archived?: boolean; updatedAt: Date | string };

/** Pinned first, then most recently updated. */
export function compareNotes(a: ListNote, b: ListNote): number {
  if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
  return new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime();
}

type SearchNote = {
  title: string | null;
  body: string;
  checklist: readonly ChecklistItem[];
  audio: readonly AudioClip[];
  links?: readonly NoteLink[];
};

/** Case-insensitive search over title, body, checklist texts, transcripts and link titles. */
export function noteMatches(note: SearchNote, query: string): boolean {
  const q = query.trim().toLocaleLowerCase("id-ID");
  if (!q) return true;
  const hay = [
    note.title ?? "",
    note.body,
    ...note.checklist.map((c) => c.text),
    ...note.audio.map((a) => a.transcript ?? ""),
    ...(note.links ?? []).map((l) => `${l.title ?? ""} ${l.url}`),
  ]
    .join("\n")
    .toLocaleLowerCase("id-ID");
  return q.split(/\s+/).every((w) => hay.includes(w));
}

/** Plain text of a markdown line (headings, quote, list markers, emphasis, links removed). */
export function stripMarkdown(line: string): string {
  return line
    .replace(/^\s{0,3}(#{1,6}\s+|>\s?|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)/, "")
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/(\*\*|__|\*|_|`|~~)/g, "")
    .trim();
}

/** First non-empty line of the body as plain text (≤ max chars). */
export function firstLine(body: string, max = NOTE_TITLE_MAX): string {
  for (const l of body.split("\n")) {
    const t = stripMarkdown(l);
    if (t) return t.length > max ? `${t.slice(0, max - 1).trimEnd()}…` : t;
  }
  return "";
}

/** Plain-text excerpt of the body (markdown stripped, lines joined) ≤ max chars. */
export function bodyExcerpt(body: string, max = 2000): string {
  const text = body
    .split("\n")
    .map(stripMarkdown)
    .filter(Boolean)
    .join("\n");
  return text.length > max ? `${text.slice(0, max - 1).trimEnd()}…` : text;
}

/** Title used when converting a note: its title, else the body's first line, else checklist/"Catatan". */
export function noteDisplayTitle(note: { title: string | null; body: string; checklist?: readonly ChecklistItem[] }, max = NOTE_TITLE_MAX): string {
  return (
    note.title?.slice(0, max) ||
    firstLine(note.body, max) ||
    note.checklist?.find((c) => c.text)?.text.slice(0, max) ||
    "Catatan"
  );
}

// ---------- Convert → Transaksi: amount ----------

const SUFFIX: Record<string, number> = { k: 1e3, rb: 1e3, ribu: 1e3, jt: 1e6, juta: 1e6 };

/** "25.000" → 25000, "1.250.000,50" → 1250000.5, "25,5" (+ suffix) → 25.5, "2.5" (+ suffix) → 2.5. */
function parseNumber(raw: string, hasSuffix: boolean): number | null {
  let s = raw.replace(/[.,]$/, "");
  if (/^\d{1,3}(\.\d{3})+(,\d+)?$/.test(s)) s = s.replace(/\./g, "").replace(",", ".");
  else if (/^\d{1,3}(,\d{3})+(\.\d+)?$/.test(s) && !hasSuffix) s = s.replace(/,/g, "");
  else if (/^\d+,\d+$/.test(s)) s = s.replace(",", ".");
  else if (/^\d+\.\d{3}$/.test(s) && !hasSuffix) s = s.replace(".", "");
  const n = Number(s);
  return Number.isFinite(n) && n > 0 ? n : null;
}

const RP_RE = /\bRp\.?\s*(\d[\d.,]*)\s*(k|rb|ribu|jt|juta)?\b/gi;
const NUM_RE = /(?<![\w.,])(\d[\d.,]*)\s*(k|rb|ribu|jt|juta)?(?![\w])/gi;

/**
 * Amount for "→ Transaksi": the single distinct `Rp …` amount in the text; if there is
 * none, the single distinct plain number ≥ 1000 (or with a k/rb/jt suffix). Several
 * different candidates → null (the user types it). Dates/times aren't amounts.
 */
export function parseAmount(text: string): number | null {
  const pick = (re: RegExp, filter: (n: number, suffix: boolean) => boolean) => {
    const found = new Set<number>();
    for (const m of text.matchAll(re)) {
      const suffix = m[2]?.toLowerCase();
      const n = parseNumber(m[1], !!suffix);
      if (n == null) continue;
      const v = Math.round(n * (suffix ? SUFFIX[suffix] : 1) * 100) / 100;
      if (filter(v, !!suffix)) found.add(v);
    }
    return found;
  };
  const rp = pick(RP_RE, () => true);
  if (rp.size > 0) return rp.size === 1 ? [...rp][0] : null;
  // Skip dates (12/09/2026, 2026-09-12) and times (10:30) before looking for plain numbers.
  const cleaned = text.replace(/\b\d{1,4}[/-]\d{1,2}[/-]\d{1,4}\b/g, " ").replace(/\b\d{1,2}[:.]\d{2}\s*(wib|wita|wit)\b/gi, " ").replace(/\b\d{1,2}:\d{2}\b/g, " ");
  const plain = new Set<number>();
  for (const m of cleaned.matchAll(NUM_RE)) {
    const suffix = m[2]?.toLowerCase();
    const n = parseNumber(m[1], !!suffix);
    if (n == null) continue;
    const v = Math.round(n * (suffix ? SUFFIX[suffix] : 1) * 100) / 100;
    if (suffix || v >= 1000) plain.add(v);
  }
  return plain.size === 1 ? [...plain][0] : null;
}
