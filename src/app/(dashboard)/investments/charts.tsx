"use client";

import * as React from "react";
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip, LineChart, Line, XAxis, YAxis, CartesianGrid } from "recharts";
import { LineChart as LineChartIcon, PieChart as PieChartIcon } from "lucide-react";
import { Money } from "@/components/money/money";
import { useMoneyFormat } from "@/components/money/balance-privacy";
import { COLOR_PALETTE } from "@/lib/constants";
import { cn } from "@/lib/utils";
import type { AllocationSlice } from "@/lib/investments";
import { daysAgoKey, fmtDateKey, fmtPct, KIND_COLORS } from "./format";
import type { HistoryPoint } from "./types";

function TooltipBox({ children }: { children: React.ReactNode }) {
  return <div className="rounded-lg border border-border bg-card px-3 py-2 text-xs shadow-sm">{children}</div>;
}

export function Segmented<T extends string>({
  value,
  onChange,
  options,
  label,
  className,
}: {
  value: T;
  onChange: (v: T) => void;
  options: readonly { value: T; label: string }[];
  label: string;
  className?: string;
}) {
  return (
    <div role="radiogroup" aria-label={label} className={cn("inline-flex rounded-lg bg-accent p-0.5", className)}>
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          role="radio"
          aria-checked={value === o.value}
          onClick={() => onChange(o.value)}
          className={cn(
            "rounded-md px-2.5 py-1 text-xs font-medium transition",
            value === o.value ? "bg-card text-foreground shadow-sm" : "text-muted hover:text-foreground",
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

export function AllocationCard({ byAsset, byKind, currency }: { byAsset: AllocationSlice[]; byKind: AllocationSlice[]; currency: string }) {
  const [mode, setMode] = React.useState<"asset" | "kind">("asset");
  const money = useMoneyFormat();
  const slices = mode === "asset" ? byAsset : byKind;
  const color = (s: AllocationSlice, i: number) => (mode === "kind" ? (KIND_COLORS[s.key] ?? COLOR_PALETTE[i % 15]) : COLOR_PALETTE[i % COLOR_PALETTE.length]);
  const total = slices.reduce((s, x) => s + x.value, 0);
  return (
    <div className="rounded-card border border-border bg-card p-5 shadow-sm">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-base font-semibold text-foreground">Alokasi</h3>
        <Segmented
          label="Kelompokkan alokasi"
          value={mode}
          onChange={setMode}
          options={[
            { value: "asset", label: "Per aset" },
            { value: "kind", label: "Per jenis" },
          ]}
        />
      </div>
      {slices.length === 0 ? (
        <div className="flex flex-col items-center gap-2 py-10 text-center">
          <PieChartIcon className="h-8 w-8 text-muted-soft" />
          <p className="text-sm text-muted">Belum ada nilai untuk dialokasikan.</p>
        </div>
      ) : (
        <div className="flex flex-col items-center gap-5 sm:flex-row">
          <div className="relative h-44 w-44 shrink-0">
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie data={slices} dataKey="value" nameKey="label" cx="50%" cy="50%" innerRadius={56} outerRadius={80} paddingAngle={2} stroke="none">
                  {slices.map((s, i) => (
                    <Cell key={s.key} fill={color(s, i)} />
                  ))}
                </Pie>
                <Tooltip
                  content={({ active, payload }) => {
                    if (!active || !payload?.length) return null;
                    const s = payload[0].payload as AllocationSlice;
                    return (
                      <TooltipBox>
                        <p className="font-medium text-foreground">{s.label}</p>
                        <p className="text-muted">
                          {money.format(s.value, currency)} · {fmtPct(s.pct, false)}
                        </p>
                      </TooltipBox>
                    );
                  }}
                />
              </PieChart>
            </ResponsiveContainer>
            <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
              <span className="text-xs text-muted">Total</span>
              <span className="text-sm font-bold text-foreground">
                <Money amount={total} currency={currency} compact />
              </span>
            </div>
          </div>
          <ul className="w-full flex-1 space-y-2 self-stretch">
            {slices.slice(0, 8).map((s, i) => (
              <li key={s.key} className="flex items-center gap-2.5 text-sm">
                <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: color(s, i) }} />
                <span className="min-w-0 flex-1 truncate text-foreground">{s.label}</span>
                <span className="text-xs text-muted">{fmtPct(s.pct, false)}</span>
                <span className="w-20 text-right text-xs font-medium text-foreground">
                  <Money amount={s.value} currency={currency} compact />
                </span>
              </li>
            ))}
            {slices.length > 8 && <li className="text-xs text-muted">+{slices.length - 8} aset lainnya</li>}
          </ul>
        </div>
      )}
    </div>
  );
}

const RANGES = [
  { value: "1m", label: "1B", days: 31 },
  { value: "3m", label: "3B", days: 92 },
  { value: "6m", label: "6B", days: 183 },
  { value: "1y", label: "1T", days: 366 },
  { value: "all", label: "Semua", days: null },
] as const;
type RangeKey = (typeof RANGES)[number]["value"];

export function HistoryCard({ history, currency }: { history: HistoryPoint[]; currency: string }) {
  const [range, setRange] = React.useState<RangeKey>("3m");
  const money = useMoneyFormat();
  const days = RANGES.find((r) => r.value === range)?.days ?? null;
  const from = days == null ? "" : daysAgoKey(days);
  const data = history.filter((h) => h.date >= from);
  return (
    <div className="min-w-0 rounded-card border border-border bg-card p-5 shadow-sm">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-base font-semibold text-foreground">Riwayat nilai</h3>
        <Segmented label="Rentang waktu" value={range} onChange={setRange} options={RANGES} />
      </div>
      {data.length < 2 ? (
        <div className="flex flex-col items-center gap-2 py-10 text-center">
          <LineChartIcon className="h-8 w-8 text-muted-soft" />
          <p className="max-w-xs text-sm text-muted">
            Riwayat terisi otomatis satu titik per hari setiap kali portofolio dibuka. Grafik muncul setelah ada 2 hari data.
          </p>
        </div>
      ) : (
        <>
          <div className="h-56 w-full" data-testid="history-chart">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--color-border)" />
                <XAxis
                  dataKey="date"
                  tickLine={false}
                  axisLine={false}
                  minTickGap={24}
                  tick={{ fill: "var(--color-muted)", fontSize: 11 }}
                  tickFormatter={(d: string) => fmtDateKey(d, { day: "numeric", month: "short" })}
                />
                <YAxis
                  tickLine={false}
                  axisLine={false}
                  width={68}
                  domain={["auto", "auto"]}
                  tick={{ fill: "var(--color-muted)", fontSize: 11 }}
                  tickFormatter={(v: number) => money.axis(v, currency)}
                />
                <Tooltip
                  content={({ active, payload, label }) => {
                    if (!active || !payload?.length) return null;
                    const p = payload[0].payload as HistoryPoint;
                    return (
                      <TooltipBox>
                        <p className="mb-1 font-medium text-foreground">{fmtDateKey(String(label))}</p>
                        <p className="text-primary">Nilai: {money.format(p.value, currency)}</p>
                        <p className="text-muted">Modal: {money.format(p.cost, currency)}</p>
                      </TooltipBox>
                    );
                  }}
                />
                <Line type="monotone" dataKey="cost" stroke="var(--color-muted-soft)" strokeDasharray="4 4" strokeWidth={1.5} dot={false} />
                <Line type="monotone" dataKey="value" stroke="var(--color-primary)" strokeWidth={2} dot={false} />
              </LineChart>
            </ResponsiveContainer>
          </div>
          <div className="mt-2 flex items-center gap-4 text-xs text-muted">
            <span className="inline-flex items-center gap-1.5">
              <span className="h-0.5 w-4 bg-primary" /> Nilai pasar
            </span>
            <span className="inline-flex items-center gap-1.5">
              <span className="h-0.5 w-4 border-t border-dashed border-muted-soft" /> Modal
            </span>
          </div>
        </>
      )}
    </div>
  );
}
