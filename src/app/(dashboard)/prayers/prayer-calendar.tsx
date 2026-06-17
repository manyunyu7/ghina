"use client";

import * as React from "react";
import { useRouter, usePathname } from "next/navigation";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { startOfMonth, endOfMonth, eachDayOfInterval, getDay } from "date-fns";
import { Modal } from "@/components/ui/modal";
import { Card, CardContent } from "@/components/ui/card";
import { cn, MONTHS } from "@/lib/utils";
import { dateKey, todayKey, PRAYERS } from "./constants";
import { PrayerToggles } from "./prayer-toggles";

const WEEKDAYS = ["Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"];

export function PrayerCalendar({
  year,
  month, // 1-12
  data,
}: {
  year: number;
  month: number;
  data: Record<string, string[]>;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const [selected, setSelected] = React.useState<string | null>(null);

  const tKey = todayKey();
  const monthStart = startOfMonth(new Date(year, month - 1, 1));
  const days = eachDayOfInterval({ start: monthStart, end: endOfMonth(monthStart) });
  const leadPad = getDay(monthStart); // 0 = Sunday

  function go(delta: number) {
    let m = month + delta;
    let y = year;
    if (m < 1) { m = 12; y -= 1; }
    if (m > 12) { m = 1; y += 1; }
    router.replace(`${pathname}?month=${m}&year=${y}`, { scroll: false });
  }

  return (
    <Card>
      <CardContent>
        {/* Header */}
        <div className="mb-4 flex items-center justify-between">
          <h3 className="font-semibold text-foreground">
            {MONTHS[month - 1]} {year}
          </h3>
          <div className="flex gap-1">
            <button onClick={() => go(-1)} className="rounded-lg p-1.5 text-muted hover:bg-accent" aria-label="Previous month">
              <ChevronLeft className="h-5 w-5" />
            </button>
            <button onClick={() => go(1)} className="rounded-lg p-1.5 text-muted hover:bg-accent" aria-label="Next month">
              <ChevronRight className="h-5 w-5" />
            </button>
          </div>
        </div>

        {/* Weekday header */}
        <div className="mb-1 grid grid-cols-7 text-center text-xs font-medium text-muted-soft">
          {WEEKDAYS.map((w) => (
            <div key={w} className="py-1">{w}</div>
          ))}
        </div>

        {/* Day grid */}
        <div className="grid grid-cols-7 gap-1">
          {Array.from({ length: leadPad }).map((_, i) => (
            <div key={`pad-${i}`} />
          ))}
          {days.map((d) => {
            const key = dateKey(d);
            const count = data[key]?.length ?? 0;
            const isToday = key === tKey;
            const isFuture = key > tKey;

            let dot = "bg-transparent border border-border";
            if (count === 5) dot = "bg-income";
            else if (count > 0) dot = "bg-amber-400";
            else if (!isFuture) dot = "bg-expense/30";

            return (
              <button
                key={key}
                onClick={() => setSelected(key)}
                className={cn(
                  "flex aspect-square flex-col items-center justify-center gap-1 rounded-lg text-sm transition hover:bg-accent",
                  isToday && "ring-2 ring-primary",
                  isFuture ? "text-muted-soft" : "text-foreground",
                )}
              >
                <span>{d.getDate()}</span>
                <span className={cn("h-2 w-2 rounded-full", dot)} />
              </button>
            );
          })}
        </div>

        {/* Legend */}
        <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted">
          <Legend className="bg-income" label="Complete (5/5)" />
          <Legend className="bg-amber-400" label="Partial" />
          <Legend className="bg-expense/30" label="Missed" />
        </div>

        {/* Day editor */}
        <Modal
          open={selected !== null}
          onClose={() => setSelected(null)}
          title={selected ? formatLong(selected) : ""}
          description="Tap a prayer to mark it done or undo."
        >
          {selected && (
            <PrayerToggles key={selected} dateKey={selected} initialDone={data[selected] ?? []} size="lg" />
          )}
          {selected && (
            <p className="mt-3 text-center text-sm text-muted">
              {(data[selected]?.length ?? 0)} of {PRAYERS.length} prayers
            </p>
          )}
        </Modal>
      </CardContent>
    </Card>
  );
}

function Legend({ className, label }: { className: string; label: string }) {
  return (
    <span className="inline-flex items-center gap-1.5">
      <span className={cn("h-2.5 w-2.5 rounded-full", className)} />
      {label}
    </span>
  );
}

function formatLong(key: string): string {
  const [y, m, d] = key.split("-").map(Number);
  return new Intl.DateTimeFormat("en-US", { weekday: "long", day: "numeric", month: "long", year: "numeric" }).format(
    new Date(y, m - 1, d),
  );
}
