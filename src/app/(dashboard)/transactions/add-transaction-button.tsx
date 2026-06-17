"use client";

import * as React from "react";
import { Plus } from "lucide-react";
import type { Wallet, Category } from "@prisma/client";
import { Button } from "@/components/ui/button";
import { TransactionForm } from "./transaction-form";

export function AddTransactionButton({
  wallets,
  categories,
}: {
  wallets: Wallet[];
  categories: Category[];
}) {
  const [open, setOpen] = React.useState(false);

  return (
    <>
      <Button onClick={() => setOpen(true)} disabled={wallets.length === 0}>
        <Plus className="h-4 w-4" />
        Add Transaction
      </Button>
      <TransactionForm
        open={open}
        onClose={() => setOpen(false)}
        wallets={wallets}
        categories={categories}
      />
    </>
  );
}
