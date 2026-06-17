"use client";

import * as React from "react";
import type { Wallet, Category } from "@prisma/client";
import { ChevronDown, Check } from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Input, Select, Field } from "@/components/ui/input";
import { CategoryIcon } from "@/components/icon";
import { COLOR_PALETTE, CATEGORY_ICONS } from "@/lib/constants";
import { cn } from "@/lib/utils";
import { CYCLES, SUBSCRIPTION_PRESETS, type Cycle } from "./presets";
import { createSubscription, updateSubscription } from "./actions";

export type SubscriptionFormData = {
  id: string;
  name: string;
  amount: number;
  currency: string;
  cycle: string;
  nextBilling: Date | string;
  categoryId: string | null;
  walletId: string | null;
  color: string;
  icon: string;
  note: string | null;
  active: boolean;
};

function toDateInput(value: Date | string | undefined): string {
  const d = value ? new Date(value) : new Date();
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60_000).toISOString().slice(0, 10);
}

export function SubscriptionForm({
  open,
  onClose,
  wallets,
  categories,
  subscription,
  defaultCurrency,
}: {
  open: boolean;
  onClose: () => void;
  wallets: Wallet[];
  categories: Category[];
  subscription?: SubscriptionFormData;
  defaultCurrency: string;
}) {
  const isEdit = Boolean(subscription);
  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEdit ? "Edit subscription" : "Add subscription"}
      description={isEdit ? "Update this subscription." : "Track a recurring payment like Netflix or Spotify."}
    >
      {open && (
        <FormBody
          wallets={wallets}
          categories={categories}
          subscription={subscription}
          defaultCurrency={defaultCurrency}
          onClose={onClose}
        />
      )}
    </Modal>
  );
}

