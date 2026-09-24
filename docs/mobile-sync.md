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
| POST | `/api/mobile/upload` | multipart, field `file` (image/*, ≤ 5 MB) | `{url}` e.g. `"/uploads/abc.jpg"` |

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
prefix it with the API base URL to display it.

## Entities

Wire names and fields. Fields are the Prisma field names minus `userId`.
Dates are ISO-8601 strings with `Z`. `id` is a string; the mobile app creates new rows
with UUID v4 ids, the server keeps its existing cuid ids — both are valid.

| entity | Prisma model | fields |
|---|---|---|
| `wallets` | Wallet | id, name, type, balance, currency, color, icon, archived, createdAt, updatedAt |
| `categories` | Category | id, name, type, color, icon, createdAt, updatedAt |
| `transactions` | Transaction | id, walletId, toWalletId, categoryId, type, amount, note, date, createdAt, updatedAt |
| `budgets` | Budget | id, categoryId, amount, month, year, createdAt, updatedAt |
| `subscriptions` | Subscription | id, name, amount, currency, cycle, nextBilling, categoryId, walletId, color, icon, note, active, createdAt, updatedAt |
| `planned` | PlannedTransaction | id, type, amount, note, categoryId, walletId, date, done, createdAt, updatedAt |
| `prayers` | PrayerEntry | id, date (`YYYY-MM-DD` string), prayer, status, qobliyah, badiyah, rakaat, prayedAt, note, createdAt, updatedAt |
| `health` | HealthEntry | id, date, weight, systolic, diastolic, pulse, note, createdAt, updatedAt |
| `food` | FoodLog | id, date, name, meal, calories, photoUrl, note, createdAt, updatedAt |

Schema changes the server makes for sync:
- `PrayerEntry` gains `updatedAt DateTime @default(now()) @updatedAt`.
- `User` gains `syncEpoch String @default(cuid())`.
- New model `SyncTombstone { id, userId, entity, entityId, deletedAt @default(now()) }`,
  indexed on `(userId, deletedAt)`. `entity` is the wire name (`transactions`, …).
- `PrayerEntry` gains `status String @default("ontime")`, `qobliyah Boolean @default(false)`,
  `badiyah Boolean @default(false)`, `rakaat Int?`, `prayedAt DateTime?`, `note String?`
  (docs/prayer-quality.md). Existing rows read as `status = "ontime"`.
- `Transaction.type` may be `adjustment` (docs/balance-adjustment.md) — no column change.
- `Wallet` gains `editedAt DateTime` — server-only, **not** on the wire. It is the
  last-write-wins timestamp for wallets (see Push), because a wallet's `updatedAt`
  also moves every time a transaction changes its balance.

## Wallet balances

`wallet.balance` is **server-authoritative**. The server changes it only through
transactions (and the initial balance when a wallet is created). Effect of a transaction:
income `+amount` to `walletId`; expense `−amount` from `walletId`; transfer `−amount`
from `walletId` and `+amount` to `toWalletId`; adjustment `+amount` (signed) to `walletId`.
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
- Delete a category → transactions/subscriptions/planned get `categoryId = null`;
  budgets for it are deleted (tombstoned).

The server does the nulling with `updateMany` before the delete so those rows get a fresh
`updatedAt` and reach other devices through the normal pull. The mobile app applies the
same rules locally when it deletes (and when it receives a tombstone).

"Reset all data" on the web deletes the user's wallets, categories, transactions and
budgets (subscriptions/planned stay, with `walletId`/`categoryId` nulled; prayers, health
and food stay), drops their tombstones and assigns a new `syncEpoch`. Clients see the new
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
    "subscriptions": [ … ], "planned": [ … ], "prayers": [ … ], "health": [ … ], "food": [ … ]
  },
  "deleted": [ { "entity": "transactions", "id": "…", "deletedAt": "…" } ]
}
```

- `changes.X` = rows with `updatedAt >= since`; `deleted` = tombstones with `deletedAt >= since`.
  All 9 keys are always present (possibly `[]`). Archived wallets are included.
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
- `upsert` data holds the full row minus id/createdAt/updatedAt. Same validation as the
  web forms (zod), same ownership checks (referenced wallet/category must belong to the user).
- Last write wins: if the server row's `updatedAt` (for wallets: `editedAt`) is later
  than `clientUpdatedAt`, the mutation is `skipped` and the server row stays (the client
  gets it on the next pull). This applies to `delete` too.
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
- `prayers` and `budgets` have unique keys (`date+prayer`, `categoryId+month+year`). If
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
| transactions | walletId, toWalletId, categoryId, type, amount, note, date | type ∈ expense/income/transfer/adjustment; amount > 0, except `adjustment`: signed, finite, non-zero; wallets/category must be the user's; transfer needs a different `toWalletId` and is stored with `categoryId = null` (non-transfers with `toWalletId = null`) — the client should store the same; `adjustment` with a non-null `categoryId` or `toWalletId` → rejected |
| budgets | categoryId, amount, month, year | category must be the user's **expense** category; month 1–12; amount > 0 |
| subscriptions | name, amount, currency, cycle, nextBilling, categoryId, walletId, color, icon, note, active | cycle ∈ weekly/monthly/yearly; currency any 1–8 chars; note ≤ 200; `active` default true |
| planned | type, amount, note, categoryId, walletId, date, done | type ∈ expense/income; note ≤ 200; `done` default false |
| prayers | date, prayer, status?, qobliyah?, badiyah?, rakaat?, prayedAt?, note? | see "Prayers" below |
| health | date, weight, systolic, diastolic, pulse, note | weight 1–500; systolic 50–300, diastolic 30–200, pulse 20–250 (integers); systolic and diastolic both or neither; at least one of weight/BP/pulse |
| food | date, name, meal, calories, photoUrl, note | name 1–120; unknown `meal` → null; calories 0–20000, rounded to an integer |

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

### JSON conventions

- Numbers are JSON numbers, never strings (`amount`, `balance`, `weight` may be
  fractional; `amount` is negative only for `adjustment`; `month`, `year`, `calories`,
  `systolic`, `diastolic`, `pulse`, `rakaat` are integers). Booleans are JSON booleans
  (`archived`, `active`, `done`, `qobliyah`, `badiyah`).
- Every wire field is always present in pulled rows; missing values are `null`.
- Server dates are ISO-8601 UTC with milliseconds (`2026-09-23T10:00:00.000Z`). Send
  `DateTime` fields (`date`, `nextBilling`) as UTC ISO strings with `Z` too — a string
  without an offset would be read in the server's local timezone.
- `prayers.date` is a plain `YYYY-MM-DD` string (the user's local day), not a timestamp.

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
adjustments too. `node scripts/test-prayer-quality.mjs` unit-tests the scoring module,
report ranges and the ledger's adjustment effect (no server needed).
