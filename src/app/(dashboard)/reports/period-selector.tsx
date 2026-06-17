"use client";

import * as React from "react";
import { useRouter, usePathname, useSearchParams } from "next/navigation";
import { Calendar } from "lucide-react";
import { Select } from "@/components/ui/input";

type Preset = "6m" | "12m" | "month" | "year";

/**
 * Period selector for the Reports page. Updates the URL query string
 * (`?range=6m | 12m | month` plus an optional `?year=` for the year picker)
 * without a full navigation. The server `page.tsx` reads these params.
 */
export function PeriodSelector({ currentYear }: { currentYear: number }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const range = (searchParams.get("range") as Preset | null) ?? "6m";
  const year = searchParams.get("year") ?? String(currentYear);

  const setParams = React.useCallback(
    (next: Record<string, string | null>) => {
      const params = new URLSearchParams(searchParams.toString());
      for (const [key, value] of Object.entries(next)) {
        if (value) params.set(key, value);
        else params.delete(key);
      }
      const qs = params.toString();
      router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false });
    },
    [router, pathname, searchParams],
  );

  const years = React.useMemo(() => {
    const arr: number[] = [];
    for (let y = currentYear; y >= currentYear - 6; y--) arr.push(y);
    return arr;
  }, [currentYear]);

  return (
    <div className="flex items-center gap-2">
      <div className="relative">
        <Calendar className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-soft" />
        <Select
          className="w-auto pl-9"
          value={range}
          onChange={(e) => {
            const v = e.target.value as Preset;
            // Carry the selected year only in year mode.
            setParams({ range: v, year: v === "year" ? year : null });
          }}
          aria-label="Reporting period"
        >
          <option value="6m">Last 6 months</option>
          <option value="12m">Last 12 months</option>
          <option value="month">This month</option>
          <option value="year">This year</option>
        </Select>
      </div>

      {range === "year" && (
        <Select
          className="w-auto"
          value={year}
          onChange={(e) => setParams({ range: "year", year: e.target.value })}
          aria-label="Select year"
        >
          {years.map((y) => (
            <option key={y} value={String(y)}>
              {y}
            </option>
          ))}
        </Select>
      )}
    </div>
  );
}
