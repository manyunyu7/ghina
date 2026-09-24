# Prayer quality — spec (web + mobile)

Prayers stop being a yes/no checklist. Every prayer gets a **status**, fardhu prayers can
carry their **rawatib** (sunnah before/after), daily **sunnah** prayers are tracked too,
and a **report** covers any date range with a color map (one colored cell per prayer per
day). "Late" is chosen manually by the user (no prayer-time calculation yet).

Web (`src/app/(dashboard)/prayers/`) and mobile (`mobile/`) implement the same rules.
Shared constants must match exactly (ids, order, colors, points). Web reference
implementation (pure, unit-tested): `src/lib/prayer-quality.ts` +
`scripts/test-prayer-quality.mjs`.

## Data model (one table, `PrayerEntry`)

```prisma
model PrayerEntry {
  id        String    @id @default(cuid())
  userId    String
  date      String    // local date YYYY-MM-DD
  prayer    String    // fardhu: subuh|dzuhur|ashar|maghrib|isya · sunnah: dhuha|tahajud|witir
  status    String    @default("ontime") // see Status; sunnah rows are always "done"
  qobliyah  Boolean   @default(false)    // rawatib before (fardhu rows only, where it exists)
  badiyah   Boolean   @default(false)    // rawatib after  (fardhu rows only, where it exists)
  rakaat    Int?                         // sunnah rows only, optional
  prayedAt  DateTime?                    // optional: when it was prayed
  note      String?
  ...createdAt, updatedAt, @@unique([userId, date, prayer]) unchanged
}
```

- Existing rows keep their meaning (performed) and get `status = "ontime"` via the default.
- A row still means "the user recorded something for that prayer that day". No row =
  not filled in yet. `missed` and `excused` are explicit rows.
- Unique key stays `(userId, date, prayer)` — one status per prayer per day.

### Status (fardhu only)

| id | label (ID) | points | color | counts as prayed |
|---|---|---|---|---|
| `masjid` | Jamaah di masjid | 10 | `#1B7A2E` | yes |
| `jamaah` | Jamaah | 8 | `#58CC02` | yes |
| `ontime` | Sendiri, awal waktu | 6 | `#1CB0F6` | yes |
| `late` | Sendiri, telat | 3 | `#FFC800` | yes |
| `qadha` | Qadha | 1 | `#FF9600` | yes (made up) |
| `missed` | Terlewat | 0 | `#FF4B4B` | no |
| `excused` | Berhalangan (haid/nifas) | — | `#CE82FF` | excluded from everything |
| *(no row)* | Belum diisi | — | `#E5E5E5` (dark: `#37464F`) | — |

Order everywhere = the order above. Default when the user taps once (quick log) = `jamaah`.
(Mobile: tap = jamaah, long-press / sheet = pick any status. Web: status chips/dropdown.)

### Rawatib (muakkad) per fardhu

| prayer | qobliyah | ba'diyah |
|---|---|---|
| subuh | ✓ | – |
| dzuhur | ✓ | ✓ |
| ashar | – | – |
| maghrib | – | ✓ |
| isya | – | ✓ |

Only shown/allowed where ✓. Rawatib can only be ticked on a fardhu row whose status is a
"prayed" status (masjid/jamaah/ontime/late/qadha); switching to missed/excused clears them.

### Daily sunnah

`dhuha`, `tahajud`, `witir` — a row means done (`status = "done"`), optional `rakaat`
(dhuha 2–12 even, tahajud 2–12 even, witir 1–11 odd). Deleting the row = not done.

| id | label | dot color |
|---|---|---|
| `dhuha` | Dhuha | `#F472B6` |
| `tahajud` | Tahajud | `#6366F1` |
| `witir` | Witir | `#14B8A6` |

(Dot colors were unspecified; chosen to stay clear of the status colors.)

`note` is at most 500 characters (trimmed; empty = null). `prayedAt` is a full timestamp;
UIs pick a time of day on the row's date in the device's local timezone.

