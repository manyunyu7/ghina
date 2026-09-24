# Notes — spec (web + mobile)

A general notes app inside Ghina (Google-Keep-like), optimised for **fast capture** and
for turning a note into action (task, content, transaction). Offline-first on mobile.
Content ideas are just notes (usually labelled `ide-konten`) — see `docs/content.md`.

## Decisions

- **Labels, no folders.** A note has 0..n labels. Labels can be **pinned as tabs**
  (e.g. Semua · Ide Konten · Kerjaan · Belanja). Folders can be added later without
  breaking data.
- **Voice notes** supported, with optional on-device transcription.
- Single user (no sharing).

## Data model

```prisma
model Note {
  id        String   @id @default(cuid())
  userId    String
  title     String?            // ≤ 200
  body      String   @default("")   // Markdown subset, ≤ 50 000 chars
  checklist String   @default("[]") // JSON [{id, text, done}] (≤ 200 items), shown under body
  labels    String   @default("[]") // JSON array of label ids
  color     String?            // card color from the palette, null = default
  pinned    Boolean  @default(false)
  archived  Boolean  @default(false)
  photos    String   @default("[]") // JSON array of /uploads URLs (≤ 10), same rules as transaction photos
  audio     String   @default("[]") // JSON [{url, durationSec, transcript?}] (≤ 5 clips, ≤ 10 min each)
  links     String   @default("[]") // JSON [{url, title?}] (≤ 20) — URLs found in body or shared in
  source    String?            // "share" | "quick" | "voice" | null — how it was captured
  linkedTaskId        String?  // set when converted → Task (SetNull)
  linkedContentId     String?  // set when converted → ContentItem (SetNull)
  linkedTransactionId String?  // set when converted → Transaction (SetNull)
  createdAt, updatedAt
  @@index([userId, updatedAt])
}

model NoteLabel {
  id        String  @id @default(cuid())
  userId    String
  name      String           // 1–30, unique per user (case-insensitive)
  color     String  @default("#58CC02")
  pinnedTab Boolean @default(false)   // shown as a tab
  sortOrder Int     @default(0)
  createdAt, updatedAt
  @@unique([userId, name])
}
```

- Deleting a label removes its id from notes (server updates affected notes' `labels`
  so they sync; mobile mirrors).
- Default label seeded on first use: `Ide Konten` (pinned tab, deterministic id
  `label-ide-konten-<userId>`) — the Content module relies on it.
- Trash: deleting a note is a real delete (tombstone) after a confirm; archive is the
  soft option. (No trash bin in v1.)

## Body format

