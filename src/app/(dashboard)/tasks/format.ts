import { useSyncExternalStore } from "react";
import { addDaysKey, isMepet, isOverdue, isoWeekday, localClock, type LocalClock, type Recurrence } from "@/lib/tasks";
import type { TaskDTO } from "./types";

/** ISO weekday labels (index 0 = Monday). */
export const WEEKDAYS_SHORT = ["Sen", "Sel", "Rab", "Kam", "Jum", "Sab", "Min"];
export const WEEKDAYS_LONG = ["Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu", "Minggu"];
const MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];

// ---------- Browser clock (focus mode follows the user's local time) ----------

function clockKey() {
  const c = localClock();
  return `${c.date} ${c.time}`;
}

function subscribeClock(cb: () => void) {
  const t = setInterval(cb, 20_000);
  const onVisible = () => document.visibilityState === "visible" && cb();
  document.addEventListener("visibilitychange", onVisible);
  return () => {
    clearInterval(t);
    document.removeEventListener("visibilitychange", onVisible);
  };
}

/**
 * The user's local clock, re-evaluated every ~20 s. `null` during server rendering and
 * hydration (the server doesn't know the browser's zone) — callers render a neutral state.
 */
export function useLocalClock(): LocalClock | null {
  const key = useSyncExternalStore(subscribeClock, clockKey, () => null);
  if (!key) return null;
  const [date, time] = key.split(" ");
  return { date, time, weekday: isoWeekday(date) };
}

/** Status flags for a task at `clock` (none while the browser clock is unknown). */
export function taskStatus(task: TaskDTO, clock: LocalClock | null) {
  if (!clock) return { overdue: false, mepet: false };
  const overdue = isOverdue(task, clock);
  return { overdue, mepet: !overdue && isMepet(task, clock.date) };
}

// ---------- Dates ----------

/** "Hari ini", "Besok", "Kemarin", or "Sen, 24 Sep" (year added when not the current one). */
export function formatDueDate(key: string, today: string | null): string {
  if (today) {
    if (key === today) return "Hari ini";
    if (key === addDaysKey(today, 1)) return "Besok";
    if (key === addDaysKey(today, -1)) return "Kemarin";
  }
  const [y, m, d] = key.split("-").map(Number);
  const base = `${WEEKDAYS_SHORT[isoWeekday(key) - 1]}, ${d} ${MONTHS_SHORT[m - 1]}`;
  return today && today.slice(0, 4) !== String(y) ? `${base} ${y}` : base;
}

/** "24 Sep 2026, 14.05" for an ISO timestamp, in the browser's zone. */
export function formatDoneAt(iso: string): string {
  return new Intl.DateTimeFormat("id-ID", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(iso));
}

export function remindLabel(min: number): string {
  if (min === 0) return "Saat jatuh tempo";
  if (min % 60 === 0) return `${min / 60} jam sebelumnya`;
  return `${min} menit sebelumnya`;
}

export function recurrenceLabel(r: Recurrence): string {
  const every = (unit: string) => (r.interval === 1 ? `Setiap ${unit}` : `Setiap ${r.interval} ${unit}`);
  if (r.freq === "daily") return r.interval === 1 ? "Setiap hari" : every("hari");
  if (r.freq === "weekly") {
    const days = r.weekdays?.length ? ` (${r.weekdays.map((d) => WEEKDAYS_SHORT[d - 1]).join(", ")})` : "";
    return every("minggu") + days;
  }
  return every("bulan") + (r.monthDay ? ` (tgl ${r.monthDay})` : "");
}

// ---------- Errors ----------

const ERROR_ID: [RegExp, string][] = [
  [/^Code (\w+) is already used by another area$/, "Kode $1 sudah dipakai area lain"],
  [/^Task not found$/, "Tugas tidak ditemukan"],
  [/^Area not found$/, "Area tidak ditemukan"],
  [/^Wallet not found$/, "Dompet tidak ditemukan"],
  [/^Category not found$/, "Kategori tidak ditemukan"],
  [/^A task's category must be an expense category$/, "Kategori harus kategori pengeluaran"],
  [/^Title is required$/, "Judul wajib diisi"],
  [/^Name is required$/, "Nama wajib diisi"],
  [/^Code must be/, "Kode harus 1–8 huruf/angka (A–Z, 0–9)"],
  [/^A recurring task needs a due date$/, "Tugas berulang perlu tanggal"],
  [/^A due time needs a due date$/, "Jam perlu tanggal"],
  [/^Schedule start must be before its end$/, "Jam mulai harus sebelum jam selesai"],
  [/^Pick at least one day$/, "Pilih minimal satu hari"],
  [/^Amount must be greater than 0$/, "Nominal harus lebih dari 0"],
  [/^Something went wrong$/, "Terjadi kesalahan"],
];

/** Server actions answer in English; show the known messages in Indonesian. */
export function errorText(msg: string | null | undefined): string {
  if (!msg) return "Terjadi kesalahan";
  for (const [re, id] of ERROR_ID) if (re.test(msg)) return msg.replace(re, id);
  return msg;
}
