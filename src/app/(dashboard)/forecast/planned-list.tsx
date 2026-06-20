"use client";

import * as React from "react";
import type { Wallet, Category } from "@prisma/client";
import { Pencil, Trash2, Check, CalendarClock, Wallet as WalletIcon } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { CategoryIcon } from "@/components/icon";
import { formatCurrency, formatDate, cn } from "@/lib/utils";
import { PlannedForm, type PlannedFormData } from "./planned-form";
import { deletePlanned, togglePlannedDone } from "./actions";

type Item = PlannedFormData & { done: boolean };

export function PlannedList({
  items,
  wallets,
  categories,
  currency,
}: {
  items: Item[];
  wallets: Wallet[];
  categories: Category[];
  currency: string;
}) {
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {items.map((item) => (
        <PlannedCard
          key={item.id}
          item={item}
          wallets={wallets}
          categories={categories}
          currency={currency}
        />
      ))}
    </div>
  );
}

function PlannedCard({
  item,
  wallets,
  categories,
  currency,
}: {
  item: Item;
  wallets: Wallet[];
  categories: Category[];
  currency: string;
}) {
  const [editing, setEditing] = React.useState(false);
  const [confirming, setConfirming] = React.useState(false);
  const [pending, startTransition] = React.useTransition();

  const done = item.done;
  const isExpense = item.type === "expense";
  const category = categories.find((c) => c.id === item.categoryId);
  const wallet = wallets.find((w) => w.id === item.walletId);

  function runToggle() {
    const fd = new FormData();
    fd.set("id", item.id);
    startTransition(async () => {
      await togglePlannedDone(fd);
    });
  }
  function runDelete() {
    const fd = new FormData();
    fd.set("id", item.id);
    startTransition(async () => {
      await deletePlanned(fd);
      setConfirming(false);
    });
  }

  return (
    <Card className={cn("p-4 transition", done && "opacity-60")}>
      <div className="flex items-start gap-3">
        <div
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl text-white"
          style={{ background: category?.color ?? (isExpense ? "#ef4444" : "#22c55e") }}
        >
          <CategoryIcon name={category?.icon ?? "circle"} className="h-5 w-5" />
        </div>

        <div className="min-w-0 flex-1">
          <p className={cn("truncate font-semibold text-foreground", done && "line-through")}>
            {item.note || (isExpense ? "Expense" : "Income")}
          </p>
          <p className={cn("text-sm font-medium", isExpense ? "text-expense" : "text-income")}>
            {isExpense ? "-" : "+"}
            {formatCurrency(item.amount, currency)}
          </p>

          <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted">
            <span className="inline-flex items-center gap-1">
              <CalendarClock className="h-3.5 w-3.5" />
              {formatDate(item.date)}
            </span>
            {category && <span>{category.name}</span>}
            {wallet && (
              <span className="inline-flex items-center gap-1">
                <WalletIcon className="h-3.5 w-3.5" />
                {wallet.name}
              </span>
            )}
          </div>
        </div>
      </div>

      <div className="mt-3 flex items-center gap-1 border-t border-border-soft pt-3">
        <Button variant={done ? "secondary" : "ghost"} size="sm" onClick={runToggle} disabled={pending}>
          <Check className="h-4 w-4" />
          {done ? "Done" : "Mark done"}
        </Button>
        <div className="ml-auto flex items-center gap-1">
          <Button variant="ghost" size="sm" onClick={() => setEditing(true)}>
            <Pencil className="h-4 w-4" />
            Edit
          </Button>
          <Button variant="ghost" size="icon" onClick={() => setConfirming(true)} aria-label="Delete">
            <Trash2 className="h-4 w-4 text-expense" />
          </Button>
        </div>
      </div>

      <PlannedForm
        open={editing}
        onClose={() => setEditing(false)}
        wallets={wallets}
        categories={categories}
        planned={item}
      />

      <Modal
        open={confirming}
        onClose={() => setConfirming(false)}
        title="Delete planned item?"
        description={`“${item.note || "This item"}” will be removed from your forecast.`}
      >
        <div className="flex justify-end gap-2">
          <Button variant="outline" onClick={() => setConfirming(false)} disabled={pending}>
            Cancel
          </Button>
          <Button variant="danger" onClick={runDelete} disabled={pending}>
            {pending ? "Deleting…" : "Delete"}
          </Button>
        </div>
      </Modal>
    </Card>
  );
}
