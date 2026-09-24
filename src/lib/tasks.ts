import { z } from "zod";
import { CATEGORY_ICONS } from "@/lib/constants";
import { isValidDateKey } from "@/lib/prayer-quality";

/**
 * Tasks (to-do) — pure, shared rules (docs/tasks.md). No DB access here: used by the
 * web server actions, the mobile sync endpoint and the web UI. The mobile app mirrors
 * these constants and algorithms exactly.
 */

// ---------- Buckets ----------

export const BUCKETS = [
  { id: "fire", label: "FIRE", emoji: "🔥", meaning: "Hari ini / besok", color: "#FF4B4B", xp: 10 },
  { id: "want", label: "WANT", emoji: "✨", meaning: "Dalam 1–2 minggu", color: "#CE82FF", xp: 8 },
  { id: "should", label: "SHOULD", emoji: "📋", meaning: "Kapan saja / rutin", color: "#1CB0F6", xp: 5 },
] as const;

export type BucketId = (typeof BUCKETS)[number]["id"];
/** Display order everywhere: fire, want, should. */
export const BUCKET_IDS = BUCKETS.map((b) => b.id) as [BucketId, ...BucketId[]];
export const DEFAULT_BUCKET: BucketId = "want";

export function bucketInfo(id: string) {
  return BUCKETS.find((b) => b.id === id) ?? BUCKETS[1];
}

/** XP for completing a task in `bucket` (gamification, mobile). */
export const bucketXp = (bucket: string): number => bucketInfo(bucket).xp;
/** Max completed tasks counted for XP per local day. */
export const TASK_XP_DAILY_CAP = 20;

export const MEPET_LABEL = "Mepet";
export const OVERDUE_LABEL = "Terlambat";
export const OVERDUE_COLOR = "#FF4B4B";

// ---------- Limits / formats ----------

export const TASK_TITLE_MAX = 200;
export const TASK_NOTE_MAX = 2000;
export const AREA_NAME_MAX = 40;
export const AREA_CODE_MAX = 8;
export const AREA_CODE_RE = /^[A-Z0-9]{1,8}$/;
export const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;
/** seriesId + "_YYYYMMDD" must still fit the 64-char sync id limit. */
export const SERIES_ID_RE = /^[A-Za-z0-9_-]{1,55}$/;
/** Reminder presets offered by the UIs (minutes before due; 0 = at due time). */
export const REMIND_BEFORE_OPTIONS = [0, 10, 30, 60] as const;
/** Largest accepted `remindBefore` (7 days). */
export const REMIND_BEFORE_MAX = 7 * 24 * 60;
/** Max local notifications the mobile app schedules (soonest first). */
export const MAX_TASK_NOTIFICATIONS = 60;
export const DEFAULT_AREA_COLOR = "#58CC02";
export const DEFAULT_AREA_ICON = "briefcase";
export const RECURRENCE_FREQS = ["daily", "weekly", "monthly"] as const;
export type RecurrenceFreq = (typeof RECURRENCE_FREQS)[number];

// ---------- Local dates (YYYY-MM-DD keys, calendar math in UTC so DST never shifts a day) ----------

