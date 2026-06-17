"use client";

import * as React from "react";
import { ChevronDown, Receipt } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Badge, Progress } from "@/components/ui/misc";
import { CategoryIcon } from "@/components/icon";
import { formatCurrency, formatDate, cn } from "@/lib/utils";
import { BudgetActions } from "./budget-actions";
import type { BudgetEditData } from "./budget-form";

export type BudgetTx = { id: string; note: string | null; amount: number; date: string };

export function BudgetCard({
  editData,
  spent,
  remaining,
  pct,
  over,
  currency,
  month,
  year,
  transactions,
}: {
  editData: BudgetEditData;
  spent: number;
  remaining: number;
  pct: number;
  over: boolean;
  currency: string;
  month: number;
  year: number;
  transactions: BudgetTx[];
}) {
  const [open, setOpen] = React.useState(false);
  const { categoryName, categoryColor, categoryIcon, amount } = editData;
  const count = transactions.length;

  return (
    <Card>
      <CardContent className="space-y-3 p-4">
        <div className="flex items-center gap-3">
          <div
            className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full"
            style={{ background: `${categoryColor}1a`, color: categoryColor }}
          >
            <CategoryIcon name={categoryIcon} className="h-5 w-5" />
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <p className="truncate font-medium text-foreground">{categoryName}</p>
              {over && <Badge variant="expense">Over budget</Badge>}
            </div>
            <p className="mt-0.5 text-xs text-muted">
              {formatCurrency(spent, currency)} of {formatCurrency(amount, currency)}
            </p>
          </div>
          <BudgetActions budget={editData} month={month} year={year} />
        </div>

        <Progress value={pct} color={categoryColor} />

        <div className="flex items-center justify-between text-xs">
          <span className="text-muted">{Math.round(pct)}% used</span>
          <span
            className={cn(
              "font-medium tabular-nums",
              remaining < 0 ? "text-expense" : "text-income",
            )}
          >
            {remaining < 0
              ? `${formatCurrency(Math.abs(remaining), currency)} over`
              : `${formatCurrency(remaining, currency)} left`}
          </span>
        </div>

        {/* Expected vs Actual variance, made explicit */}
        <div className="grid grid-cols-3 gap-2 rounded-lg bg-background px-3 py-2 text-center">
          <div>
            <p className="text-[11px] text-muted-soft">Expected</p>
            <p className="text-xs font-semibold tabular-nums text-foreground">{formatCurrency(amount, currency)}</p>
          </div>
          <div>
            <p className="text-[11px] text-muted-soft">Actual</p>
            <p className="text-xs font-semibold tabular-nums text-foreground">{formatCurrency(spent, currency)}</p>
          </div>
          <div>
            <p className="text-[11px] text-muted-soft">Difference</p>
            <p
              className={cn(
                "text-xs font-semibold tabular-nums",
                spent > amount ? "text-expense" : "text-income",
              )}
            >
              {spent > amount ? "+" : "−"}
              {formatCurrency(Math.abs(spent - amount), currency)}
            </p>
          </div>
        </div>

        {/* Breakdown of the small transactions that make up this budget */}
        {count > 0 && (
          <div>
            <button
              type="button"
              onClick={() => setOpen((v) => !v)}
              className="flex w-full items-center justify-between rounded-lg px-1 py-1.5 text-xs font-medium text-muted transition hover:text-foreground"
            >
              <span className="inline-flex items-center gap-1.5">
                <Receipt className="h-3.5 w-3.5" />
                {count} {count === 1 ? "transaction" : "transactions"}
              </span>
              <ChevronDown className={cn("h-4 w-4 transition", open && "rotate-180")} />
            </button>

            {open && (
              <ul className="mt-1 divide-y divide-border-soft border-t border-border-soft">
                {transactions.map((t) => (
                  <li key={t.id} className="flex items-center justify-between gap-3 py-2 text-sm">
                    <div className="min-w-0">
                      <p className="truncate text-foreground">{t.note?.trim() || categoryName}</p>
                      <p className="text-xs text-muted-soft">{formatDate(t.date)}</p>
                    </div>
                    <span className="shrink-0 tabular-nums text-expense">
                      −{formatCurrency(t.amount, currency)}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
