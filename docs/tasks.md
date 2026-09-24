# Tasks (to-do) — spec (web + mobile)

A to-do list built on the "FIRE / WANT / SHOULD" method, split by **user-defined areas**
(default: Kerjaan and Keseharian). Offline-first on mobile like every other entity.
Web and mobile implement the same rules; constants must match exactly.

## Concepts

- **Area** — a life context the user defines (Kerjaan, Keseharian, Kuliah, Bisnis, …).
  Has a short **code** used in notifications (`[KERJA-FIRE] …`) and an optional **active
  schedule** (days + hours) that drives focus mode.
- **Bucket** — how urgent a task is:

| id | label | meaning | color | XP on done |
|---|---|---|---|---|
| `fire` | 🔥 FIRE | today / tomorrow | `#FF4B4B` | 10 |
| `want` | ✨ WANT | within 1–2 weeks | `#CE82FF` | 8 |
| `should` | 📋 SHOULD | whenever / routine | `#1CB0F6` | 5 |

  Order everywhere: fire, want, should.
- **"Mepet" highlight** — an undone WANT task whose due date is today or tomorrow is
  highlighted ("Mepet", fire color accent) but NOT moved automatically. Any undone task
  whose due date/time is past is **overdue** (red "Terlambat" label): a date-only task
  once its day has ended, a timed one once `dueTime < now` on its day. An overdue WANT is
  "Terlambat", not "Mepet". (`isMepet` / `isOverdue` in `src/lib/tasks.ts`.)

## Data model

```prisma
model TaskArea {
  id        String   @id @default(cuid())
  userId    String
  name      String            // 1–40 chars
  code      String            // 1–8 chars, A–Z 0–9, uppercase, unique per user
  color     String   @default("#58CC02")
  icon      String   @default("briefcase")   // same icon set as categories
  schedule  String?           // JSON, see below; null = no schedule ("anytime")
  sortOrder Int      @default(0)
  archived  Boolean  @default(false)
  createdAt, updatedAt
  @@unique([userId, code])
}

model Task {
  id            String    @id @default(cuid())
  userId        String
  areaId        String            // → TaskArea, cascade delete (tombstoned)
  title         String            // 1–200 chars
  note          String?           // ≤ 2000
  bucket        String   @default("want")   // fire | want | should
  dueDate       String?           // local date YYYY-MM-DD
  dueTime       String?           // local HH:mm, only with dueDate
  remindBefore  Int?              // minutes before due (0 = at due time); null = no reminder.
                                  // Only meaningful with dueDate+dueTime.
  recurrence    String?           // JSON, see below; null = one-off
  seriesId      String?           // same for every occurrence of a recurring task
  done          Boolean  @default(false)
  doneAt        DateTime?
  sortOrder     Float    @default(0)   // manual order within (area, bucket)
  amount        Float?            // optional money link (> 0)
  walletId      String?           // → Wallet, SetNull
  categoryId    String?           // → Category (expense), SetNull
  transactionId String?           // the expense recorded when completing; → Transaction, SetNull
  createdAt, updatedAt
  @@index([userId, done]) @@index([userId, dueDate])
}
```

### Area schedule JSON