## Scoring

- Points per fardhu status as in the table.
- **Quality score** for a period (0–100) = sum of points ÷ (10 × counted slots) × 100.
  Counted slots = every (day, fardhu) in the range up to today, **excluding** `excused`;
  unrecorded slots on past days count as 0; for today only recorded slots count.
- Percentages (jamaah, masjid, awal waktu, telat, qadha, terlewat, belum diisi) are over
  counted slots. "Jamaah %" = masjid + jamaah.
- "Complete day" = all 5 fardhu recorded with a prayed status (excused days are neutral:
  they neither break nor count toward streaks).
  Precisely, per day: **complete** = all 5 prayed; **neutral** = ≥1 fardhu `excused` and
  every other fardhu prayed; otherwise **broken**. Streak = consecutive complete days
  ending today, skipping neutral days; an incomplete today doesn't break it (it just
  doesn't count yet). Scores are rounded to an integer; percentages to 1 decimal.
- Per-prayer score = the same formula restricted to one fardhu.
- **Weakest** = the fardhu with the most (late + missed); ties → lower score, then fardhu
  order. **Strongest** = highest score; ties → fewer (late + missed), then fardhu order.
  Only prayers with counted slots take part; none are highlighted if fewer than 2 take
  part or all have the same score and (late + missed); weakest is not shown if it is the
  same prayer as strongest.
- Rawatib counted = ticks on rows with a prayed status (max 5 per day). Sunnah counts =
  rows per sunnah id in the range (up to today).

Mobile XP (gamification, replaces the flat +5/prayer): per fardhu = its points
(missed/excused 0); each rawatib +2; each daily sunnah +3; all-5-prayed day bonus +15.
New achievements: 7-day Subuh jamaah (masjid or jamaah), a full week all-masjid for at
least one prayer time (e.g. Isya), 10× tahajud, a day with all 5 rawatib-applicable
sunnah done, 30 complete days.

## Report (both platforms)

- Range: presets (7 hari, Bulan ini, Bulan lalu, 3 bulan) + custom from/to date.
  7 hari = today−6 … today · Bulan ini = 1st … last day of this month (future days shown
  greyed, not counted) · Bulan lalu = the whole previous month · 3 bulan = today−89 … today
  (90 days) · custom: reversed from/to are swapped; longer than 366 days is clamped to the
  366 days ending at `to`. Web default = 7 hari.
- Summary: quality score, percentages per status, complete days, counts of rawatib and
  each daily sunnah.
- Per-prayer breakdown: for each of the 5 fardhu, count per status (stacked bar or table),
  highlight the weakest (most late/missed) and strongest.
- **Color map**: rows = days in range (newest first on mobile; web may use columns =
  days), 5 columns = fardhu in order, each cell colored by status (legend below). Small
  dots next to each day for dhuha / tahajud / witir, and rawatib shown as tiny
  corner marks on the fardhu cell (white dot top-left = qobliyah, top-right = ba'diyah).
  Tap/hover a cell = detail + edit. Future days are shown faded and not editable.
  Web: `/prayers/report` (own nav entry "Laporan Shalat"), columns = days oldest → newest.

## Sync (mobile)

`prayers` entity gains fields: `status, qobliyah, badiyah, rakaat, prayedAt, note`
(see `docs/mobile-sync.md`). Server validates: `prayer` in the 8 ids, `status` valid for
the prayer kind, rawatib only where allowed and only with a prayed status, rakaat parity
and range for sunnah (and no rakaat on fardhu). Invalid combinations are **rejected**, not
silently fixed — the client must clear rawatib itself when switching to missed/excused.
Older app versions that send rows without the new fields keep working: on create missing
fields get defaults, on update missing fields keep the stored values. Mobile drift schema bumps to version 2 with a migration that
adds the columns (existing rows → `ontime`).
