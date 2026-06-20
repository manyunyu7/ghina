"use client";

import * as React from "react";
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  CartesianGrid,
  XAxis,
  YAxis,
  Tooltip,
  Legend,
  PieChart,
  Pie,
  Cell,
  AreaChart,
  Area,
} from "recharts";
import { formatCompactCurrency, formatCurrency } from "@/lib/utils";

const INCOME = "#16a34a";
const EXPENSE = "#ef4444";
const PRIMARY = "#6366f1";

type MonthlyPoint = { month: string; income: number; expense: number };
type CashflowPoint = { month: string; net: number };
type DonutSlice = { name: string; value: number; color: string };

function axisCurrency(currency: string) {
  return (value: number) => formatCompactCurrency(value, currency);
}

/** Shared tooltip styling matching the design tokens. */
function TooltipBox({ children }: { children: React.ReactNode }) {
  return (
    <div className="rounded-lg border border-border bg-card px-3 py-2 text-xs shadow-sm">
      {children}
    </div>
  );
}

/* ---------------------------- Income vs Expense ---------------------------- */

export function IncomeExpenseChart({
  data,
  currency,
}: {
  data: MonthlyPoint[];
  currency: string;
}) {
  return (
    <ResponsiveContainer width="100%" height={300}>
      <BarChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
        <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--color-border)" />
        <XAxis
          dataKey="month"
          tickLine={false}
          axisLine={false}
          tick={{ fill: "var(--color-muted)", fontSize: 12 }}
        />
        <YAxis
          tickLine={false}
          axisLine={false}
          width={56}
          tick={{ fill: "var(--color-muted)", fontSize: 12 }}
          tickFormatter={axisCurrency(currency)}
        />
        <Tooltip
          cursor={{ fill: "var(--color-accent)", opacity: 0.4 }}
          content={({ active, payload, label }) => {
            if (!active || !payload?.length) return null;
            return (
              <TooltipBox>
                <p className="mb-1 font-medium text-foreground">{label}</p>
                {payload.map((p) => (
                  <p key={p.dataKey as string} className="text-muted">
                    <span
                      className="mr-1.5 inline-block h-2 w-2 rounded-full align-middle"
                      style={{ background: p.color }}
                    />
                    {p.name}: {formatCurrency(Number(p.value), currency)}
                  </p>
                ))}
              </TooltipBox>
            );
          }}
        />
        <Legend
          iconType="circle"
          wrapperStyle={{ fontSize: 12, paddingTop: 8, color: "var(--color-muted)" }}
        />
        <Bar dataKey="income" name="Income" fill={INCOME} radius={[4, 4, 0, 0]} maxBarSize={36} />
        <Bar dataKey="expense" name="Expense" fill={EXPENSE} radius={[4, 4, 0, 0]} maxBarSize={36} />
      </BarChart>
    </ResponsiveContainer>
  );
}

/* ------------------------------ Category donut ----------------------------- */

export function CategoryDonut({
  data,
  currency,
}: {
  data: DonutSlice[];
  currency: string;
}) {
  const total = data.reduce((sum, d) => sum + d.value, 0);

  return (
    <div className="flex flex-col items-center gap-4 sm:flex-row">
      <div className="relative h-[220px] w-full max-w-[240px] shrink-0">
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={data}
              dataKey="value"
              nameKey="name"
              cx="50%"
              cy="50%"
              innerRadius={62}
              outerRadius={92}
              paddingAngle={2}
              stroke="var(--color-card)"
              strokeWidth={2}
            >
              {data.map((slice) => (
                <Cell key={slice.name} fill={slice.color} />
              ))}
            </Pie>
            <Tooltip
              content={({ active, payload }) => {
                if (!active || !payload?.length) return null;
                const p = payload[0];
                const value = Number(p.value);
                const pct = total > 0 ? Math.round((value / total) * 100) : 0;
                return (
                  <TooltipBox>
                    <p className="font-medium text-foreground">{p.name}</p>
                    <p className="text-muted">
                      {formatCurrency(value, currency)} · {pct}%
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
            {formatCompactCurrency(total, currency)}
          </span>
        </div>
      </div>

      <ul className="flex w-full min-w-0 flex-col gap-2">
        {data.map((slice) => {
          const pct = total > 0 ? Math.round((slice.value / total) * 100) : 0;
          return (
            <li key={slice.name} className="flex items-center gap-2 text-sm">
              <span
                className="h-2.5 w-2.5 shrink-0 rounded-full"
                style={{ background: slice.color }}
              />
              <span className="min-w-0 flex-1 truncate text-foreground">{slice.name}</span>
              <span className="shrink-0 tabular-nums text-muted">
                {formatCurrency(slice.value, currency)}
              </span>
              <span className="w-9 shrink-0 text-right tabular-nums text-muted-soft">{pct}%</span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

/* ----------------------------- Cashflow trend ------------------------------ */

export function CashflowChart({
  data,
  currency,
}: {
  data: CashflowPoint[];
  currency: string;
}) {
  return (
    <ResponsiveContainer width="100%" height={240}>
      <AreaChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
        <defs>
          <linearGradient id="netGradient" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={PRIMARY} stopOpacity={0.3} />
            <stop offset="100%" stopColor={PRIMARY} stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--color-border)" />
        <XAxis
          dataKey="month"
          tickLine={false}
          axisLine={false}
          tick={{ fill: "var(--color-muted)", fontSize: 12 }}
        />
        <YAxis
          tickLine={false}
          axisLine={false}
          width={56}
          tick={{ fill: "var(--color-muted)", fontSize: 12 }}
          tickFormatter={axisCurrency(currency)}
        />
        <Tooltip
          content={({ active, payload, label }) => {
            if (!active || !payload?.length) return null;
            const value = Number(payload[0].value);
            return (
              <TooltipBox>
                <p className="mb-0.5 font-medium text-foreground">{label}</p>
                <p className={value >= 0 ? "text-income" : "text-expense"}>
                  Net: {formatCurrency(value, currency)}
                </p>
              </TooltipBox>
            );
          }}
        />
        <Area
          type="monotone"
          dataKey="net"
          name="Net cashflow"
          stroke={PRIMARY}
          strokeWidth={2}
          fill="url(#netGradient)"
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}