function keyToUtc(key: string): Date {
  const [y, m, d] = key.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

const utcToKey = (d: Date) => d.toISOString().slice(0, 10);

export function addDaysKey(key: string, n: number): string {
  const d = keyToUtc(key);
  d.setUTCDate(d.getUTCDate() + n);
  return utcToKey(d);
}

/** ISO weekday of a date key: 1 = Monday … 7 = Sunday. */
export function isoWeekday(key: string): number {
  return keyToUtc(key).getUTCDay() || 7;
}

export function daysInMonth(year: number, month1: number): number {
  return new Date(Date.UTC(year, month1, 0)).getUTCDate();
}

/** A moment in the user's local time — what focus mode / overdue checks compare against. */
export type LocalClock = { date: string; time: string; weekday: number };

const pad = (n: number) => String(n).padStart(2, "0");

/**
 * Local clock for `d`: in `timeZone` (IANA, e.g. "Asia/Jakarta") when given, else in the
 * runtime's local zone (browser = the user's zone).
 */
export function localClock(d: Date = new Date(), timeZone?: string): LocalClock {
  let date: string;
  let time: string;
  if (timeZone) {
    const parts = Object.fromEntries(
      new Intl.DateTimeFormat("en-CA", {
        timeZone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        hourCycle: "h23",
      })
        .formatToParts(d)
        .map((p) => [p.type, p.value]),
    );
    date = `${parts.year}-${parts.month}-${parts.day}`;
    time = `${parts.hour}:${parts.minute}`;
  } else {
    date = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    time = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
  return { date, time, weekday: isoWeekday(date) };
}

// ---------- JSON shapes ----------

const uniqSorted = (xs: number[]) => [...new Set(xs)].sort((a, b) => a - b);
const weekday = z.number().int().min(1, "Weekday must be 1–7").max(7, "Weekday must be 1–7");
const hhmm = z.string().regex(TIME_RE, "Time must be HH:mm");

/** Area active schedule: ISO weekdays + local start/end (start < end, no overnight). */
export const areaScheduleSchema = z
  .object({
    days: z.array(weekday).min(1, "Pick at least one day").max(7).transform(uniqSorted),
    start: hhmm,
    end: hhmm,
  })
  .refine((s) => s.start < s.end, { message: "Schedule start must be before its end", path: ["end"] });

export type AreaSchedule = z.infer<typeof areaScheduleSchema>;

/**
 * Recurrence rule. `weekdays` only for weekly, `monthDay` only for monthly. On save the
 * defaults (due date's weekday / day of month) are materialized — see `normalizeRecurrence`.
 */
export const recurrenceSchema = z
  .object({
    freq: z.enum(RECURRENCE_FREQS),
    interval: z.number().int().min(1, "Interval must be 1–365").max(365, "Interval must be 1–365").default(1),
    weekdays: z.array(weekday).min(1).max(7).transform(uniqSorted).nullish(),
    monthDay: z.number().int().min(1, "Day of month must be 1–31").max(31, "Day of month must be 1–31").nullish(),
  })
  .superRefine((r, ctx) => {
    if (r.weekdays != null && r.freq !== "weekly")
      ctx.addIssue({ code: "custom", path: ["weekdays"], message: "weekdays is only for weekly recurrence" });
    if (r.monthDay != null && r.freq !== "monthly")
      ctx.addIssue({ code: "custom", path: ["monthDay"], message: "monthDay is only for monthly recurrence" });
  })
  .transform((r) => {
    const out: Recurrence = { freq: r.freq, interval: r.interval };
    if (r.weekdays != null) out.weekdays = r.weekdays;
    if (r.monthDay != null) out.monthDay = r.monthDay;
    return out;
  });

export type Recurrence = { freq: RecurrenceFreq; interval: number; weekdays?: number[]; monthDay?: number };

/** Fill the rule's defaults from the due date so later occurrences never drift (31 → 28 → 28…). */
export function normalizeRecurrence(rule: Recurrence, dueDate: string): Recurrence {
  const out: Recurrence = { freq: rule.freq, interval: rule.interval };
  if (rule.freq === "weekly") out.weekdays = rule.weekdays?.length ? uniqSorted(rule.weekdays) : [isoWeekday(dueDate)];
  if (rule.freq === "monthly") out.monthDay = rule.monthDay ?? Number(dueDate.slice(8, 10));
  return out;
}

/** Parse a stored JSON column leniently (bad/missing JSON → null). */
function parseJson<T>(schema: z.ZodType<T>, raw: unknown): T | null {
  if (raw == null || raw === "") return null;
  let v = raw;
  if (typeof raw === "string") {
    try {
      v = JSON.parse(raw);
    } catch {
      return null;
    }
  }
  const r = schema.safeParse(v);
  return r.success ? r.data : null;
}

export const parseSchedule = (raw: unknown): AreaSchedule | null => parseJson(areaScheduleSchema, raw);
export const parseRecurrence = (raw: unknown): Recurrence | null => parseJson(recurrenceSchema, raw);
/** DB column value for a JSON field (null stays null). */
export const toJsonColumn = (v: object | null | undefined): string | null => (v == null ? null : JSON.stringify(v));

// ---------- Area / task payloads (sync wire format; the web actions build the same shape) ----------

const hexColor = z.string().regex(/^#[0-9a-fA-F]{6}$/, "Invalid color");
const optionalId = z
  .string()
  .nullish()
  .transform((v) => (v && v.length > 0 ? v : null));
const nullableText = (max: number, label: string) =>
  z
    .string()
    .nullish()
    .transform((v) => (v && v.trim().length > 0 ? v.trim() : null))
    .refine((v) => v == null || v.length <= max, `${label} is too long (max ${max})`);

export const taskAreaSchema = z.object({
  name: z.string().trim().min(1, "Name is required").max(AREA_NAME_MAX, `Name is too long (max ${AREA_NAME_MAX})`),
  // Uppercased before checking: "kerja" is stored as "KERJA".
  code: z
    .string()
    .trim()
    .transform((v) => v.toUpperCase())
    .pipe(z.string().regex(AREA_CODE_RE, "Code must be 1–8 letters/digits (A–Z, 0–9)")),
  color: hexColor.default(DEFAULT_AREA_COLOR),
  icon: z.enum(CATEGORY_ICONS as [string, ...string[]]).default(DEFAULT_AREA_ICON),
  schedule: areaScheduleSchema.nullish().transform((v) => v ?? null),
  sortOrder: z.number().int().min(-1_000_000).max(1_000_000).default(0),
  archived: z.boolean().default(false),
});

export type TaskAreaData = z.output<typeof taskAreaSchema>;

export const taskSchema = z
  .object({
    areaId: z.string().min(1, "Area is required"),
    title: z.string().trim().min(1, "Title is required").max(TASK_TITLE_MAX, `Title is too long (max ${TASK_TITLE_MAX})`),
    note: nullableText(TASK_NOTE_MAX, "Note"),
    bucket: z.enum(BUCKET_IDS).default(DEFAULT_BUCKET),
    dueDate: z
      .string()
      .nullish()
      .transform((v) => (v ? v : null))
      .refine((v) => v == null || isValidDateKey(v), "Due date must be a real YYYY-MM-DD date"),
    dueTime: z
      .string()
      .nullish()
      .transform((v) => (v ? v : null))
      .refine((v) => v == null || TIME_RE.test(v), "Due time must be HH:mm"),
    remindBefore: z
      .number()
      .int("remindBefore must be whole minutes")
      .min(0, `remindBefore must be 0–${REMIND_BEFORE_MAX}`)
      .max(REMIND_BEFORE_MAX, `remindBefore must be 0–${REMIND_BEFORE_MAX}`)
      .nullish()
      .transform((v) => v ?? null),
    recurrence: recurrenceSchema.nullish().transform((v) => v ?? null),
    seriesId: z
      .string()
      .nullish()
      .transform((v) => (v ? v : null))
      .refine((v) => v == null || SERIES_ID_RE.test(v), "Invalid seriesId"),
    done: z.boolean().default(false),
    doneAt: z.iso
      .datetime({ offset: true, message: "doneAt must be ISO-8601 with Z/offset" })
      .transform((v) => new Date(v))
      .nullish()
      .transform((v) => v ?? null),
    sortOrder: z.number().finite().default(0),
    amount: z.number().finite().positive("Amount must be greater than 0").nullish().transform((v) => v ?? null),
    walletId: optionalId,
    categoryId: optionalId,
    transactionId: optionalId,
  })
  .superRefine((t, ctx) => {
    if (t.dueTime && !t.dueDate) ctx.addIssue({ code: "custom", path: ["dueTime"], message: "A due time needs a due date" });
    if (t.recurrence && !t.dueDate)
      ctx.addIssue({ code: "custom", path: ["recurrence"], message: "A recurring task needs a due date" });
  })
  .transform((t) => ({
    ...t,
    recurrence: t.recurrence && t.dueDate ? normalizeRecurrence(t.recurrence, t.dueDate) : null,
    // doneAt only on done tasks; a done task without one is stamped now.
    doneAt: t.done ? (t.doneAt ?? new Date()) : null,
  }));

export type TaskData = z.output<typeof taskSchema>;

// ---------- Recurrence math ----------

/**
 * Next due date after `dueDate` under `rule` (computed from the current due date, not today).
 * weekly: the next listed weekday later in the same ISO week, else the first listed weekday
 * `interval` weeks later. monthly: `monthDay` later in the same month if still ahead, else
 * `interval` months later — clamped to the month's last day (31 → 30/28/29).
 */
export function nextDueDate(rule: Recurrence, dueDate: string): string {
  const r = normalizeRecurrence(rule, dueDate);
  if (r.freq === "daily") return addDaysKey(dueDate, r.interval);

  if (r.freq === "weekly") {
    const days = r.weekdays!;
    const wd = isoWeekday(dueDate);
    const later = days.find((d) => d > wd);
    if (later !== undefined) return addDaysKey(dueDate, later - wd);
    const weekStart = addDaysKey(dueDate, -(wd - 1));
    return addDaysKey(weekStart, 7 * r.interval + (days[0] - 1));
  }

  const md = r.monthDay!;
  const [y, m, d] = dueDate.split("-").map(Number);
  const sameMonth = Math.min(md, daysInMonth(y, m));
  if (sameMonth > d) return `${y}-${pad(m)}-${pad(sameMonth)}`;
  const idx = y * 12 + (m - 1) + r.interval;
  const ny = Math.floor(idx / 12);
  const nm = (idx % 12) + 1;
  return `${ny}-${pad(nm)}-${pad(Math.min(md, daysInMonth(ny, nm)))}`;
}

/** Deterministic id of an occurrence: `<seriesId>_<YYYYMMDD>`. */
export function occurrenceId(seriesId: string, dueDate: string): string {
  return `${seriesId}_${dueDate.replaceAll("-", "")}`;
}

/** The fields copied from one occurrence to the next. */
export type OccurrenceSource = {
  id: string;
  seriesId: string | null;
  recurrence: Recurrence | string | null;
  dueDate: string | null;
  areaId: string;
  title: string;
  note: string | null;
  bucket: string;
  dueTime: string | null;
  remindBefore: number | null;
  sortOrder: number;
  amount: number | null;
  walletId: string | null;
  categoryId: string | null;
};

/**
 * The occurrence that follows `task` when it is completed, or null for a one-off task.
 * Same fields, `done=false`, new due date, `transactionId` null, deterministic id — so two
 * offline devices completing the same occurrence upsert the same row.
 */
export function nextOccurrence(task: OccurrenceSource) {
  const rule = typeof task.recurrence === "string" ? parseRecurrence(task.recurrence) : task.recurrence;
  if (!rule || !task.dueDate) return null;
  const seriesId = task.seriesId ?? task.id;
  const dueDate = nextDueDate(rule, task.dueDate);
  return {
    id: occurrenceId(seriesId, dueDate),
    data: {
      areaId: task.areaId,
      title: task.title,
      note: task.note,
      bucket: task.bucket as BucketId,
      dueDate,
      dueTime: task.dueTime,
      remindBefore: task.remindBefore,
      recurrence: normalizeRecurrence(rule, task.dueDate),
      seriesId,
      done: false,
      doneAt: null,
      sortOrder: task.sortOrder,
      amount: task.amount,
      walletId: task.walletId,
      categoryId: task.categoryId,
      transactionId: null,
    } satisfies TaskData,
  };
}

// ---------- Status helpers ----------

type StatusTask = { bucket: string; done: boolean; dueDate: string | null; dueTime?: string | null };

/** A WANT task due today or tomorrow — highlighted, never moved automatically. */
export function isMepet(task: StatusTask, today: string): boolean {
  return (
    task.bucket === "want" && !task.done && !!task.dueDate && task.dueDate >= today && task.dueDate <= addDaysKey(today, 1)
  );
}

/** Undone and past due: a date-only task after its day ends, a timed one after its time. */
export function isOverdue(task: StatusTask, now: LocalClock): boolean {
  if (task.done || !task.dueDate) return false;
  if (task.dueDate < now.date) return true;
  return task.dueDate === now.date && !!task.dueTime && task.dueTime < now.time;
}

// ---------- Focus mode ----------

type FocusArea = { archived: boolean; schedule: AreaSchedule | string | null };

export function isAreaActive(area: { schedule: AreaSchedule | string | null }, now: LocalClock): boolean {
  const s = typeof area.schedule === "string" ? parseSchedule(area.schedule) : area.schedule;
  return !!s && s.days.includes(now.weekday) && s.start <= now.time && now.time < s.end;
}

/**
 * Focus areas at `now`: non-archived areas whose schedule contains now; if none match,
 * the non-archived areas without a schedule. Keeps the input order.
 */
export function focusAreas<A extends FocusArea>(areas: A[], now: LocalClock): A[] {
  const live = areas.filter((a) => !a.archived);
  const active = live.filter((a) => isAreaActive(a, now));
  if (active.length > 0) return active;
  return live.filter((a) => (typeof a.schedule === "string" ? parseSchedule(a.schedule) : a.schedule) == null);
}

// ---------- Ordering ----------

export function compareAreas(a: { sortOrder: number; name: string }, b: { sortOrder: number; name: string }) {
  return a.sortOrder - b.sortOrder || a.name.localeCompare(b.name);
}

/** Bucket order (fire, want, should), then manual sortOrder, then oldest first. */
export function compareTasks(
  a: { bucket: string; sortOrder: number; createdAt?: Date | string },
  b: { bucket: string; sortOrder: number; createdAt?: Date | string },
) {
  const bi = (x: string) => {
    const i = BUCKET_IDS.indexOf(x as BucketId);
    return i < 0 ? BUCKET_IDS.length : i;
  };
  return (
    bi(a.bucket) - bi(b.bucket) ||
    a.sortOrder - b.sortOrder ||
    new Date(a.createdAt ?? 0).getTime() - new Date(b.createdAt ?? 0).getTime()
  );
}

/** A sortOrder between two neighbours (either may be missing) — for drag & drop inserts. */
export function sortOrderBetween(before?: number | null, after?: number | null): number {
  if (before == null && after == null) return 0;
  if (before == null) return after! - 1;
  if (after == null) return before + 1;
  return (before + after) / 2;
}

// ---------- Notifications ----------

/** `[KERJA-FIRE] Kirim revisi client A` */
export function taskNotificationTitle(areaCode: string, bucket: string, title: string): string {
  return `[${areaCode}-${bucketInfo(bucket).label}] ${title}`;
}

// ---------- Default areas ----------

/** Deterministic ids so seeding on the server and on two devices never duplicates. */
export const defaultAreaIds = (userId: string) => ({
  kerjaan: `area-kerjaan-${userId}`,
  life: `area-life-${userId}`,
});

export function defaultAreas(userId: string): (TaskAreaData & { id: string })[] {
  const ids = defaultAreaIds(userId);
  return [
    {
      id: ids.kerjaan,
      name: "Kerjaan",
      code: "KERJA",
      color: "#1CB0F6",
      icon: "briefcase",
      schedule: { days: [1, 2, 3, 4, 5], start: "09:00", end: "17:00" },
      sortOrder: 0,
      archived: false,
    },
    {
      id: ids.life,
      name: "Keseharian",
      code: "LIFE",
      color: "#58CC02",
      icon: "home",
      schedule: null,
      sortOrder: 1,
      archived: false,
    },
  ];
}
