"use client";

import * as React from "react";
import { Modal } from "@/components/ui/modal";
import { cn } from "@/lib/utils";
import {
  FARDHU,
  SUNNAH,
  RAWATIB,
  UNFILLED,
  daysBetween,
  parseDateKey,
  prayerLabel,
  statusInfo,
} from "@/lib/prayer-quality";
import { PrayerDayEditor } from "../prayer-day-editor";
import { StatusLegend } from "../status-legend";
import { byDate, formatLong, type PrayerEntryDTO } from "../types";

const MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];

/**
 * Color map: columns = days (oldest → newest), rows = the 5 fardhu in order, each
 * cell colored by status. Rawatib = tiny white corner marks (top-left qobliyah,
 * top-right ba'diyah); dhuha/tahajud/witir = dots under each day.
 * Hover = detail tooltip, click = edit that day.
 */
export function ColorMap({
  from,
  to,
  today,
  entries,
}: {
  from: string;
  to: string;
  today: string;
  entries: PrayerEntryDTO[];
}) {
  const [selected, setSelected] = React.useState<string | null>(null);
  const data = React.useMemo(() => byDate(entries), [entries]);
  const days = React.useMemo(() => daysBetween(from, to), [from, to]);
  const big = days.length <= 31;
  const cell = big ? "h-7 w-7" : "h-4 w-4";
  const col = big ? "w-7" : "w-4";

  return (
    <div>
      <div className="flex gap-2">
        {/* Row labels */}
        <div className={cn("shrink-0 text-xs text-muted", big ? "space-y-1" : "space-y-0.5")}>
          <div className={big ? "h-5" : "h-4"} />
          {FARDHU.map((p) => (
            <div key={p.id} className={cn("flex items-center", big ? "h-7" : "h-4")}>
              {p.label}
            </div>
          ))}
          <div className="flex h-4 items-center text-[10px] text-muted-soft">Sunnah</div>
        </div>

        {/* Day columns */}
        <div className="overflow-x-auto pb-2">
          <div className={cn("flex", big ? "gap-1" : "gap-0.5")}>
            {days.map((d) => {
              const day = data[d];
              const future = d > today;
              const dt = parseDateKey(d);
              const dom = dt.getDate();
              const showLabel = big || dom === 1 || d === from || dt.getDay() === 1;
              return (
                <div key={d} className={cn("flex shrink-0 flex-col items-center", big ? "gap-1" : "gap-0.5", col)}>
                  <div
                    className={cn(
                      "flex items-end justify-center whitespace-nowrap text-muted-soft",
                      big ? "h-5 text-[11px]" : "h-4 text-[9px]",
                      d === today && "font-bold text-primary",
                    )}
                  >
                    {showLabel ? (dom === 1 && !big ? MONTHS_SHORT[dt.getMonth()] : dom) : ""}
                  </div>
                  {FARDHU.map((p) => {
                    const e = day?.[p.id];
                    const info = e ? statusInfo(e.status) : null;
                    const q = e?.qobliyah && RAWATIB[p.id].qobliyah;
                    const b = e?.badiyah && RAWATIB[p.id].badiyah;
                    return (
                      <button
                        key={p.id}
                        type="button"
                        disabled={future}
                        onClick={() => setSelected(d)}
                        title={tooltip(d, p.id, e)}
                        aria-label={tooltip(d, p.id, e)}
                        // prayedAt renders in the viewer's timezone, which may differ from the server's.
                        suppressHydrationWarning
                        className={cn(
                          "relative shrink-0 rounded-[3px] transition hover:ring-2 hover:ring-foreground/30 disabled:cursor-default disabled:opacity-30 disabled:hover:ring-0",
                          cell,
                        )}
                        style={{ background: info?.color ?? UNFILLED.color }}
                      >
                        {q && <span className={cn("absolute left-0.5 top-0.5 rounded-full bg-white", big ? "h-1.5 w-1.5" : "h-1 w-1")} />}
                        {b && <span className={cn("absolute right-0.5 top-0.5 rounded-full bg-white", big ? "h-1.5 w-1.5" : "h-1 w-1")} />}
                      </button>
                    );
                  })}
                  <div className={cn("flex h-4 items-center justify-center", big ? "gap-0.5" : "flex-col gap-px")}>
                    {SUNNAH.map((s) =>
                      day?.[s.id] ? (
                        <span
                          key={s.id}
                          title={`${s.label}${day[s.id].rakaat ? ` · ${day[s.id].rakaat} rakaat` : ""}`}
                          className={cn("rounded-full", big ? "h-1.5 w-1.5" : "h-1 w-1")}
                          style={{ background: s.color }}
                        />
                      ) : null,
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>

      <StatusLegend extras className="mt-4" />

      <Modal
        open={selected !== null}
        onClose={() => setSelected(null)}
        title={selected ? formatLong(selected) : ""}
        description="Pilih status tiap shalat."
        className="sm:max-w-2xl"
      >
        {selected && (
          <PrayerDayEditor
            key={`${selected}:${JSON.stringify(data[selected] ?? {})}`}
            dateKey={selected}
            initial={data[selected] ?? {}}
            readOnly={selected > today}
          />
        )}
      </Modal>
    </div>
  );
}

function tooltip(date: string, prayer: string, e: PrayerEntryDTO | undefined): string {
  const parts = [`${formatLong(date)} · ${prayerLabel(prayer)}`, e ? (statusInfo(e.status)?.label ?? e.status) : UNFILLED.label];
  if (e?.qobliyah) parts.push("Qobliyah ✓");
  if (e?.badiyah) parts.push("Ba'diyah ✓");
  if (e?.prayedAt) {
    const d = new Date(e.prayedAt);
    parts.push(`Pukul ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`);
  }
  if (e?.note) parts.push(e.note);
  return parts.join("\n");
}
