import { z } from "zod";
import { addDaysKey, isoWeekday, TIME_RE } from "@/lib/tasks";
import { isValidDateKey } from "@/lib/prayer-quality";
import { cleanLine, cleanText, HEX_COLOR_RE } from "@/lib/notes";
import { DEFAULT_TIME_ZONE, localParts, weekStart } from "@/lib/content";

/**
 * Habits ("Teman Streak") — pure, shared rules (docs/habits.md). No DB access: used by
 * the web server actions, the mobile sync endpoint and the web UI. The mobile app
 * mirrors these constants and algorithms exactly.
 *
 * Dates are local `YYYY-MM-DD` keys; calendar math is done on keys (UTC), so DST never
 * shifts a day. Weeks are ISO weeks (Monday first).
 */

// ---------- Constants ----------

export const HABIT_KINDS = ["build", "quit"] as const;
export type HabitKind = (typeof HABIT_KINDS)[number];
export const HABIT_LOG_TYPES = ["done", "skip", "relapse", "urge"] as const;
export type HabitLogType = (typeof HABIT_LOG_TYPES)[number];
/** Log types allowed per habit kind (`done` on a quit habit = the explicit "Hari ini bersih ✅" check-in). */
export const LOG_TYPES_BY_KIND: Record<HabitKind, readonly HabitLogType[]> = {
  build: ["done", "skip"],
  quit: ["done", "relapse", "urge"],
};

export const HABIT_NAME_MAX = 60;
export const HABIT_EMOJI_MAX = 32; // UTF-16 units: ZWJ sequences / flags are long
export const HABIT_WHY_MAX = 500;
export const HABIT_NOTE_MAX = 1000;
export const HABIT_REMINDERS_MAX = 5;
export const HABIT_TRIGGERS_MAX = 10;
export const HABIT_TRIGGER_MAX = 30;
export const HABIT_UNIT_MAX = 20;
export const HABIT_COUNT_GOAL_MAX = 10_000;
export const HABIT_DURATION_GOAL_MAX = 1440;
/** Upper bound for a day's progress value (count/minutes). */
export const HABIT_VALUE_MAX = 100_000;
/** Upper bound for relapse/urge counts in one day. */
export const HABIT_EVENT_COUNT_MAX = 1000;
export const DEFAULT_HABIT_COLOR = "#58CC02";
export const DEFAULT_COUNT_UNIT = "kali";
/** Intentional rest days allowed per rolling 7 days (UI enforces; the server just stores). */
export const MAX_SKIPS_PER_7_DAYS = 2;
/** Preset trigger tags (relapse/urge). Custom tags are allowed too. */
export const TRIGGER_PRESETS = ["bosan", "stres", "sendirian", "malam", "medsos", "capek"] as const;
/** Quick actions shown on the emergency screen (text only). */
export const URGE_QUICK_ACTIONS = ["Jalan sebentar", "Minum air", "Telpon teman", "Tarik napas dalam"] as const;
/** Duration of the emergency breathing screen, seconds. */
export const URGE_BREATHING_SECONDS = 60;
/** Notification text for private habits (the name is never shown). */
export const PRIVATE_HABIT_REMINDER = "Waktunya cek kebiasaanmu ✨";
export const PRIVATE_HABIT_MASK = "Kebiasaan pribadi";

/** Clean-day milestones for quit habits; after 365: every 100 days (400, 500, …). */
export const QUIT_MILESTONES = [1, 3, 7, 14, 21, 30, 40, 60, 90, 120, 180, 270, 365] as const;

/** Gamification (mobile). XP never decreases on relapse — rules just stop adding. */
export const HABIT_XP = {
  buildMet: 5,
  /** Max build habits per day that earn `buildMet`. */
  buildMetDailyCap: 10,
  quitCleanCheckIn: 3,
  urgeResisted: 5,
  urgeResistedDailyCap: 5,
  /** Quit: clean-day streak → bonus. */
  quitMilestoneBonus: { 7: 20, 30: 50, 90: 100, 365: 365 } as Record<number, number>,
  /** Build: streak length (in the streak's unit: days, or weeks for perWeek) → bonus. */
  buildStreakBonus: { 7: 20, 30: 50, 100: 100 } as Record<number, number>,
} as const;

