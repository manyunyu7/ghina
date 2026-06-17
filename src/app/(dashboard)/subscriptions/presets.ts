import { addWeeks, addMonths, addYears } from "date-fns";

export type Cycle = "weekly" | "monthly" | "yearly";

export const CYCLES: { value: Cycle; label: string; per: string }[] = [
  { value: "weekly", label: "Weekly", per: "/wk" },
  { value: "monthly", label: "Monthly", per: "/mo" },
  { value: "yearly", label: "Yearly", per: "/yr" },
];

export function cycleLabel(cycle: string): string {
  return CYCLES.find((c) => c.value === cycle)?.per ?? "/mo";
}

// Popular subscriptions — tap to prefill the form. Keep the list short so it isn't overwhelming.
export const SUBSCRIPTION_PRESETS: {
  name: string;
  color: string;
  icon: string;
  cycle: Cycle;
}[] = [
  { name: "Netflix", color: "#E50914", icon: "tv", cycle: "monthly" },
  { name: "Spotify", color: "#1DB954", icon: "music", cycle: "monthly" },
  { name: "YouTube Premium", color: "#FF0000", icon: "tv", cycle: "monthly" },
  { name: "Disney+ Hotstar", color: "#1F80E0", icon: "tv", cycle: "monthly" },
  { name: "Amazon Prime", color: "#00A8E1", icon: "shopping-bag", cycle: "yearly" },
  { name: "Apple iCloud", color: "#555555", icon: "cloud", cycle: "monthly" },
  { name: "Google One", color: "#4285F4", icon: "cloud", cycle: "monthly" },
  { name: "Microsoft 365", color: "#D83B01", icon: "briefcase", cycle: "yearly" },
  { name: "ChatGPT Plus", color: "#10A37F", icon: "sparkles", cycle: "monthly" },
  { name: "Gym Membership", color: "#f97316", icon: "dumbbell", cycle: "monthly" },
];

/** Normalize any cycle's amount to a per-month figure. */
export function monthlyAmount(amount: number, cycle: string): number {
  if (cycle === "weekly") return (amount * 52) / 12;
  if (cycle === "yearly") return amount / 12;
  return amount;
}

/** Normalize to a per-year figure. */
export function yearlyAmount(amount: number, cycle: string): number {
  if (cycle === "weekly") return amount * 52;
  if (cycle === "monthly") return amount * 12;
  return amount;
}

/** Roll a billing anchor forward to the next occurrence on/after `from` (default: today). */
export function nextOccurrence(anchor: Date | string, cycle: string, from: Date = new Date()): Date {
  let d = new Date(anchor);
  const start = new Date(from.getFullYear(), from.getMonth(), from.getDate());
  let guard = 0;
  while (d < start && guard < 1000) {
    if (cycle === "weekly") d = addWeeks(d, 1);
    else if (cycle === "yearly") d = addYears(d, 1);
    else d = addMonths(d, 1);
    guard++;
  }
  return d;
}

export function daysUntil(date: Date, from: Date = new Date()): number {
  const a = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const b = new Date(from.getFullYear(), from.getMonth(), from.getDate());
  return Math.round((a.getTime() - b.getTime()) / 86_400_000);
}
