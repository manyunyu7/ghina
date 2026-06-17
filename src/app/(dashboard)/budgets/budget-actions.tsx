"use client";

import * as React from "react";
import { Pencil, Trash2, AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { BudgetForm, type BudgetEditData } from "./budget-form";
import { deleteBudget, type BudgetActionResult } from "./actions";

export function BudgetActions({
  budget,
  month,
  year,
}: {
  budget: BudgetEditData;
  month: number;
  year: number;
}) {
  const [editing, setEditing] = React.useState(false);
  const [confirming, setConfirming] = React.useState(false);
  const [pending, setPending] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  async function handleDelete() {
    setPending(true);
    setError(null);
    const formData = new FormData();
    formData.set("id", budget.id);
    let result: BudgetActionResult;
    try {
      result = await deleteBudget(formData);
    } catch {
      result = { ok: false, error: "Something went wrong" };
    }
    setPending(false);
    if (result.ok) {
      setConfirming(false);
    } else {
      setError(result.error ?? "Failed to delete budget");
    }
  }

  return (
    <>
      <div className="flex items-center gap-1">
        <Button
          variant="ghost"
          size="icon"
          aria-label={`Edit budget for ${budget.categoryName}`}
          onClick={() => setEditing(true)}
        >
          <Pencil className="h-4 w-4" />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          aria-label={`Delete budget for ${budget.categoryName}`}
          onClick={() => setConfirming(true)}
        >
          <Trash2 className="h-4 w-4" />
        </Button>
      </div>

      <BudgetForm
        open={editing}
        onClose={() => setEditing(false)}
        month={month}
        year={year}
        budget={budget}
      />

      <Modal open={confirming} onClose={() => setConfirming(false)} title="Delete budget">
        <div className="space-y-4">
          <div className="flex gap-3 rounded-lg bg-expense-soft p-3 text-expense">
            <AlertTriangle className="h-5 w-5 shrink-0" />
            <div className="text-sm">
              <p className="font-medium">This cannot be undone.</p>
              <p className="mt-0.5 text-expense/90">
                Remove the budget for{" "}
                <span className="font-semibold">{budget.categoryName}</span> this month? Your
                transactions are not affected.
              </p>
            </div>
          </div>

          {error && <p className="text-sm text-expense">{error}</p>}

          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={() => setConfirming(false)} disabled={pending}>
              Cancel
            </Button>
            <Button variant="danger" onClick={handleDelete} disabled={pending}>
              {pending ? "Deleting…" : "Delete budget"}
            </Button>
          </div>
        </div>
      </Modal>
    </>
  );
}