/** Gentle lines for the emergency screen (non-judgmental, Indonesian). */
export const ENCOURAGEMENTS = [
  "Rasa pengen ini akan lewat. Kamu lebih kuat dari 60 detik ini.",
  "Tarik napas pelan-pelan. Kamu nggak harus menang selamanya, cukup sekarang.",
  "Setiap kali kamu tahan, otakmu belajar jalan baru.",
  "Kamu sudah sejauh ini — itu nyata, dan itu milikmu.",
  "Nggak apa-apa merasa pengen. Yang penting kamu memilih.",
] as const;

// ---------- Date helpers ----------

function keyToUtcMs(key: string): number {
  const [y, m, d] = key.split("-").map(Number);
  return Date.UTC(y, m - 1, d);
}

/** Whole days from `a` to `b` (b − a). */
export function daysBetween(a: string, b: string): number {
  return Math.round((keyToUtcMs(b) - keyToUtcMs(a)) / 86_400_000);
}

const maxKey = (a: string, b: string) => (a > b ? a : b);
const minKey = (a: string, b: string) => (a < b ? a : b);

/** Today's local date key in `timeZone` (default Asia/Jakarta). */
export const todayKey = (now: Date = new Date(), timeZone: string = DEFAULT_TIME_ZONE) => localParts(now, timeZone).date;

// ---------- JSON shapes ----------

const uniqSorted = (xs: number[]) => [...new Set(xs)].sort((a, b) => a - b);
const weekday = z.number().int().min(1, "Hari harus 1–7").max(7, "Hari harus 1–7");

export const habitScheduleSchema = z.discriminatedUnion(
  "type",
  [
    z.object({ type: z.literal("daily") }),
    z.object({
      type: z.literal("weekdays"),
      days: z.array(weekday).min(1, "Pilih minimal satu hari").max(7).transform(uniqSorted),
    }),
    z.object({
      type: z.literal("perWeek"),
      times: z.number().int("Target per minggu harus bilangan bulat").min(1, "Target per minggu 1–7").max(7, "Target per minggu 1–7"),
    }),
  ],
  { error: "Jadwal tidak valid" },
);
export type HabitSchedule = z.output<typeof habitScheduleSchema>;

export const habitTargetSchema = z.discriminatedUnion(
  "type",
  [
    z.object({ type: z.literal("check") }),
    z.object({
      type: z.literal("count"),
      goal: z
        .number()
        .finite()
        .positive("Target harus lebih dari 0")
        .max(HABIT_COUNT_GOAL_MAX, `Target maksimal ${HABIT_COUNT_GOAL_MAX}`),
      unit: z
        .string()
        .nullish()
        .transform((v) => (v == null ? "" : cleanLine(v)))
        .transform((v) => v || DEFAULT_COUNT_UNIT)
        .refine((v) => v.length <= HABIT_UNIT_MAX, `Satuan maksimal ${HABIT_UNIT_MAX} karakter`),
    }),
    z.object({
      type: z.literal("duration"),
      goal: z
        .number()
        .int("Durasi dalam menit (bilangan bulat)")
        .min(1, `Durasi 1–${HABIT_DURATION_GOAL_MAX} menit`)
        .max(HABIT_DURATION_GOAL_MAX, `Durasi 1–${HABIT_DURATION_GOAL_MAX} menit`),
    }),
  ],
  { error: "Target tidak valid" },
);
export type HabitTarget = z.output<typeof habitTargetSchema>;

export const remindersSchema = z
  .array(z.string().regex(TIME_RE, "Jam pengingat harus HH:mm"))
  .max(HABIT_REMINDERS_MAX, `Maksimal ${HABIT_REMINDERS_MAX} pengingat`)
  .transform((xs) => [...new Set(xs)].sort());

/** Trigger tags: one line 1–30, deduplicated case-insensitively (first spelling kept), ≤ 10. */
export const triggersSchema = z
  .array(z.string())
  .transform((xs) => {
    const seen = new Set<string>();
    const out: string[] = [];
    for (const x of xs) {
      const t = cleanLine(x);
      const k = t.toLocaleLowerCase("id-ID");
      if (!t || seen.has(k)) continue;
      seen.add(k);
      out.push(t);
    }
    return out;
  })
  .refine((xs) => xs.every((x) => x.length <= HABIT_TRIGGER_MAX), `Pemicu maksimal ${HABIT_TRIGGER_MAX} karakter`)
  .refine((xs) => xs.length <= HABIT_TRIGGERS_MAX, `Maksimal ${HABIT_TRIGGERS_MAX} pemicu`);

