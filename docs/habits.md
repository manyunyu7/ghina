# Habits ("Teman Streak") — spec (web + mobile)

A general habit tracker and streak companion: habits to **build** (olahraga, baca buku,
minum air) and habits to **quit** (rokok, begadang, PMO, judol, scroll medsos). Private by
design, offline-first on mobile, gentle and non-judgmental in tone (relapse = data, not
failure). Web and mobile implement the same rules; constants must match.

Pure rules: `src/lib/habits.ts` (unit-tested by `scripts/test-habits.mjs`; mobile mirrors
it). DB helpers: `src/lib/habits-server.ts`. Web actions: `src/app/(dashboard)/habits/actions.ts`.

## Model

```prisma
model Habit {
  id        String   @id @default(cuid())
  userId    String
  name      String            // 1–60, one line
  emoji     String?           // one emoji, optional
  color     String   @default("#58CC02")
  kind      String   @default("build")   // build | quit
  schedule  String   @default("{\"type\":\"daily\"}")
            // JSON: {"type":"daily"} | {"type":"weekdays","days":[1..7]} | {"type":"perWeek","times":1..7}
  target    String   @default("{\"type\":\"check\"}")
            // build only. JSON: {"type":"check"} | {"type":"count","goal":>0..10000,"unit":"gelas"}
            //                 | {"type":"duration","goal":1..1440}  (minutes)
  reminders String   @default("[]")    // JSON ["07:00","21:30"] local HH:mm, ≤ 5
  private   Boolean  @default(false)   // masked name in home cards, widgets and notifications
  why       String?           // ≤ 500 — "alasan berhenti/mulai", shown on the emergency screen
  startDate String            // YYYY-MM-DD; streak counting starts here (quit: "hari bersih" start)
  archived  Boolean  @default(false)
  sortOrder Int      @default(0)
  createdAt, updatedAt
}

model HabitLog {
  id        String   @id @default(cuid())
  userId    String
  habitId   String            // → Habit, cascade (tombstoned)
  date      String            // local YYYY-MM-DD
  type      String            // done | skip | relapse | urge
  value     Float?            // done: progress that day; relapse/urge: count that day; skip: null
  note      String?           // ≤ 1000 — journaling
  triggers  String   @default("[]")    // JSON tags for relapse/urge: ["bosan","stres","sendirian","malam","medsos","capek", custom…] ≤ 10
  at        DateTime?         // when it happened (relapse/urge time of day for analysis)
  createdAt, updatedAt
  @@unique([habitId, date, type])  // one row per habit/day/type; counts go in `value`
}
```

Log types per kind:
- build: `done` — value = progress that day (count/minutes; always 1 for `check`). The day
  is **met** when value ≥ goal (check: the row exists). `skip` — intentional rest day
  (sakit, libur): neutral for streaks, max 2 per rolling 7 days (UI/web actions enforce;
  sync just stores).
- quit: `relapse` — the habit happened that day, value = how many times (default 1).
  `urge` — cravings resisted ("Lagi pengen, tapi tahan"), value = count that day. `done`
  (value 1) — the explicit "Hari ini bersih ✅" check-in (gamification only; streak math
  ignores it).
- Any other combination (skip on quit, relapse/urge on build) is rejected.

## Streak rules

