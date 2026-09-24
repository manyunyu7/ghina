import type { AreaSchedule } from "@/lib/tasks";
import { WEEKDAYS_SHORT } from "./format";

/** "Sen–Jum 09:00–17:00", "Setiap hari 06:00–08:00", "Sen, Rab 19:00–21:00" or "Kapan saja". */
export function scheduleLabel(s: AreaSchedule | null): string {
  if (!s) return "Kapan saja";
  const days = [...s.days].sort((a, b) => a - b);
  let d: string;
  if (days.length === 7) d = "Setiap hari";
  else if (days.length > 2 && days.every((x, i) => i === 0 || x === days[i - 1] + 1))
    d = `${WEEKDAYS_SHORT[days[0] - 1]}–${WEEKDAYS_SHORT[days[days.length - 1] - 1]}`;
  else d = days.map((x) => WEEKDAYS_SHORT[x - 1]).join(", ");
  return `${d} ${s.start}–${s.end}`;
}