// ---------- Habit / log payloads (sync wire format; the web actions build the same shape) ----------

/**
 * A habit row (full row: a missing optional field gets its default). Quit habits are
 * always daily with a `check` target (normalized, not rejected).
 */
export const habitSchema = z
  .object({
    name: z
      .string()
      .transform(cleanLine)
      .pipe(z.string().min(1, "Nama wajib diisi").max(HABIT_NAME_MAX, `Nama maksimal ${HABIT_NAME_MAX} karakter`)),
    emoji: z
      .string()
      .nullish()
      .transform((v) => (v == null ? null : cleanLine(v) || null))
      .refine((v) => v == null || v.length <= HABIT_EMOJI_MAX, "Emoji tidak valid"),
    color: z.string().regex(HEX_COLOR_RE, "Warna tidak valid").nullish().transform((v) => v ?? DEFAULT_HABIT_COLOR),
    kind: z.enum(HABIT_KINDS, { error: "Jenis kebiasaan tidak valid" }).default("build"),
    // A JSON *string* is rejected like any other non-object.
    schedule: habitScheduleSchema.nullish().transform((v): HabitSchedule => v ?? { type: "daily" }),
    target: habitTargetSchema.nullish().transform((v): HabitTarget => v ?? { type: "check" }),
    reminders: remindersSchema.nullish().transform((v) => v ?? []),
    private: z.boolean().nullish().transform((v) => v ?? false),
    why: z
      .string()
      .nullish()
      .transform((v) => (v == null ? null : cleanText(v).trim() || null))
      .refine((v) => v == null || v.length <= HABIT_WHY_MAX, `Alasan maksimal ${HABIT_WHY_MAX} karakter`),
    startDate: z.string({ error: "Tanggal mulai wajib diisi" }).refine(isValidDateKey, "Tanggal mulai tidak valid"),
    archived: z.boolean().nullish().transform((v) => v ?? false),
    sortOrder: z.number().int().min(-1_000_000).max(1_000_000).nullish().transform((v) => v ?? 0),
  })
  .transform((h) =>
    h.kind === "quit" ? { ...h, schedule: { type: "daily" } as HabitSchedule, target: { type: "check" } as HabitTarget } : h,
  );
export type HabitData = z.output<typeof habitSchema>;

/** A log row as sent (context-free checks). Kind-dependent rules: `normalizeHabitLog`. */
export const habitLogSchema = z.object({
  habitId: z.string({ error: "Kebiasaan wajib diisi" }).min(1, "Kebiasaan wajib diisi").max(128),
  date: z.string({ error: "Tanggal wajib diisi" }).refine(isValidDateKey, "Tanggal tidak valid"),
  type: z.enum(HABIT_LOG_TYPES, { error: "Jenis catatan tidak valid" }),
  value: z.number().finite("Nilai tidak valid").nullish().transform((v) => v ?? null),
  note: z
    .string()
    .nullish()
    .transform((v) => (v == null ? null : cleanText(v).trim() || null))
    .refine((v) => v == null || v.length <= HABIT_NOTE_MAX, `Catatan maksimal ${HABIT_NOTE_MAX} karakter`),
  triggers: triggersSchema.nullish().transform((v) => v ?? []),
  at: z.iso
    .datetime({ offset: true, message: "Waktu harus ISO-8601 dengan Z/offset" })
    .transform((v) => new Date(v))
    .nullish()
    .transform((v) => v ?? null),
});
export type HabitLogInput = z.output<typeof habitLogSchema>;

export type HabitLike = { kind: string; schedule: HabitSchedule; target: HabitTarget; startDate: string };

/**
 * Kind/target-dependent rules for a log (docs/habits.md). Returns the normalized log or
 * an Indonesian error message:
 * - build: `done` (value = progress; check → 1; count/duration need a value 0–100000) | `skip` (value null)
 * - quit: `done` (clean check-in, value 1) | `relapse` / `urge` (value = count, integer ≥ 1, default 1)
 * - `triggers` only on relapse/urge (else []).
 */
