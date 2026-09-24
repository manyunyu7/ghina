import { cn } from "@/lib/utils";
import { STATUSES, SUNNAH, UNFILLED } from "@/lib/prayer-quality";

/** Legend for status colors (+ optionally sunnah dots and rawatib marks). */
export function StatusLegend({ extras = false, className }: { extras?: boolean; className?: string }) {
  return (
    <div className={cn("flex flex-wrap items-center gap-x-4 gap-y-1.5 text-xs text-muted", className)}>
      {STATUSES.map((s) => (
        <span key={s.id} className="inline-flex items-center gap-1.5">
          <span className="h-3 w-3 rounded-sm" style={{ background: s.color }} />
          {s.label}
        </span>
      ))}
      <span className="inline-flex items-center gap-1.5">
        <span className="h-3 w-3 rounded-sm" style={{ background: UNFILLED.color }} />
        {UNFILLED.label}
      </span>
      {extras && (
        <>
          {SUNNAH.map((s) => (
            <span key={s.id} className="inline-flex items-center gap-1.5">
              <span className="h-2 w-2 rounded-full" style={{ background: s.color }} />
              {s.label}
            </span>
          ))}
          <span className="inline-flex items-center gap-1.5">
            <span className="relative h-3 w-3 rounded-sm" style={{ background: STATUSES[1].color }}>
              <span className="absolute left-0 top-0 h-1 w-1 rounded-full bg-white" />
              <span className="absolute right-0 top-0 h-1 w-1 rounded-full bg-white" />
            </span>
            Rawatib (kiri: qobliyah, kanan: ba&apos;diyah)
          </span>
        </>
      )}
    </div>
  );
}