function FormBody({
  wallets,
  categories,
  subscription,
  defaultCurrency,
  onClose,
}: {
  wallets: Wallet[];
  categories: Category[];
  subscription?: SubscriptionFormData;
  defaultCurrency: string;
  onClose: () => void;
}) {
  const isEdit = Boolean(subscription);
  const expenseCategories = categories.filter((c) => c.type === "expense");

  const [name, setName] = React.useState(subscription?.name ?? "");
  const [cycle, setCycle] = React.useState<Cycle>((subscription?.cycle as Cycle) ?? "monthly");
  const [color, setColor] = React.useState(subscription?.color ?? "#6366f1");
  const [icon, setIcon] = React.useState(subscription?.icon ?? "credit-card");
  const [active, setActive] = React.useState(subscription?.active ?? true);
  const [showMore, setShowMore] = React.useState(false);
  const [submitting, setSubmitting] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  function applyPreset(p: (typeof SUBSCRIPTION_PRESETS)[number]) {
    setName(p.name);
    setCycle(p.cycle);
    setColor(p.color);
    setIcon(p.icon);
  }

  async function handleAction(formData: FormData) {
    setSubmitting(true);
    setError(null);
    const res = isEdit ? await updateSubscription(formData) : await createSubscription(formData);
    if (res.ok) {
      onClose();
    } else {
      setError(res.error ?? "Something went wrong");
      setSubmitting(false);
    }
  }

  return (
    <form action={handleAction} className="space-y-4">
      {isEdit && subscription && <input type="hidden" name="id" value={subscription.id} />}
      <input type="hidden" name="color" value={color} />
      <input type="hidden" name="icon" value={icon} />
      <input type="hidden" name="active" value={active ? "true" : "false"} />

      {/* Presets (create only) */}
      {!isEdit && (
        <div>
          <p className="mb-2 text-sm font-medium text-foreground">Quick pick</p>
          <div className="flex flex-wrap gap-2">
            {SUBSCRIPTION_PRESETS.map((p) => (
              <button
                type="button"
                key={p.name}
                onClick={() => applyPreset(p)}
                className={cn(
                  "flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium transition",
                  name === p.name
                    ? "border-transparent text-white"
                    : "border-border bg-surface text-foreground hover:bg-accent",
                )}
                style={name === p.name ? { background: p.color } : undefined}
              >
                <CategoryIcon name={p.icon} className="h-3.5 w-3.5" />
                {p.name}
              </button>
            ))}
          </div>
        </div>
      )}

      <Field label="Name">
        <Input
          name="name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="e.g. Netflix"
          required
        />
      </Field>

      <div className="grid grid-cols-2 gap-3">
        <Field label="Amount">
          <Input
            name="amount"
            type="number"
            inputMode="decimal"
            step="any"
            min="0"
            required
            placeholder="0"
            defaultValue={subscription ? String(subscription.amount) : ""}
          />
        </Field>
        <Field label="Billing cycle">
          <Select name="cycle" value={cycle} onChange={(e) => setCycle(e.target.value as Cycle)}>
            {CYCLES.map((c) => (
              <option key={c.value} value={c.value}>
                {c.label}
              </option>
            ))}
          </Select>
        </Field>
      </div>

      <Field label="Next billing date">
        <Input name="nextBilling" type="date" required defaultValue={toDateInput(subscription?.nextBilling)} />
      </Field>

      <Field label="Paid with">
        <Select name="walletId" defaultValue={subscription?.walletId ?? ""}>
          <option value="">— None —</option>
          {wallets.map((w) => (
            <option key={w.id} value={w.id}>
              {w.name}
            </option>
          ))}
        </Select>
        {wallets.length === 0 && (
          <p className="mt-1 text-xs text-muted">
            Tip: create a wallet named “GoPay”, “OVO”, or your card on the Wallets page to pick it here.
          </p>
        )}
      </Field>

      {/* Hidden currency follows the user's default */}
      <input type="hidden" name="currency" value={subscription?.currency ?? defaultCurrency} />

      {/* More options */}
      <button
        type="button"
        onClick={() => setShowMore((v) => !v)}
        className="flex items-center gap-1 text-sm font-medium text-muted hover:text-foreground"
      >
        <ChevronDown className={cn("h-4 w-4 transition", showMore && "rotate-180")} />
        More options
      </button>

      {showMore && (
        <div className="space-y-4 rounded-lg border border-border-soft bg-background p-3">
          <Field label="Category">
            <Select name="categoryId" defaultValue={subscription?.categoryId ?? ""}>
              <option value="">Uncategorized</option>
              {expenseCategories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          </Field>

          <Field label="Color">
            <div className="flex flex-wrap gap-2">
              {COLOR_PALETTE.map((c) => (
                <button
                  type="button"
                  key={c}
                  onClick={() => setColor(c)}
                  className={cn(
                    "flex h-7 w-7 items-center justify-center rounded-full transition",
                    color === c && "ring-2 ring-offset-2 ring-foreground/30",
                  )}
                  style={{ background: c }}
                  aria-label={`Color ${c}`}
                >
                  {color === c && <Check className="h-3.5 w-3.5 text-white" />}
                </button>
              ))}
            </div>
          </Field>

          <Field label="Icon">
            <div className="grid grid-cols-8 gap-1.5">
              {CATEGORY_ICONS.map((ic) => (
                <button
                  type="button"
                  key={ic}
                  onClick={() => setIcon(ic)}
                  className={cn(
                    "flex h-8 w-8 items-center justify-center rounded-lg border transition",
                    icon === ic ? "border-primary bg-primary-soft text-primary" : "border-border text-muted hover:bg-accent",
                  )}
                  aria-label={ic}
                >
                  <CategoryIcon name={ic} className="h-4 w-4" />
                </button>
              ))}
            </div>
          </Field>

          <Field label="Note">
            <Input name="note" placeholder="Optional" defaultValue={subscription?.note ?? ""} />
          </Field>

          {isEdit && (
            <label className="flex items-center gap-2 text-sm text-foreground">
              <input
                type="checkbox"
                checked={active}
                onChange={(e) => setActive(e.target.checked)}
                className="h-4 w-4 rounded border-border"
              />
              Active
            </label>
          )}
        </div>
      )}

      {error && <p className="text-sm text-expense">{error}</p>}

      <div className="flex justify-end gap-2 pt-1">
        <Button type="button" variant="outline" onClick={onClose} disabled={submitting}>
          Cancel
        </Button>
        <Button type="submit" disabled={submitting}>
          {submitting ? "Saving…" : isEdit ? "Save changes" : "Add subscription"}
        </Button>
      </div>
    </form>
  );
}
