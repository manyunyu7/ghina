# Ghina mobile ⇄ server sync contract

The Flutter app (`mobile/`) is offline-first: every write lands in its local SQLite
database first and is queued in an outbox. When online, it pushes the outbox and then
pulls everything that changed on the server since its last cursor. The web app keeps
using server actions; both share the same database and the same balance rules.

This document is the contract. Backend (`src/app/api/mobile/**`) and mobile
(`mobile/lib/data/**`, `mobile/lib/sync/**`) must both match it exactly.

## Auth

All `/api/mobile/**` routes except the auth ones require `Authorization: Bearer <token>`.
The token is an HS256 JWT signed with a key derived from `AUTH_SECRET`, `sub` = user id,
valid 90 days. Missing/invalid/expired token → `401 {"error":"unauthorized"}`.

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/api/mobile/auth/login` | `{email, password}` | `{token, user}` |
| POST | `/api/mobile/auth/register` | `{name, email, password}` (password ≥ 8) | `{token, user}` |
| POST | `/api/mobile/auth/google` | `{idToken}` | `{token, user}` |
| GET | `/api/mobile/me` | – | `{user}` |
| PATCH | `/api/mobile/me` | `{name?, currency?}` | `{user}` |
| GET | `/api/mobile/prices?symbols=stock:BBCA,crypto:BTC` | – | `{serverTime, prices: Quote[]}` — see "Prices" |
| POST | `/api/mobile/upload` | multipart, field `file`: an image (JPEG/PNG/WebP/GIF/HEIC, ≤ 5 MB) or an audio clip (M4A/MP4-AAC, raw AAC/ADTS, MP3, Ogg/Opus, WebM; ≤ 20 MB), detected by file signature — the sent MIME type and name are ignored; SVG, HTML, WAV etc. → 400 | `{url, kind}` e.g. `{"url":"/uploads/abc.jpg","kind":"image"}` / `{"url":"/uploads/def.m4a","kind":"audio"}` (extension from the detected type: jpg/png/webp/gif/heic/heif, m4a/aac/mp3/ogg/webm) |

`user` = `{id, name, email, image, currency, syncEpoch}`.

Google: verify the ID token's signature against Google's JWKS, `iss` Google, and `aud`
in `AUTH_GOOGLE_ID` or the comma-separated `AUTH_GOOGLE_MOBILE_CLIENT_IDS`. Find the user
by email (create if missing), same as the web's dangerous email account linking.

Errors are always `{"error": "<human readable message>"}` with a 4xx/5xx status.
Invalid credentials → 401, validation errors → 400, email taken → 409, Google not
configured on the server → 503.

New users created by mobile register/Google get the same starter "Cash" wallet and
default categories as a web sign-up. Google sign-in also links a Google `Account` row, so
the web's Google login lands on the same user. `upload` returns a relative path —
prefix it with the API base URL to display it. `kind` is new (older clients only read
`url`); an image sent where audio was expected comes back as `kind: "image"` — the
client must check `kind` (and the extension) before using the url as a voice clip.

## Entities

Wire names and fields. Fields are the Prisma field names minus `userId`.
Dates are ISO-8601 strings with `Z`. `id` is a string; the mobile app creates new rows
with UUID v4 ids, the server keeps its existing cuid ids — both are valid.

| entity | Prisma model | fields |
|---|---|---|
| `wallets` | Wallet | id, name, type, balance, currency, color, icon, archived, createdAt, updatedAt |
| `categories` | Category | id, name, type, color, icon, createdAt, updatedAt |
| `transactions` | Transaction | id, walletId, toWalletId, categoryId, type, amount, note, date, photos, createdAt, updatedAt |
| `budgets` | Budget | id, categoryId, amount, month, year, createdAt, updatedAt |
| `subscriptions` | Subscription | id, name, amount, currency, cycle, nextBilling, categoryId, walletId, color, icon, note, active, createdAt, updatedAt |
| `planned` | PlannedTransaction | id, type, amount, note, categoryId, walletId, date, done, createdAt, updatedAt |
| `prayers` | PrayerEntry | id, date (`YYYY-MM-DD` string), prayer, status, qobliyah, badiyah, rakaat, prayedAt, note, createdAt, updatedAt |
| `health` | HealthEntry | id, date, weight, systolic, diastolic, pulse, note, createdAt, updatedAt |
| `food` | FoodLog | id, date, name, meal, calories, photoUrl, note, createdAt, updatedAt |
| `taskAreas` | TaskArea | id, name, code, color, icon, schedule, sortOrder, archived, createdAt, updatedAt |
| `tasks` | Task | id, areaId, title, note, bucket, dueDate, dueTime, remindBefore, recurrence, seriesId, done, doneAt, sortOrder, amount, walletId, categoryId, transactionId, createdAt, updatedAt |
| `noteLabels` | NoteLabel | id, name, color, pinnedTab, sortOrder, createdAt, updatedAt |
| `notes` | Note | id, title, body, checklist, labels, color, pinned, archived, photos, audio, links, source, linkedTaskId, linkedContentId, linkedTransactionId, createdAt, updatedAt |
| `socialAccounts` | SocialAccount | id, platform, platformName, handle, color, targetPerWeek, archived, sortOrder, createdAt, updatedAt |
| `contentPillars` | ContentPillar | id, name, color, sortOrder, createdAt, updatedAt |
| `contentItems` | ContentItem | id, title, stage, format, pillar, idea, noteId, checklist, photos, assetLinks, sponsor, createdAt, updatedAt |
| `contentPosts` | ContentPost | id, contentId, accountId, caption, hashtags, scheduledAt, remindBefore, status, postedAt, url, metrics, metricsAt, createdAt, updatedAt |
| `habits` | Habit | id, name, emoji, color, kind, schedule, target, reminders, private, why, startDate, archived, sortOrder, createdAt, updatedAt |
| `habitLogs` | HabitLog | id, habitId, date, type, value, note, triggers, at, createdAt, updatedAt |
| `assets` | Asset | id, kind, symbol, name, currency, priceMode, manualPrice, manualPriceAt, unit, walletId, archived, sortOrder, createdAt, updatedAt |
| `assetTrades` | AssetTrade | id, assetId, type, date, quantity, price, fee, amount, ratio, note, cashTransactionId, createdAt, updatedAt |

`transactions.photos` is a JSON array of strings (docs/transaction-photos.md);
`taskAreas.schedule` and `tasks.recurrence` are JSON objects or `null` (docs/tasks.md) —
never JSON-encoded strings. The same holds for the notes/content JSON fields:
`notes.checklist/labels/photos/audio/links`, `contentItems.checklist/photos/assetLinks`
(arrays), `contentItems.sponsor` (object or null) and `contentPosts.metrics` (object),
`habits.schedule`/`habits.target` (objects), `habits.reminders` and `habitLogs.triggers`
(arrays).
Old app versions ignore the keys and tombstones of entities they don't know.

Schema changes the server makes for sync:
- `PrayerEntry` gains `updatedAt DateTime @default(now()) @updatedAt`.
- `User` gains `syncEpoch String @default(cuid())`.
- New model `SyncTombstone { id, userId, entity, entityId, deletedAt @default(now()) }`,
  indexed on `(userId, deletedAt)`. `entity` is the wire name (`transactions`, …).
- `PrayerEntry` gains `status String @default("ontime")`, `qobliyah Boolean @default(false)`,
  `badiyah Boolean @default(false)`, `rakaat Int?`, `prayedAt DateTime?`, `note String?`
  (docs/prayer-quality.md). Existing rows read as `status = "ontime"`.
- `Transaction.type` may be `adjustment` (docs/balance-adjustment.md) — no column change.
- `Transaction` gains `photos String @default("[]")` (JSON array text; wire: array).
- New models `TaskArea` and `Task` (docs/tasks.md). Task → TaskArea cascade; Task →
  Wallet/Category/Transaction `SetNull`. `@@unique([userId, code])` on TaskArea.
- `Wallet` gains `editedAt DateTime` — server-only, **not** on the wire. It is the
  last-write-wins timestamp for wallets (see Push), because a wallet's `updatedAt`
  also moves every time a transaction changes its balance.
- New models `Note`, `NoteLabel` (docs/notes.md) and `SocialAccount`, `ContentItem`,
  `ContentPost`, `ContentPillar` (docs/content.md) — additive `CREATE TABLE`s only.
  ContentPost → ContentItem and → SocialAccount cascade; Note.linkedTaskId /
  linkedContentId / linkedTransactionId and ContentItem.noteId `SetNull`.
  `@@unique([userId, name])` on NoteLabel and ContentPillar (the server additionally
  enforces case-insensitive uniqueness). JSON columns are `String` with defaults (`"[]"`,
  `"{}"`, sponsor `NULL`).
- `Note` has `editedAt DateTime` — server-only, **not** on the wire: the last-write-wins
  timestamp for notes, because `updatedAt` also moves when the server fills link titles
  (see "Notes") or strips a deleted label.
- New models `Habit`, `HabitLog` (docs/habits.md) and `Asset`, `AssetTrade` (synced),
  `SecurityPrice`, `PortfolioSnapshot` (server-only, docs/investments.md) — additive
  `CREATE TABLE`s only. HabitLog → Habit and AssetTrade → Asset cascade; Asset.walletId
  and AssetTrade.cashTransactionId `SetNull`. `@@unique([habitId, date, type])` on
  HabitLog, `@@unique([userId, kind, symbol])` on Asset (the server additionally enforces
  case-insensitive symbols), `cashTransactionId @unique`.
- `Transaction.type` may be `investment` (docs/investments.md) — no column change.

## Wallet balances

`wallet.balance` is **server-authoritative**. The server changes it only through
transactions (and the initial balance when a wallet is created). Effect of a transaction:
income `+amount` to `walletId`; expense `−amount` from `walletId`; transfer `−amount`
from `walletId` and `+amount` to `toWalletId`; adjustment and investment `+amount`
(signed) to `walletId`.
Editing a wallet's balance (web or mobile) never overwrites it — it records an
`adjustment` transaction for the difference (docs/balance-adjustment.md). Editing a transaction reverses the old
effect and applies the new one; deleting reverses it. The server implements this once in
`src/lib/ledger.ts`, used by both the web actions and the sync endpoint.

On mobile the displayed balance = last pulled server balance + the effects of every
transaction mutation still pending in the outbox (so a pull while mutations are pending
never makes the balance jump backwards).

## Deletes

Every delete of a synced row — from the web, from sync, or by cascade — writes a
`SyncTombstone`. The server implements this centrally (a Prisma client extension or a
helper every delete path calls), not ad hoc per page.

Relations, mirrored on both sides:
- Delete a wallet → its transactions (either side of a transfer) are deleted (tombstoned);
  subscriptions/planned with that `walletId` get `walletId = null`. These cascaded
  transaction deletes do **not** reverse balances on the surviving wallet (a transfer
  from A into a deleted B leaves A's balance as it was) — same as the web always did.
  Tasks with that `walletId` get `walletId = null`; tasks linked to one of the deleted
  transactions get `transactionId = null`.
- Delete a category → transactions/subscriptions/planned/tasks get `categoryId = null`;
  budgets for it are deleted (tombstoned).
- Delete a transaction → tasks with that `transactionId` get `transactionId = null`.
- Delete a task area → its tasks are deleted (tombstoned) (and their notes' `linkedTaskId` nulled).
- Delete a task → notes with that `linkedTaskId` get `linkedTaskId = null`.
- Delete a transaction (any path, incl. wallet cascade) → notes get
  `linkedTransactionId = null`; a content item whose `sponsor.transactionId` is that
  transaction gets `sponsor.transactionId = null` inside the JSON (`paid` unchanged).
- Delete a note label → its id is removed from every note's `labels` (those notes are
  updated, so they re-sync).
- Delete a note → content items with that `noteId` get `noteId = null`; the note's photo
  and audio files are deleted after commit (unless another row still references them).
- Delete a social account → its posts are deleted (tombstoned).
- Delete a content item → its posts are deleted (tombstoned); notes with that
  `linkedContentId` get `null`; its photo files are deleted after commit (unless shared).
- Delete a content pillar → content items whose `pillar` equals its name
  (case-insensitive) get `pillar = null`. Renaming a pillar (sync upsert or web) renames
  it on those items too (updated rows re-sync).
- Delete a habit → its logs are deleted (tombstoned).
- Delete an asset → its trades are deleted (tombstoned), each with its linked cash
  transaction (next rule).
- Delete a trade → its linked transaction (`cashTransactionId`: the `investment` or the
  dividend `income`) is deleted through the ledger — balance reversed, tombstoned.
- Delete a transaction (any path) → trades with that `cashTransactionId` get `null` (the
  trade stays). Delete a wallet → assets with that `walletId` get `null`.
- Deleting a transaction by any path (sync, web, wallet cascade, reset) deletes its photo
  files after the DB change commits — unless another transaction/food/note/content row
  still references the same file (best effort). A note converted to a transaction shares
  its photo files with it, so this reference check matters.

The server does the nulling with `updateMany` before the delete so those rows get a fresh
`updatedAt` and reach other devices through the normal pull. The mobile app applies the
same rules locally when it deletes (and when it receives a tombstone).

"Reset all data" on the web deletes the user's wallets, categories, transactions and
budgets (subscriptions/planned stay, with `walletId`/`categoryId` nulled; task areas and
tasks stay, with `walletId`/`categoryId`/`transactionId` nulled; notes, labels, social
accounts, content items/posts/pillars stay, with `notes.linkedTransactionId` and
`sponsor.transactionId` nulled — `paid` kept; habits and their logs stay; assets and
trades stay with `walletId`/`cashTransactionId` nulled; prayers, health and food stay), removes the
deleted transactions' photo files (except ones a note/content item still uses), drops
all tombstones and assigns a new `syncEpoch`. Clients see the new
epoch and do a full re-pull, so no tombstones are needed.

Server implementation: `src/lib/sync-deletes.ts` (+ `deleteLedgerTransaction` in
`src/lib/ledger.ts`). An ESLint rule forbids `.delete()`/`.deleteMany()` on synced
models anywhere else.

## Pull

`GET /api/mobile/sync?since=<cursor>` (cursor = ms since epoch; `0` or absent = full pull)

```json
{
  "serverTime": 1790000000000,
  "epoch": "ckx…",
  "changes": {
    "wallets": [ … ], "categories": [ … ], "transactions": [ … ], "budgets": [ … ],
    "subscriptions": [ … ], "planned": [ … ], "prayers": [ … ], "health": [ … ], "food": [ … ],
    "taskAreas": [ … ], "tasks": [ … ],
    "noteLabels": [ … ], "notes": [ … ], "socialAccounts": [ … ],
    "contentPillars": [ … ], "contentItems": [ … ], "contentPosts": [ … ],
    "habits": [ … ], "habitLogs": [ … ], "assets": [ … ], "assetTrades": [ … ]
  },
  "deleted": [ { "entity": "transactions", "id": "…", "deletedAt": "…" } ]
}
```

- `changes.X` = rows with `updatedAt >= since`; `deleted` = tombstones with `deletedAt >= since`.
  All 21 keys are always present (possibly `[]`). Archived wallets, areas, notes and
  accounts are included.
- Default task areas: before building the response, if the user has **no** `TaskArea`
  rows at all, the server creates Kerjaan (`area-kerjaan-<userId>`, code `KERJA`, Mon–Fri
  09:00–17:00) and Keseharian (`area-life-<userId>`, code `LIFE`, no schedule) and drops
  any old tombstones for those ids — so the first pull (full or incremental) carries them.
  The mobile app may seed the same rows locally (same ids and fields) if it has none;
  pushing them later is a normal upsert of the same id (LWW), never a duplicate.
- Default note label and content pillars, seeded **once** (not re-seeded after the user
  deletes them): before building the response the server creates the `Ide Konten` label
  (`label-ide-konten-<userId>`, color `#CE82FF`, `pinnedTab` true, sortOrder 0) unless
  that id exists, has a tombstone, or another label already has that name
  (case-insensitive); and, if the user has **no** pillars and none of the default pillar
  ids has a tombstone, the pillars Edukasi `#1CB0F6`, Hiburan `#FF9600`, Promo `#FF4B4B`,
  Behind the scene `#CE82FF`, Personal `#58CC02` (ids `pillar-<edukasi|hiburan|promo|bts|personal>-<userId>`,
  sortOrder 0–4). Mobile should **not** seed these itself once it has pulled
  successfully (a tombstone it never saw would resurrect a deleted default); before the
  first successful pull it may seed the same ids/fields locally (a later push is an
  upsert of the same id). Reset drops tombstones, so after a reset a user without
  pillars/that label gets them again.
