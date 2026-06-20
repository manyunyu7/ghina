"use client";

import * as React from "react";
import type { Wallet, Category } from "@prisma/client";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Input, Select, Field } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { createPlanned, updatePlanned } from "./actions";

export type PlannedFormData = {
  id: string;
  type: string;
  amount: number;
  note: string | null;
  date: Date | string;
  categoryId: string | null;
  walletId: string | null;
};

function toDateInput(value: Date | string | undefined): string {
  const d = value ? new Date(value) : new Date();
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60_000).toISOString().slice(0, 10);
}

export function PlannedForm({
  open,
  onClose,
  wallets,
  categories,
  planned,
  defaultDate,
}: {
  open: boolean;
  onClose: () => void;
  wallets: Wallet[];
  categories: Category[];
  planned?: PlannedFormData;
  /** YYYY-MM-DD to prefill when adding (the month currently being viewed). */
  defaultDate?: string;
}) {
  const isEdit = Boolean(planned);
  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEdit ? "Edit planned item" : "Add planned item"}
      description={
        isEdit
          ? "Update this expected transaction."
          : "Jot down a transaction you expect to happen — a bill, salary, or one-off. It won't touch any wallet balance."
      }
    >
      {open && (
        <FormBody
          wallets={wallets}
          categories={categories}
          planned={planned}
          defaultDate={defaultDate}
          onClose={onClose}
        />
      )}
    </Modal>
  );
}

function FormBody({
  wallets,
  categories,
  planned,
  defaultDate,
  onClose,
}: {
  wallets: Wallet[];
  categories: Category[];
  planned?: PlannedFormData;
  defaultDate?: string;
  onClose: () => void;
}) {
  const isEdit = Boolean(planned);
  const [type, setType] = React.useState<"expense" | "income">((planned?.type as "expense" | "income") ?? "expense");
  const [submitting, setSubmitting] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  const typedCategories = categories.filter((c) => c.type === type);

  async function handleAction(formData: FormData) {
    setSubmitting(true);
    setError(null);
    const res = isEdit ? await updatePlanned(formData) : await createPlanned(formData);
    if (res.ok) {
      onClose();
    } else {
      setError(res.error ?? "Something went wrong");
      setSubmitting(false);
    }
  }

  return (
    <form action={handleAction} className="space-y-4">
      {isEdit && planned && <input type="hidden" name="id" value={planned.id} />}
      <input type="hidden" name="type" value={type} />

      {/* Expense / income toggle */}
      <div className="grid grid-cols-2 gap-2">
        {(["expense", "income"] as const).map((t) => (
          <button
            type="button"
            key={t}
            onClick={() => setType(t)}
            className={cn(
              "rounded-lg border px-3 py-2 text-sm font-medium capitalize transition",
              type === t
                ? t === "expense"
                  ? "border-transparent bg-expense-soft text-expense"
                  : "border-transparent bg-income-soft text-income"
                : "border-border bg-surface text-muted hover:bg-accent",
            )}
          >
            {t === "expense" ? "Money out" : "Money in"}
          </button>
        ))}
      </div>

      <Field label="What is it?">
        <Input
          name="note"
          placeholder={type === "expense" ? "e.g. Pajak motor" : "e.g. Gajian"}
          defaultValue={planned?.note ?? ""}
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
            defaultValue={planned ? String(planned.amount) : ""}
          />
        </Field>
        <Field label="Expected date">
          <Input
            name="date"
            type="date"
            required
            defaultValue={toDateInput(planned?.date ?? defaultDate)}
          />
        </Field>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Field label="Category">
          <Select name="categoryId" defaultValue={planned?.categoryId ?? ""}>
            <option value="">Uncategorized</option>
            {typedCategories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Wallet">
          <Select name="walletId" defaultValue={planned?.walletId ?? ""}>
            <option value="">— None —</option>
            {wallets.map((w) => (
              <option key={w.id} value={w.id}>
                {w.name}
              </option>
            ))}
          </Select>
        </Field>
      </div>

      {error && <p className="text-sm text-expense">{error}</p>}

      <div className="flex justify-end gap-2 pt-1">
        <Button type="button" variant="outline" onClick={onClose} disabled={submitting}>
          Cancel
        </Button>
        <Button type="submit" disabled={submitting}>
          {submitting ? "Saving…" : isEdit ? "Save changes" : "Add item"}
        </Button>
      </div>
    </form>
  );
}
