/**
 * Prayer quality — shared constants, validation and scoring (docs/prayer-quality.md).
 * Pure module: no Prisma / React imports, so it runs in server code, client code,
 * the sync endpoint and plain node test scripts alike. The mobile app mirrors these
 * constants exactly (ids, order, colors, points).
 */

// ---------- Prayers ----------

export const FARDHU = [
  { id: "subuh", label: "Subuh" },
  { id: "dzuhur", label: "Dzuhur" },
  { id: "ashar", label: "Ashar" },
  { id: "maghrib", label: "Maghrib" },
  { id: "isya", label: "Isya" },
] as const;

export const SUNNAH = [
  { id: "dhuha", label: "Dhuha", color: "#F472B6", rakaat: { min: 2, max: 12, parity: "even" } },
  { id: "tahajud", label: "Tahajud", color: "#6366F1", rakaat: { min: 2, max: 12, parity: "even" } },
  { id: "witir", label: "Witir", color: "#14B8A6", rakaat: { min: 1, max: 11, parity: "odd" } },
] as const;

export type FardhuId = (typeof FARDHU)[number]["id"];
export type SunnahId = (typeof SUNNAH)[number]["id"];
export type PrayerId = FardhuId | SunnahId;

export const FARDHU_IDS: readonly string[] = FARDHU.map((p) => p.id);
export const SUNNAH_IDS: readonly string[] = SUNNAH.map((p) => p.id);
/** All 8 prayer ids accepted in `PrayerEntry.prayer`. */
export const ALL_PRAYER_IDS: readonly string[] = [...FARDHU_IDS, ...SUNNAH_IDS];

export const isFardhu = (id: string): id is FardhuId => FARDHU_IDS.includes(id);
export const isSunnah = (id: string): id is SunnahId => SUNNAH_IDS.includes(id);

export function prayerLabel(id: string): string {
  return [...FARDHU, ...SUNNAH].find((p) => p.id === id)?.label ?? id;
}

// ---------- Status (fardhu) ----------

export const STATUSES = [
  { id: "masjid", label: "Jamaah di masjid", short: "Masjid", points: 10, color: "#1B7A2E", prayed: true },
  { id: "jamaah", label: "Jamaah", short: "Jamaah", points: 8, color: "#58CC02", prayed: true },
  { id: "ontime", label: "Sendiri, awal waktu", short: "Awal waktu", points: 6, color: "#1CB0F6", prayed: true },
  { id: "late", label: "Sendiri, telat", short: "Telat", points: 3, color: "#FFC800", prayed: true },
  { id: "qadha", label: "Qadha", short: "Qadha", points: 1, color: "#FF9600", prayed: true },
  { id: "missed", label: "Terlewat", short: "Terlewat", points: 0, color: "#FF4B4B", prayed: false },
  { id: "excused", label: "Berhalangan (haid/nifas)", short: "Berhalangan", points: null, color: "#CE82FF", prayed: false },
] as const;

export type StatusId = (typeof STATUSES)[number]["id"];
export const STATUS_IDS: readonly string[] = STATUSES.map((s) => s.id);
/** Status of every sunnah row. */
export const SUNNAH_STATUS = "done";
/** Default status of a quick one-tap log. */
export const QUICK_STATUS: StatusId = "jamaah";
/** Default status of a fardhu row created without one (old clients / pre-existing rows). */
export const LEGACY_STATUS: StatusId = "ontime";

export const UNFILLED = { label: "Belum diisi", color: "#E5E5E5", colorDark: "#37464F" } as const;

export const MAX_POINTS = 10;

export function statusInfo(id: string) {
  return STATUSES.find((s) => s.id === id);
}

/** A "prayed" status: masjid, jamaah, ontime, late or qadha. */
export function isPrayedStatus(status: string | null | undefined): boolean {
  return !!status && !!statusInfo(status)?.prayed;
}

export function statusColor(status: string | null | undefined): string {
  return (status && statusInfo(status)?.color) || UNFILLED.color;
}

// ---------- Rawatib ----------