- Dividend category, seeded **once** for users with at least one asset: before building
  the response the server creates the income category `Dividen`
  (`category-dividen-<userId>`, color `#10b981`, icon `circle-dollar-sign`) unless an income
  category named "Dividen" (case-insensitive) exists, that id exists, or it has a
  tombstone (the user deleted it). Mobile may create the same id/fields locally when it
  records a dividend and has no Dividen category (a later push is an upsert of the same id).
- A full pull (`since` 0/absent) always returns `deleted: []` — the client starts empty.
- An id never appears in both `changes` and `deleted` of one response.
- `serverTime` = the request start time minus 5 seconds; the client stores it as its next
  cursor. Rows can therefore arrive twice — applying them is idempotent (upsert by id).
- `epoch` is an opaque string (compare for equality only).
- If `epoch` differs from the one the client stored, the client wipes all local synced
  tables (keeping its outbox is pointless — drop it too) and does a full pull.
- The client applies a pulled row only if the row has no pending outbox mutation;
  otherwise the pending local version wins until it is pushed.

## Push

`POST /api/mobile/sync`

```json
{
  "epoch": "ckx…",
  "mutations": [
    {
      "id": "uuid of the mutation",
      "entity": "transactions",
      "op": "upsert",
      "entityId": "uuid-or-cuid",
      "data": { "walletId": "…", "type": "expense", "amount": 25000, "date": "…", … },
      "clientUpdatedAt": "2026-09-23T10:00:00.000Z"
    },
    { "id": "…", "entity": "food", "op": "delete", "entityId": "…", "clientUpdatedAt": "…" }
  ]
}
```