- **Quit habit** — "hari bersih": today counts as clean so far (labelled "hari ini masih
  berjalan"). `current = daysBetween(max(startDate, lastRelapse + 1), today) + 1`; 0 if
  the relapse is today (or startDate is in the future). Longest = the longest clean run
  between startDate, relapses and today. Milestones: 1, 3, 7, 14, 21, 30, 40, 60, 90, 120,
  180, 270, 365, then 400, 500, 600, … (every hundred).
- **Build habit** — period-based; days before `startDate` never count:
  - daily: consecutive met days; `skip` days are neutral (don't break, don't count);
    today unmet doesn't break until the day ends. A past day with some progress below the
    goal is a miss.
  - weekdays: only the scheduled weekdays count; other days are ignored (even if done).
  - perWeek(n): consecutive ISO weeks (Mon–Sun) with ≥ need met days, where need =
    min(n, available days) and available = days of the week on/after startDate minus skip
    days. need 0 → neutral week. The current week counts once met, otherwise it doesn't
    break yet. Streak unit = weeks.
  Completion rate over a range (clamped to [startDate, today]) = met scheduled periods ÷
  scheduled periods (skip days / neutral weeks excluded; today / the current week only once
  met). Quit: clean days ÷ days.

## Companion features

- **Tombol darurat** (quit habits): big "Lagi pengen…" button → logs an urge (+1), then a
  calming screen: 60-s box-breathing animation, the habit's `why`, a random encouraging
  line (`ENCOURAGEMENTS`, Indonesian, non-judgmental), current clean streak, and quick
  actions (`URGE_QUICK_ACTIONS`: jalan sebentar, minum air, telpon teman — text only).
  After 60 s: "Berhasil tahan? 💪" (keeps the urge) / "Aku kalah kali ini" (converts it:
  urge −1, relapse +1 with triggers — web action `urgeToRelapse`).
- **Relapse flow**: no shaming. Ask optional triggers + note, show the previous streak as
  an achievement ("Kamu sempat bersih 12 hari — itu nyata", `cleanStreakBefore`), the new
  streak starts tomorrow.
- **Journal**: optional note on the day's done/skip/relapse/urge row.
- **Insights** (range): completion % / clean days, streak history (clean runs), heatmap
  calendar, relapse & urge by weekday and hour, top triggers, urges resisted total
  (`habitInsights`).
- **Reminders**: local notifications at `reminders` times on scheduled days if not yet
  met (build) / a daily check-in nudge (quit). Private habits show "Waktunya cek
  kebiasaanmu ✨" without the name. Reuse the tasks notification infra and its cap.
- **Privacy**: private habits are masked ("Kebiasaan pribadi") everywhere outside the
  Habits screen (home, notifications, widgets, web dashboard). Mobile: optional app-level
  lock for the Habits screen with device biometrics/PIN (`local_auth`) — setting "Kunci
  Kebiasaan".
- **Gamification** (mobile, `HABIT_XP`): build day met +5 (cap 10 habits/day), quit
  clean check-in +3/day, urge resisted +5 (cap 5/day), milestone bonuses (quit:
  7→+20, 30→+50, 90→+100, 365→+365; build streaks 7→+20, 30→+50, 100→+100 in the streak's
  unit). Achievements: first habit, 7-day build streak, 30 hari bersih, 100 urges
  resisted, 3 habits all met for 7 days. XP never decreases visibly on relapse (derived
  rules just stop adding).

## UI

- **Mobile**: new "Kebiasaan" entry (home quick actions + Profile; home card "Kebiasaan
  hari ini" with one-tap check / +1 / timer, and for quit habits the clean-days counter
  with a flame-tree; private ones masked). Habit list, habit detail (big streak ring,
  calendar heatmap, insights), create/edit (name, emoji, color, kind, schedule, target,
  reminders, private, why, start date — "sudah bersih sejak…" for quit), emergency
  button, relapse sheet, journal.
- **Web** `/habits`: list with today's check-in controls, detail with charts/heatmap and
  insights, create/edit, relapse/urge logging, journal. Nav entry "Kebiasaan".

## Sync

Entities `habits`, `habitLogs` (JSON fields as JSON). Unique (habitId, date, type) →
`duplicate` handling like prayers. Habit delete → logs tombstoned. Reset-all-data keeps
habits (like tasks/notes). Details: docs/mobile-sync.md "Habits".

## Clarifications

Decisions taken while implementing the backend (2026-09-25):

1. `Habit.why String?` (≤ 500) added — the emergency screen's "alasan".
2. Quit habits are always `{"type":"daily"}` + `{"type":"check"}`: the server normalizes
   (not rejects) whatever schedule/target is sent for `kind = quit`.
3. Quit `done` rows (value 1) are the explicit clean check-in; they are ignored by streak
   math. Build habits can't log relapse/urge; quit habits can't log skip (→ rejected).
4. `value` rules: build `check` done → always 1; `count` done needs a value 0–100000;
   `duration` done needs whole minutes; relapse/urge integer 1–1000 (default 1); skip null.
   A done row with value 0 is allowed (not met).
5. Counts are aggregated in one row per (habit, date, type): the web actions add to the
   row (`logUrge`, `logRelapse`, `checkInHabit {add}`); mobile does the same locally.
6. Today unmet is `pending` (never breaks); a past day with partial progress is a miss.
   Days before `startDate` are ignored (they neither count nor break). For weekdays
   schedules, a done row on an unscheduled day doesn't count.
7. perWeek need = min(times, available days) with skips and days before startDate removed
   (a half first week asks for less); weeks with need 0 are neutral.
8. Milestones after 365: every round hundred (400, 500, …).
9. Skip limit: at most 2 skips in **every** 7-day window containing the new skip
   (`canSkip`). Enforced by the web action and the mobile UI; sync stores what it gets.
10. Triggers: one line ≤ 30 chars, ≤ 10, deduplicated case-insensitively (first spelling
    kept); only stored on relapse/urge rows (others → `[]`). Insights merge case-insensitively.
11. Insights by weekday use the log's `date` (Mon = index 0); by hour use `at` in the
    user's zone (default Asia/Jakarta); rows without `at` count as `unknownHour`.
    Counts are weighted by `value`.
12. The server keeps no XP; `HABIT_XP` constants live in src/lib/habits.ts for mobile.
13. Changing a habit's kind keeps its logs; logs of the other kind's types are ignored by
    the math.