export const RAWATIB: Record<FardhuId, { qobliyah: boolean; badiyah: boolean }> = {
  subuh: { qobliyah: true, badiyah: false },
  dzuhur: { qobliyah: true, badiyah: true },
  ashar: { qobliyah: false, badiyah: false },
  maghrib: { qobliyah: false, badiyah: true },
  isya: { qobliyah: false, badiyah: true },
};

/** Number of rawatib slots per day (subuh q, dzuhur q+b, maghrib b, isya b). */
export const RAWATIB_PER_DAY = 5;

// ---------- Validation (web actions + sync) ----------

export type PrayerFields = {
  date: string;
  prayer: string;
  status: string;
  qobliyah: boolean;
  badiyah: boolean;
  rakaat: number | null;
  prayedAt: Date | null;
  note: string | null;
};

export const DATE_KEY_RE = /^\d{4}-\d{2}-\d{2}$/;
export const PRAYER_NOTE_MAX = 500;

/** Real calendar date in `YYYY-MM-DD` form. */
export function isValidDateKey(v: string): boolean {
  if (!DATE_KEY_RE.test(v)) return false;
  const [y, m, d] = v.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d;
}

/** Returns an error message (Indonesian) or null when the entry is valid. */
export function prayerEntryError(e: PrayerFields): string | null {
  if (!isValidDateKey(e.date)) return "Tanggal tidak valid";
  if (!ALL_PRAYER_IDS.includes(e.prayer)) return "Shalat tidak dikenal";
  if (e.note != null && e.note.length > PRAYER_NOTE_MAX) return `Catatan maksimal ${PRAYER_NOTE_MAX} karakter`;

  if (isFardhu(e.prayer)) {
    if (!STATUS_IDS.includes(e.status)) return "Status tidak valid";
    const allowed = RAWATIB[e.prayer];
    if (e.qobliyah && !allowed.qobliyah) return `Tidak ada qobliyah untuk ${prayerLabel(e.prayer)}`;
    if (e.badiyah && !allowed.badiyah) return `Tidak ada ba'diyah untuk ${prayerLabel(e.prayer)}`;
    if ((e.qobliyah || e.badiyah) && !isPrayedStatus(e.status)) return "Rawatib hanya untuk shalat yang dikerjakan";
    if (e.rakaat != null) return "Rakaat hanya untuk shalat sunnah";
    return null;
  }

  // Daily sunnah
  if (e.status !== SUNNAH_STATUS) return "Status shalat sunnah harus \"done\"";
  if (e.qobliyah || e.badiyah) return "Rawatib hanya untuk shalat fardhu";
  if (e.rakaat != null) {
    const rule = SUNNAH.find((s) => s.id === e.prayer)!.rakaat;
    const ok =
      Number.isInteger(e.rakaat) &&
      e.rakaat >= rule.min &&
      e.rakaat <= rule.max &&
      (rule.parity === "even" ? e.rakaat % 2 === 0 : e.rakaat % 2 === 1);
    if (!ok) {
      return `Rakaat ${prayerLabel(e.prayer)} harus ${rule.parity === "even" ? "genap" : "ganjil"} ${rule.min}–${rule.max}`;
    }
  }
  return null;
}

/** Allowed rakaat choices for a sunnah prayer (for pickers). */
export function rakaatOptions(id: SunnahId): number[] {
  const rule = SUNNAH.find((s) => s.id === id)!.rakaat;
  const out: number[] = [];
  for (let n = rule.min; n <= rule.max; n += 2) out.push(n);
  return out;
}

/** Default status for a row that arrives without one. */
export function defaultStatusFor(prayer: string): string {
  return isSunnah(prayer) ? SUNNAH_STATUS : LEGACY_STATUS;
}

// ---------- Dates (local `YYYY-MM-DD` keys) ----------