export function normalizeHabitLog(
  habit: { kind: string; target: HabitTarget },
  log: HabitLogInput,
): { ok: true; log: HabitLogInput } | { ok: false; error: string } {
  const kind = habit.kind === "quit" ? "quit" : "build";
  if (!LOG_TYPES_BY_KIND[kind].includes(log.type)) {
    return {
      ok: false,
      error: kind === "build" ? "Kebiasaan membangun hanya bisa dicatat selesai atau libur" : "Kebiasaan berhenti tidak bisa diberi hari libur",
    };
  }
  const out = { ...log };
  if (log.type !== "relapse" && log.type !== "urge") out.triggers = [];
  if (log.type === "skip") out.value = null;
  else if (log.type === "done") {
    if (kind === "quit" || habit.target.type === "check") out.value = 1;
    else {
      if (log.value == null) return { ok: false, error: "Progres wajib diisi" };
      if (log.value < 0 || log.value > HABIT_VALUE_MAX) return { ok: false, error: `Progres harus 0–${HABIT_VALUE_MAX}` };
      if (habit.target.type === "duration" && !Number.isInteger(log.value))
        return { ok: false, error: "Durasi dalam menit (bilangan bulat)" };
    }
  } else {
    const v = log.value ?? 1;
    if (!Number.isInteger(v) || v < 1 || v > HABIT_EVENT_COUNT_MAX)
      return { ok: false, error: `Jumlah harus bilangan bulat 1–${HABIT_EVENT_COUNT_MAX}` };
    out.value = v;
  }
  return { ok: true, log: out };
}

// ---------- Lenient parsing of stored JSON columns ----------

function parseJsonValue(raw: unknown): unknown {
  if (typeof raw !== "string") return raw;
  try {
    return JSON.parse(raw);
  } catch {
    return undefined;
  }
}

export function parseHabitSchedule(raw: unknown): HabitSchedule {
  const r = habitScheduleSchema.safeParse(parseJsonValue(raw));
  return r.success ? r.data : { type: "daily" };
}

export function parseHabitTarget(raw: unknown): HabitTarget {
  const r = habitTargetSchema.safeParse(parseJsonValue(raw));
  return r.success ? r.data : { type: "check" };
}

export function parseReminders(raw: unknown): string[] {
  const v = parseJsonValue(raw);
  if (!Array.isArray(v)) return [];
  return [...new Set(v.filter((x): x is string => typeof x === "string" && TIME_RE.test(x)))].sort().slice(0, HABIT_REMINDERS_MAX);
}

export function parseTriggers(raw: unknown): string[] {
  const v = parseJsonValue(raw);
  if (!Array.isArray(v)) return [];
  const r = triggersSchema.safeParse(v.filter((x) => typeof x === "string"));
  return r.success ? r.data : [];
}

// ---------- Day status ----------

export type LogLite = { date: string; type: string; value: number | null; at?: Date | string | null; note?: string | null; triggers?: string[] };

/** Per date: the progress of the `done` row, skip, relapse/urge counts. */
export type DayLogs = { done: number | null; skip: boolean; relapse: number; urge: number };

export function indexLogs(logs: readonly LogLite[]): Map<string, DayLogs> {
  const m = new Map<string, DayLogs>();
  for (const l of logs) {
    let d = m.get(l.date);
    if (!d) m.set(l.date, (d = { done: null, skip: false, relapse: 0, urge: 0 }));
    if (l.type === "done") d.done = l.value ?? 1;
    else if (l.type === "skip") d.skip = true;
    else if (l.type === "relapse") d.relapse += Math.max(0, l.value ?? 1);
    else if (l.type === "urge") d.urge += Math.max(0, l.value ?? 1);
  }
  return m;
}

/** Whether a build day is met: check → a `done` row exists; count/duration → value ≥ goal. */
export function isMet(target: HabitTarget, day: DayLogs | undefined): boolean {
  if (!day || day.done == null) return false;
  if (target.type === "check") return true;
  return day.done >= target.goal;
}

/** Whether `date` is a scheduled day of a daily/weekdays habit (perWeek: every day may count). */
export function isScheduledDay(schedule: HabitSchedule, date: string): boolean {
  if (schedule.type === "weekdays") return schedule.days.includes(isoWeekday(date));
  return true;
}

export type BuildDayStatus = "met" | "partial" | "skip" | "missed" | "pending" | "off" | "before" | "future";

