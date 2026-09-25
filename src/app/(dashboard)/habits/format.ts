import { addDaysKey, isoWeekday } from "@/lib/tasks";
import { isValidDateKey } from "@/lib/prayer-quality";
import type { HabitSchedule, HabitTarget } from "@/lib/habits";

/** ISO weekday labels (index 0 = Monday). */
export const WEEKDAYS_SHORT = ["Sen", "Sel", "Rab", "Kam", "Jum", "Sab", "Min"];
export const WEEKDAYS_LONG = ["Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu", "Minggu"];
export const MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];
export const MONTHS_LONG = [
  "Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember",
];

export const LOG_TYPE_LABEL: Record<string, string> = {
  done: "Selesai",
  skip: "Libur",
  relapse: "Kambuh",
  urge: "Pengen (tahan)",
};

/** Browser-local YYYY-MM-DD. */
export function browserToday(d: Date = new Date()): string {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export function browserTimeZone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "Asia/Jakarta";
  } catch {
    return "Asia/Jakarta";
  }
}

/** Browser-local HH:mm. */
export function browserTime(d: Date = new Date()): string {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${p(d.getHours())}:${p(d.getMinutes())}`;
}

/**
 * `?today=` from the URL, accepted only within ±1 day of the server's today (the browser's
 * local day may differ from Asia/Jakarta).
 */
export function resolveToday(param: string | undefined, serverToday: string): string {
  if (!param || !isValidDateKey(param)) return serverToday;
  return param === addDaysKey(serverToday, -1) || param === addDaysKey(serverToday, 1) || param === serverToday ? param : serverToday;
}

export function resolveTimeZone(param: string | undefined): string | undefined {
  if (!param || param.length > 64) return undefined;
  try {
    new Intl.DateTimeFormat("en", { timeZone: param });
    return param;
  } catch {
    return undefined;
  }
}

/** "Sen, 24 Sep" (+ year when not `yearOf`'s). */
export function formatDay(key: string, today?: string | null): string {
  if (today) {
    if (key === today) return "Hari ini";
    if (key === addDaysKey(today, -1)) return "Kemarin";
  }
  const [y, m, d] = key.split("-").map(Number);
  const base = `${WEEKDAYS_SHORT[isoWeekday(key) - 1]}, ${d} ${MONTHS_SHORT[m - 1]}`;
  return today && today.slice(0, 4) !== String(y) ? `${base} ${y}` : base;
}

export function formatLongDate(key: string): string {
  const [y, m, d] = key.split("-").map(Number);
  return `${d} ${MONTHS_LONG[m - 1]} ${y}`;
}

export function scheduleLabel(s: HabitSchedule): string {
  if (s.type === "daily") return "Setiap hari";
  if (s.type === "perWeek") return `${s.times}× per minggu`;
  if (s.days.length === 7) return "Setiap hari";
  if (s.days.join() === "1,2,3,4,5") return "Hari kerja";
  if (s.days.join() === "6,7") return "Akhir pekan";
  return s.days.map((d) => WEEKDAYS_SHORT[d - 1]).join(", ");
}

export function formatMinutes(min: number): string {
  if (min < 60) return `${min} mnt`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return m ? `${h} j ${m} mnt` : `${h} jam`;
}

export function targetLabel(t: HabitTarget): string {
  if (t.type === "check") return "Centang";
  if (t.type === "count") return `${fmtNum(t.goal)} ${t.unit}`;
  return formatMinutes(t.goal);
}

export const fmtNum = (n: number) => new Intl.NumberFormat("id-ID", { maximumFractionDigits: 2 }).format(n);

/** Progress text "3/8 gelas" or "15/30 mnt". */
export function progressLabel(t: HabitTarget, progress: number | null): string {
  const v = progress ?? 0;
  if (t.type === "count") return `${fmtNum(v)}/${fmtNum(t.goal)} ${t.unit}`;
  if (t.type === "duration") return `${fmtNum(v)}/${fmtNum(t.goal)} mnt`;
  return v > 0 ? "Selesai" : "Belum";
}
