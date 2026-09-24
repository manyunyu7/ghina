"use client";

import * as React from "react";
import { usePathname } from "next/navigation";
import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { PendingBar } from "@/components/pending-bar";
import { useNavTransition } from "@/components/use-nav-transition";
import { PRESETS, type PresetId } from "./range";

export function RangePicker({ preset, from, to, today }: { preset: PresetId; from: string; to: string; today: string }) {
  const { pending, replace } = useNavTransition();
  const [target, setTarget] = React.useState<string | null>(null);
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

  const go = (qs: string, which: string) => {
    setTarget(which);
    replace(`${pathname}?${qs}`, { scroll: false });
  };
  const busy = (which: string) => pending && target === which;

  return (
    <div className="mb-6 flex flex-wrap items-end gap-3" aria-busy={pending || undefined}>
      <PendingBar pending={pending} />
      <div className="flex flex-wrap gap-1 rounded-lg border border-border bg-surface p-1">
        {PRESETS.map((p) => (
          <button
            key={p.id}
            type="button"
            onClick={() => go(`preset=${p.id}`, p.id)}
            disabled={pending}
            aria-busy={busy(p.id) || undefined}
            className={cn(
              "relative rounded-md px-3 py-1.5 text-sm font-medium transition disabled:cursor-wait",
              preset === p.id ? "bg-primary text-white" : "text-muted hover:bg-accent hover:text-foreground",
              busy(p.id) && "bg-primary/15 text-primary",
            )}
          >
            <span className={cn(busy(p.id) && "opacity-0")}>{p.label}</span>
            {busy(p.id) && (
              <Loader2 aria-hidden className="absolute inset-0 m-auto h-4 w-4 animate-spin" />
            )}
          </button>
        ))}
      </div>
      <form
        className="flex flex-wrap items-end gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          if (f && t) go(`from=${f}&to=${t}`, "custom");
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
        <Button type="submit" size="sm" variant={preset === "custom" ? "primary" : "outline"} className="h-9" loading={busy("custom")}>
          Terapkan
        </Button>
      </form>
    </div>
  );
}
