"use client";

import * as React from "react";
import type { Wallet, Category } from "@prisma/client";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { PlannedForm } from "./planned-form";

export function AddPlannedButton({
  wallets,
  categories,
  defaultDate,
  variant = "primary",
  label = "Add planned item",
}: {
  wallets: Wallet[];
  categories: Category[];
  defaultDate?: string;
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
      <PlannedForm
        open={open}
        onClose={() => setOpen(false)}
        wallets={wallets}
        categories={categories}
        defaultDate={defaultDate}
      />
    </>
  );
}