/**
 * Status of one day of a build habit. `pending` = today, not met yet (doesn't break
 * anything until the day ends; the heatmap shows its `value`); `off` = not a scheduled
 * weekday (even if done — only scheduled days count); `partial` = a past day with some progress below the goal (a miss for
 * daily/weekdays). perWeek habits never get `missed` (weeks are judged as a whole — see
 * `weekStatus`); their unmet past days are `off` or `partial`.
 */
export function buildDayStatus(habit: HabitLike, idx: Map<string, DayLogs>, date: string, today: string): BuildDayStatus {
  if (date < habit.startDate) return "before";
  if (date > today) return "future";
  if (!isScheduledDay(habit.schedule, date)) return "off";
  const day = idx.get(date);
  if (isMet(habit.target, day)) return "met";
  if (day?.skip) return "skip";
  if (date === today) return "pending";
  const some = day?.done != null && day.done > 0;
  if (habit.schedule.type === "perWeek") return some ? "partial" : "off";
  return some ? "partial" : "missed";
}

/** A past scheduled day of a daily/weekdays habit that wasn't met (partial progress is still a miss). */
const isMiss = (s: BuildDayStatus) => s === "missed" || s === "partial";

export type WeekStatus = { week: string; met: number; need: number; status: "met" | "missed" | "pending" | "neutral" };

/**
 * perWeek(n) — ISO week starting `week`: need = min(n, available days), where available
 * = days of the week on/after `startDate` minus skip days (future days of the current week
 * count as available). need 0 → neutral. The current week is `pending` until met.
 */
export function weekStatus(habit: HabitLike, idx: Map<string, DayLogs>, week: string, today: string): WeekStatus {
  const times = habit.schedule.type === "perWeek" ? habit.schedule.times : 7;
  let met = 0;
  let available = 0;
  for (let i = 0; i < 7; i++) {
    const d = addDaysKey(week, i);
    if (d < habit.startDate) continue;
    const day = idx.get(d);
    if (isMet(habit.target, day)) {
      met++;
      available++;
    } else if (!day?.skip) available++;
  }
  const need = Math.min(times, available);
  if (need <= 0 || week > today) return { week, met, need, status: "neutral" };
  if (met >= need) return { week, met, need, status: "met" };
  return { week, met, need, status: weekStart(today) === week ? "pending" : "missed" };
}

// ---------- Streaks ----------

export type BuildStreak = {
  kind: "build";
  /** "day" for daily/weekdays, "week" for perWeek. */
  unit: "day" | "week";
  current: number;
  longest: number;
  /** Today (or this week, for perWeek) is already met. */
  periodMet: boolean;
};

export type CleanSegment = { start: string; end: string; days: number; ongoing: boolean };

export type QuitStreak = {
  kind: "quit";
  unit: "day";
  /** Clean days including today ("hari ini masih berjalan"); 0 if the relapse is today. */
  current: number;
  longest: number;
  lastRelapse: string | null;
  relapsedToday: boolean;
  /** Clean runs, oldest first; the last one is ongoing unless the relapse is today. */
  segments: CleanSegment[];
};

export type HabitStreak = BuildStreak | QuitStreak;

/** Earliest date that can matter for a build streak (days before the first log are all misses). */
function buildScanStart(habit: HabitLike, logs: readonly LogLite[]): string {
  let first: string | null = null;
  for (const l of logs) if ((l.type === "done" || l.type === "skip") && (first == null || l.date < first)) first = l.date;
  return first ? maxKey(habit.startDate, first) : habit.startDate;
}

