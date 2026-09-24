"use client";

import * as React from "react";
import { useRouter, usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { PRESETS, type PresetId } from "./range";

export function RangePicker({ preset, from, to, today }: { preset: PresetId; from: string; to: string; today: string }) {
  const router = useRouter();
  const pathname = usePathname();
  const [f, setF] = React.useState(from);
  const [t, setT] = React.useState(to);

  // Keep the inputs in step with the URL (reset during render, not in an effect).
  const [prev, setPrev] = React.useState(`${from}|${to}`);
  if (prev !== `${from}|${to}`) {
    setPrev(`${from}|${to}`);
    setF(from);
    setT(to);
  }

  const go = (qs: string) => router.replace(`${pathname}?${qs}`, { scroll: false });

  return (
    <div className="mb-6 flex flex-wrap items-end gap-3">
      <div className="flex flex-wrap gap-1 rounded-lg border border-border bg-surface p-1">
        {PRESETS.map((p) => (
          <button
            key={p.id}
            type="button"
            onClick={() => go(`preset=${p.id}`)}
            className={cn(
              "rounded-md px-3 py-1.5 text-sm font-medium transition",
              preset === p.id ? "bg-primary text-white" : "text-muted hover:bg-accent hover:text-foreground",
            )}
          >
            {p.label}
          </button>
        ))}
      </div>
      <form
        className="flex flex-wrap items-end gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          if (f && t) go(`from=${f}&to=${t}`);
        }}
      >
        <label className="text-xs text-muted">
          Dari
          <input
            type="date"
            value={f}
            max={today}
            onChange={(e) => setF(e.target.value)}
            className="mt-1 block h-9 rounded-lg border border-border bg-surface px-2 text-sm text-foreground outline-none focus:border-primary"
          />
        </label>
        <label className="text-xs text-muted">
          Sampai
          <input
            type="date"
            value={t}
            onChange={(e) => setT(e.target.value)}
            className="mt-1 block h-9 rounded-lg border border-border bg-surface px-2 text-sm text-foreground outline-none focus:border-primary"
          />
        </label>
        <Button type="submit" size="sm" variant={preset === "custom" ? "primary" : "outline"} className="h-9">
          Terapkan
        </Button>
      </form>
    </div>
  );
}
