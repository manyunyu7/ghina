# Content planner (social media) — spec (web + mobile)

Plan, schedule and track posts for the user's **own** social accounts (single user, no
team, no client management). Builds on Notes (ideas), the notification infrastructure
(reminders) and Finance (sponsorship income). **No auto-posting** in v1 — the app reminds,
copies the caption and opens the platform app/site.

## Accounts

```prisma
model SocialAccount {
  id           String  @id @default(cuid())
  userId       String
  platform     String          // instagram | tiktok | youtube | x | threads | linkedin | facebook | other
  platformName String?         // display name when platform = other (e.g. "Pinterest")
  handle       String          // @username or channel name, ≤ 60
  color        String          // default per platform
  targetPerWeek Int?           // posting goal, e.g. 3 (null = none)
  archived     Boolean @default(false)
  sortOrder    Int     @default(0)
  createdAt, updatedAt
}
```

Built-in platform list with icon + default color + "open" URL scheme/web URL; users can
add `other` platforms with a custom name.

## Content items

```prisma
model ContentItem {
  id          String   @id @default(cuid())
  userId      String
  title       String            // ≤ 200
  stage       String   @default("ide")  // ide | naskah | produksi | siap | terjadwal | tayang
  format      String?           // post | carousel | reel | story | video | short | thread | live | other
  pillar      String?           // content pillar name (user-defined list, see below)
  idea        String   @default("")    // markdown: the idea / script / notes
  noteId      String?           // source note (SetNull)
  checklist   String   @default("[]")  // JSON [{id,text,done}] production checklist
  photos      String   @default("[]")  // JSON /uploads URLs (≤ 10) — thumbnails/assets refs
  assetLinks  String   @default("[]")  // JSON [{url,label}] (Drive/Canva/CapCut links)
  sponsor     String?           // JSON {brand, amount, currency, due?, paid, transactionId?} or null
  createdAt, updatedAt
}

model ContentPost {            // one per target account (the "variant")
  id          String   @id @default(cuid())
  userId      String
  contentId   String            // → ContentItem, cascade (tombstoned)
  accountId   String            // → SocialAccount, cascade (tombstoned)
  caption     String   @default("")   // ≤ 5000
  hashtags    String   @default("")   // free text, ≤ 1000
  scheduledAt DateTime?           // planned publish time
  remindBefore Int?               // minutes; null = no reminder
  status      String   @default("draft")  // draft | scheduled | posted | skipped
  postedAt    DateTime?
  url         String?             // link to the live post
  metrics     String   @default("{}")    // JSON {views,likes,comments,shares,saves,followers} (manual)
  metricsAt   DateTime?
  createdAt, updatedAt
}

model ContentPillar { id, userId, name (≤30, unique), color, sortOrder, createdAt, updatedAt }
```

- The item's `stage` is the pipeline column; a post's `status` tracks each account.
  When any post is `scheduled`, the item moves to `terjadwal` (unless the user moved it
  further); when all non-skipped posts are `posted`, the item moves to `tayang`.
- Default pillars seeded: Edukasi, Hiburan, Promo, Behind the scene, Personal.

## Features

- **Pipeline board** (web + mobile): columns per stage, drag between stages, filters by
  account, pillar and format.
- **Calendar** (week / month): posts by `scheduledAt`, colored by account; **empty slots**
  vs each account's `targetPerWeek` ("IG: 1/3 minggu ini"); drag to reschedule (web).
- **Idea inbox**: notes with the `Ide Konten` label appear as an inbox; "Jadikan konten"
  converts (creates ContentItem at `ide`, links `noteId`).
- **Reminders** (mobile, reuse the tasks notification infra and cap): at
  `scheduledAt − remindBefore` → `[IG-TAYANG] <title>`; tapping opens the post with
  **Salin caption + hashtag** and **Buka Instagram** (platform deep link / web URL), then
  "Sudah tayang" (sets posted + postedAt, optionally paste URL).
- **Metrics**: 3 days after `postedAt` a gentle prompt "Isi performa?" (in-app, and a
  notification if enabled); manual entry per post.
- **Reports** (date range): posts per account vs target, consistency streak per account
  (weeks meeting the target), best posts by views/engagement, averages by pillar, format
  and weekday/hour, pillar balance chart.
- **Sponsorship**: optional sponsor on an item; when marked paid → offer to record an
  income transaction (amount, wallet picker, note "Endorse <brand>") and link it; report
  of sponsor income per account/month; unpaid list with due dates.
- **Gamification** (mobile): XP for moving items forward (ide→naskah +3 … tayang +10),
  posting on schedule, weekly target met per account (+20); achievements (first post,
  4-week consistency, 50 posts, first sponsor).

## Navigation

- Mobile: "Konten" from home quick actions and Profile menu (not a bottom tab); a home
  card "Tayang hari ini" when posts are scheduled today.
- Web: `/content` (board, calendar, report tabs), `/content/accounts`.

## Sync