export function buildStreak(habit: HabitLike, logs: readonly LogLite[], today: string): BuildStreak {
  const idx = indexLogs(logs);
  if (habit.schedule.type === "perWeek") {
    const cur = weekStart(today);
    const startWeek = weekStart(buildScanStart(habit, logs));
    let current = 0;
    if (habit.startDate <= today) {
      for (let w = cur; w >= startWeek; w = addDaysKey(w, -7)) {
        const s = weekStatus(habit, idx, w, today).status;
        if (s === "met") current++;
        else if (s === "missed") break;
      }
    }
    let longest = 0;
    let run = 0;
    for (let w = startWeek; w <= cur && habit.startDate <= today; w = addDaysKey(w, 7)) {
      const s = weekStatus(habit, idx, w, today).status;
      if (s === "met") longest = Math.max(longest, ++run);
      else if (s === "missed") run = 0;
    }
    return { kind: "build", unit: "week", current, longest, periodMet: weekStatus(habit, idx, cur, today).status === "met" };
  }

  const start = buildScanStart(habit, logs);
  let current = 0;
  for (let d = today; d >= start; d = addDaysKey(d, -1)) {
    const s = buildDayStatus(habit, idx, d, today);
    if (s === "met") current++;
    else if (isMiss(s)) break;
    // skip / off / pending (today) are neutral
  }
  let longest = 0;
  let run = 0;
  for (let d = start; d <= today; d = addDaysKey(d, 1)) {
    const s = buildDayStatus(habit, idx, d, today);
    if (s === "met") longest = Math.max(longest, ++run);
    else if (isMiss(s)) run = 0;
  }
  return { kind: "build", unit: "day", current, longest, periodMet: isMet(habit.target, idx.get(today)) };
}

/** Sorted distinct relapse dates within [startDate, today]. */
export function relapseDates(habit: { startDate: string }, logs: readonly LogLite[], today: string): string[] {
  const set = new Set<string>();
  for (const l of logs)
    if (l.type === "relapse" && (l.value ?? 1) > 0 && l.date >= habit.startDate && l.date <= today) set.add(l.date);
  return [...set].sort();
}

/**
 * Quit habit "hari bersih": current = daysBetween(max(startDate, lastRelapse + 1), today) + 1
 * (0 if the relapse is today; 0 before startDate). Longest = longest clean run between
 * start, relapses and today.
 */
export function quitStreak(habit: { startDate: string }, logs: readonly LogLite[], today: string): QuitStreak {
  if (habit.startDate > today)
    return { kind: "quit", unit: "day", current: 0, longest: 0, lastRelapse: null, relapsedToday: false, segments: [] };
  const rel = relapseDates(habit, logs, today);
  const segments: CleanSegment[] = [];
  let start = habit.startDate;
  for (const r of rel) {
    if (r > start) segments.push({ start, end: addDaysKey(r, -1), days: daysBetween(start, r), ongoing: false });
    start = addDaysKey(r, 1);
  }
  if (start <= today) segments.push({ start, end: today, days: daysBetween(start, today) + 1, ongoing: true });
  const lastRelapse = rel.length ? rel[rel.length - 1] : null;
  const relapsedToday = lastRelapse === today;
  const current = relapsedToday ? 0 : daysBetween(lastRelapse ? addDaysKey(lastRelapse, 1) : habit.startDate, today) + 1;
  const longest = segments.reduce((m, s) => Math.max(m, s.days), 0);
  return { kind: "quit", unit: "day", current, longest, lastRelapse, relapsedToday, segments };
}

export function habitStreak(habit: HabitLike, logs: readonly LogLite[], today: string): HabitStreak {
  return habit.kind === "quit" ? quitStreak(habit, logs, today) : buildStreak(habit, logs, today);
}

/**
 * The clean streak a relapse on `date` ends ("Kamu sempat bersih 12 hari — itu nyata"):
 * clean days up to the day before `date`, ignoring relapses on/after `date`.
 */
export function cleanStreakBefore(habit: { startDate: string }, logs: readonly LogLite[], date: string): number {
  const prev = addDaysKey(date, -1);
  return quitStreak(habit, logs.filter((l) => l.date < date), prev).current;
}

// ---------- Milestones ----------

export function isQuitMilestone(days: number): boolean {
  if ((QUIT_MILESTONES as readonly number[]).includes(days)) return true;
  return days > 365 && days % 100 === 0;
}

/** Smallest milestone strictly greater than `days`. */
export function nextQuitMilestone(days: number): number {
  for (const m of QUIT_MILESTONES) if (m > days) return m;
  return (Math.floor(days / 100) + 1) * 100;
}

/** Milestones reached with a streak of `days` (ascending). */
export function quitMilestonesReached(days: number): number[] {
  const out = QUIT_MILESTONES.filter((m) => m <= days) as number[];
  for (let m = 400; m <= days; m += 100) out.push(m);
  return out;
}

// ---------- Rates / today ----------

export type CompletionRate = { met: number; total: number; rate: number | null };

/**
 * Build: met scheduled periods ÷ scheduled periods in [from, to] (clamped to
 * [startDate, today]); skip days / neutral weeks are excluded, and today / the current
 * week only counts once met. Quit: clean days ÷ days.
 */
