"use client";

import * as React from "react";
import type { Wallet, Category } from "@prisma/client";
import { TrendingUp, ArrowDownCircle, ArrowUpCircle, Repeat, History, CalendarClock, NotebookPen } from "lucide-react";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/misc";
import { CategoryIcon } from "@/components/icon";
import { formatCurrency, formatDate, cn } from "@/lib/utils";
import { PlannedList } from "./planned-list";
import { AddPlannedButton } from "./add-planned-button";
import type { PlannedFormData } from "./planned-form";

type PlannedItem = PlannedFormData & { done: boolean };
type SubItem = { id: string; name: string; amount: number; currency: string; color: string; icon: string; date: string };
type AvgItem = { id: string; name: string; color: string; icon: string; avg: number };

type Source = "manual" | "subs" | "history";

export function ForecastView({
  plannedItems,
  subItems,
  averages,
  wallets,
  categories,
  currency,
  monthLabel,
  defaultDate,
  historyMonths,
}: {
  plannedItems: PlannedItem[];
  subItems: SubItem[];
  averages: AvgItem[];
  wallets: Wallet[];
  categories: Category[];
  currency: string;
  monthLabel: string;
  defaultDate: string;
  historyMonths: number;
}) {
  // History is off by default — it's only a rough estimate, not a commitment.
  const [active, setActive] = React.useState<Record<Source, boolean>>({
    manual: true,
    subs: true,
    history: false,
  });

  function toggle(source: Source) {
    setActive((prev) => ({ ...prev, [source]: !prev[source] }));
  }

  const plannedExpense = plannedItems.filter((p) => p.type === "expense").reduce((s, p) => s + p.amount, 0);
  const plannedIncome = plannedItems.filter((p) => p.type === "income").reduce((s, p) => s + p.amount, 0);
  const subsExpense = subItems.reduce((s, x) => s + x.amount, 0);
  const estExpense = averages.reduce((s, x) => s + x.avg, 0);

  const projectedExpense =
    (active.manual ? plannedExpense : 0) + (active.subs ? subsExpense : 0) + (active.history ? estExpense : 0);
  const projectedIncome = active.manual ? plannedIncome : 0;
  const net = projectedIncome - projectedExpense;

  const isEmpty = plannedItems.length === 0 && subItems.length === 0 && averages.length === 0;
  const nothingSelected = !active.manual && !active.subs && !active.history;

  const chips: { source: Source; label: string; count: number }[] = [
    { source: "manual", label: "Manual", count: plannedItems.length },
    { source: "subs", label: "Subscriptions", count: subItems.length },
    { source: "history", label: "History", count: averages.length },
  ];

  if (isEmpty) {
    return (
      <EmptyState
        icon={CalendarClock}
        title={`Nothing forecast for ${monthLabel} yet`}
        description="Add an expected bill, your salary, or a one-off you know is coming. Active subscriptions and your spending history will show up here automatically."
        action={<AddPlannedButton wallets={wallets} categories={categories} defaultDate={defaultDate} variant="primary" />}
      />
    );
  }

  return (
    <div>
      {/* Summary */}
      <div className="mb-6 grid gap-3 sm:grid-cols-3">
        <StatTile
          icon={<ArrowDownCircle className="h-5 w-5" />}
          label="Projected out"
          value={formatCurrency(projectedExpense, currency)}
          tint="bg-expense-soft text-expense"
        />
        <StatTile
          icon={<ArrowUpCircle className="h-5 w-5" />}
          label="Projected in"
          value={formatCurrency(projectedIncome, currency)}
          tint="bg-income-soft text-income"
        />
        <StatTile
          icon={<TrendingUp className="h-5 w-5" />}
          label="Projected net"
          value={`${net < 0 ? "-" : "+"}${formatCurrency(Math.abs(net), currency)}`}
          tint={net < 0 ? "bg-expense-soft text-expense" : "bg-primary-soft text-primary"}
        />
      </div>

      {/* Source toggles — tap to show/hide each source. */}
      <div className="mb-6 flex flex-wrap gap-2">
        {chips.map((c) => {
          const on = active[c.source];
          return (
            <button
              type="button"
              key={c.source}
              onClick={() => toggle(c.source)}
              aria-pressed={on}
              className={cn(
                "inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium transition",
                on
                  ? "border-transparent bg-primary text-white"
                  : "border-border bg-surface text-muted hover:bg-accent",
              )}
            >
              {c.label}
              <span
                className={cn(
                  "rounded-full px-1.5 text-[10px] tabular-nums",
                  on ? "bg-white/20" : "bg-accent text-muted",
                )}
              >
                {c.count}
              </span>
            </button>
          );
        })}
      </div>

      {nothingSelected ? (
        <Card className="p-4 text-sm text-muted">Pick a source above to see your forecast.</Card>
      ) : (
        <div className="space-y-8">
          {/* Manual — Tier 3 */}
          {active.manual && (
            <Section
              title="Your planned items"
              hint="Things you've noted down. These don't affect your wallet balances."
              icon={<NotebookPen className="h-4 w-4" />}
            >
              {plannedItems.length > 0 ? (
                <PlannedList items={plannedItems} wallets={wallets} categories={categories} currency={currency} />
              ) : (
                <Card className="p-4 text-sm text-muted">
                  No planned items for {monthLabel} yet. Use “Add planned item” to jot one down.
                </Card>
              )}
            </Section>
          )}

          {/* Subscriptions — Tier 1 */}
          {active.subs && subItems.length > 0 && (
            <Section
              title="From your subscriptions"
              hint="Recurring payments that fall in this month, based on their billing cycle."
              icon={<Repeat className="h-4 w-4" />}
            >
              <Card className="divide-y divide-border-soft p-0">
                {subItems.map((s) => (
                  <ReadonlyRow
                    key={s.id}
                    color={s.color}
                    icon={s.icon}
                    title={s.name}
                    date={formatDate(s.date)}
                    amount={`-${formatCurrency(s.amount, s.currency || currency)}`}
                  />
                ))}
              </Card>
            </Section>
          )}

          {/* History — Tier 2 */}
          {active.history && averages.length > 0 && (
            <Section
              title="Estimated from history"
              hint={`Typical spend per category, averaged over the last ${historyMonths} months. A rough guide, not a commitment.`}
              icon={<History className="h-4 w-4" />}
            >
              <Card className="divide-y divide-border-soft p-0">
                {averages.map((a) => (
                  <ReadonlyRow
                    key={a.id}
                    color={a.color}
                    icon={a.icon}
                    title={a.name}
                    date="avg / month"
                    amount={`~${formatCurrency(a.avg, currency)}`}
                  />
                ))}
              </Card>
            </Section>
          )}
        </div>
      )}
    </div>
  );
}