Entities `socialAccounts`, `contentItems`, `contentPosts`, `contentPillars`; JSON fields as
JSON values; cascades per the model; photo cleanup like other photo fields; sponsor
transaction link nulled when that transaction is deleted.

## Clarifications (backend implementation)

Decided while building the backend; the web and mobile follow these.

- **Platforms** (`PLATFORMS` in `src/lib/content.ts`): id, label, short code (IG, TT, YT,
  X, TH, IN, FB; `other` → first 4 letters of its name or LAIN — used in `[IG-TAYANG] …`),
  default color, a lucide icon name (lucide has no brand logos), and profile / create /
  app-deep-link URL templates with `{handle}` (leading `@` dropped, URL-encoded).
  `platformName` is required for `other` and null otherwise; `targetPerWeek` 1–50 (0 → null).
- **Pillar** on an item is the pillar **name** (free text ≤ 30, not required to exist).
  Pillar names are unique per user case-insensitively. Renaming a pillar renames it on
  the items; deleting it sets their `pillar` to null (case-insensitive match).
- **Default pillars** are seeded once (ids `pillar-<edukasi|hiburan|promo|bts|personal>-<userId>`,
  colors `#1CB0F6`, `#FF9600`, `#FF4B4B`, `#CE82FF`, `#58CC02`) — only when the user has
  no pillars and never deleted a default one.
- **Stage auto-advance** (`autoStage`): all non-skipped posts posted (≥ 1) → `tayang`;
  else any post `scheduled` → `terjadwal` if the item is before it; never moves backwards.
  Applied by whoever changes posts (web actions; mobile locally, then pushes the item) —
  the sync endpoint doesn't derive it. Mobile also re-applies it after a pull that
  changed a post's status (two phones posting different accounts offline would
  otherwise both leave the item at `terjadwal`); a post first seen in a full pull
  doesn't trigger it, so a stage moved back by hand isn't undone by a re-download. Moving stages by hand is free in both directions.
- **Posts**: `scheduled` requires `scheduledAt`; `postedAt` only on `posted` (stamped if
  missing). One post per (item, account) is enforced by the web actions / mobile UI, not
  the DB. Metrics: `{views, likes, comments, shares, saves, followers}` non-negative
  integers, each optional; engagement = likes + comments + shares + saves; rate =
  engagement / views. "Isi performa?" when posted ≥ 3 days ago and no metrics yet.
- **Weeks** are ISO weeks (Mon–Sun) in the user's local time (server-side default zone
  `Asia/Jakarta`, overridable per call). Calendar placement: `postedAt` for posted posts,
  else `scheduledAt`. Week slots per account: `planned` = non-skipped posts placed in the
  week, `posted` = posted in the week, empty = max(0, target − planned), met = posted ≥ target.
- **Reports** (`buildContentReport`): posted posts by `postedAt` in the range; expected =
  round(target × days / 7) (prorated); consistency (weeks met, longest and current streak)
  on the **full** ISO weeks inside the range — an in-progress week that isn't met yet
  doesn't break the current streak; best posts by views and by engagement (top 5);
  averages (views, engagement, rate — over posts with metrics) by pillar, format, local
  weekday (1–7) and hour (0–23); pillar balance = share of posted posts.
- **Sponsorship**: `sponsor.amount` ≥ 0 (0 = barter), currency 3 letters (default IDR),
  `due` YYYY-MM-DD. Marking paid with "record income" creates an `income` transaction via
  the ledger (chosen wallet, optional income category, note `Endorse <brand>`) and links
  it; an item never records a second one. Marking it unpaid keeps the transaction and
  its link (unless the user chooses to delete it too), so marking paid again reuses it;
  only when the linked transaction is gone does "record income" create a new one.
  Removing a sponsor whose income is still linked is refused (delete the transaction
  first) — otherwise re-adding it and paying would record the income twice.
  `sponsor.transactionId` must be one of the user's **income** transactions; any other
  id is stored as null (soft link, like a deleted one). Deleting that transaction (any
  path, incl. reset) sets `sponsor.transactionId = null` and keeps `paid`. Sponsor income per month
  uses the transaction's date (else due, else the item's creation); per account it is
  split equally across the item's accounts.
- **XP** (mobile): per stage newly reached naskah +3, produksi +4, siap +5, terjadwal +6,
  tayang +10 (`stageXp`); weekly target met +20. A paid sponsor's XP is dated by its
  linked income transaction's date, else when the device first saw it paid (device-only),
  else the item's creation — never its `updatedAt`.
- **Reset all data** keeps accounts, pillars, items and posts (sponsor links nulled).

Server implementation: `src/lib/content.ts` (pure; `scripts/test-content.mjs`),
`src/lib/content-server.ts` (save/seed/auto-stage/sponsor/calendar/report/idea inbox),
`src/lib/sync-links.ts` + `src/lib/sync-deletes.ts` (cascades),
`src/app/(dashboard)/content/actions.ts` (web server actions).
