"use client";

import * as React from "react";
import type { Wallet, Category } from "@prisma/client";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { SubscriptionForm } from "./subscription-form";

export function AddSubscriptionButton({
  wallets,
  categories,
  currency,
  variant = "primary",
  label = "Add Subscription",
}: {
  wallets: Wallet[];
  categories: Category[];
  currency: string;
  variant?: "primary" | "outline";
  label?: string;
}) {
  const [open, setOpen] = React.useState(false);
  return (
    <>
      <Button variant={variant} onClick={() => setOpen(true)}>
        <Plus className="h-4 w-4" />
        {label}
      </Button>
      <SubscriptionForm
        open={open}
        onClose={() => setOpen(false)}
        wallets={wallets}
        categories={categories}
        defaultCurrency={currency}
      />
    </>
  );
}
