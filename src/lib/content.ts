import { z } from "zod";
import {
  checklistSchema,
  cleanLine,
  cleanText,
  HEX_COLOR_RE,
  httpUrlSchema,
  imageListSchema,
  nameKey,
  NOTE_BODY_MAX,
} from "@/lib/notes";
import { isValidDateKey } from "@/lib/prayer-quality";
import { addDaysKey, isoWeekday, REMIND_BEFORE_MAX } from "@/lib/tasks";

/**
 * Content planner — pure, shared rules (docs/content.md). No DB access: used by the web
 * server actions, the mobile sync endpoint and the web UI. The mobile app mirrors these
 * constants and algorithms exactly. Error messages are Indonesian.
 */

// ---------- Platforms ----------

export type PlatformId = "instagram" | "tiktok" | "youtube" | "x" | "threads" | "linkedin" | "facebook" | "other";

export type PlatformInfo = {
  id: PlatformId;
  label: string;
  /** Notification / badge code, e.g. `[IG-TAYANG] …`. */
  short: string;
  /** Default account color. */
  color: string;
  /** lucide icon name (kebab-case; lucide has no brand logos) — pair it with `short`/color. */
  icon: string;
  /** Profile page; `{handle}` = handle without a leading "@", URL-encoded. null for `other`. */
  profileUrl: string | null;
  /** Where to go to publish (web). */
  createUrl: string | null;
  /** App deep link to open the app (mobile); may fail if the app is missing → use profileUrl. */
  appUrl: string | null;
};

export const PLATFORMS: readonly PlatformInfo[] = [
  { id: "instagram", label: "Instagram", short: "IG", color: "#E1306C", icon: "camera", profileUrl: "https://www.instagram.com/{handle}/", createUrl: "https://www.instagram.com/", appUrl: "instagram://user?username={handle}" },
  { id: "tiktok", label: "TikTok", short: "TT", color: "#FE2C55", icon: "music-2", profileUrl: "https://www.tiktok.com/@{handle}", createUrl: "https://www.tiktok.com/upload", appUrl: "snssdk1233://user/profile/{handle}" },
  { id: "youtube", label: "YouTube", short: "YT", color: "#FF0000", icon: "play", profileUrl: "https://www.youtube.com/@{handle}", createUrl: "https://studio.youtube.com/", appUrl: "vnd.youtube://www.youtube.com/@{handle}" },
  { id: "x", label: "X", short: "X", color: "#0F1419", icon: "at-sign", profileUrl: "https://x.com/{handle}", createUrl: "https://x.com/compose/post", appUrl: "twitter://user?screen_name={handle}" },
  { id: "threads", label: "Threads", short: "TH", color: "#101010", icon: "at-sign", profileUrl: "https://www.threads.net/@{handle}", createUrl: "https://www.threads.net/", appUrl: "barcelona://user?username={handle}" },
  { id: "linkedin", label: "LinkedIn", short: "IN", color: "#0A66C2", icon: "briefcase", profileUrl: "https://www.linkedin.com/in/{handle}/", createUrl: "https://www.linkedin.com/feed/?shareActive=true", appUrl: "linkedin://in/{handle}" },
  { id: "facebook", label: "Facebook", short: "FB", color: "#1877F2", icon: "users", profileUrl: "https://www.facebook.com/{handle}", createUrl: "https://www.facebook.com/", appUrl: "fb://facewebmodal/f?href=https://www.facebook.com/{handle}" },
  { id: "other", label: "Lainnya", short: "LAIN", color: "#8E8E93", icon: "globe", profileUrl: null, createUrl: null, appUrl: null },
];

export const PLATFORM_IDS = PLATFORMS.map((p) => p.id) as [PlatformId, ...PlatformId[]];

export function platformInfo(id: string): PlatformInfo {
  return PLATFORMS.find((p) => p.id === id) ?? PLATFORMS[PLATFORMS.length - 1];
}

/** Display name of an account's platform (the custom name for `other`). */
export function platformLabel(a: { platform: string; platformName?: string | null }): string {
  return a.platform === "other" ? a.platformName || "Lainnya" : platformInfo(a.platform).label;
}

/** Short code for notifications: IG/TT/…; `other` → first letters of its name (≤ 4, A–Z0–9) or LAIN. */
export function platformShort(a: { platform: string; platformName?: string | null }): string {
  if (a.platform !== "other") return platformInfo(a.platform).short;
  const code = (a.platformName ?? "")
    .normalize("NFKD")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, 4);
  return code || "LAIN";
}