`{"days":[1,2,3,4,5],"start":"09:00","end":"17:00"}` — ISO weekdays (1 = Monday …
7 = Sunday), local times, `start < end` (no overnight ranges in v1). Default seed for
every user that has no areas (server on first tasks sync / web first visit; mobile on
first use if the pull brought none — use deterministic ids `area-kerjaan-<userId>` and
`area-life-<userId>` so seeding on two devices can't duplicate):
- **Kerjaan** — code `KERJA`, color `#1CB0F6`, icon `briefcase`, schedule Mon–Fri 09:00–17:00, sortOrder 0
- **Keseharian** — code `LIFE`, color `#58CC02`, icon `home`, no schedule, sortOrder 1

"Has no areas" counts archived areas too. A user who deletes every area gets the two
defaults again on the next sync / board visit (a task always needs an area).
Area codes are stored uppercase (input is uppercased) and are unique per user; in sync a
code held by another area id answers `duplicate`.

### Recurrence JSON

`{"freq":"daily"|"weekly"|"monthly","interval":1..365,"weekdays":[1..7]?,"monthDay":1..31?}`
- daily: every `interval` days. weekly: every `interval` weeks on `weekdays`
  (default: the due date's weekday). monthly: every `interval` months on `monthDay`
  (default: due date's day; clamp to the month's last day, e.g. 31 → 30/28).
- `interval` defaults to 1. `weekdays` is only allowed for weekly and `monthDay` only for
  monthly (otherwise invalid).
- The defaults are **materialized on save** (weekly → `weekdays: [weekday of dueDate]`,
  monthly → `monthDay: day of dueDate`), so 31 Jan → 28 Feb → 31 Mar never drifts to 28.
- Next due date, computed from the current due date: weekly = the next listed weekday
  later in the same ISO week (Mon–Sun), else the first listed weekday `interval` weeks
  after this week; monthly = `monthDay` later in the same month if it is still ahead,
  else `interval` months later (clamped). Reference: `nextDueDate` in `src/lib/tasks.ts`
  (unit-tested in `scripts/test-tasks.mjs`; mobile must match).
- A recurring task needs a `dueDate`.
- **Completing** an occurrence: mark it done, and create the next occurrence (same
  fields, `done=false`, next due date from the rule computed from the *current due
  date*, not today; keep `dueTime`, `remindBefore`, bucket, area, money link — but
  `transactionId` null). The next occurrence's id is **deterministic**:
  `<seriesId>_<YYYYMMDD>` so two offline devices completing the same occurrence create
  the same row (upsert) instead of duplicates. `seriesId` = the first occurrence's id
  (the server fills `seriesId = id` for a recurring task that has none, so the first
  occurrence's id must be ≤ 55 chars). If the next occurrence already exists (complete →
  un-complete → complete) it is left as is.
  Un-completing does not delete the next occurrence and keeps `transactionId` (the web
  offers deleting the linked expense explicitly — `uncompleteTask(id, {deleteExpense})`).

## Focus mode (time-based context)

At a given local time, the **focus areas** are the non-archived areas whose schedule
contains now; if none match, the focus areas are the areas **without** a schedule.
Mobile Tugas tab and web board open on focus areas, with a switch to show any single
area or "Semua". Mobile home shows focus-area FIRE tasks. Sunday before 12:00 the mobile
home also shows a "Sapu bersih SHOULD 🧹" card listing undone SHOULD tasks of unscheduled
areas.

## Money link

A task may carry `amount` (+ optional wallet/category). When the user marks it done,
the app offers "Catat pengeluaran Rp X?" (prefilled expense: amount, wallet, category,
note = task title, date = today). Accepting creates the transaction and sets
`transactionId`. Declining just completes the task. The category must be an **expense**
category. A task that already has a `transactionId` never records a second expense.

## Notifications (mobile only)

Local notifications, rescheduled after every local change and every sync pull:
- For each undone task with `dueDate + dueTime` and `remindBefore != null`, schedule at
  due − remindBefore (skip if in the past).
- Title: `[<AREA CODE>-<BUCKET>] <title>` e.g. `[KERJA-FIRE] Kirim revisi client A`;
  body: due time + area name (+ amount if any). Tapping opens the task.
- Cap 60 scheduled notifications (soonest first) — Android/iOS limits.
- Settings: master on/off, default `remindBefore` for new tasks with a time (0 / 10 /
  30 / 60 min).

## Gamification (mobile)

Completing a task = an activity (counts toward the daily goal and streak-neutral —
the transaction streak stays transaction-only). XP by bucket (table above), by `doneAt`
local day, max 20 tasks counted per day. Un-completing removes it (derived). Achievements:
first task done, 10 FIRE tasks done, "FIRE kosong" (end a day with 0 undone FIRE in focus
areas) 7 times, 100 tasks done, a recurring task completed 10 times.

## UI summary

- **Web** `/tasks`: board = columns per area (focus areas first, others collapsible),
  rows per bucket; drag & drop between buckets/areas and to reorder; quick add per cell;
  task dialog with all fields (due date/time, recurrence builder, money link); filters
  (Hari ini, Mepet, Terlambat, Selesai); area manager (name, code, color, icon,
  schedule, order, archive/delete). Nav entry "Tugas".
- **Mobile** bottom tab **"Tugas"** replaces "Belajar" (Belajar stays reachable from the
  home "Lanjut belajar" card and the Profile menu). Area chips on top (focus areas
  preselected, "Semua"), three bucket sections, swipe to complete/delete, long-press to
  move bucket, fast quick-add (title + bucket + optional due), full task sheet, area
  manager, completion celebration with XP.

## Sync

Entities `taskAreas` and `tasks` (wire names) with the fields above (JSON fields travel
as JSON objects on the wire, not strings). Delete rules: deleting an area deletes its
tasks (tombstones); deleting a wallet/category/transaction nulls the task's reference
(`updateMany`, like other entities). Validation mirrors this spec — exact rules in
docs/mobile-sync.md ("Task areas", "Tasks"). Old app versions ignore the new entities.
"Reset all data" keeps areas and tasks (like prayers) but nulls their
wallet/category/transaction links, since those rows are wiped.

## Server implementation

- `src/lib/tasks.ts` — pure: constants, zod schemas, recurrence math, `nextOccurrence`,
  `isMepet`, `isOverdue`, `focusAreas`, `localClock`, default areas. `scripts/test-tasks.mjs`.
- `src/lib/tasks-server.ts` — DB: `saveTask`, `validateTaskRefs`, `createNextOccurrence`,
  `ensureDefaultTaskAreas`.
- `src/lib/sync-deletes.ts` — `deleteTaskAreaCascade`, task deletes (tombstones).
- `src/app/(dashboard)/tasks/actions.ts` — web server actions.
