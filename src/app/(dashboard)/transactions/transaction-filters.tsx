"use client";

import * as React from "react";
import { useRouter, usePathname, useSearchParams } from "next/navigation";
import { Search, X } from "lucide-react";
import type { Wallet, Category } from "@prisma/client";
import { Input, Select } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { MONTHS } from "@/lib/utils";

export function TransactionFilters({
  wallets,
  categories,
  currentYear,
}: {
  wallets: Wallet[];
  categories: Category[];
  currentYear: number;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const get = (key: string) => searchParams.get(key) ?? "";

  const setParam = React.useCallback(
    (key: string, value: string) => {
      const params = new URLSearchParams(searchParams.toString());
      if (value) params.set(key, value);
      else params.delete(key);
      router.replace(`${pathname}?${params.toString()}`, { scroll: false });
    },
    [router, pathname, searchParams],
  );

  // Debounced search on note. Uncontrolled input + ref timer so we never
  // call setState inside an effect; external changes (Clear) remount via key.
  const debounceRef = React.useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const onSearchChange = (value: string) => {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      if ((searchParams.get("q") ?? "") !== value) setParam("q", value);
    }, 300);
  };

  const years = React.useMemo(() => {
    const arr: number[] = [];
    for (let y = currentYear; y >= currentYear - 5; y--) arr.push(y);
    return arr;
  }, [currentYear]);

  const hasFilters =
    Boolean(get("type") || get("walletId") || get("categoryId") || get("month") || get("year") || get("q"));

  function clearAll() {
    router.replace(pathname, { scroll: false });
  }

  return (
    <div className="mb-6 space-y-3">
      <div className="relative">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-soft" />
        <Input
          key={get("q")}
          className="pl-9"
          placeholder="Search notes…"
          defaultValue={get("q")}
          onChange={(e) => onSearchChange(e.target.value)}
        />
      </div>

      <div className="flex flex-wrap gap-2">
        <Select
          className="w-auto"
          value={get("type")}
          onChange={(e) => setParam("type", e.target.value)}
          aria-label="Filter by type"
        >
          <option value="">All types</option>
          <option value="income">Income</option>
          <option value="expense">Expense</option>
          <option value="transfer">Transfer</option>
        </Select>

        <Select
          className="w-auto"
          value={get("walletId")}
          onChange={(e) => setParam("walletId", e.target.value)}
          aria-label="Filter by wallet"
        >
          <option value="">All wallets</option>
          {wallets.map((w) => (
            <option key={w.id} value={w.id}>
              {w.name}
            </option>
          ))}
        </Select>

        <Select
          className="w-auto"
          value={get("categoryId")}
          onChange={(e) => setParam("categoryId", e.target.value)}
          aria-label="Filter by category"
        >
          <option value="">All categories</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </Select>

        <Select
          className="w-auto"
          value={get("month")}
          onChange={(e) => setParam("month", e.target.value)}
          aria-label="Filter by month"
        >
          <option value="">All months</option>
          {MONTHS.map((m, i) => (
            <option key={m} value={String(i + 1)}>
              {m}
            </option>
          ))}
        </Select>

        <Select
          className="w-auto"
          value={get("year")}
          onChange={(e) => setParam("year", e.target.value)}
          aria-label="Filter by year"
        >
          <option value="">All years</option>
          {years.map((y) => (
            <option key={y} value={String(y)}>
              {y}
            </option>
          ))}
        </Select>

        {hasFilters && (
          <Button variant="ghost" size="sm" onClick={clearAll}>
            <X className="h-4 w-4" />
            Clear
          </Button>
        )}
      </div>
    </div>
  );
}
