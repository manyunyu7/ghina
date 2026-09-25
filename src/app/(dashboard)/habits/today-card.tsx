import { todayKey, maskedHabitName } from "@/lib/habits";
import { getHabitsOverview } from "@/lib/habits-server";
import { HabitsTodayCardView, type TodayRow } from "./today-card-view";

const MAX = 6;

/**
 * Dashboard card "Kebiasaan hari ini" (docs/habits.md): today's due build habits and the
 * quit habits' clean-day counters, with one-tap check-ins. Private habits are masked here
 * on the server — their real name/emoji never reach the dashboard's HTML. Hidden when the
 * user has no active habits.
 */
export async function HabitsTodayCard({ userId }: { userId: string }) {
  const today = todayKey();
  const habits = await getHabitsOverview(userId, { today });
  const shown = habits.filter((h) => h.kind === "quit" || (h.startDate <= today && (h.today.scheduled || h.today.met || h.today.skipped)));
  if (!shown.length) return null;
  const rows: TodayRow[] = shown.map((h) => ({
    id: h.id,
    name: maskedHabitName(h),
    emoji: h.private ? null : h.emoji,
    private: h.private,
    color: h.color,
    kind: h.kind === "quit" ? "quit" : "build",
    // The unit can hint at the habit ("batang"): hidden for private ones.
    target: h.private && h.target.type === "count" ? { ...h.target, unit: "" } : h.target,
    today: {
      progress: h.today.progress,
      met: h.today.met,
      skipped: h.today.skipped,
      cleanCheckIn: h.today.cleanCheckIn,
      streak: h.today.streak.current,
      unit: h.today.streak.unit,
      relapsedToday: h.today.streak.kind === "quit" && h.today.streak.relapsedToday,
      beforeStart: h.startDate > today,
    },
  }));
  return <HabitsTodayCardView rows={rows.slice(0, MAX)} more={Math.max(0, rows.length - MAX)} today={today} />;
}
