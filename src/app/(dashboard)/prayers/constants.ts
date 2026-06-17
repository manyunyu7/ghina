export const PRAYERS: { id: string; label: string }[] = [
  { id: "subuh", label: "Subuh" },
  { id: "dzuhur", label: "Dzuhur" },
  { id: "ashar", label: "Ashar" },
  { id: "maghrib", label: "Maghrib" },
  { id: "isya", label: "Isya" },
];

export const PRAYER_IDS = PRAYERS.map((p) => p.id);

/** Local date -> "YYYY-MM-DD" (no timezone shift). */
export function dateKey(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export function todayKey(): string {
  return dateKey(new Date());
}
