"use client";

import * as React from "react";
import { Pencil, Trash2 } from "lucide-react";
import type { Wallet, Category } from "@prisma/client";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { TransactionForm, type TransactionFormData } from "./transaction-form";
import { deleteTransaction } from "./actions";

export function TransactionActions({
  transaction,
  wallets,
  categories,
}: {
  transaction: TransactionFormData;
  wallets: Wallet[];
  categories: Category[];
}) {
  const [editOpen, setEditOpen] = React.useState(false);
  const [confirmOpen, setConfirmOpen] = React.useState(false);
  const [deleting, setDeleting] = React.useState(false);

  async function handleDelete(formData: FormData) {
    setDeleting(true);
    try {
      await deleteTransaction(formData);
      setConfirmOpen(false);
    } finally {
      setDeleting(false);
    }
  }

  return (
    <>
      <div className="flex items-center gap-0.5">
        <Button
          variant="ghost"
          size="icon"
          aria-label="Edit transaction"
          onClick={() => setEditOpen(true)}
        >
          <Pencil className="h-4 w-4" />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          aria-label="Delete transaction"
          onClick={() => setConfirmOpen(true)}
        >
          <Trash2 className="h-4 w-4" />
        </Button>
      </div>

      <TransactionForm
        open={editOpen}
        onClose={() => setEditOpen(false)}
        wallets={wallets}
        categories={categories}
        transaction={transaction}
      />

      <Modal
        open={confirmOpen}
        onClose={() => setConfirmOpen(false)}
        title="Delete transaction?"
        description="This will permanently remove the transaction and adjust your wallet balance."
      >
        <form action={handleDelete} className="flex justify-end gap-2 pt-2">
          <input type="hidden" name="id" value={transaction.id} />
          <Button type="button" variant="outline" onClick={() => setConfirmOpen(false)} disabled={deleting}>
            Cancel
          </Button>
          <Button type="submit" variant="danger" disabled={deleting}>
            {deleting ? "Deleting…" : "Delete"}
          </Button>
        </form>
      </Modal>
    </>
  );
}
