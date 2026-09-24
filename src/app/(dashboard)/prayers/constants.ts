// Prayer constants live in the shared pure module (also used by the sync endpoint).
export { FARDHU as PRAYERS, FARDHU_IDS as PRAYER_IDS, dateKey } from "@/lib/prayer-quality";
import { dateKey } from "@/lib/prayer-quality";

export function todayKey(): string {
  return dateKey(new Date());
}