/** Fill a platform URL template with the account handle (leading "@" dropped, URL-encoded). */
export function platformUrl(template: string | null, handle: string): string | null {
  if (!template) return null;
  return template.replaceAll("{handle}", encodeURIComponent(handle.trim().replace(/^@+/, "")));
}

/** `[IG-TAYANG] <title>` — the reminder notification title. */
export function postNotificationTitle(account: { platform: string; platformName?: string | null }, title: string): string {
  return `[${platformShort(account)}-TAYANG] ${title}`;
}

// ---------- Stages / formats / statuses ----------

export const STAGES = [
  { id: "ide", label: "Ide", color: "#AFAFAF", xp: 0 },
  { id: "naskah", label: "Naskah", color: "#1CB0F6", xp: 3 },
  { id: "produksi", label: "Produksi", color: "#CE82FF", xp: 4 },
  { id: "siap", label: "Siap", color: "#FF9600", xp: 5 },
  { id: "terjadwal", label: "Terjadwal", color: "#FFC800", xp: 6 },
  { id: "tayang", label: "Tayang", color: "#58CC02", xp: 10 },
] as const;
export type StageId = (typeof STAGES)[number]["id"];
export const STAGE_IDS = STAGES.map((s) => s.id) as [StageId, ...StageId[]];
export const stageIndex = (id: string) => STAGE_IDS.indexOf(id as StageId);
export const stageInfo = (id: string) => STAGES.find((s) => s.id === id) ?? STAGES[0];

/**
 * XP for moving an item forward from `from` to `to` (mobile gamification): the sum of the
 * `xp` of every stage newly reached (ide→naskah +3 … →tayang +10). Backwards = 0.
 */
export function stageXp(from: string, to: string): number {
  const a = stageIndex(from);
  const b = stageIndex(to);
  if (a < 0 || b <= a) return 0;
  return STAGES.slice(a + 1, b + 1).reduce((s, x) => s + x.xp, 0);
}
/** XP when an account meets its weekly target (mobile). */
export const WEEKLY_TARGET_XP = 20;

export const FORMATS = [
  { id: "post", label: "Post" },
  { id: "carousel", label: "Carousel" },
  { id: "reel", label: "Reel" },
  { id: "story", label: "Story" },
  { id: "video", label: "Video" },
  { id: "short", label: "Short" },
  { id: "thread", label: "Thread" },
  { id: "live", label: "Live" },
  { id: "other", label: "Lainnya" },
] as const;
export type FormatId = (typeof FORMATS)[number]["id"];
export const FORMAT_IDS = FORMATS.map((f) => f.id) as [FormatId, ...FormatId[]];

export const POST_STATUSES = [
  { id: "draft", label: "Draf", color: "#AFAFAF" },
  { id: "scheduled", label: "Terjadwal", color: "#FFC800" },
  { id: "posted", label: "Tayang", color: "#58CC02" },
  { id: "skipped", label: "Dilewati", color: "#777777" },
] as const;
export type PostStatus = (typeof POST_STATUSES)[number]["id"];
export const POST_STATUS_IDS = POST_STATUSES.map((s) => s.id) as [PostStatus, ...PostStatus[]];

/**
 * Stage after a post change (never moves backwards): all non-skipped posts `posted`
 * (and at least one) → `tayang`; else any post `scheduled` → at least `terjadwal`
 * (an item the user already moved further keeps its stage). Clients apply this when
 * they change posts and save the item; the sync endpoint does not derive it.
 */
export function autoStage(stage: string, posts: readonly { status: string }[]): StageId {
  const cur = stageIndex(stage) < 0 ? "ide" : (stage as StageId);
  const live = posts.filter((p) => p.status !== "skipped");
  let target: StageId = cur;
  if (live.length > 0 && live.every((p) => p.status === "posted")) target = "tayang";
  else if (posts.some((p) => p.status === "scheduled")) target = "terjadwal";
  return stageIndex(target) > stageIndex(cur) ? target : cur;
}

// ---------- Limits ----------

export const CONTENT_TITLE_MAX = 200;
export const HANDLE_MAX = 60;
export const PLATFORM_NAME_MAX = 30;
export const PILLAR_NAME_MAX = 30;
export const CAPTION_MAX = 5000;
export const HASHTAGS_MAX = 1000;
export const CONTENT_PHOTOS_MAX = 10;
export const ASSET_LINKS_MAX = 20;
export const ASSET_LABEL_MAX = 100;
export const BRAND_MAX = 100;
export const TARGET_PER_WEEK_MAX = 50;
/** Days after `postedAt` before the "Isi performa?" prompt. */
export const METRICS_PROMPT_DAYS = 3;
export const METRIC_KEYS = ["views", "likes", "comments", "shares", "saves", "followers"] as const;
export type MetricKey = (typeof METRIC_KEYS)[number];
export type Metrics = Partial<Record<MetricKey, number>>;
export const METRIC_LABELS: Record<MetricKey, string> = {
  views: "Tayangan",
  likes: "Suka",
  comments: "Komentar",
  shares: "Dibagikan",
  saves: "Disimpan",
  followers: "Pengikut baru",
};

