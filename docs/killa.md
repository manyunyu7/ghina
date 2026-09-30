# Killa — personal Claude agent

Killa is a personal Claude agent served by **killa-engine**, a local HTTP service. Ghina
is its front end (web `/killa`, mobile `/api/mobile/killa/*`) and records the whole chat
in its own DB (`KillaMessage`). Only allowlisted accounts can use it.

## Setup

1. Run killa-engine **on the same host** as Ghina, bound to localhost (e.g.
   `http://127.0.0.1:8377`). Ghina calls it server-side only; it is never exposed.
2. Env vars (`.env`):

   | Var | Meaning |
   | --- | --- |
   | `KILLA_BASE_URL` | engine base URL, e.g. `http://127.0.0.1:8377` |
   | `KILLA_TOKEN` | sent as `Authorization: Bearer …` to the engine |
   | `KILLA_ALLOWED_EMAILS` | comma list of Ghina account emails allowed to use Killa (case-insensitive). Empty = nobody |
   | `KILLA_WA_NUMBER` | optional. Owner's WhatsApp number, digits (e.g. `6281234567890`; must be in the engine's `OWNER_NUMBERS`). Set → every engine call uses chatKey `wa:<number>`: the Ghina chat **is** the owner's WhatsApp DM (one session, transcript, `/model`, reminders; reminders fire on WhatsApp). Empty → chatKey = Ghina user id (separate chat) |
   | `KILLA_MIRROR_TOKEN` | optional. Bearer secret the engine sends to `POST /api/killa/mirror` (= engine `MIRROR_TOKEN`). Empty = mirror endpoint always 401 |

3. `npx prisma db push` (adds the `KillaMessage` table / the `channel` + `attachments`
   columns — additive) and restart.
4. Reverse proxy: a reply can take ~5 minutes. Raise the proxy read timeout for the app
   (nginx: `proxy_read_timeout 360s; proxy_send_timeout 360s;`), at least for `/killa`
   (Server Actions post to the page URL) and `/api/mobile/killa/`. Otherwise the client
   sees a 504 even though the reply is still recorded when it arrives.
   Attachments: a chat request may carry ~24 MB (web, multipart) or ~33 MB (mobile, JSON
   base64) — raise `client_max_body_size` (nginx) to ~40m for those paths.
5. WhatsApp mirror (optional, with `KILLA_WA_NUMBER`): on the engine set
   `MIRROR_URL=http://127.0.0.1:<ghina port>/api/killa/mirror` and
   `MIRROR_TOKEN=<KILLA_MIRROR_TOKEN>`.