Response:

```json
{ "serverTime": 1790000000000,
  "results": [ { "id": "mutation id", "status": "applied" }, { "id": "…", "status": "rejected", "error": "Wallet not found" } ] }
```

Rules:
- `epoch` (optional, but the client should always send it) is the epoch its local data
  belongs to. If it differs from the server's, **nothing is applied** and the response is
  `409 {"error": "…", "epoch": "<current epoch>"}` — the client wipes local tables + outbox
  and does a full pull. (Without this, a device that missed a web "reset" would push its
  old outbox and resurrect wiped data before it ever pulled the new epoch.)
- At most 1000 mutations per push (else 400).
- Mutations are applied **in order**, each in its own DB transaction. One failing does not
  stop the rest.
  Client order (Flutter outbox): referenced rows first (wallets, categories, areas,
  transactions, other upserts, notes, content items, posts; habits before habit logs;
  assets before trades — a trade's linked transaction is a transaction, so it goes first); deletes of unique-keyed rows
  (labels, areas, budgets, prayers) before those upserts so a re-created name/slot is free;
  pillar deletes then pillar upserts after the items; every other delete **last** — a
  server delete cascade (nulling a link, a pillar, a sponsor's transaction) bumps the
  affected rows' `updatedAt`, which would make the device's own queued edits of those rows
  lose last-write-wins if they were sent after it. Deleting a trade: queue the trade's
  delete **before** its linked transaction's delete (the server's trade delete already
  removes the transaction; the second delete is an idempotent `applied`).
- `upsert` data holds the full row minus id/createdAt/updatedAt. Same validation as the
  web forms (zod), same ownership checks (referenced wallet/category must belong to the user).
- Last write wins: if the server row's `updatedAt` (for wallets and notes: `editedAt`) is
  later than `clientUpdatedAt`, the mutation is `skipped` and the server row stays (the
  client gets it on the next pull). This applies to `delete` too.
- Upsert of an id that no longer exists but has a tombstone: if the tombstone is newer
  than `clientUpdatedAt` → `skipped` (the row stays deleted; the client gets the tombstone
  on the pull). Otherwise the row is re-created and the tombstone removed.
- `clientUpdatedAt` must be ISO-8601 **with** `Z` or an offset (Dart:
  `dt.toUtc().toIso8601String()`); microseconds are fine.
- `delete` of a row that doesn't exist is `applied` (idempotent). Delete applies the
  cascade rules above and writes tombstones.
- `wallets` upsert: `balance` is honored only when creating the wallet (initial balance).
  On update it is ignored.
- `transactions` upsert/delete adjust wallet balances via `src/lib/ledger.ts` (including
  `adjustment`: `+amount` signed). Clients must tolerate unknown future `type` values from
  a pull (skip or show generically; never crash).
- `prayers`, `budgets`, `habitLogs` and `assets` have unique keys (`date+prayer`,
  `categoryId+month+year`, `habitId+date+type`, `kind+symbol` case-insensitive). If
  another row with a different id already holds that key, the mutation returns
  `duplicate`. The client then deletes its local row; the server row arrives on the pull.
- Upserting or deleting a row whose id exists but belongs to another user → `rejected`
  (`"error": "Not found"`).
- `entityId` must match `^[A-Za-z0-9_-]{1,64}$` (UUIDs and cuids do).
- A malformed mutation (unknown entity/op, bad timestamp, …) → `rejected`; its `id` is
  echoed if it was a string, else `null`.
- `status` is one of `applied | skipped | duplicate | rejected`. The client removes the
  mutation from the outbox for every status (a `rejected` one is logged and surfaced to
  the user as a sync error, then its local row is reverted on the next pull).
- `transactions.photos`: array of 0–5 strings, each matching `^/uploads/[A-Za-z0-9-]+\.[a-z]+$`
  (what `/api/mobile/upload` returns), duplicates dropped, order kept. **Optional**: a
  missing `photos` keeps the stored list on update (`[]` on create), so old app versions
  never wipe photos; `null` means `[]`. Anything else (not an array, > 5, other URL) →
  `rejected`. Upload pending local files first, then push the upsert with the returned
  URLs. When an update drops URLs from the list, those files are deleted after the
  change commits (unless still referenced elsewhere).
- A `food` row whose photo was taken offline: the client first uploads the file via
  `/api/mobile/upload`, then sends the upsert with the returned `photoUrl`. `photoUrl`
  must be `null` or a path returned by the upload endpoint (`/uploads/<name>.<ext>`),
  else `rejected`. Deleting a food row, or changing its `photoUrl`, deletes the old file
  on the server (like the web).

The push response's `serverTime` is informational; the client's cursor only ever comes
from a pull.

### Per-entity upsert data (validation = the web forms, `src/lib/schemas.ts`)

| entity | fields in `data` | rules |
|---|---|---|
| wallets | name, type, balance?, currency, color, icon, archived? | type ∈ cash/bank/ewallet/credit/savings/investment; currency ∈ IDR/USD/EUR/GBP/JPY/SGD/MYR; color `#rrggbb`; name 1–60; `balance` only used on create (default 0); `archived` default false |
| categories | name, type, color, icon | type ∈ expense/income; icon must be one of the web's `CATEGORY_ICONS` (`src/lib/constants.ts`) |
| transactions | walletId, toWalletId, categoryId, type, amount, note, date | type ∈ expense/income/transfer/adjustment/investment; amount > 0, except `adjustment` and `investment`: signed, finite, non-zero; wallets/category must be the user's; transfer needs a different `toWalletId` and is stored with `categoryId = null` (non-transfers with `toWalletId = null`) — the client should store the same; `adjustment`/`investment` with a non-null `categoryId` or `toWalletId` → rejected |
| budgets | categoryId, amount, month, year | category must be the user's **expense** category; month 1–12; amount > 0 |
| subscriptions | name, amount, currency, cycle, nextBilling, categoryId, walletId, color, icon, note, active | cycle ∈ weekly/monthly/yearly; currency any 1–8 chars; note ≤ 200; `active` default true |
| planned | type, amount, note, categoryId, walletId, date, done | type ∈ expense/income; note ≤ 200; `done` default false |
| prayers | date, prayer, status?, qobliyah?, badiyah?, rakaat?, prayedAt?, note? | see "Prayers" below |
| health | date, weight, systolic, diastolic, pulse, note | weight 1–500; systolic 50–300, diastolic 30–200, pulse 20–250 (integers); systolic and diastolic both or neither; at least one of weight/BP/pulse |
| food | date, name, meal, calories, photoUrl, note | name 1–120; unknown `meal` → null; calories 0–20000, rounded to an integer |
| transactions (photos) | photos? | see `transactions.photos` above |
| taskAreas | name, code, color?, icon?, schedule?, sortOrder?, archived? | see "Task areas" below |
| tasks | areaId, title, note?, bucket?, dueDate?, dueTime?, remindBefore?, recurrence?, seriesId?, done?, doneAt?, sortOrder?, amount?, walletId?, categoryId?, transactionId? | see "Tasks" below |
| noteLabels | name, color?, pinnedTab?, sortOrder? | see "Note labels" below |
| notes | title?, body?, checklist?, labels?, color?, pinned?, archived?, photos?, audio?, links?, source?, linkedTaskId?, linkedContentId?, linkedTransactionId? | see "Notes" below |
| socialAccounts | platform, platformName?, handle, color?, targetPerWeek?, archived?, sortOrder? | see "Social accounts" below |
| contentPillars | name, color?, sortOrder? | see "Content pillars" below |
| contentItems | title, stage?, format?, pillar?, idea?, noteId?, checklist?, photos?, assetLinks?, sponsor? | see "Content items" below |
| contentPosts | contentId, accountId, caption?, hashtags?, scheduledAt?, remindBefore?, status?, postedAt?, url?, metrics?, metricsAt? | see "Content posts" below |
| habits | name, emoji?, color?, kind?, schedule?, target?, reminders?, private?, why?, startDate, archived?, sortOrder? | see "Habits" below |
| habitLogs | habitId, date, type, value?, note?, triggers?, at? | see "Habit logs" below |
| assets | kind, symbol, name?, currency?, priceMode?, manualPrice?, manualPriceAt?, unit?, walletId?, archived?, sortOrder? | see "Assets" below |
| assetTrades | assetId, type, date, quantity?, price?, fee?, amount?, ratio?, note?, cashTransactionId? | see "Asset trades" below |

Empty/whitespace `note` becomes `null`; `""` ids become `null`.

#### Prayers (docs/prayer-quality.md)

- `date`: a real calendar date `YYYY-MM-DD`. `prayer` ∈ subuh/dzuhur/ashar/maghrib/isya
  (fardhu) or dhuha/tahajud/witir (daily sunnah).
- `status`: fardhu ∈ masjid/jamaah/ontime/late/qadha/missed/excused; sunnah must be `done`.
- `qobliyah`/`badiyah` (bool): only where the rawatib exists (qobliyah: subuh, dzuhur;
  ba'diyah: dzuhur, maghrib, isya) and only with a prayed status
  (masjid/jamaah/ontime/late/qadha). Never on sunnah rows. Violations → `rejected` (the
  server does not silently clear them — send `false` when switching to missed/excused).
- `rakaat` (int or null): sunnah only — dhuha/tahajud even 2–12, witir odd 1–11. Non-null
  on a fardhu row → `rejected`.
- `prayedAt`: ISO-8601 **with** `Z`/offset, or null. `note`: string ≤ 500 chars or null
  (trimmed; empty → null).
- Backward compatibility: every new field is optional. **On create** a missing field gets
  its default (`status` fardhu → `ontime`, sunnah → `done`; booleans false; others null).
  **On update** a missing field keeps the stored value (so an old app version re-pushing
  `{date, prayer}` never wipes a status it doesn't know). Validation runs on the merged row.
  New clients should always send all fields.
- Pulled rows always carry all fields (`rakaat`, `prayedAt`, `note` may be null).

#### Task areas (docs/tasks.md)

- `name` 1–40 (trimmed). `code` trimmed, **uppercased by the server**, then must match
  `^[A-Z0-9]{1,8}$`. `color` `#rrggbb` (default `#58CC02`). `icon` one of `CATEGORY_ICONS`
  (default `briefcase`). `sortOrder` integer (default 0). `archived` bool (default false).
- `schedule`: `null` (anytime) or `{"days":[1..7],"start":"HH:mm","end":"HH:mm"}` — ISO
  weekdays (1 = Mon … 7 = Sun), ≥ 1 day, stored deduplicated + sorted; 24 h `HH:mm`;
  `start < end` (no overnight). A JSON **string** is rejected.
- `code` is unique per user: if another area id already holds it → `duplicate` (the
  client deletes its local area; the server's arrives on the pull). Clients should check
  code uniqueness locally before saving.

#### Tasks (docs/tasks.md)

- `areaId`: the user's area (archived is fine), else `rejected` ("Area not found").
- `title` 1–200 (trimmed). `note` ≤ 2000, trimmed, empty → null.
- `bucket` ∈ fire/want/should (default `want`).
- `dueDate` real `YYYY-MM-DD` or null; `dueTime` `HH:mm` or null — needs `dueDate`.
- `remindBefore` integer minutes 0–10080 or null (only meaningful with dueDate+dueTime).
- `recurrence` null or `{"freq":"daily"|"weekly"|"monthly","interval":1..365,"weekdays":[1..7]?,"monthDay":1..31?}`
  (`interval` default 1). `weekdays` only with weekly, `monthDay` only with monthly, else
  `rejected`. Needs `dueDate`. The server **materializes the defaults** from `dueDate`
  (weekly without `weekdays` → `[weekday of dueDate]`; monthly without `monthDay` → day of
  dueDate) so a clamped month (31 → 28) never drifts; clients should store the same.
- `seriesId` null or `^[A-Za-z0-9_-]{1,55}$`. A recurring task without one gets
  `seriesId = id` (so a recurring task's own id must be ≤ 55 chars — UUIDs/cuids are).
- `done` bool (default false). `doneAt` ISO-8601 with `Z`/offset or null; forced to
  null when `done` is false; a done task without `doneAt` is stamped with server time
  (clients should always send it — XP/streaks use it).
- `sortOrder` finite number (fractional OK, default 0) — manual order within (area, bucket).
- `amount` > 0 or null. `walletId` the user's wallet or null. `categoryId` the user's
  **expense** category or null. `transactionId` the user's transaction or null — push
  the expense before the task that links it (same push, earlier position is fine).
- Completing a recurring task (client side, `nextOccurrence` in `src/lib/tasks.ts`):
  push the done upsert of the current occurrence **and** an upsert of the next one with
  id `<seriesId>_<YYYYMMDD>` (next due date), same fields, `done=false`, `doneAt=null`,
  `transactionId=null`. The server validates both as plain upserts, so two devices that
  completed the same occurrence offline land on the same row: the later
  `clientUpdatedAt` wins, the other is `skipped`. Un-completing never deletes the next
  occurrence.

#### Notes and content — common rules

Pure rules: `src/lib/notes.ts`, `src/lib/content.ts` (unit-tested by
`scripts/test-notes.mjs`, `scripts/test-content.mjs`; mobile mirrors them). Upserts carry
the **full row**: a missing optional field gets its default (not the stored value).
Validation error messages are Indonesian. Text hygiene: `\r\n` → `\n`, control
characters (except tab/newline) removed; "one-line" fields (titles, names, checklist
texts, brand, handle, labels) also turn newlines into spaces and are trimmed.
Soft links are resolved leniently (they may point at rows deleted while the device was
offline): `notes.labels` ids that aren't the user's labels are **dropped**;
`notes.linkedTaskId/linkedContentId/linkedTransactionId`, `contentItems.noteId` and
`sponsor.transactionId` that aren't the user's rows are stored as **null** — never
`rejected`. Hard parents (`contentPosts.contentId/accountId`) must exist → else
`rejected`. Checklists (notes and items): array of ≤ 200 `{id, text, done}`, `id`
`^[A-Za-z0-9_-]{1,64}$` unique within the list, `text` one line ≤ 1000 (empty allowed),
`done` default false. Photo lists: image upload paths only
(`^/uploads/[A-Za-z0-9-]+\.(jpg|png|webp|gif|heic|heif)$`), duplicates dropped, order
kept. Removing a photo/clip URL from a list (or deleting the row) deletes the file after
commit unless another row still references it. Upload pending local files first.

#### Note labels (docs/notes.md)

- `name` one line 1–30. Unique per user **case-insensitively**: another id holding the
  name → `duplicate` (client deletes its local label and moves its notes to the pulled
  one). `color` `#rrggbb` (default `#58CC02`), `pinnedTab` bool (default false),
  `sortOrder` integer (default 0).

#### Notes (docs/notes.md)

- `title` one line ≤ 200 or null (empty → null). `body` Markdown subset ≤ 50 000 chars
  (not trimmed). `color` null or a palette id: red, orange, yellow, green, teal, blue,
  darkblue, purple, pink, brown, gray (`NOTE_COLORS`; each platform maps the id to its
  light/dark shade). `pinned`, `archived` bool (default false). `source`
  share/quick/voice; anything else → null.
- `labels`: array of ≤ 20 label ids, deduplicated; unknown/foreign ids dropped.
- `photos`: ≤ 10 image paths. `audio`: ≤ 5 `{url, durationSec, transcript}` — `url`
  an audio upload path (`^/uploads/[A-Za-z0-9-]+\.(m4a|aac|mp3|ogg|webm)$`),
  `durationSec` number 0–610 (10 min + rounding slack), `transcript` ≤ 20 000 or null
  (trimmed, empty → null); a repeated url keeps the first clip.
- `links`: ≤ 20 `{url, title}` — `url` http(s) without credentials ≤ 2000, `title` one
  line ≤ 300 or null. The server **appends every http(s) URL found in `body`** that
  isn't in the list yet (order of appearance; trailing `.,;:!?'"` and unbalanced `)`/`]`
  are not part of a URL — `extractUrls`), capped at 20 (sent entries first). A sent link
  whose `title` is null keeps the title already stored for that url. Clients should run
  the same merge locally (`mergeLinks`) so their copy matches.
- After an applied note upsert the server fetches missing titles **in the background**
  (og:title / `<title>`, SSRF-safe, 3 s, cached; never blocks the push) and updates only
  `links` (+ `updatedAt`, not `editedAt`) — the client receives the titles on a later pull.
- LWW compares `clientUpdatedAt` with `editedAt` (the last user edit), so a title fill or
  label strip never makes a later device edit `skipped`.
- Any array/object sent as a JSON **string** → `rejected`.

#### Social accounts (docs/content.md)

- `platform` ∈ instagram/tiktok/youtube/x/threads/linkedin/facebook/other (else
  `rejected`). `platformName` one line ≤ 30 — required for `other`, forced to null for
  the others. `handle` one line 1–60 (kept as typed, e.g. `@ghina`). `color` `#rrggbb`;
  null/missing → the platform default (`PLATFORMS` in src/lib/content.ts).
  `targetPerWeek` integer 0–50 or null; 0 is stored as null (= no target). `archived`
  bool, `sortOrder` integer.

#### Content pillars (docs/content.md)

- `name` one line 1–30, unique per user case-insensitively (→ `duplicate`). `color`
  `#rrggbb` (default `#58CC02`), `sortOrder` integer. Renaming renames `pillar` on the
  user's items (server-side, those items re-sync); deleting nulls it (see Deletes).

#### Content items (docs/content.md)

- `title` one line 1–200. `stage` ∈ ide/naskah/produksi/siap/terjadwal/tayang (default
  ide). `format` null or post/carousel/reel/story/video/short/thread/live/other.
  `pillar` one line ≤ 30 or null — a pillar **name** (free text; not required to exist).
  `idea` Markdown ≤ 50 000. `noteId` soft link. `photos` ≤ 10 image paths.
  `assetLinks` ≤ 20 `{url (http/https), label (≤ 100 or null)}`.
- `sponsor`: null or `{brand (1–100), amount (≥ 0, 0 = barter), currency (3 letters,
  uppercased, default IDR), due (YYYY-MM-DD or null), paid (default false), transactionId
  (soft link or null)}`. The server never records the income transaction itself from a
  push: the client pushes the income `transactions` upsert first, then the item with
  `sponsor.transactionId` set.
- **Stage auto-advance** (`autoStage`): the client that changes posts applies it and
  pushes the item: all non-skipped posts `posted` (≥ 1) → `tayang`; else any post
  `scheduled` → `terjadwal` if the item is before it; never backwards. The sync endpoint
  stores what it receives (the web actions apply the same rule).

#### Content posts (docs/content.md)

- `contentId`/`accountId`: the user's item/account, else `rejected` ("Konten/Akun tidak
  ditemukan"). Push the item/account before its posts.
- `caption` ≤ 5000 (not trimmed), `hashtags` ≤ 1000 (trimmed). `scheduledAt` ISO with
  Z/offset or null. `remindBefore` integer 0–10080 or null. `status` ∈
  draft/scheduled/posted/skipped (default draft); `scheduled` requires `scheduledAt`.
  `postedAt` ISO or null — forced to null unless `posted`; a posted post without it is
  stamped with server time (clients should send it). `url` http(s) or null (`""` → null).
  `metrics` object with optional non-negative integer `views, likes, comments, shares,
  saves, followers` (null = not entered; unknown keys dropped); `metricsAt` ISO or null.
- The server does not enforce one post per (item, account); clients (and the web
  actions) refuse adding the same account twice to an item.

#### Habits and habit logs (docs/habits.md)

Pure rules: `src/lib/habits.ts` (`scripts/test-habits.mjs`; mobile mirrors it). Upserts
carry the full row (missing optional fields get defaults). Messages are Indonesian.

- **habits**: `name` one line 1–60. `emoji` one line ≤ 32 UTF-16 units or null. `color`
  `#rrggbb` (default `#58CC02`). `kind` build/quit (default build). `schedule`
  `{"type":"daily"}` | `{"type":"weekdays","days":[1..7]}` (≥ 1, stored deduplicated +
  sorted) | `{"type":"perWeek","times":1..7}`; `target` `{"type":"check"}` |
  `{"type":"count","goal":>0..10000,"unit":one line ≤ 20, default "kali"}` |
  `{"type":"duration","goal":1..1440 integer minutes}` — objects, a JSON **string** →
  `rejected`; missing/null → daily / check. **Quit habits are stored as daily + check**
  whatever is sent (normalized). `reminders` ≤ 5 `HH:mm`, deduplicated + sorted.
  `private` bool, `why` ≤ 500 (trimmed, empty → null), `startDate` real `YYYY-MM-DD`
  (required), `archived` bool, `sortOrder` integer.
- **habitLogs**: `habitId` the user's habit, else `rejected` ("Kebiasaan tidak ditemukan").
  `date` real `YYYY-MM-DD`. `type` done/skip/relapse/urge — build: done/skip; quit:
  done/relapse/urge (others → `rejected`). `value`: build check done → stored as 1; build
  count/duration done → required, 0–100000 (duration integer); quit done → 1; skip → null;
  relapse/urge → integer 1–1000 (default 1). `note` ≤ 1000 (trimmed, empty → null).
  `triggers` array ≤ 10 of one-line tags ≤ 30 (deduplicated case-insensitively), only
  kept on relapse/urge (else `[]`). `at` ISO with Z/offset or null.
  (habitId, date, type) held by another id → `duplicate` (client deletes its local row and
  merges its value into the pulled one). One row per day and type: counts go in `value`
  (increment the existing row, never add a second row).

#### Assets and asset trades (docs/investments.md)

Pure rules: `src/lib/investments.ts` (`scripts/test-investments.mjs`; mobile mirrors it).

- **assets**: `kind` stock/fund/gold/crypto/bond/other. `symbol`: stock/crypto uppercased
  (`.JK`/`-IDR` stripped), stock `^[A-Z0-9][A-Z0-9-]{0,11}$`, crypto `^[A-Z0-9]{1,15}$`;
  other kinds one line 1–20 (case kept). Another asset of the user with the same kind +
  symbol (case-insensitive) → `duplicate`. `name` one line ≤ 100 or null. `currency` 3
  letters (uppercased, default IDR). `priceMode` auto/manual — stored as `manual` for
  every kind but stock/crypto (default auto for those). `manualPrice` ≥ 0 or null,
  `manualPriceAt` ISO or null. `unit` one line ≤ 20, default per kind (lembar / koin /
  gram / unit). `walletId`: soft link — not the user's wallet → stored null. `archived`,
  `sortOrder` integer.
- **assetTrades**: `assetId` the user's asset, else `rejected` ("Aset tidak ditemukan").
  `type` buy/sell/dividend/split/fee; `date` ISO with Z/offset. Per type (irrelevant
  fields are stored null, `fee` 0): buy/sell `quantity` > 0 (units/shares, never lots),
  `price` > 0, `fee` ≥ 0; dividend `amount` > 0; split `ratio` > 0 and ≠ 1; fee
  `amount` > 0. `note` ≤ 500.
- **Sanity check**: holdings are derived in date order (then createdAt, then id); an
  upsert that makes a sell exceed the held quantity where it didn't before → `rejected`
  ("Jumlah jual (X) melebihi kepemilikan (Y) per YYYY-MM-DD"). Deletes are always applied.
- **Cash link** (`cashTransactionId`): the client creates the wallet transaction itself
  and pushes it **before** the trade — buy `investment` −(q·p + fee), sell `investment`
  +(q·p − fee), fee `investment` −amount, dividend `income` +amount (category Dividen),
  split none (`tradeCashEffect`, rounded to 2 decimals). The server checks the link: a
  transaction that isn't the user's (e.g. deleted offline) → stored null; wrong type or
  sign, or one already linked to another trade → `rejected`. Editing a trade offline: push
  the updated transaction, then the trade. See Deletes for cascades.

### Prices

`GET /api/mobile/prices?symbols=stock:BBCA,crypto:BTC` (auth required) — up to 50
`kind:SYMBOL` items (kind stock/crypto, case-insensitive, `.JK`/`-IDR` tolerated,
duplicates dropped); anything else → 400. Response `{serverTime, prices}` in request
order, each:
`{kind, symbol, name, price, prevClose, change, changePct, currency, asOf, fetchedAt,
source, stale, error}` — `price`/`prevClose`/`change`/`changePct`/`name`/`asOf`/`fetchedAt`
may be null (never fetched); `stale` true when the cache rules say the price is old (a
refresh failed or is backing off); `error` null or `not_found` (unknown symbol — use it to
validate a new asset) / `unavailable` (timeout, 5xx) / `rate_limited`. The server
refreshes stale symbols from Yahoo first (cache rules in docs/investments.md), so the
call can take up to ~5 s. Mobile caches the last response for offline display.

### JSON conventions

- Numbers are JSON numbers, never strings (`amount`, `balance`, `weight` may be
  fractional; `amount` is negative only for `adjustment`; `month`, `year`, `calories`,
  `systolic`, `diastolic`, `pulse`, `rakaat` are integers). Booleans are JSON booleans
  (`archived`, `active`, `done`, `qobliyah`, `badiyah`). Task `sortOrder`/`amount` may be
  fractional; area `sortOrder` and task `remindBefore` are integers.
- JSON-typed fields are JSON values: `transactions.photos` (array, `[]` when none),
  `taskAreas.schedule` and `tasks.recurrence` (object or null), the notes/content JSON
  fields (arrays `[]` when empty, `metrics` `{}` when empty, `sponsor` object or null).
  Pulled JSON values are re-validated leniently: invalid entries are left out.
- Notes/content integers: `sortOrder`, `targetPerWeek`, `remindBefore`, metric values;
  `durationSec` and `sponsor.amount` may be fractional.
- Every wire field is always present in pulled rows; missing values are `null`.
- Server dates are ISO-8601 UTC with milliseconds (`2026-09-23T10:00:00.000Z`). Send
  `DateTime` fields (`date`, `nextBilling`) as UTC ISO strings with `Z` too — a string
  without an offset would be read in the server's local timezone.
- `prayers.date` and `tasks.dueDate` are plain `YYYY-MM-DD` strings (the user's local
  day), `tasks.dueTime` a local `HH:mm` — not timestamps. `tasks.doneAt` is a timestamp.

## Client sync loop

Order is always **push, then pull**. Triggers: app start/resume, connectivity regained,
~2 s after a local write (debounced), pull-to-refresh, and every 60 s while in foreground.
One sync at a time. Mutations to the same entity id collapse in the outbox (the latest
upsert replaces an earlier one; a delete after an unpushed create removes both).

The API base URL defaults to production `https://ghina.tentrem.space`; override with
`--dart-define=API_BASE_URL=…` (Android emulator → `http://10.0.2.2:3000`, iOS simulator →
`http://localhost:3000`).

## Server test

`node scripts/test-mobile-sync.mjs [baseUrl]` (default `http://localhost:3100`, e.g. after
`npx next dev -p 3100`) runs the whole protocol end to end against a throwaway user and
deletes it afterwards. It covers prayer statuses/rawatib/sunnah validation and balance
adjustments, task areas/tasks (validation, recurrence idempotency, cascades), transaction
photos (validation + file cleanup) and the web task/transaction actions too.
Flutter end-to-end (real data layer, two devices, v2→v4 and v3→v4 upgrades, notes/content): `GHINA_E2E_BASE_URL=http://localhost:3100 flutter test test/data/e2e_sync_test.dart test/data/e2e_tasks_photos_test.dart test/data/e2e_upgrade_test.dart test/data/e2e_upgrade_v3_test.dart test/data/e2e_notes_content_test.dart` (uses `scripts/e2e-helper.mjs` for the web reset, the link-title fill and cleanup; voice fixture `test/data/fixtures/voice.m4a`). `node scripts/perf-sync.mjs` times pull/push at ~1500 transactions + 300 tasks + 500 notes + 200 content items / 400 posts.
`node scripts/test-tasks.mjs` unit-tests src/lib/tasks.ts and src/lib/photos.ts (no server).
`node scripts/test-notes.mjs` unit-tests src/lib/notes.ts, audio/image sniffing and the
SSRF-safe link-title fetcher (local HTTP servers, blocked address ranges, redirects,
timeout, size cap); `node scripts/test-content.mjs` unit-tests src/lib/content.ts
(platforms, schemas, auto-stage, weeks/consistency, reports, sponsorship). The e2e script
also covers notes/labels/accounts/pillars/items/posts sync (validation, soft links,
cascades, seeding, audio uploads, file cleanup, reset) and the notes/content web actions.
`node scripts/test-habits.mjs` unit-tests src/lib/habits.ts (schemas, streaks, rates,
insights); `node scripts/test-investments.mjs` unit-tests src/lib/investments.ts (holdings,
cash effect, fees, lots) and src/lib/prices.ts with a mocked fetch. The e2e script also
covers habits/logs and assets/trades sync (validation, duplicates, sanity check, cash
links, cascades, balances, reset), the prices endpoint (seeded test tickers, no network)
and the habits/investments web actions.
`node scripts/test-prayer-quality.mjs` unit-tests the scoring module,
report ranges and the ledger's adjustment effect (no server needed).