// ---------- JSON shapes ----------

const hexColor = z.string().regex(HEX_COLOR_RE, "Warna tidak valid");
const sortOrder = z.number().int().min(-1_000_000).max(1_000_000).default(0);
const optionalId = z
  .string()
  .nullish()
  .transform((v) => (v && v.length > 0 ? v : null));
const isoDate = (label: string) =>
  z.iso
    .datetime({ offset: true, message: `${label} harus ISO-8601 dengan Z/offset` })
    .transform((v) => new Date(v))
    .nullish()
    .transform((v) => v ?? null);

export type AssetLink = { url: string; label: string | null };

export const assetLinksSchema = z
  .array(
    z.object({
      url: httpUrlSchema,
      label: z
        .string()
        .nullish()
        .transform((v) => (v == null ? null : cleanLine(v) || null))
        .refine((v) => v == null || v.length <= ASSET_LABEL_MAX, `Label tautan maksimal ${ASSET_LABEL_MAX} karakter`),
    }),
    { message: "assetLinks harus berupa array" },
  )
  .max(ASSET_LINKS_MAX, `Maksimal ${ASSET_LINKS_MAX} tautan aset`)
  .transform((xs): AssetLink[] => xs.map((x) => ({ url: x.url, label: x.label })));

export type Sponsor = {
  brand: string;
  amount: number;
  currency: string;
  /** Local due date YYYY-MM-DD. */
  due: string | null;
  paid: boolean;
  /** The income transaction recorded when paid (nulled when that transaction is deleted). */
  transactionId: string | null;
};

/** `{brand, amount, currency, due?, paid, transactionId?}`; amount ≥ 0 (0 = barter). */
export const sponsorSchema = z
  .object({
    brand: z
      .string()
      .transform(cleanLine)
      .pipe(z.string().min(1, "Nama brand wajib diisi").max(BRAND_MAX, `Nama brand maksimal ${BRAND_MAX} karakter`)),
    amount: z.number({ message: "Nominal sponsor harus berupa angka" }).finite().min(0, "Nominal sponsor tidak boleh negatif"),
    currency: z
      .string()
      .trim()
      .transform((v) => v.toUpperCase())
      .pipe(z.string().regex(/^[A-Z]{3}$/, "Mata uang harus 3 huruf (mis. IDR)"))
      .default("IDR"),
    due: z
      .string()
      .nullish()
      .transform((v) => (v ? v : null))
      .refine((v) => v == null || isValidDateKey(v), "Tanggal jatuh tempo harus YYYY-MM-DD"),
    paid: z.boolean().default(false),
    transactionId: optionalId,
  })
  .transform((s): Sponsor => ({ ...s }));

const metricValue = z
  .number({ message: "Metrik harus berupa angka" })
  .int("Metrik harus bilangan bulat")
  .min(0, "Metrik tidak boleh negatif")
  .max(1e12, "Metrik terlalu besar")
  .nullish();

/** Manual metrics; every key optional, unknown keys dropped, null/missing = not entered. */
export const metricsSchema = z
  .object(Object.fromEntries(METRIC_KEYS.map((k) => [k, metricValue])) as Record<MetricKey, typeof metricValue>, {
    message: "metrics harus berupa objek",
  })
  .transform((m): Metrics => {
    const out: Metrics = {};
    for (const k of METRIC_KEYS) if (m[k] != null) out[k] = m[k]!;
    return out;
  });

// ---------- Entity payloads (sync wire format; the web actions build the same shape) ----------

export const socialAccountSchema = z
  .object({
    platform: z.enum(PLATFORM_IDS, { message: "Platform tidak dikenal" }),
    platformName: z
      .string()
      .nullish()
      .transform((v) => (v == null ? null : cleanLine(v) || null))
      .refine((v) => v == null || v.length <= PLATFORM_NAME_MAX, `Nama platform maksimal ${PLATFORM_NAME_MAX} karakter`),
    handle: z
      .string()
      .transform(cleanLine)
      .pipe(z.string().min(1, "Username wajib diisi").max(HANDLE_MAX, `Username maksimal ${HANDLE_MAX} karakter`)),
    color: hexColor.nullish(),
    // 0 means "no target".
    targetPerWeek: z
      .number()
      .int("Target per minggu harus bilangan bulat")
      .min(0, `Target per minggu 1–${TARGET_PER_WEEK_MAX}`)
      .max(TARGET_PER_WEEK_MAX, `Target per minggu 1–${TARGET_PER_WEEK_MAX}`)
      .nullish()
      .transform((v) => (v ? v : null)),
    archived: z.boolean().default(false),
    sortOrder,
  })
  .superRefine((a, ctx) => {
    if (a.platform === "other" && !a.platformName)
      ctx.addIssue({ code: "custom", path: ["platformName"], message: "Isi nama platform untuk platform Lainnya" });
  })
  .transform((a) => ({
    ...a,
    platformName: a.platform === "other" ? a.platformName : null,
    color: a.color ?? platformInfo(a.platform).color,
  }));