Non-allowed users get **404** on the web pages (the "Killa" nav entry is visible to
everyone) and **403** `{"error":"forbidden"}` from the mobile API. The engine `chatKey` is
`wa:<KILLA_WA_NUMBER>` when set (single-user: every allowlisted account talks into the
owner's WhatsApp DM — keep the allowlist to the owner), else the Ghina user id.

## Data

```prisma
model KillaMessage {
  id        String   @id @default(cuid())
  userId    String
  role      String   // user | assistant | system ("Sesi baru" divider)
  body      String
  model     String?  // fable | opus | sonnet | haiku; null = engine default
  channel     String  @default("app") // app (sent from Ghina) | wa (mirrored from WhatsApp)
  attachments String? // JSON string[]: /uploads URLs (user) or engine paths (assistant)
  createdAt DateTime @default(now())
  @@index([userId, createdAt])
}
```

Server-only, not part of mobile sync. Sending records the user message first, then the
reply once the engine answers; if the engine fails, the user message stays and the error
is returned.

**Media.** A user message may carry ≤ 3 files (JPEG, PNG, WebP, GIF, PDF; ≤ 8 MB each;
the type is sniffed from the bytes — HEIC is refused, the engine doesn't take it). Each
file is saved to `/uploads/<uuid>.<ext>` (recorded in the user message's `attachments`)
**and** sent to the engine as base64 `media`. The web composer re-encodes photos larger
than 1.5 MB / 2048 px to JPEG first. Reply `attachments` are engine paths (agent output
via `[[send:]]`), stored on the assistant message and served through the media proxy
(`GET /api/killa/media?path=` web session, `GET /api/mobile/killa/media?path=` Bearer →
engine `GET /v1/media`, ≤ 15 MB; images/PDF inline, others as download). Older replies
(before this) have them as a `Lampiran:` list in the body.

**Mirror** — `POST /api/killa/mirror` (engine → Ghina, no user session):
`Authorization: Bearer <KILLA_MIRROR_TOKEN>` (constant-time; 401 otherwise). Body
`{channel:"wa", number, messages:[{role:"user"|"assistant", text, at (epoch ms)}]}`
(≤ 50 messages; `number` must equal `KILLA_WA_NUMBER` when that is set). Rows are filed
under the owner — the first `KILLA_ALLOWED_EMAILS` entry that has a Ghina account — with
`channel:"wa"`, `createdAt = at`; an exact (role, text, at) duplicate is skipped.
→ `{ok:true, inserted, skipped}`. Only WhatsApp-side DM turns arrive here (the engine does
not mirror turns sent from Ghina), so nothing is recorded twice.

## Engine contract (used by `src/lib/killa.ts`)

- `POST /v1/chat {chatKey, text, model?, media?:[{name, mimeType, dataBase64}]}` → `{reply, attachments?}` (≤ ~5 min; Ghina waits 330 s)
- `GET /v1/reminders?chatKey=` → `{reminders:[{id, spec, text, nextAt}]}`
- `POST /v1/reminders/cancel {chatKey, id}` → `{ok}` (false = already gone)
- `GET /v1/usage?days=` → `{since, days, byModel, total}` (all chats; cost = CLI estimate)
- `GET /v1/media?path=` → raw file (reply attachments)
- `POST /v1/chat/new {chatKey}` → `{ok}`
- `GET /v1/chat/history?chatKey=&limit=` → `{messages:[{at,who,text}]}` (client only; Ghina's own log is the source of truth)
- `GET /v1/workspace/files?path=` → `{entries:[{name,type,size}]}`
- `GET /v1/workspace/file?path=` → `{path, content}` (413 too large / 415 not text)
- `PUT /v1/workspace/file {path, content}` → `{ok, path}` (create or overwrite)
- `DELETE /v1/workspace/file?path=` → `{ok}`
- `POST /v1/git/commit {message?}` → `{ok, hash|null}` (null = nothing to commit)
- `GET /v1/git/log?limit=` → `{commits:[{hash,date,author,subject}]}`

## Web

`/killa` chat (newest 50 messages, "Muat pesan lama" loads older pages; model selector;
"Sesi baru"), `/killa/files?path=` / `?file=` workspace browser (Markdown files
rendered, others monospace; a text file has an **Edit** mode — monospace textarea, Save
(Ctrl/⌘+S) → `PUT /v1/workspace/file` — and a **Commit** bar with an optional message →
`POST /v1/git/commit`, showing the new hash), `/killa/commits` latest 100 commits,
`/killa/reminders` ("Pengingat Killa": the chat's scheduled reminders, **Batalkan** →
`POST /v1/reminders/cancel`), `/killa/usage` (30 days: daily cost bars, totals, per-model
table; cost is an API-price estimate, not a bill).
Edits are not committed automatically.

Chat: paperclip button (or paste) attaches ≤ 3 images/PDFs; day separators; a **WA**
badge on WhatsApp-mirrored messages; auto-scrolls to the newest message unless scrolled
up. While the tab is visible (and nothing is sending) it polls
`GET /api/killa/messages?limit=30` (session; newest page, same shape as the mobile GET)
every 20 s so mirrored WhatsApp turns appear without reload.

## Mobile API

Bearer token as the other mobile routes, then the allowlist. Errors are `{error}`:
401 token, 403 not allowlisted, 400 invalid input, 413/415 file, 502 engine error or
unreachable, 503 not configured, 504 engine timeout.

| Route | Result |
| --- | --- |
| `GET /api/mobile/killa/chat?before=<id>&limit=50` (limit ≤ 200) | `{messages, nextBefore}` — messages oldest first; pass `nextBefore` as `before` for the previous page (null = start reached) |
| `POST /api/mobile/killa/chat {text, model?, media?}` | `{userMessage, reply}` — waits for the reply (up to ~5.5 min). `text` ≤ 20 000 chars (may be `""` with media); `model` ∈ default, fable, opus, sonnet, haiku; `media` ≤ 3 × `{name?, mimeType?, dataBase64}` (JPEG/PNG/WebP/GIF/PDF, ≤ 8 MB decoded; type sniffed, `mimeType` ignored; 413 too big, 415 wrong type) |
| `POST /api/mobile/killa/chat/new` | `{divider}` |
| `GET /api/mobile/killa/files?path=` | `{path, entries:[{name, type: "file"\|"dir", size}]}` |
| `GET /api/mobile/killa/file?path=` | `{path, content}` |
| `PUT /api/mobile/killa/file {path, content}` | `{ok, path}` — create or overwrite a text file; `content` ≤ 1 000 000 chars |
| `DELETE /api/mobile/killa/file?path=` | `{ok, path}` |
| `POST /api/mobile/killa/commit {message?}` | `{ok, hash}` — commits the workspace; `hash` null = nothing to commit; `message` ≤ 500 (empty body allowed) |
| `GET /api/mobile/killa/commits?limit=50` (≤ 200) | `{commits:[{hash, date, author, subject}]}` |
| `GET /api/mobile/killa/media?path=` | raw file of an `engine` attachment (Content-Type from the engine; 400/404/413) |
| `GET /api/mobile/killa/reminders` | `{reminders:[{id, spec, text, nextAt (epoch ms)}]}` soonest first |
| `POST /api/mobile/killa/reminders/cancel {id}` | `{ok}` — false when already fired/cancelled |
| `GET /api/mobile/killa/usage?days=30` (≤ 90) | `{since, days:[{date, turns, inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens, costUsd}], byModel:{<model>: totals}, total}` — `costUsd` is an estimate |

Message: `{id, role: "user"|"assistant"|"system", body, model, channel: "app"|"wa",
attachments: [{path, name, kind: "image"|"file", source: "upload"|"engine"}], createdAt (ISO)}`.
`body` may be `""` when the message is only files. Render `source:"upload"` from
`<origin><path>` (public `/uploads/…`), `source:"engine"` via
`/api/mobile/killa/media?path=<urlencoded path>` with the Bearer header.
