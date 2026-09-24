"use client";

import * as React from "react";
import { usePathname } from "next/navigation";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/input";
import { MONTHS } from "@/lib/utils";
import { PendingBar } from "@/components/pending-bar";
import { SavingHint } from "@/components/ui/saving-hint";
import { useNavTransition } from "@/components/use-nav-transition";

export function MonthSelector({
  month: propMonth,
  year: propYear,
  currentYear,
}: {
  month: number;
  year: number;
  currentYear: number;
}) {
  const pathname = usePathname();
  const { pending, push } = useNavTransition();

  // Show the picked month right away while the new page loads (the URL only updates once
  // the navigation commits); re-sync whenever the server props change.
  const propKey = `${propMonth}-${propYear}`;
  const [view, setView] = React.useState({ month: propMonth, year: propYear, key: propKey });
  if (view.key !== propKey && !pending) {
    setView({ month: propMonth, year: propYear, key: propKey });
  }
  const { month, year } = view;

  const go = React.useCallback(
    (m: number, y: number) => {
      setView((v) => ({ ...v, month: m, year: y }));
      const params = new URLSearchParams({ month: String(m), year: String(y) });
      push(`${pathname}?${params.toString()}`, { scroll: false });
    },
    [push, pathname],
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
    <div className="flex items-center gap-2" aria-busy={pending || undefined}>
      <PendingBar pending={pending} />
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
      <SavingHint pending={pending} label={null} />
    </div>
  );
}