export type SocialAccountData = z.output<typeof socialAccountSchema>;

export const contentPillarSchema = z.object({
  name: z
    .string()
    .transform(cleanLine)
    .pipe(z.string().min(1, "Nama pilar wajib diisi").max(PILLAR_NAME_MAX, `Nama pilar maksimal ${PILLAR_NAME_MAX} karakter`)),
  color: hexColor.default("#58CC02"),
  sortOrder,
});

export type ContentPillarData = z.output<typeof contentPillarSchema>;

const emptyArray = <T extends z.ZodType>(s: T) => s.nullish().transform((v) => (v ?? []) as z.output<T>);

export const contentItemSchema = z.object({
  title: z
    .string()
    .transform(cleanLine)
    .pipe(z.string().min(1, "Judul wajib diisi").max(CONTENT_TITLE_MAX, `Judul maksimal ${CONTENT_TITLE_MAX} karakter`)),
  stage: z.enum(STAGE_IDS, { message: "Tahap tidak dikenal" }).default("ide"),
  format: z.enum(FORMAT_IDS, { message: "Format tidak dikenal" }).nullish().transform((v) => v ?? null),
  pillar: z
    .string()
    .nullish()
    .transform((v) => (v == null ? null : cleanLine(v) || null))
    .refine((v) => v == null || v.length <= PILLAR_NAME_MAX, `Nama pilar maksimal ${PILLAR_NAME_MAX} karakter`),
  idea: z
    .string()
    .nullish()
    .transform((v) => cleanText(v ?? ""))
    .refine((v) => v.length <= NOTE_BODY_MAX, `Ide/naskah terlalu panjang (maks ${NOTE_BODY_MAX.toLocaleString("id-ID")} karakter)`),
  noteId: optionalId,
  checklist: emptyArray(checklistSchema),
  photos: emptyArray(imageListSchema(CONTENT_PHOTOS_MAX)),
  assetLinks: emptyArray(assetLinksSchema),
  sponsor: sponsorSchema.nullish().transform((v) => v ?? null),
});

export type ContentItemData = z.output<typeof contentItemSchema>;

export const contentPostSchema = z
  .object({
    contentId: z.string().min(1, "Konten wajib dipilih"),
    accountId: z.string().min(1, "Akun wajib dipilih"),
    caption: z
      .string()
      .nullish()
      .transform((v) => cleanText(v ?? ""))
      .refine((v) => v.length <= CAPTION_MAX, `Caption maksimal ${CAPTION_MAX} karakter`),
    hashtags: z
      .string()
      .nullish()
      .transform((v) => cleanText(v ?? "").trim())
      .refine((v) => v.length <= HASHTAGS_MAX, `Hashtag maksimal ${HASHTAGS_MAX} karakter`),
    scheduledAt: isoDate("scheduledAt"),
    remindBefore: z
      .number()
      .int("remindBefore harus menit bulat")
      .min(0, `remindBefore 0–${REMIND_BEFORE_MAX}`)
      .max(REMIND_BEFORE_MAX, `remindBefore 0–${REMIND_BEFORE_MAX}`)
      .nullish()
      .transform((v) => v ?? null),
    status: z.enum(POST_STATUS_IDS, { message: "Status posting tidak dikenal" }).default("draft"),
    postedAt: isoDate("postedAt"),
    url: z
      .string()
      .nullish()
      .transform((v) => (v && v.trim() ? v.trim() : null))
      .pipe(httpUrlSchema.nullable()),
    metrics: metricsSchema.nullish().transform((v): Metrics => v ?? {}),
    metricsAt: isoDate("metricsAt"),
  })
  .superRefine((p, ctx) => {
    if (p.status === "scheduled" && !p.scheduledAt)
      ctx.addIssue({ code: "custom", path: ["scheduledAt"], message: "Posting terjadwal butuh waktu tayang" });
  })
  // postedAt only on posted posts; a posted one without it is stamped now (clients should send it).
  .transform((p) => ({ ...p, postedAt: p.status === "posted" ? (p.postedAt ?? new Date()) : null }));

