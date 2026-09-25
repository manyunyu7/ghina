"use client";

import { Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";

const TOOLTIP_STYLE: React.CSSProperties = {
  borderRadius: 12,
  border: "1px solid var(--color-border)",
  background: "var(--color-card)",
  fontSize: 12,
  color: "var(--color-foreground)",
  boxShadow: "0 4px 16px rgba(0,0,0,0.08)",
};

const AXIS = { fontSize: 11, fill: "var(--color-muted)" };

export type SeriesDef = { key: string; label: string; color: string };

/** Grouped bars: one row per category (weekday / hour), one bar per series. */
export function GroupedBars({
  data,
  series,
  height = 200,
  unit = "",
  interval = 0,
}: {
  data: Record<string, string | number>[];
  series: SeriesDef[];
  height?: number;
  unit?: string;
  interval?: number;
}) {
  return (
    <div style={{ height }} className="w-full min-w-0">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data} margin={{ top: 4, right: 4, left: -24, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--color-border)" />
          <XAxis dataKey="label" tick={AXIS} tickLine={false} axisLine={false} interval={interval} />
          <YAxis tick={AXIS} tickLine={false} axisLine={false} allowDecimals={false} />
          <Tooltip
            contentStyle={TOOLTIP_STYLE}
            cursor={{ fill: "var(--color-accent)" }}
            formatter={(v, name) => [`${v}${unit}`, name]}
          />
          {series.length > 1 && <Legend wrapperStyle={{ fontSize: 12 }} iconType="circle" iconSize={8} />}
          {series.map((s) => (
            <Bar key={s.key} dataKey={s.key} name={s.label} fill={s.color} radius={[4, 4, 0, 0]} maxBarSize={28} isAnimationActive={false} />
          ))}
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

/** Streak history: one bar per run (clean run / met streak), oldest → newest. */
export function StreakHistoryChart({
  runs,
  color,
  unit,
}: {
  runs: { label: string; length: number; range: string; ongoing: boolean }[];
  color: string;
  unit: string;
}) {
  return (
    <div className="h-52 w-full min-w-0">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={runs} margin={{ top: 4, right: 4, left: -24, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--color-border)" />
          <XAxis dataKey="label" tick={AXIS} tickLine={false} axisLine={false} minTickGap={8} />
          <YAxis tick={AXIS} tickLine={false} axisLine={false} allowDecimals={false} />
          <Tooltip
            contentStyle={TOOLTIP_STYLE}
            cursor={{ fill: "var(--color-accent)" }}
            labelFormatter={(_, p) => (p?.[0]?.payload as { range?: string } | undefined)?.range ?? ""}
            formatter={(v, _n, p) => [`${v} ${unit}${(p?.payload as { ongoing?: boolean })?.ongoing ? " (berjalan)" : ""}`, "Streak"]}
          />
          <Bar dataKey="length" name="Streak" fill={color} radius={[4, 4, 0, 0]} maxBarSize={36} isAnimationActive={false} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
