"use client";

import * as React from "react";
import { Check } from "lucide-react";
import { cn } from "@/lib/utils";
import { PRAYERS } from "./constants";
import { togglePrayer } from "./actions";

export function PrayerToggles({
  dateKey,
  initialDone,
  size = "md",
}: {
  dateKey: string;
  initialDone: string[];
  size?: "md" | "lg";
}) {
  const [done, setDone] = React.useState<Set<string>>(() => new Set(initialDone));
  const [, startTransition] = React.useTransition();

  function toggle(id: string) {
    // optimistic
    setDone((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
    const fd = new FormData();
    fd.set("date", dateKey);
    fd.set("prayer", id);
    startTransition(async () => {
      const res = await togglePrayer(fd);
      if (!res.ok) {
        // revert on failure
        setDone((prev) => {
          const next = new Set(prev);
          if (next.has(id)) next.delete(id);
          else next.add(id);
          return next;
        });
      }
    });
  }

  return (
    <div className={cn("grid gap-2", size === "lg" ? "grid-cols-2 sm:grid-cols-5" : "grid-cols-5")}>
      {PRAYERS.map((p) => {
        const active = done.has(p.id);
        return (
          <button
            key={p.id}
            type="button"
            onClick={() => toggle(p.id)}
            className={cn(
              "flex flex-col items-center justify-center gap-1.5 rounded-xl border transition",
              size === "lg" ? "px-3 py-4" : "px-2 py-3",
              active
                ? "border-income bg-income-soft text-income"
                : "border-border bg-surface text-muted hover:bg-accent",
            )}
            aria-pressed={active}
          >
            <span
              className={cn(
                "flex items-center justify-center rounded-full transition",
                size === "lg" ? "h-8 w-8" : "h-6 w-6",
                active ? "bg-income text-white" : "border border-border bg-background",
              )}
            >
              {active && <Check className={size === "lg" ? "h-5 w-5" : "h-4 w-4"} />}
            </span>
            <span className={cn("font-medium", size === "lg" ? "text-sm" : "text-xs")}>{p.label}</span>
          </button>
        );
      })}
    </div>
  );
}
