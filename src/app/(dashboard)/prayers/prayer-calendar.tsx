"use client";

import * as React from "react";
import { usePathname, useSearchParams } from "next/navigation";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { startOfMonth, endOfMonth, eachDayOfInterval, getDay } from "date-fns";
import { Modal } from "@/components/ui/modal";
import { Card, CardContent } from "@/components/ui/card";
import { cn, MONTHS } from "@/lib/utils";
import { PendingBar } from "@/components/pending-bar";
import { SavingHint } from "@/components/ui/saving-hint";
import { useNavTransition } from "@/components/use-nav-transition";
import { FARDHU, SUNNAH, dateKey, statusColor } from "@/lib/prayer-quality";
import { PrayerDayEditor } from "./prayer-day-editor";
import { StatusLegend } from "./status-legend";
import { formatLong, type PrayerEntryDTO } from "./types";

const WEEKDAYS = ["Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"];

export function PrayerCalendar({
  year,
  month, // 1-12
  data,
  today,
}: {
  year: number;
  month: number;
  data: Record<string, Record<string, PrayerEntryDTO>>;
  today: string;
}) {
  const { pending, replace } = useNavTransition();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [selected, setSelected] = React.useState<string | null>(null);

  const monthStart = startOfMonth(new Date(year, month - 1, 1));
  const days = eachDayOfInterval({ start: monthStart, end: endOfMonth(monthStart) });
  const leadPad = getDay(monthStart); // 0 = Sunday

  function go(delta: number) {
    let m = month + delta;
    let y = year;
    if (m < 1) { m = 12; y -= 1; }
    if (m > 12) { m = 1; y += 1; }
    const params = new URLSearchParams(searchParams.toString());
    params.set("month", String(m));
    params.set("year", String(y));
    replace(`${pathname}?${params.toString()}`, { scroll: false });
  }

  return (
    <Card>
      <CardContent>
        {/* Header */}
        <div className="mb-4 flex items-center justify-between">
          <h3 className="font-semibold text-foreground">
            {MONTHS[month - 1]} {year}
          </h3>
          <div className="flex items-center gap-1" aria-busy={pending || undefined}>
            <PendingBar pending={pending} />
            <SavingHint pending={pending} label={null} className="mr-1" />
            <button onClick={() => go(-1)} className="rounded-lg p-1.5 text-muted hover:bg-accent" aria-label="Bulan sebelumnya">
              <ChevronLeft className="h-5 w-5" />
            </button>
            <button onClick={() => go(1)} className="rounded-lg p-1.5 text-muted hover:bg-accent" aria-label="Bulan berikutnya">
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

        {/* Day grid: one colored segment per fardhu (in order), sunnah dots below */}
        <div className="grid grid-cols-7 gap-1">
          {Array.from({ length: leadPad }).map((_, i) => (
            <div key={`pad-${i}`} />
          ))}
          {days.map((d) => {
            const key = dateKey(d);
            const day = data[key];
            const isToday = key === today;
            const isFuture = key > today;
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
                <span className={cn("flex gap-0.5", isFuture && "opacity-40")} aria-hidden>
                  {FARDHU.map((p) => (
                    <span
                      key={p.id}
                      className="h-1.5 w-1.5 rounded-sm sm:w-2"
                      style={{ background: statusColor(day?.[p.id]?.status) }}
                    />
                  ))}
                </span>
                <span className="flex h-1 gap-0.5" aria-hidden>
                  {SUNNAH.map((s) =>
                    day?.[s.id] ? <span key={s.id} className="h-1 w-1 rounded-full" style={{ background: s.color }} /> : null,
                  )}
                </span>
              </button>
            );
          })}
        </div>

        <div className="mt-4">
          <StatusLegend />
        </div>

        {/* Day editor */}
        <Modal
          open={selected !== null}
          onClose={() => setSelected(null)}
          title={selected ? formatLong(selected) : ""}
          description="Pilih status tiap shalat."
          className="sm:max-w-2xl"
        >
          {selected && (
            <PrayerDayEditor key={selected} dateKey={selected} initial={data[selected] ?? {}} readOnly={selected > today} />
          )}
        </Modal>
      </CardContent>
    </Card>
  );
}
