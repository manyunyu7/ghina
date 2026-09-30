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

3. `npx prisma db push` (adds the `KillaMessage` table — additive) and restart.
4. Reverse proxy: a reply can take ~5 minutes. Raise the proxy read timeout for the app
   (nginx: `proxy_read_timeout 360s; proxy_send_timeout 360s;`), at least for `/killa`
   (Server Actions post to the page URL) and `/api/mobile/killa/`. Otherwise the client
   sees a 504 even though the reply is still recorded when it arrives.

Non-allowed users get **404** on the web pages (the "Killa" nav entry is visible to
everyone) and **403** `{"error":"forbidden"}` from the mobile API. The engine `chatKey` is
the Ghina user id.

## Data

```prisma
model KillaMessage {
  id        String   @id @default(cuid())
  userId    String
  role      String   // user | assistant | system ("Sesi baru" divider)
  body      String
  model     String?  // fable | opus | sonnet | haiku; null = engine default
  createdAt DateTime @default(now())
  @@index([userId, createdAt])
}
```

Server-only, not part of mobile sync. Sending records the user message first, then the
reply once the engine answers; if the engine fails, the user message stays and the error
is returned. Reply `attachments` (paths) are appended to the reply body as a
`Lampiran:` list.

## Engine contract (used by `src/lib/killa.ts`)

- `POST /v1/chat {chatKey, text, model?}` → `{reply, attachments?}` (≤ ~5 min; Ghina waits 330 s)
- `POST /v1/chat/new {chatKey}` → `{ok}`
- `GET /v1/chat/history?chatKey=&limit=` → `{messages:[{at,who,text}]}` (client only; Ghina's own log is the source of truth)
- `GET /v1/workspace/files?path=` → `{entries:[{name,type,size}]}`
- `GET /v1/workspace/file?path=` → `{path, content}` (413 too large / 415 not text)
- `GET /v1/git/log?limit=` → `{commits:[{hash,date,author,subject}]}`

## Web

`/killa` chat (newest 50 messages, "Muat pesan lama" loads older pages; model selector;
"Sesi baru"), `/killa/files?path=` / `?file=` read-only workspace browser (Markdown files
rendered, others monospace), `/killa/commits` latest 100 commits.

## Mobile API

Bearer token as the other mobile routes, then the allowlist. Errors are `{error}`:
401 token, 403 not allowlisted, 400 invalid input, 413/415 file, 502 engine error or
unreachable, 503 not configured, 504 engine timeout.

| Route | Result |
| --- | --- |
| `GET /api/mobile/killa/chat?before=<id>&limit=50` (limit ≤ 200) | `{messages, nextBefore}` — messages oldest first; pass `nextBefore` as `before` for the previous page (null = start reached) |
| `POST /api/mobile/killa/chat {text, model?}` | `{userMessage, reply}` — waits for the reply (up to ~5.5 min). `text` ≤ 20 000 chars; `model` ∈ default, fable, opus, sonnet, haiku |
| `POST /api/mobile/killa/chat/new` | `{divider}` |
| `GET /api/mobile/killa/files?path=` | `{path, entries:[{name, type: "file"\|"dir", size}]}` |
| `GET /api/mobile/killa/file?path=` | `{path, content}` |
| `GET /api/mobile/killa/commits?limit=50` (≤ 200) | `{commits:[{hash, date, author, subject}]}` |

Message: `{id, role: "user"|"assistant"|"system", body, model, createdAt (ISO)}`.
