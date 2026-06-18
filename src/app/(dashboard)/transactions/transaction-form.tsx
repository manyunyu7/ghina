"use client";

import * as React from "react";
import type { Wallet, Category } from "@prisma/client";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Input, Textarea, Select, Field } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { createTransaction, updateTransaction } from "./actions";

export type TransactionFormData = {
  id: string;
  type: string;
  amount: number;
  walletId: string;
  toWalletId: string | null;
  categoryId: string | null;
  note: string | null;
  date: Date | string;
};

const TYPES: { value: "expense" | "income" | "transfer"; label: string }[] = [
  { value: "expense", label: "Expense" },
  { value: "income", label: "Income" },
  { value: "transfer", label: "Transfer" },
];

function toDateInput(value: Date | string | undefined): string {
  const d = value ? new Date(value) : new Date();
  // YYYY-MM-DD in local time
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60_000).toISOString().slice(0, 10);
}

export function TransactionForm({
  open,
  onClose,
  wallets,
  categories,
  transaction,
}: {
  open: boolean;
  onClose: () => void;
  wallets: Wallet[];
  categories: Category[];
  transaction?: TransactionFormData;
}) {
  const isEdit = Boolean(transaction);

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEdit ? "Edit transaction" : "Add transaction"}
      description={isEdit ? "Update the details of this transaction." : "Record a new income or expense."}
    >
      {/* Mount fresh each time the modal opens so local state initializes from props
          (no setState-in-effect needed). */}
      {open && (
        <TransactionFormBody
          wallets={wallets}
          categories={categories}
          transaction={transaction}
          onClose={onClose}
        />
      )}
    </Modal>
  );
}

function TransactionFormBody({
  wallets,
  categories,
  transaction,
  onClose,
}: {
  wallets: Wallet[];
  categories: Category[];
  transaction?: TransactionFormData;
  onClose: () => void;
}) {
  const isEdit = Boolean(transaction);
  const [type, setType] = React.useState<string>(transaction?.type ?? "expense");
  const [walletId, setWalletId] = React.useState<string>(transaction?.walletId ?? "");
  const [submitting, setSubmitting] = React.useState(false);

  // Categories filtered by the chosen type. Transfers have no category list.
  const filteredCategories = React.useMemo(() => {
    if (type === "income") return categories.filter((c) => c.type === "income");
    if (type === "expense") return categories.filter((c) => c.type === "expense");
    return [];
  }, [categories, type]);

  async function handleAction(formData: FormData) {
    setSubmitting(true);
    try {
      if (isEdit) {
        await updateTransaction(formData);
      } else {
        await createTransaction(formData);
      }
      onClose();
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form action={handleAction} className="space-y-4">
        {isEdit && transaction && <input type="hidden" name="id" value={transaction.id} />}

        {/* Type toggle */}
        <Field label="Type">
          <div className="grid grid-cols-3 gap-2">
            {TYPES.map((t) => (
              <button
                type="button"
                key={t.value}
                onClick={() => setType(t.value)}
                className={cn(
                  "h-10 rounded-lg border text-sm font-medium transition",
                  type === t.value
                    ? t.value === "income"
                      ? "border-income bg-income-soft text-income"
                      : t.value === "expense"
                        ? "border-expense bg-expense-soft text-expense"
                        : "border-primary bg-primary-soft text-primary"
                    : "border-border bg-surface text-muted hover:bg-accent",
                )}
              >
                {t.label}
              </button>
            ))}
          </div>
          <input type="hidden" name="type" value={type} />
        </Field>

        <Field label="Amount">
          <Input
            name="amount"
            type="number"
            inputMode="decimal"
            step="any"
            min="0"
            required
            placeholder="0"
            defaultValue={transaction ? String(transaction.amount) : ""}
          />
        </Field>

        <Field label={type === "transfer" ? "From wallet" : "Wallet"}>
          <Select
            name="walletId"
            required
            value={walletId}
            onChange={(e) => setWalletId(e.target.value)}
          >
            <option value="" disabled>
              Select a wallet
            </option>
            {wallets.map((w) => (
              <option key={w.id} value={w.id}>
                {w.name}
              </option>
            ))}
          </Select>
        </Field>

        {type === "transfer" && (
          <Field label="To wallet">
            <Select name="toWalletId" key={walletId} required defaultValue={transaction?.toWalletId ?? ""}>
              <option value="" disabled>
                Select destination
              </option>
              {wallets
                .filter((w) => w.id !== walletId)
                .map((w) => (
                  <option key={w.id} value={w.id}>
                    {w.name}
                  </option>
                ))}
            </Select>
          </Field>
        )}

        {type !== "transfer" && (
          <Field label="Category">
            <Select
              name="categoryId"
              key={type}
              defaultValue={transaction?.categoryId ?? ""}
            >
              <option value="">Uncategorized</option>
              {filteredCategories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          </Field>
        )}

        <Field label="Date">
          <Input name="date" type="date" required defaultValue={toDateInput(transaction?.date)} />
        </Field>

        <Field label="Note">
          <Textarea name="note" placeholder="Optional note" defaultValue={transaction?.note ?? ""} />
        </Field>

        <div className="flex justify-end gap-2 pt-1">
          <Button type="button" variant="outline" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button type="submit" disabled={submitting || wallets.length === 0}>
            {submitting ? "Saving…" : isEdit ? "Save changes" : "Add transaction"}
          </Button>
        </div>
    </form>
  );
}
