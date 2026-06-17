"use client";

import * as React from "react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Input, Select, Field, Label } from "@/components/ui/input";
import { cn, CURRENCIES } from "@/lib/utils";
import { COLOR_PALETTE, WALLET_TYPES } from "@/lib/constants";
import { Check } from "lucide-react";
import { createWallet, updateWallet, type WalletActionResult } from "./actions";

export type WalletFormData = {
  id: string;
  name: string;
  type: string;
  balance: number;
  currency: string;
  color: string;
};

export function WalletForm({
  open,
  onClose,
  wallet,
  defaultCurrency,
}: {
  open: boolean;
  onClose: () => void;
  /** When provided, the form edits this wallet; otherwise it creates a new one. */
  wallet?: WalletFormData;
  defaultCurrency: string;
}) {
  const isEdit = Boolean(wallet);

  const [type, setType] = React.useState(wallet?.type ?? WALLET_TYPES[0].value);
  const [color, setColor] = React.useState(wallet?.color ?? COLOR_PALETTE[0]);
  const [error, setError] = React.useState<string | null>(null);
  const [pending, setPending] = React.useState(false);

  // Reset local state during render whenever the modal is (re)opened or the target
  // wallet changes — the React-recommended alternative to syncing via an effect.
  const instanceKey = `${open ? "open" : "closed"}:${wallet?.id ?? "new"}`;
  const [prevKey, setPrevKey] = React.useState(instanceKey);
  if (prevKey !== instanceKey) {
    setPrevKey(instanceKey);
    setType(wallet?.type ?? WALLET_TYPES[0].value);
    setColor(wallet?.color ?? COLOR_PALETTE[0]);
    setError(null);
    setPending(false);
  }

  async function handleAction(formData: FormData) {
    setPending(true);
    setError(null);
    const action = isEdit ? updateWallet : createWallet;
    let result: WalletActionResult;
    try {
      result = await action(formData);
    } catch {
      result = { ok: false, error: "Something went wrong" };
    }
    setPending(false);
    if (result.ok) {
      onClose();
    } else {
      setError(result.error ?? "Something went wrong");
    }
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEdit ? "Edit wallet" : "Add wallet"}
      description={isEdit ? "Update your wallet details." : "Create a new wallet to track your money."}
    >
      <form action={handleAction} className="space-y-4">
        {isEdit && <input type="hidden" name="id" value={wallet!.id} />}
        {/* icon mirrors the selected type so the card can render a matching glyph */}
        <input type="hidden" name="icon" value={type} />
        <input type="hidden" name="color" value={color} />

        <Field label="Name">
          <Input
            name="name"
            placeholder="e.g. Main Bank Account"
            defaultValue={wallet?.name ?? ""}
            autoFocus
            required
            maxLength={60}
          />
        </Field>

        <div>
          <Label>Type</Label>
          <div className="grid grid-cols-3 gap-2">
            {WALLET_TYPES.map((t) => {
              const Icon = t.icon;
              const active = type === t.value;
              return (
                <button
                  type="button"
                  key={t.value}
                  onClick={() => setType(t.value)}
                  className={cn(
                    "flex flex-col items-center gap-1.5 rounded-lg border p-3 text-center transition",
                    active
                      ? "border-primary bg-primary-soft text-primary"
                      : "border-border bg-surface text-muted hover:bg-accent hover:text-foreground",
                  )}
                  aria-pressed={active}
                >
                  <Icon className="h-5 w-5" />
                  <span className="text-xs font-medium leading-tight">{t.label}</span>
                </button>
              );
            })}
          </div>
          <input type="hidden" name="type" value={type} />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <Field label={isEdit ? "Balance" : "Initial balance"}>
            <Input
              name="balance"
              type="number"
              step="any"
              inputMode="decimal"
              placeholder="0"
              defaultValue={wallet ? String(wallet.balance) : "0"}
            />
          </Field>
          <Field label="Currency">
            <Select name="currency" defaultValue={wallet?.currency ?? defaultCurrency}>
              {CURRENCIES.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </Select>
          </Field>
        </div>

        <div>
          <Label>Color</Label>
          <div className="flex flex-wrap gap-2">
            {COLOR_PALETTE.map((c) => {
              const active = color === c;
              return (
                <button
                  type="button"
                  key={c}
                  onClick={() => setColor(c)}
                  aria-label={`Select color ${c}`}
                  aria-pressed={active}
                  style={{ background: c }}
                  className={cn(
                    "flex h-8 w-8 items-center justify-center rounded-full transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40",
                    active ? "ring-2 ring-offset-2 ring-offset-card ring-foreground/60" : "hover:scale-110",
                  )}
                >
                  {active && <Check className="h-4 w-4 text-white" />}
                </button>
              );
            })}
          </div>
        </div>

        {error && <p className="text-sm text-expense">{error}</p>}

        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="ghost" onClick={onClose} disabled={pending}>
            Cancel
          </Button>
          <Button type="submit" disabled={pending}>
            {pending ? "Saving…" : isEdit ? "Save changes" : "Create wallet"}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
