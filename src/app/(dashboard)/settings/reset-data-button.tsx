"use client";

import * as React from "react";
import { Trash2, AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { resetData } from "./actions";

export function ResetDataButton() {
  const [open, setOpen] = React.useState(false);
  const [pending, setPending] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  async function onConfirm() {
    setPending(true);
    setError(null);
    const res = await resetData();
    setPending(false);
    if (res.ok) {
      setOpen(false);
    } else {
      setError(res.error ?? "Failed to reset data");
    }
  }

  return (
    <>
      <Button variant="danger" onClick={() => setOpen(true)}>
        <Trash2 className="h-4 w-4" />
        Reset all data
      </Button>

      <Modal
        open={open}
        onClose={() => !pending && setOpen(false)}
        title="Reset all data?"
        description="This permanently deletes all your wallets, transactions, categories, and budgets. Your account stays. This cannot be undone."
      >
        <div className="mb-4 flex items-start gap-3 rounded-lg border border-expense/30 bg-expense-soft p-3 text-sm text-expense">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          <span>Everything will be erased. There is no way to recover it.</span>
        </div>
        {error && <p className="mb-3 text-sm text-expense">{error}</p>}
        <div className="flex justify-end gap-3">
          <Button variant="outline" onClick={() => setOpen(false)} disabled={pending}>
            Cancel
          </Button>
          <Button variant="danger" onClick={onConfirm} disabled={pending}>
            {pending ? "Resetting…" : "Yes, reset everything"}
          </Button>
        </div>
      </Modal>
    </>
  );
}
