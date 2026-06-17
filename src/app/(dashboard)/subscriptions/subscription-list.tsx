"use client";

import * as React from "react";
import type { Wallet, Category } from "@prisma/client";
import { Pencil, Trash2, Pause, Play, CalendarClock, CreditCard, Check } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/misc";
import { Modal } from "@/components/ui/modal";
import { CategoryIcon } from "@/components/icon";
import { formatCurrency, formatDate, cn } from "@/lib/utils";
import { cycleLabel, nextOccurrence, daysUntil } from "./presets";
import { SubscriptionForm, type SubscriptionFormData } from "./subscription-form";
import { deleteSubscription, toggleSubscription, markSubscriptionPaid } from "./actions";

type Sub = SubscriptionFormData;

export function SubscriptionList({
  subscriptions,
  wallets,
  categories,
  currency,
}: {
  subscriptions: Sub[];
  wallets: Wallet[];
  categories: Category[];
  currency: string;
}) {
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {subscriptions.map((s) => (
        <SubscriptionCard
          key={s.id}
          sub={s}
          wallets={wallets}
          categories={categories}
          currency={currency}
        />
      ))}
    </div>
  );
}

function SubscriptionCard({
  sub,
  wallets,
  categories,
  currency,
}: {
  sub: Sub;
  wallets: Wallet[];
  categories: Category[];
  currency: string;
}) {
  const [editing, setEditing] = React.useState(false);
  const [confirming, setConfirming] = React.useState(false);
  const [payError, setPayError] = React.useState<string | null>(null);
  const [pending, startTransition] = React.useTransition();

  const wallet = wallets.find((w) => w.id === sub.walletId);
  const upcoming = sub.active ? nextOccurrence(sub.nextBilling, sub.cycle) : new Date(sub.nextBilling);
  const days = daysUntil(upcoming);

  function runToggle() {
    const fd = new FormData();
    fd.set("id", sub.id);
    startTransition(async () => {
      await toggleSubscription(fd);
    });
  }
  function runDelete() {
    const fd = new FormData();
    fd.set("id", sub.id);
    startTransition(async () => {
      await deleteSubscription(fd);
      setConfirming(false);
    });
  }
  function runMarkPaid() {
    const fd = new FormData();
    fd.set("id", sub.id);
    setPayError(null);
    startTransition(async () => {
      const res = await markSubscriptionPaid(fd);
      if (!res.ok) setPayError(res.error ?? "Failed to record payment");
    });
  }

  const due =
    days < 0 ? "Overdue" : days === 0 ? "Today" : days === 1 ? "Tomorrow" : `in ${days} days`;

  return (
    <Card className={cn("p-4 transition", !sub.active && "opacity-60")}>
      <div className="flex items-start gap-3">
        <div
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl text-white"
          style={{ background: sub.color }}
        >
          <CategoryIcon name={sub.icon} className="h-5 w-5" />
        </div>

        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <p className="truncate font-semibold text-foreground">{sub.name}</p>
              <p className="text-sm text-muted">
                {formatCurrency(sub.amount, sub.currency || currency)}
                <span className="text-muted-soft"> {cycleLabel(sub.cycle)}</span>
              </p>
            </div>
            {!sub.active && <Badge>Paused</Badge>}
          </div>

          <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted">
            <span className="inline-flex items-center gap-1">
              <CalendarClock className="h-3.5 w-3.5" />
              {formatDate(upcoming)}
              {sub.active && (
                <span className={cn("ml-1 font-medium", days <= 3 ? "text-expense" : "text-muted-soft")}>· {due}</span>
              )}
            </span>
            {wallet && (
              <span className="inline-flex items-center gap-1">
                <CreditCard className="h-3.5 w-3.5" />
                {wallet.name}
              </span>
            )}
          </div>
        </div>
      </div>

      <div className="mt-3 flex items-center gap-1 border-t border-border-soft pt-3">
        {sub.active && (
          <Button variant="secondary" size="sm" onClick={runMarkPaid} disabled={pending}>
            <Check className="h-4 w-4" />
            {pending ? "Recording…" : "Mark paid"}
          </Button>
        )}
        <div className="ml-auto flex items-center gap-1">
          <Button variant="ghost" size="sm" onClick={runToggle} disabled={pending}>
            {sub.active ? <Pause className="h-4 w-4" /> : <Play className="h-4 w-4" />}
            {sub.active ? "Pause" : "Resume"}
          </Button>
          <Button variant="ghost" size="sm" onClick={() => setEditing(true)}>
            <Pencil className="h-4 w-4" />
            Edit
          </Button>
          <Button variant="ghost" size="icon" onClick={() => setConfirming(true)} aria-label="Delete">
            <Trash2 className="h-4 w-4 text-expense" />
          </Button>
        </div>
      </div>
      {payError && <p className="mt-2 text-xs text-expense">{payError}</p>}

      <SubscriptionForm
        open={editing}
        onClose={() => setEditing(false)}
        wallets={wallets}
        categories={categories}
        subscription={sub}
        defaultCurrency={currency}
      />

      <Modal
        open={confirming}
        onClose={() => setConfirming(false)}
        title="Delete subscription?"
        description={`“${sub.name}” will be removed. This only removes the reminder — it doesn't delete any transactions.`}
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