export type ContentPostData = z.output<typeof contentPostSchema>;

// ---------- Stored columns → values (lenient) ----------

function parseJsonValue(raw: unknown): unknown {
  if (typeof raw !== "string") return raw;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export function parseSponsor(raw: unknown): Sponsor | null {
  if (raw == null || raw === "") return null;
  const r = sponsorSchema.safeParse(parseJsonValue(raw));
  return r.success ? r.data : null;
}

export function parseMetrics(raw: unknown): Metrics {
  const r = metricsSchema.safeParse(parseJsonValue(raw));
  return r.success ? r.data : {};
}

export function parseAssetLinks(raw: unknown): AssetLink[] {
  const v = parseJsonValue(raw);
  if (!Array.isArray(v)) return [];
  const out: AssetLink[] = [];
  for (const x of v) {
    const r = assetLinksSchema.safeParse([x]);
    if (r.success) out.push(r.data[0]);
  }
  return out.slice(0, ASSET_LINKS_MAX);
}

// ---------- Metrics ----------

/** likes + comments + shares + saves (missing = 0). */
export function engagement(m: Metrics): number {
  return (m.likes ?? 0) + (m.comments ?? 0) + (m.shares ?? 0) + (m.saves ?? 0);
}

/** engagement / views, or null without views. */
export function engagementRate(m: Metrics): number | null {
  return m.views ? engagement(m) / m.views : null;
}

export const hasMetrics = (m: Metrics) => METRIC_KEYS.some((k) => m[k] != null);

/** "Isi performa?": posted ≥ 3 days ago and no metrics entered yet. */
export function needsMetricsPrompt(
  post: { status: string; postedAt: Date | string | null; metricsAt?: Date | string | null; metrics?: Metrics },
  now: Date = new Date(),
): boolean {
  if (post.status !== "posted" || !post.postedAt || post.metricsAt) return false;
  if (post.metrics && hasMetrics(post.metrics)) return false;
  return new Date(post.postedAt).getTime() + METRICS_PROMPT_DAYS * 86_400_000 <= now.getTime();
}

// ---------- Local dates / weeks ----------

/** Default zone for server-side calendars and reports (the user base is Indonesian). */
export const DEFAULT_TIME_ZONE = "Asia/Jakarta";

/** Local YYYY-MM-DD / hour / ISO weekday of an instant in `timeZone`. */
export function localParts(d: Date | string, timeZone: string = DEFAULT_TIME_ZONE) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      hourCycle: "h23",
    })
      .formatToParts(new Date(d))
      .map((p) => [p.type, p.value]),
  );
  const date = `${parts.year}-${parts.month}-${parts.day}`;
  return { date, hour: Number(parts.hour), weekday: isoWeekday(date) };
}

export const localDateKey = (d: Date | string, timeZone?: string) => localParts(d, timeZone).date;

/** Monday (ISO week start) of the week containing `dateKey`. */
export function weekStart(dateKey: string): string {
  return addDaysKey(dateKey, -(isoWeekday(dateKey) - 1));
}

/** Week-start keys (Mondays) of every ISO week overlapping [from, to]. */
export function weeksInRange(from: string, to: string): string[] {
  const out: string[] = [];
  for (let w = weekStart(from); w <= to; w = addDaysKey(w, 7)) out.push(w);
  return out;
}

/** Week-start keys of the ISO weeks lying entirely inside [from, to]. */
export function fullWeeksInRange(from: string, to: string): string[] {
  return weeksInRange(from, to).filter((w) => w >= from && addDaysKey(w, 6) <= to);
}

/** Every date key in [from, to]. */
export function daysInRange(from: string, to: string): string[] {
  const out: string[] = [];
  for (let d = from; d <= to; d = addDaysKey(d, 1)) out.push(d);
  return out;
}

type PostLike = {
  id: string;
  accountId: string;
  status: string;
  scheduledAt: Date | string | null;
  postedAt: Date | string | null;
};

/** When a post sits on the calendar: postedAt for posted posts, else scheduledAt (null = unscheduled). */
export function postTime(p: PostLike): Date | null {
  const t = p.status === "posted" ? (p.postedAt ?? p.scheduledAt) : p.scheduledAt;
  return t ? new Date(t) : null;
}

export type WeekSlot = {
  accountId: string;
  target: number | null;
  /** Non-skipped posts placed in the week (scheduled + posted + drafts with a date). */
  planned: number;
  /** Posts actually posted in the week (by postedAt). */
  posted: number;
  /** Empty slots vs the target: max(0, target − planned); null without a target. */
  empty: number | null;
  met: boolean | null;
};

