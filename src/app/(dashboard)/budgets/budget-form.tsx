"use client";

import * as React from "react";
import type { Category } from "@prisma/client";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Input, Select, Field } from "@/components/ui/input";
import { CategoryIcon } from "@/components/icon";
import { MONTHS } from "@/lib/utils";
import { setBudget, updateBudget, type BudgetActionResult } from "./actions";

export type BudgetEditData = {
  id: string;
  categoryId: string;
  categoryName: string;
  categoryColor: string;
  categoryIcon: string;
  amount: number;
};

export function BudgetForm({
  open,
  onClose,
  month,
  year,
  /** Expense categories without an existing budget — used when creating. */
  availableCategories = [],
  /** When provided, the form edits this budget's amount; otherwise it creates a new one. */
  budget,
}: {
  open: boolean;
  onClose: () => void;
  month: number;
  year: number;
  availableCategories?: Category[];
  budget?: BudgetEditData;
}) {
  const isEdit = Boolean(budget);

  const [categoryId, setCategoryId] = React.useState(
    budget?.categoryId ?? availableCategories[0]?.id ?? "",
  );
  const [amount, setAmount] = React.useState(budget ? String(budget.amount) : "");
  const [error, setError] = React.useState<string | null>(null);
  const [pending, setPending] = React.useState(false);

  // Reset local state during render whenever the modal is (re)opened or the target changes.
  const instanceKey = `${open ? "open" : "closed"}:${budget?.id ?? "new"}:${month}-${year}`;
  const [prevKey, setPrevKey] = React.useState(instanceKey);
  if (prevKey !== instanceKey) {
    setPrevKey(instanceKey);
    setCategoryId(budget?.categoryId ?? availableCategories[0]?.id ?? "");
    setAmount(budget ? String(budget.amount) : "");
    setError(null);
    setPending(false);
  }

  async function handleAction(formData: FormData) {
    setPending(true);
    setError(null);
    const action = isEdit ? updateBudget : setBudget;
    let result: BudgetActionResult;
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

  const monthLabel = `${MONTHS[month - 1]} ${year}`;
  const noCategories = !isEdit && availableCategories.length === 0;

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEdit ? "Edit budget" : "Set budget"}
      description={
        isEdit
          ? `Update the budget for ${budget!.categoryName} in ${monthLabel}.`
          : `Set a spending limit for a category in ${monthLabel}.`
      }
    >
      <form action={handleAction} className="space-y-4">
        <input type="hidden" name="month" value={month} />
        <input type="hidden" name="year" value={year} />
        {isEdit && <input type="hidden" name="id" value={budget!.id} />}
        {isEdit && <input type="hidden" name="categoryId" value={budget!.categoryId} />}

        {isEdit ? (
          <div className="flex items-center gap-3 rounded-lg border border-border bg-surface p-3">
            <div
              className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full"
              style={{ background: `${budget!.categoryColor}1a`, color: budget!.categoryColor }}
            >
              <CategoryIcon name={budget!.categoryIcon} className="h-5 w-5" />
            </div>
            <span className="font-medium text-foreground">{budget!.categoryName}</span>
          </div>
        ) : noCategories ? (
          <p className="rounded-lg border border-dashed border-border bg-surface px-4 py-6 text-center text-sm text-muted">
            Every expense category already has a budget for {monthLabel}.
          </p>
        ) : (
          <Field label="Category">
            <Select
              name="categoryId"
              value={categoryId}
              onChange={(e) => setCategoryId(e.target.value)}
              required
            >
              {availableCategories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          </Field>
        )}

        <Field label="Monthly limit">
          <Input
            name="amount"
            type="number"
            inputMode="decimal"
            min="0"
            step="any"
            placeholder="0"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            autoFocus
            required
            disabled={noCategories}
          />
        </Field>

        {error && <p className="text-sm text-expense">{error}</p>}

        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="ghost" onClick={onClose} disabled={pending}>
            Cancel
          </Button>
          <Button type="submit" disabled={pending || noCategories}>
            {pending ? "Saving…" : isEdit ? "Save changes" : "Set budget"}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