Markdown subset rendered on both platforms: headings (#, ##), bold, italic, bullet and
numbered lists, links, inline code, quotes. The editor is plain text with a small
formatting toolbar (web + mobile) and live preview toggle — no heavy rich-text engine.
URLs in the body are auto-detected into `links` (title fetched server-side when online,
best effort, no third-party service; skip if it fails).

## Voice notes

- Mobile: hold-to-record or tap-to-record button (max 10 min, AAC/m4a mono ~64 kbps),
  waveform while recording, playback with scrubbing. Stored locally first, uploaded like
  photos (new upload kinds: `audio/*` ≤ 20 MB via the same upload endpoint, extended).
- **Transcription** (optional toggle): on-device speech recognition in `id-ID` while
  recording (Android SpeechRecognizer / iOS Speech via a Flutter plugin). The transcript
  is saved into the clip's `transcript` and can be inserted into the body. No cloud
  transcription in v1 (privacy + cost). If the device lacks offline recognition, show a
  hint and keep the audio only.
- Web: plays audio clips and shows transcripts; recording on web is optional (MediaRecorder
  if simple, otherwise play-only).

## Capture paths

- Mobile quick add (FAB in Notes, and "+ Catatan" in the home quick actions): opens an
  empty note with keyboard up; saving on back.
- **Android share target**: sharing text/URL/image(s) from any app to Ghina creates a note
  (`source = "share"`) with the content, then shows a small sheet: add label, or convert
  (→ Tugas / → Konten). iOS share extension is out of scope for v1.
- Voice-first: long-press the Notes FAB → start recording immediately.

## Convert to action

From a note (keeps the note, sets the link both ways where the target has a field):
- **→ Tugas**: title = note title or first line; note = body excerpt; pick area + bucket.
- **→ Konten**: creates a ContentItem at stage `ide` with the note as its idea/draft
  (`docs/content.md`).
- **→ Transaksi**: opens the transaction form prefilled (amount parsed from the note if a
  single `Rp …` / number is found; note = title), attaching the note's photos.

## UI

- **Mobile**: new "Catatan" entry reachable from home quick actions and Profile menu,
  plus the share target; grid/list toggle of note cards (color, pinned first, label chips,
  photo/audio/checklist indicators), label tabs, search (title/body/checklist/transcripts),
  note editor with toolbar, checklist, photos, voice clips, labels, color, pin, archive,
  convert menu.
- **Web** `/notes`: masonry grid, label sidebar/tabs, search, editor dialog/page with the
  same capabilities (audio playback), keyboard shortcut `n` for new note.

## Sync

Entities `notes` and `noteLabels`; JSON fields travel as JSON values. Validation mirrors
the model limits. Photo/audio files cleaned up when removed or when the note is deleted.

## Clarifications (backend implementation)

Decided while building the backend; the web and mobile follow these.

- **Colors**: `color` stores a palette **id** — red, orange, yellow, green, teal, blue,
  darkblue, purple, pink, brown, gray (`NOTE_COLORS` in `src/lib/notes.ts`, with light and
  dark hex per id) — not a hex value, so each platform can theme it.
- **Limits** besides the model's: checklist text one line ≤ 1000; ≤ 20 labels per note;
  transcript ≤ 20 000; `durationSec` ≤ 610 (10 min + encoder slack). Titles/names/checklist
  texts are single-line; bodies keep newlines; control characters are stripped.
- **Labels** are unique per user case-insensitively (sync: `duplicate`). Notes store label
  ids, so a rename changes nothing on notes. Label ids a note references that the user
  doesn't have are dropped on save (offline races), never rejected.
- **Default label** `Ide Konten` (`label-ide-konten-<userId>`, `#CE82FF`, pinned tab) is
  seeded **once** by the server (first pull / first web visit) — not re-created after the
  user deletes it (tombstone), and skipped if a label with that name already exists.
- **Links**: `links` = the sent list + every body URL not yet in it (`extractUrls`,
  `mergeLinks`), ≤ 20. Titles are fetched by the server after save (fire-and-forget;
  `src/lib/link-titles.ts`): http/https only, every resolved address must be public
  (private, loopback, link-local/metadata, CGNAT, multicast, reserved, IPv4-mapped/NAT64/
  6to4 forms refused, checked at connect time), ≤ 3 validated redirects, 3 s, ≤ 256 KB,
  `text/html` only, og:title → `<title>`, cached per URL (24 h; failures 1 h). A sent link
  without a title keeps the stored one.
- **LWW**: notes carry a server-only `editedAt` (last user edit) used for sync
  last-write-wins, because title fills and label strips also bump `updatedAt`.
- **Soft links** (`linked*Id`) pointing at rows that no longer exist / aren't the user's
  are stored as null instead of rejecting the note.
- **Convert**: → Tugas: title = note title / first body line (markdown stripped) /
  first checklist item / "Catatan"; task note = body as plain text ≤ 2000; sets
  `linkedTaskId`. → Konten: item at `ide` with title, `idea` = body, checklist and photos
  copied, `noteId` = note; sets `linkedContentId`. → Transaksi: amount from `parseAmount`
  (the single distinct `Rp …` amount — `Rp 25.000`, `Rp 25rb`, `Rp1,5jt` — else the single
  distinct plain number ≥ 1000 or with a k/rb/jt suffix; dates/times ignored; several →
  none); note = title; the first 5 note photos are attached (files shared, reference-
  counted); sets `linkedTransactionId`.
- **Deleting** a task / content item / transaction nulls the matching `linked*Id` on notes
  (rows re-sync). Deleting a note nulls `ContentItem.noteId` and removes its files.
- **Reset all data** keeps notes and labels (only `linkedTransactionId` is nulled).

Server implementation: `src/lib/notes.ts` (pure; `scripts/test-notes.mjs`),
`src/lib/notes-server.ts` (save/seed/title refresh/queries), `src/lib/link-titles.ts`,
`src/lib/media.ts` (audio sniffing), `src/lib/sync-links.ts` + `src/lib/sync-deletes.ts`
(cascades), `src/app/(dashboard)/notes/actions.ts` (web server actions).
