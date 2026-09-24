"use client";

import * as React from "react";
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";

const BAR = "#6366f1"; // --color-primary: one hue for magnitude

export type AvgPoint = { label: string; value: number | null; posts: number; withMetrics: number };

function Box({ children }: { children: React.ReactNode }) {
  return <div className="rounded-lg border border-border bg-card px-3 py-2 text-xs shadow-sm">{children}</div>;
}

/** Single-series bar chart of an average (views / engagement / rate) per group. */
export function AverageBars({
  data,
  format,
  metricLabel,
  height = 240,
}: {
  data: AvgPoint[];
  format: (v: number) => string;
  metricLabel: string;
  height?: number;
}) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }} barCategoryGap="20%">
        <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--color-border)" />
        <XAxis dataKey="label" tickLine={false} axisLine={false} interval="preserveStartEnd" tick={{ fill: "var(--color-muted)", fontSize: 11 }} />
        <YAxis tickLine={false} axisLine={false} width={48} tick={{ fill: "var(--color-muted)", fontSize: 11 }} tickFormatter={format} />
        <Tooltip
          cursor={{ fill: "var(--color-accent)", opacity: 0.5 }}
          content={({ active, payload }) => {
            if (!active || !payload?.length) return null;
            const p = payload[0].payload as AvgPoint;
            return (
              <Box>
                <p className="mb-0.5 font-medium text-foreground">{p.label}</p>
                <p className="text-muted">
                  {metricLabel}: <b className="text-foreground">{p.value == null ? "—" : format(p.value)}</b>
                </p>
                <p className="text-muted">
                  {p.posts} posting · {p.withMetrics} dengan data
                </p>
              </Box>
            );
          }}
        />
        <Bar dataKey="value" fill={BAR} radius={[4, 4, 0, 0]} maxBarSize={36} />
      </BarChart>
    </ResponsiveContainer>
  );
}

/** Sponsor income per month. */
export function MonthBars({ data, format }: { data: { label: string; amount: number; count: number }[]; format: (v: number) => string }) {
  return (
    <ResponsiveContainer width="100%" height={200}>
      <BarChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
        <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--color-border)" />
        <XAxis dataKey="label" tickLine={false} axisLine={false} tick={{ fill: "var(--color-muted)", fontSize: 11 }} />
        <YAxis tickLine={false} axisLine={false} width={76} tick={{ fill: "var(--color-muted)", fontSize: 11 }} tickFormatter={format} />
        <Tooltip
          cursor={{ fill: "var(--color-accent)", opacity: 0.5 }}
          content={({ active, payload }) => {
            if (!active || !payload?.length) return null;
            const p = payload[0].payload as { label: string; amount: number; count: number };
            return (
              <Box>
                <p className="mb-0.5 font-medium text-foreground">{p.label}</p>
                <p className="text-muted">
                  <b className="text-foreground">{format(p.amount)}</b> · {p.count} sponsor
                </p>
              </Box>
            );
          }}
        />
        <Bar dataKey="amount" fill="#16a34a" radius={[4, 4, 0, 0]} maxBarSize={40} />
      </BarChart>
    </ResponsiveContainer>
  );
}
