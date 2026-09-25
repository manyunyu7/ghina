"use client";

import {
  PieChart,
  Pie,
  Cell,
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
} from "recharts";
import { Money } from "@/components/money/money";
import { useMoneyFormat } from "@/components/money/balance-privacy";

export type DonutSlice = { name: string; value: number; color: string };
export type MonthlyBar = { month: string; income: number; expense: number };

const TOOLTIP_STYLE: React.CSSProperties = {
  borderRadius: 12,
  border: "1px solid var(--color-border)",
  background: "var(--color-card)",
  fontSize: 12,
  color: "var(--color-foreground)",
  boxShadow: "0 4px 16px rgba(0,0,0,0.08)",
};

export function SpendingDonut({
  data,
  currency,
  total,
}: {
  data: DonutSlice[];
  currency: string;
  total: number;
}) {
  const money = useMoneyFormat();
  return (
    <div className="flex flex-col items-center gap-5 sm:flex-row">
      <div className="relative h-44 w-44 shrink-0">
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={data}
              dataKey="value"
              nameKey="name"
              cx="50%"
              cy="50%"
              innerRadius={56}
              outerRadius={80}
              paddingAngle={2}
              stroke="none"
            >
              {data.map((slice, i) => (
                <Cell key={i} fill={slice.color} />
              ))}
            </Pie>
            <Tooltip
              contentStyle={TOOLTIP_STYLE}
              formatter={(value) => money.format(Number(value), currency)}
            />
          </PieChart>
        </ResponsiveContainer>
        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-xs text-muted">Spent</span>
          <span className="text-sm font-bold text-foreground">
            <Money amount={total} currency={currency} compact />
          </span>
        </div>
      </div>

      <ul className="flex-1 space-y-2 self-stretch">
        {data.map((slice, i) => {
          const pct = total > 0 ? Math.round((slice.value / total) * 100) : 0;
          return (
            <li key={i} className="flex items-center gap-2.5 text-sm">
              <span
                className="h-2.5 w-2.5 shrink-0 rounded-full"
                style={{ background: slice.color }}
              />
              <span className="min-w-0 flex-1 truncate text-foreground">{slice.name}</span>
              <span className="text-xs text-muted">{pct}%</span>
              <span className="w-20 text-right text-xs font-medium text-foreground">
                <Money amount={slice.value} currency={currency} compact />
              </span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

export function IncomeExpenseBars({
  data,
  currency,
}: {
  data: MonthlyBar[];
  currency: string;
}) {
  const money = useMoneyFormat();
  return (
    <div className="h-64 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data} barGap={4} margin={{ top: 8, right: 4, left: 4, bottom: 0 }}>
          <CartesianGrid vertical={false} stroke="var(--color-border)" strokeDasharray="3 3" />
          <XAxis
            dataKey="month"
            tickLine={false}
            axisLine={false}
            tick={{ fontSize: 12, fill: "var(--color-muted)" }}
          />
          <YAxis
            tickLine={false}
            axisLine={false}
            width={48}
            tick={{ fontSize: 11, fill: "var(--color-muted)" }}
            tickFormatter={(v: number) => money.axis(v, currency)}
          />
          <Tooltip
            cursor={{ fill: "var(--color-accent)", opacity: 0.5 }}
            contentStyle={TOOLTIP_STYLE}
            formatter={(value, name) => [
              money.format(Number(value), currency),
              name === "income" ? "Income" : "Expense",
            ]}
          />
          <Bar dataKey="income" fill="var(--color-income)" radius={[4, 4, 0, 0]} maxBarSize={28} />
          <Bar dataKey="expense" fill="var(--color-expense)" radius={[4, 4, 0, 0]} maxBarSize={28} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
