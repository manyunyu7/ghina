"use client";

import * as React from "react";
import { Pencil, Trash2, AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { WalletForm, type WalletFormData } from "./wallet-form";
import { deleteWallet, type WalletActionResult } from "./actions";

export function WalletCardActions({
  wallet,
  transactionCount,
  defaultCurrency,
}: {
  wallet: WalletFormData;
  transactionCount: number;
  defaultCurrency: string;
}) {
  const [editing, setEditing] = React.useState(false);
  const [confirming, setConfirming] = React.useState(false);
  const [pending, setPending] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  async function handleDelete() {
    setPending(true);
    setError(null);
    const formData = new FormData();
    formData.set("id", wallet.id);
    let result: WalletActionResult;
    try {
      result = await deleteWallet(formData);
    } catch {
      result = { ok: false, error: "Something went wrong" };
    }
    setPending(false);
    if (result.ok) {
      setConfirming(false);
    } else {
      setError(result.error ?? "Failed to delete wallet");
    }
  }

  return (
    <>
      <div className="flex items-center gap-1">
        <Button
          variant="ghost"
          size="icon"
          aria-label={`Edit ${wallet.name}`}
          onClick={() => setEditing(true)}
        >
          <Pencil className="h-4 w-4" />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          aria-label={`Delete ${wallet.name}`}
          onClick={() => setConfirming(true)}
        >
          <Trash2 className="h-4 w-4" />
        </Button>
      </div>

      <WalletForm
        open={editing}
        onClose={() => setEditing(false)}
        wallet={wallet}
        defaultCurrency={defaultCurrency}
      />

      <Modal open={confirming} onClose={() => setConfirming(false)} title="Delete wallet">
        <div className="space-y-4">
          <div className="flex gap-3 rounded-lg bg-expense-soft p-3 text-expense">
            <AlertTriangle className="h-5 w-5 shrink-0" />
            <div className="text-sm">
              <p className="font-medium">This cannot be undone.</p>
              <p className="mt-0.5 text-expense/90">
                Deleting <span className="font-semibold">{wallet.name}</span>
                {transactionCount > 0 ? (
                  <>
                    {" "}
                    will also permanently delete its{" "}
                    <span className="font-semibold">
                      {transactionCount} transaction{transactionCount === 1 ? "" : "s"}
                    </span>
                    .
                  </>
                ) : (
                  <>.</>
                )}
              </p>
            </div>
          </div>

          {error && <p className="text-sm text-expense">{error}</p>}

          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={() => setConfirming(false)} disabled={pending}>
              Cancel
            </Button>
            <Button variant="danger" onClick={handleDelete} disabled={pending}>
              {pending ? "Deleting…" : "Delete wallet"}
            </Button>
          </div>
        </div>
      </Modal>
    </>
  );
}