export function completionRate(habit: HabitLike, logs: readonly LogLite[], from: string, to: string, today: string): CompletionRate {
  const a = maxKey(from, habit.startDate);
  const b = minKey(to, today);
  if (a > b) return { met: 0, total: 0, rate: null };
  const idx = indexLogs(logs);
  let met = 0;
  let total = 0;
  if (habit.kind === "quit") {
    const rel = new Set(relapseDates(habit, logs, today));
    for (let d = a; d <= b; d = addDaysKey(d, 1)) {
      total++;
      if (!rel.has(d)) met++;
    }
  } else if (habit.schedule.type === "perWeek") {
    for (let w = weekStart(a); w <= b; w = addDaysKey(w, 7)) {
      const s = weekStatus(habit, idx, w, today).status;
      if (s === "met") {
        met++;
        total++;
      } else if (s === "missed") total++;
    }
  } else {
    for (let d = a; d <= b; d = addDaysKey(d, 1)) {
      const s = buildDayStatus(habit, idx, d, today);
      if (s === "met") {
        met++;
        total++;
      } else if (isMiss(s)) total++;
    }
  }
  return { met, total, rate: total ? met / total : null };
}

/** Skips in the rolling 7 days ending `date` (inclusive), excluding `date` itself if asked. */
export function skipsInLast7Days(logs: readonly LogLite[], date: string, excludeDate = false): number {
  const from = addDaysKey(date, -6);
  return logs.filter((l) => l.type === "skip" && l.date >= from && l.date <= date && !(excludeDate && l.date === date)).length;
}

/**
 * Whether another rest day on `date` keeps every 7-day window containing it at
 * ≤ MAX_SKIPS_PER_7_DAYS skips (an existing skip on `date` itself is not counted twice).
 */
export function canSkip(logs: readonly LogLite[], date: string): boolean {
  const skips = logs.filter((l) => l.type === "skip" && l.date !== date).map((l) => l.date);
  for (let k = 0; k < 7; k++) {
    const from = addDaysKey(date, -k);
    const to = addDaysKey(from, 6);
    if (skips.filter((d) => d >= from && d <= to).length + 1 > MAX_SKIPS_PER_7_DAYS) return false;
  }
  return true;
}

export type HabitToday = {
  date: string;
  /** build: scheduled today (perWeek: always true while the week is not met). */
  scheduled: boolean;
  progress: number | null;
  goal: number | null;
  met: boolean;
  skipped: boolean;
  relapses: number;
  urges: number;
  /** quit: explicit "Hari ini bersih ✅" check-in. */
  cleanCheckIn: boolean;
  streak: HabitStreak;
};

export function habitToday(habit: HabitLike, logs: readonly LogLite[], today: string): HabitToday {
  const idx = indexLogs(logs);
  const day = idx.get(today);
  const streak = habitStreak(habit, logs, today);
  const scheduled =
    habit.kind === "quit"
      ? true
      : habit.schedule.type === "perWeek"
        ? weekStatus(habit, idx, weekStart(today), today).status !== "met" || isMet(habit.target, day)
        : isScheduledDay(habit.schedule, today);
  return {
    date: today,
    scheduled: scheduled && habit.startDate <= today,
    progress: day?.done ?? null,
    goal: habit.target.type === "check" ? null : habit.target.goal,
    met: habit.kind === "build" && isMet(habit.target, day),
    skipped: !!day?.skip,
    relapses: day?.relapse ?? 0,
    urges: day?.urge ?? 0,
    cleanCheckIn: habit.kind === "quit" && day?.done != null,
    streak,
  };
}

// ---------- Insights ----------

export type HeatmapDay = {
  date: string;
  /** build: BuildDayStatus; quit: clean | relapse | before | future. */
  status: BuildDayStatus | "clean" | "relapse";
  value: number | null;
  relapses: number;
  urges: number;
};