/**
 * Per-account slots for the ISO week starting `weekKey` ("IG: 1/3 minggu ini" =
 * `planned/target`). Archived accounts are skipped.
 */
export function weekSlots(
  accounts: readonly { id: string; targetPerWeek: number | null; archived?: boolean }[],
  posts: readonly PostLike[],
  weekKey: string,
  timeZone?: string,
): WeekSlot[] {
  const end = addDaysKey(weekKey, 6);
  const inWeek = (d: Date | string | null) => {
    if (!d) return false;
    const k = localDateKey(d, timeZone);
    return k >= weekKey && k <= end;
  };
  return accounts
    .filter((a) => !a.archived)
    .map((a) => {
      const mine = posts.filter((p) => p.accountId === a.id && p.status !== "skipped");
      const planned = mine.filter((p) => inWeek(postTime(p))).length;
      const posted = mine.filter((p) => p.status === "posted" && inWeek(p.postedAt)).length;
      const target = a.targetPerWeek && a.targetPerWeek > 0 ? a.targetPerWeek : null;
      return {
        accountId: a.id,
        target,
        planned,
        posted,
        empty: target == null ? null : Math.max(0, target - planned),
        met: target == null ? null : posted >= target,
      };
    });
}

/** Posted count per week-start key for one account (by postedAt, local). */
export function postedPerWeek(posts: readonly PostLike[], accountId: string, timeZone?: string): Map<string, number> {
  const m = new Map<string, number>();
  for (const p of posts) {
    if (p.accountId !== accountId || p.status !== "posted" || !p.postedAt) continue;
    const w = weekStart(localDateKey(p.postedAt, timeZone));
    m.set(w, (m.get(w) ?? 0) + 1);
  }
  return m;
}

export type Consistency = { weeksMet: number; weeks: number; longestStreak: number; currentStreak: number };

/**
 * Consistency over `weeks` (ascending week-start keys): weeks meeting `target`, the
 * longest run of consecutive met weeks, and the current run ending at the last week —
 * where a last week that is still in progress (`currentWeek`) and not met yet doesn't
 * break the run (it just doesn't count yet).
 */
export function consistency(
  counts: ReadonlyMap<string, number>,
  target: number | null,
  weeks: readonly string[],
  currentWeek?: string,
): Consistency {
  if (!target) return { weeksMet: 0, weeks: weeks.length, longestStreak: 0, currentStreak: 0 };
  const met = weeks.map((w) => (counts.get(w) ?? 0) >= target);
  let longest = 0;
  let run = 0;
  for (const m of met) {
    run = m ? run + 1 : 0;
    longest = Math.max(longest, run);
  }
  let i = met.length - 1;
  if (i >= 0 && !met[i] && weeks[i] === currentWeek) i--;
  let current = 0;
  for (; i >= 0 && met[i]; i--) current++;
  return { weeksMet: met.filter(Boolean).length, weeks: weeks.length, longestStreak: longest, currentStreak: current };
}

// ---------- Reports ----------

export type ReportPost = PostLike & { contentId: string; metrics: Metrics };
export type ReportItem = { id: string; title: string; pillar: string | null; format: string | null };
export type ReportAccount = { id: string; targetPerWeek: number | null; archived?: boolean };

export type GroupStat = {
  key: string;
  /** Posted posts in the group. */
  posts: number;
  /** Posts that have `views` entered (the averages are over these). */
  withMetrics: number;
  avgViews: number | null;
  avgEngagement: number | null;
  avgRate: number | null;
};

export type BestPost = {
  postId: string;
  contentId: string;
  accountId: string;
  title: string;
  views: number | null;
  engagement: number;
  rate: number | null;
  postedAt: string | null;
};

export type ContentReport = {
  from: string;
  to: string;
  /** Full ISO weeks inside the range (Mondays) — the weeks consistency is judged on. */
  weeks: string[];
  days: number;
  totals: { posted: number; scheduled: number; skipped: number; views: number; engagement: number };
  accounts: (Consistency & {
    accountId: string;
    posted: number;
    target: number | null;
    /** round(target × days / 7) — prorated for partial weeks. */
    expected: number | null;
    /** posted / expected (0–1+), null without a target. */
    ratio: number | null;
  })[];
  bestByViews: BestPost[];
  bestByEngagement: BestPost[];
  byPillar: GroupStat[];
  byFormat: GroupStat[];
  /** ISO weekday "1".."7" of postedAt (local). */
  byWeekday: GroupStat[];
  /** Local hour "0".."23" of postedAt. */
  byHour: GroupStat[];
  /** Posted posts per pillar ("" = no pillar) with share of the total. */
  pillarBalance: { key: string; count: number; share: number }[];
};

