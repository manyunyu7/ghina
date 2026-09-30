"use client";

import * as React from "react";
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import type { KillaUsageDay } from "@/lib/killa";

const BAR = "#6366f1"; // --color-primary: one hue for magnitude
const nf = new Intl.NumberFormat("id-ID");
const usd = (v: number) => `$${v.toFixed(v >= 10 ? 2 : 3)}`;

function label(date: string) {
  const [, m, d] = date.split("-");
  return d && m ? `${Number(d)}/${Number(m)}` : date;
}

/** Estimated cost per day (oldest first); tooltip adds turns and tokens. */
export function UsageBars({ days }: { days: KillaUsageDay[] }) {
  const data = days.map((d) => ({ ...d, label: label(d.date) }));
  return (
    <ResponsiveContainer width="100%" height={240}>
      <BarChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }} barCategoryGap="20%">
        <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--color-border)" />
        <XAxis dataKey="label" tickLine={false} axisLine={false} interval="preserveStartEnd" tick={{ fill: "var(--color-muted)", fontSize: 11 }} />
        <YAxis tickLine={false} axisLine={false} width={52} tick={{ fill: "var(--color-muted)", fontSize: 11 }} tickFormatter={usd} />
        <Tooltip
          cursor={{ fill: "var(--color-accent)", opacity: 0.5 }}
          content={({ active, payload }) => {
            if (!active || !payload?.length) return null;
            const p = payload[0].payload as KillaUsageDay & { label: string };
            return (
              <div className="rounded-lg border border-border bg-card px-3 py-2 text-xs shadow-sm">
                <p className="mb-0.5 font-medium text-foreground">{p.date}</p>
                <p className="text-muted">
                  Biaya: <b className="text-foreground">{usd(p.costUsd)}</b>
                </p>
                <p className="text-muted">{nf.format(p.turns)} turn</p>
                <p className="text-muted">
                  {nf.format(p.inputTokens + p.cacheReadTokens + p.cacheCreationTokens)} in · {nf.format(p.outputTokens)} out
                </p>
              </div>
            );
          }}
        />
        <Bar dataKey="costUsd" fill={BAR} radius={[4, 4, 0, 0]} maxBarSize={24} />
      </BarChart>
    </ResponsiveContainer>
  );
}
