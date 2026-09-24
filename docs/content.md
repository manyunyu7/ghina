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