function groupStats(rows: { key: string; m: Metrics }[]): GroupStat[] {
  const groups = new Map<string, Metrics[]>();
  for (const r of rows) groups.set(r.key, [...(groups.get(r.key) ?? []), r.m]);
  const avg = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null);
  return [...groups.entries()]
    .map(([key, ms]) => {
      const withViews = ms.filter((m) => m.views != null);
      const withAny = ms.filter(hasMetrics);
      return {
        key,
        posts: ms.length,
        withMetrics: withViews.length,
        avgViews: avg(withViews.map((m) => m.views!)),
        avgEngagement: avg(withAny.map(engagement)),
        avgRate: avg(withViews.filter((m) => m.views! > 0).map((m) => engagementRate(m)!)),
      };
    })
    .sort((a, b) => b.posts - a.posts || a.key.localeCompare(b.key));
}

/**
 * Report for the local date range [from, to] (inclusive): posted posts by postedAt (pass
 * all posts; filtering happens here). Consistency (weeks meeting the target, streaks) is
 * judged on the full ISO weeks inside the range; `today` marks the in-progress week,
 * which doesn't break a streak before it ends.
 */
export function buildContentReport(input: {
  from: string;
  to: string;
  accounts: readonly ReportAccount[];
  items: readonly ReportItem[];
  posts: readonly ReportPost[];
  timeZone?: string;
  today?: string;
  top?: number;
}): ContentReport {
  const { from, to, timeZone } = input;
  const top = input.top ?? 5;
  const items = new Map(input.items.map((i) => [i.id, i]));
  const inRange = (d: Date | string | null) => {
    if (!d) return false;
    const k = localDateKey(d, timeZone);
    return k >= from && k <= to;
  };
  const posted = input.posts.filter((p) => p.status === "posted" && inRange(p.postedAt));
  const weeks = fullWeeksInRange(from, to);
  const days = daysInRange(from, to).length;
  const currentWeek = input.today ? weekStart(input.today) : undefined;

  const accounts = input.accounts.map((a) => {
    const mine = posted.filter((p) => p.accountId === a.id);
    const target = a.targetPerWeek && a.targetPerWeek > 0 ? a.targetPerWeek : null;
    const expected = target == null ? null : Math.max(1, Math.round((target * days) / 7));
    return {
      accountId: a.id,
      posted: mine.length,
      target,
      expected,
      ratio: expected ? mine.length / expected : null,
      ...consistency(postedPerWeek(mine, a.id, timeZone), target, weeks, currentWeek),
    };
  });

  const best = posted.map((p): BestPost => ({
    postId: p.id,
    contentId: p.contentId,
    accountId: p.accountId,
    title: items.get(p.contentId)?.title ?? "",
    views: p.metrics.views ?? null,
    engagement: engagement(p.metrics),
    rate: engagementRate(p.metrics),
    postedAt: p.postedAt ? new Date(p.postedAt).toISOString() : null,
  }));

  const rows = (key: (p: ReportPost) => string) => posted.map((p) => ({ key: key(p), m: p.metrics }));
  const local = (p: ReportPost) => localParts(p.postedAt!, timeZone);
  const byPillar = groupStats(rows((p) => items.get(p.contentId)?.pillar ?? ""));

  return {
    from,
    to,
    weeks,
    days,
    totals: {
      posted: posted.length,
      scheduled: input.posts.filter((p) => p.status === "scheduled" && inRange(p.scheduledAt)).length,
      skipped: input.posts.filter((p) => p.status === "skipped" && inRange(p.scheduledAt)).length,
      views: posted.reduce((s, p) => s + (p.metrics.views ?? 0), 0),
      engagement: posted.reduce((s, p) => s + engagement(p.metrics), 0),
    },
    accounts,
    bestByViews: best.filter((b) => b.views != null).sort((a, b) => b.views! - a.views! || b.engagement - a.engagement).slice(0, top),
    bestByEngagement: best.filter((b) => b.engagement > 0).sort((a, b) => b.engagement - a.engagement || (b.views ?? 0) - (a.views ?? 0)).slice(0, top),
    byPillar,
    byFormat: groupStats(rows((p) => items.get(p.contentId)?.format ?? "")),
    byWeekday: groupStats(rows((p) => String(local(p).weekday))).sort((a, b) => Number(a.key) - Number(b.key)),
    byHour: groupStats(rows((p) => String(local(p).hour))).sort((a, b) => Number(a.key) - Number(b.key)),
    pillarBalance: byPillar.map((g) => ({ key: g.key, count: g.posts, share: posted.length ? g.posts / posted.length : 0 })),
  };
}