export type HabitInsights = {
  from: string;
  to: string;
  streak: HabitStreak;
  completion: CompletionRate;
  heatmap: HeatmapDay[];
  /** perWeek habits: status per ISO week overlapping the range. */
  weeks: WeekStatus[];
  relapses: { total: number; days: number; byWeekday: number[]; byHour: number[]; unknownHour: number };
  urges: { total: number; byWeekday: number[]; byHour: number[]; unknownHour: number };
  /** Relapse + urge trigger tags, most frequent first (case-insensitive merge). */
  topTriggers: { tag: string; count: number }[];
  /** Notes written in the range, newest first. */
  journal: { date: string; type: string; note: string }[];
  /** Quit: clean runs overlapping the range (streak history chart). */
  segments: CleanSegment[];
};

/**
 * Aggregations for the insights screen over [from, to] (inclusive). byWeekday index 0 =
 * Monday … 6 = Sunday (from the log's `date`); byHour 0–23 from `at` in `timeZone`
 * (rows without `at` count in `unknownHour`). Counts are weighted by `value`.
 */
export function habitInsights(
  habit: HabitLike,
  logs: readonly LogLite[],
  opts: { from: string; to: string; today: string; timeZone?: string },
): HabitInsights {
  const { from, to, today } = opts;
  const tz = opts.timeZone ?? DEFAULT_TIME_ZONE;
  const idx = indexLogs(logs);
  const heatmap: HeatmapDay[] = [];
  const rel = habit.kind === "quit" ? new Set(relapseDates(habit, logs, today)) : null;
  for (let d = from; d <= to; d = addDaysKey(d, 1)) {
    const day = idx.get(d);
    let status: HeatmapDay["status"];
    if (rel) status = d < habit.startDate ? "before" : d > today ? "future" : rel.has(d) ? "relapse" : "clean";
    else status = buildDayStatus(habit, idx, d, today);
    heatmap.push({ date: d, status, value: day?.done ?? null, relapses: day?.relapse ?? 0, urges: day?.urge ?? 0 });
  }
  const weeks: WeekStatus[] = [];
  if (habit.kind === "build" && habit.schedule.type === "perWeek")
    for (let w = weekStart(from); w <= to; w = addDaysKey(w, 7)) weeks.push(weekStatus(habit, idx, w, today));

  const bucket = () => ({ total: 0, byWeekday: Array(7).fill(0) as number[], byHour: Array(24).fill(0) as number[], unknownHour: 0 });
  const relapses = { ...bucket(), days: 0 };
  const urges = bucket();
  const trig = new Map<string, { tag: string; count: number }>();
  const journal: HabitInsights["journal"] = [];
  const relDays = new Set<string>();
  for (const l of logs) {
    if (l.date < from || l.date > to) continue;
    if (l.note) journal.push({ date: l.date, type: l.type, note: l.note });
    if (l.type !== "relapse" && l.type !== "urge") continue;
    const n = Math.max(0, l.value ?? 1);
    const b = l.type === "relapse" ? relapses : urges;
    b.total += n;
    b.byWeekday[isoWeekday(l.date) - 1] += n;
    if (l.at) b.byHour[localParts(l.at, tz).hour] += n;
    else b.unknownHour += n;
    if (l.type === "relapse") relDays.add(l.date);
    for (const t of l.triggers ?? []) {
      const k = t.toLocaleLowerCase("id-ID");
      const e = trig.get(k) ?? { tag: t, count: 0 };
      e.count += n;
      trig.set(k, e);
    }
  }
  relapses.days = relDays.size;
  journal.sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0));
  const streak = habitStreak(habit, logs, today);
  return {
    from,
    to,
    streak,
    completion: completionRate(habit, logs, from, to, today),
    heatmap,
    weeks,
    relapses,
    urges,
    topTriggers: [...trig.values()].sort((a, b) => b.count - a.count || a.tag.localeCompare(b.tag)),
    journal,
    segments: streak.kind === "quit" ? streak.segments.filter((s) => s.end >= from && s.start <= to) : [],
  };
}

/** Display name outside the Habits screen: private habits are masked. */
export const maskedHabitName = (h: { name: string; private: boolean }) => (h.private ? PRIVATE_HABIT_MASK : h.name);

/** Order habits: unarchived first, then sortOrder, then creation. */
export function compareHabits(
  a: { archived: boolean; sortOrder: number; createdAt: Date | string },
  b: { archived: boolean; sortOrder: number; createdAt: Date | string },
): number {
  if (a.archived !== b.archived) return a.archived ? 1 : -1;
  if (a.sortOrder !== b.sortOrder) return a.sortOrder - b.sortOrder;
  return new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime();
}