function Section({
  title,
  hint,
  icon,
  children,
}: {
  title: string;
  hint?: string;
  icon?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section>
      <div className="mb-3">
        <h2 className="flex items-center gap-2 text-sm font-semibold text-foreground">
          {icon}
          {title}
        </h2>
        {hint && <p className="mt-0.5 text-xs text-muted">{hint}</p>}
      </div>
      {children}
    </section>
  );
}

function ReadonlyRow({
  color,
  icon,
  title,
  date,
  amount,
}: {
  color: string;
  icon: string;
  title: string;
  date: string;
  amount: string;
}) {
  return (
    <div className="flex items-center gap-3 p-3">
      <div
        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-white"
        style={{ background: color }}
      >
        <CategoryIcon name={icon} className="h-4 w-4" />
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium text-foreground">{title}</p>
        <p className="text-xs text-muted">{date}</p>
      </div>
      <p className="shrink-0 text-sm font-medium tabular-nums text-expense">{amount}</p>
    </div>
  );
}

function StatTile({
  icon,
  label,
  value,
  tint,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  tint: string;
}) {
  return (
    <Card className="p-4">
      <div className={cn("mb-3 flex h-9 w-9 items-center justify-center rounded-lg", tint)}>{icon}</div>
      <p className="text-sm text-muted">{label}</p>
      <p className="truncate text-xl font-bold text-foreground">{value}</p>
    </Card>
  );
}