// ---------- Sponsorship ----------

/** Note of the income transaction recorded for a paid sponsor. */
export const sponsorTransactionNote = (brand: string) => `Endorse ${brand}`;

export type SponsorSummary = {
  /** Paid sponsor income per month "YYYY-MM" (by the transaction date, else due, else item creation). */
  byMonth: { month: string; amount: number; count: number }[];
  /** Paid income per account, split equally across the item's accounts ("" = item without posts). */
  byAccount: { accountId: string; amount: number }[];
  /** Unpaid sponsors, soonest due first (no due date last). */
  unpaid: { contentId: string; title: string; brand: string; amount: number; currency: string; due: string | null; overdue: boolean }[];
};

export function sponsorSummary(input: {
  items: readonly { id: string; title: string; sponsor: Sponsor | null; createdAt: Date | string }[];
  posts: readonly { contentId: string; accountId: string }[];
  /** Date of each linked transaction (id → date). */
  transactionDates?: ReadonlyMap<string, Date | string>;
  today: string;
  timeZone?: string;
}): SponsorSummary {
  const byMonth = new Map<string, { amount: number; count: number }>();
  const byAccount = new Map<string, number>();
  const unpaid: SponsorSummary["unpaid"] = [];
  for (const item of input.items) {
    const s = item.sponsor;
    if (!s) continue;
    if (!s.paid) {
      unpaid.push({ contentId: item.id, title: item.title, brand: s.brand, amount: s.amount, currency: s.currency, due: s.due, overdue: !!s.due && s.due < input.today });
      continue;
    }
    const txDate = s.transactionId ? input.transactionDates?.get(s.transactionId) : undefined;
    const day = txDate ? localDateKey(txDate, input.timeZone) : (s.due ?? localDateKey(item.createdAt, input.timeZone));
    const month = day.slice(0, 7);
    const m = byMonth.get(month) ?? { amount: 0, count: 0 };
    byMonth.set(month, { amount: m.amount + s.amount, count: m.count + 1 });
    const accs = [...new Set(input.posts.filter((p) => p.contentId === item.id).map((p) => p.accountId))];
    const keys = accs.length ? accs : [""];
    for (const a of keys) byAccount.set(a, (byAccount.get(a) ?? 0) + s.amount / keys.length);
  }
  unpaid.sort((a, b) => (a.due ?? "9999") .localeCompare(b.due ?? "9999") || a.title.localeCompare(b.title));
  return {
    byMonth: [...byMonth.entries()].map(([month, v]) => ({ month, ...v })).sort((a, b) => a.month.localeCompare(b.month)),
    byAccount: [...byAccount.entries()].map(([accountId, amount]) => ({ accountId, amount })).sort((a, b) => b.amount - a.amount),
    unpaid,
  };
}

// ---------- Default pillars ----------

const PILLAR_SEED = [
  { key: "edukasi", name: "Edukasi", color: "#1CB0F6" },
  { key: "hiburan", name: "Hiburan", color: "#FF9600" },
  { key: "promo", name: "Promo", color: "#FF4B4B" },
  { key: "bts", name: "Behind the scene", color: "#CE82FF" },
  { key: "personal", name: "Personal", color: "#58CC02" },
] as const;

/** Deterministic ids (`pillar-<key>-<userId>`) so the server and devices never duplicate. */
export function defaultPillars(userId: string): (ContentPillarData & { id: string })[] {
  return PILLAR_SEED.map((p, i) => ({ id: `pillar-${p.key}-${userId}`, name: p.name, color: p.color, sortOrder: i }));
}

/** Whether `name` clashes (case-insensitive) with another pillar. */
export function pillarNameTaken(pillars: readonly { id: string; name: string }[], name: string, exceptId?: string): boolean {
  const k = nameKey(name);
  return pillars.some((p) => p.id !== exceptId && nameKey(p.name) === k);
}

// ---------- Ordering ----------

export function compareAccounts(a: { sortOrder: number; handle: string }, b: { sortOrder: number; handle: string }) {
  return a.sortOrder - b.sortOrder || a.handle.localeCompare(b.handle);
}

export function comparePillars(a: { sortOrder: number; name: string }, b: { sortOrder: number; name: string }) {
  return a.sortOrder - b.sortOrder || a.name.localeCompare(b.name, "id");
}

/** Text copied by "Salin caption + hashtag". */
export function captionWithHashtags(p: { caption: string; hashtags: string }): string {
  const c = p.caption.trimEnd();
  const h = p.hashtags.trim();
  return c && h ? `${c}\n\n${h}` : c || h;
}
