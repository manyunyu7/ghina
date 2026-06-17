"use client";

import * as React from "react";
import { useRouter, usePathname } from "next/navigation";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/input";
import { MONTHS } from "@/lib/utils";

export function MonthSelector({
  month,
  year,
  currentYear,
}: {
  month: number;
  year: number;
  currentYear: number;
}) {
  const router = useRouter();
  const pathname = usePathname();

  const go = React.useCallback(
    (m: number, y: number) => {
      const params = new URLSearchParams({ month: String(m), year: String(y) });
      router.push(`${pathname}?${params.toString()}`, { scroll: false });
    },
    [router, pathname],
  );

  function shift(delta: number) {
    // Convert to a zero-based absolute month index for clean wrap-around.
    const total = (year * 12 + (month - 1)) + delta;
    const y = Math.floor(total / 12);
    const m = (total % 12) + 1;
    go(m, y);
  }

  const years = React.useMemo(() => {
    const arr: number[] = [];
    for (let y = currentYear + 1; y >= currentYear - 5; y--) arr.push(y);
    return arr;
  }, [currentYear]);

  return (
    <div className="flex items-center gap-2">
      <Button
        variant="outline"
        size="icon"
        aria-label="Previous month"
        onClick={() => shift(-1)}
      >
        <ChevronLeft className="h-4 w-4" />
      </Button>

      <Select
        className="w-auto"
        value={String(month)}
        onChange={(e) => go(Number(e.target.value), year)}
        aria-label="Select month"
      >
        {MONTHS.map((m, i) => (
          <option key={m} value={String(i + 1)}>
            {m}
          </option>
        ))}
      </Select>

      <Select
        className="w-auto"
        value={String(year)}
        onChange={(e) => go(month, Number(e.target.value))}
        aria-label="Select year"
      >
        {years.map((y) => (
          <option key={y} value={String(y)}>
            {y}
          </option>
        ))}
      </Select>

      <Button variant="outline" size="icon" aria-label="Next month" onClick={() => shift(1)}>
        <ChevronRight className="h-4 w-4" />
      </Button>
    </div>
  );
}
