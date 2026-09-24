import { addDays, dateKey, isValidDateKey, parseDateKey } from "@/lib/prayer-quality";

export const PRESETS = [
  { id: "7d", label: "7 hari" },
  { id: "month", label: "Bulan ini" },
  { id: "lastmonth", label: "Bulan lalu" },
  { id: "3m", label: "3 bulan" },
] as const;

export type PresetId = (typeof PRESETS)[number]["id"] | "custom";

/** Longest custom range, in days. */
export const MAX_RANGE_DAYS = 366;

/**
 * Report range from search params (docs/prayer-quality.md):
 * 7 hari = today−6 … today · Bulan ini = 1st … last day of this month ·
 * Bulan lalu = whole previous month · 3 bulan = today−89 … today ·
 * custom = from/to (swapped if reversed, clamped to MAX_RANGE_DAYS ending at `to`).
 */
export function resolveRange(
  sp: { preset?: string; from?: string; to?: string },
  today: string,
): { preset: PresetId; from: string; to: string } {
  if (sp.from && sp.to && isValidDateKey(sp.from) && isValidDateKey(sp.to)) {
    const to = sp.from <= sp.to ? sp.to : sp.from;
    let from = sp.from <= sp.to ? sp.from : sp.to;
    // `to` may be in the future; days after today are shown but not counted.
    const span = Math.round((parseDateKey(to).getTime() - parseDateKey(from).getTime()) / 86_400_000) + 1;
    if (span > MAX_RANGE_DAYS) from = addDays(to, -(MAX_RANGE_DAYS - 1));
    return { preset: "custom", from, to };
  }
  const t = parseDateKey(today);
  switch (sp.preset) {
    case "month":
      return {
        preset: "month",
        from: dateKey(new Date(t.getFullYear(), t.getMonth(), 1)),
        to: dateKey(new Date(t.getFullYear(), t.getMonth() + 1, 0)),
      };
    case "lastmonth":
      return {
        preset: "lastmonth",
        from: dateKey(new Date(t.getFullYear(), t.getMonth() - 1, 1)),
        to: dateKey(new Date(t.getFullYear(), t.getMonth(), 0)),
      };
    case "3m":
      return { preset: "3m", from: addDays(today, -89), to: today };
    default:
      return { preset: "7d", from: addDays(today, -6), to: today };
  }
}