export function dateKey(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export function parseDateKey(key: string): Date {
  const [y, m, d] = key.split("-").map(Number);
  return new Date(y, m - 1, d);
}

export function addDays(key: string, n: number): string {
  const d = parseDateKey(key);
  d.setDate(d.getDate() + n);
  return dateKey(d);
}

/** Inclusive list of date keys from `from` to `to` (oldest first). */
export function daysBetween(from: string, to: string): string[] {
  const out: string[] = [];
  for (let k = from; k <= to; k = addDays(k, 1)) out.push(k);
  return out;
}

// ---------- Scoring ----------

export type ScoredEntry = {
  date: string;
  prayer: string;
  status: string;
  qobliyah: boolean;
  badiyah: boolean;
};

/** date -> prayer -> entry */
export type EntryIndex = Map<string, Map<string, ScoredEntry>>;

export function indexEntries(entries: ScoredEntry[]): EntryIndex {
  const idx: EntryIndex = new Map();
  for (const e of entries) {
    let day = idx.get(e.date);
    if (!day) idx.set(e.date, (day = new Map()));
    day.set(e.prayer, e);
  }
  return idx;
}

/** Status keys counted in reports: the 7 statuses plus `unfilled` (no row on a counted slot). */
export type CountKey = StatusId | "unfilled";
export type StatusCounts = Record<CountKey, number>;

const emptyCounts = (): StatusCounts => ({
  masjid: 0, jamaah: 0, ontime: 0, late: 0, qadha: 0, missed: 0, excused: 0, unfilled: 0,
});

/**
 * Day state for streaks / complete days:
 * - `complete`: all 5 fardhu recorded with a prayed status
 * - `neutral`: ≥1 fardhu excused and every other fardhu prayed (neither breaks nor counts)
 * - `broken`: anything else
 */
export type DayState = "complete" | "neutral" | "broken";

export function dayState(day: Map<string, ScoredEntry> | undefined): DayState {
  let excused = 0;
  for (const id of FARDHU_IDS) {
    const s = day?.get(id)?.status;
    if (s === "excused") excused++;
    else if (!isPrayedStatus(s)) return "broken";
  }
  return excused > 0 ? "neutral" : "complete";
}

export type PrayerBreakdown = {
  prayer: FardhuId;
  counts: StatusCounts;
  /** Counted slots for this prayer (excused excluded). */
  counted: number;
  points: number;
  /** 0–100, null when nothing counted. */
  score: number | null;
};

export type QualityReport = {
  from: string;
  to: string;
  /** Days in range up to today. */
  daysElapsed: number;
  /** (day, fardhu) slots counted in the score — excused excluded. */
  counted: number;
  points: number;
  /** 0–100 rounded, null when nothing counted. */
  score: number | null;
  counts: StatusCounts;
  /** Percent (0–100, 1 decimal) of counted slots per count key. */
  pct: Record<CountKey | "jamaahAll", number>;
  completeDays: number;
  neutralDays: number;
  rawatib: { qobliyah: number; badiyah: number; total: number };
  sunnah: Record<SunnahId, number>;
  perPrayer: PrayerBreakdown[];
  /** Weakest fardhu (most late + missed); null when not meaningful. */
  weakest: FardhuId | null;
  /** Strongest fardhu (highest score). */
  strongest: FardhuId | null;
};

const round1 = (n: number) => Math.round(n * 10) / 10;

/**
 * Quality report for [from, to] (date keys, inclusive), evaluated on `today`.
 * Counted slots = every (day, fardhu) up to today except `excused`; unrecorded slots
 * on past days count as 0 (`unfilled`); for today only recorded slots count.
 * Days after `today` are ignored.
 */
export function computeReport(entries: ScoredEntry[], from: string, to: string, today: string): QualityReport {
  const idx = indexEntries(entries);
  const last = to < today ? to : today;
  const days = from <= last ? daysBetween(from, last) : [];

  const counts = emptyCounts();
  let counted = 0;
  let points = 0;
  let completeDays = 0;
  let neutralDays = 0;
  const rawatib = { qobliyah: 0, badiyah: 0, total: 0 };
  const sunnah = { dhuha: 0, tahajud: 0, witir: 0 } as Record<SunnahId, number>;
  const per = new Map<FardhuId, PrayerBreakdown>(
    FARDHU.map((p) => [p.id, { prayer: p.id, counts: emptyCounts(), counted: 0, points: 0, score: null }]),
  );

  for (const d of days) {
    const day = idx.get(d);
    const isToday = d === today;
    for (const p of FARDHU) {
      const e = day?.get(p.id);
      const b = per.get(p.id)!;
      if (!e) {
        if (isToday) continue;
        counts.unfilled++;
        b.counts.unfilled++;
        counted++;
        b.counted++;
        continue;
      }
      // Unknown statuses (should not happen — validated on write) count as the legacy default.
      const info = statusInfo(e.status) ?? statusInfo(LEGACY_STATUS)!;
      const key: StatusId = info.id;
      counts[key]++;
      b.counts[key]++;
      if (key === "excused") continue;
      const pts = info.points ?? 0;
      counted++;
      points += pts;
      b.counted++;
      b.points += pts;
      if (isPrayedStatus(key)) {
        if (e.qobliyah && RAWATIB[p.id].qobliyah) rawatib.qobliyah++;
        if (e.badiyah && RAWATIB[p.id].badiyah) rawatib.badiyah++;
      }
    }
    for (const s of SUNNAH) if (day?.has(s.id)) sunnah[s.id]++;
    const st = dayState(day);
    if (st === "complete") completeDays++;
    else if (st === "neutral") neutralDays++;
  }
  rawatib.total = rawatib.qobliyah + rawatib.badiyah;

  for (const b of per.values()) b.score = b.counted > 0 ? Math.round((b.points / (MAX_POINTS * b.counted)) * 100) : null;

  const pctOf = (n: number) => (counted > 0 ? round1((n / counted) * 100) : 0);
  const pct = {
    masjid: pctOf(counts.masjid),
    jamaah: pctOf(counts.jamaah),
    jamaahAll: pctOf(counts.masjid + counts.jamaah),
    ontime: pctOf(counts.ontime),
    late: pctOf(counts.late),
    qadha: pctOf(counts.qadha),
    missed: pctOf(counts.missed),
    unfilled: pctOf(counts.unfilled),
    // Excused is not part of counted slots; shown as a raw count instead.
    excused: 0,
  };

  const perPrayer = [...per.values()];
  const { weakest, strongest } = weakestStrongest(perPrayer);

  return {
    from,
    to,
    daysElapsed: days.length,
    counted,
    points,
    score: counted > 0 ? Math.round((points / (MAX_POINTS * counted)) * 100) : null,
    counts,
    pct,
    completeDays,
    neutralDays,
    rawatib,
    sunnah,
    perPrayer,
    weakest,
    strongest,
  };
}

/**
 * Weakest = most (late + missed); ties → lower score, then fardhu order.
 * Strongest = highest score; ties → fewer (late + missed), then fardhu order.
 * Only prayers with counted slots take part; both null when fewer than 2 take part
 * or all scores are equal and nobody has late/missed.
 */
export function weakestStrongest(perPrayer: PrayerBreakdown[]): { weakest: FardhuId | null; strongest: FardhuId | null } {
  const cand = perPrayer.filter((b) => b.counted > 0 && b.score != null);
  if (cand.length < 2) return { weakest: null, strongest: null };
  const bad = (b: PrayerBreakdown) => b.counts.late + b.counts.missed;
  const order = (b: PrayerBreakdown) => FARDHU_IDS.indexOf(b.prayer);

  const weak = [...cand].sort((a, b) => bad(b) - bad(a) || a.score! - b.score! || order(a) - order(b))[0];
  const strong = [...cand].sort((a, b) => b.score! - a.score! || bad(a) - bad(b) || order(a) - order(b))[0];
  const allSame = cand.every((b) => b.score === cand[0].score && bad(b) === bad(cand[0]));
  if (allSame) return { weakest: null, strongest: null };
  return { weakest: weak.prayer === strong.prayer ? null : weak.prayer, strongest: strong.prayer };
}

/**
 * Current streak of complete days ending today (today counts only once complete;
 * an incomplete today does not break it). Neutral (excused) days are skipped.
 * `maxDays` bounds the look-back.
 */
export function currentStreak(entries: ScoredEntry[], today: string, maxDays = 400): number {
  const idx = indexEntries(entries);
  let streak = 0;
  let k = today;
  if (dayState(idx.get(k)) !== "complete") k = addDays(k, -1);
  for (let i = 0; i < maxDays; i++, k = addDays(k, -1)) {
    const st = dayState(idx.get(k));
    if (st === "complete") streak++;
    else if (st === "neutral") continue;
    else break;
  }
  return streak;
}
