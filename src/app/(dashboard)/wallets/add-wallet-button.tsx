"use client";

import * as React from "react";
import { Plus } from "lucide-react";
import { Button, type ButtonProps } from "@/components/ui/button";
import { WalletForm } from "./wallet-form";

export function AddWalletButton({
  defaultCurrency,
  label = "Add Wallet",
  variant = "primary",
  size = "md",
}: {
  defaultCurrency: string;
  label?: string;
  variant?: ButtonProps["variant"];
  size?: ButtonProps["size"];
}) {
  const [open, setOpen] = React.useState(false);

  return (
    <>
      <Button variant={variant} size={size} onClick={() => setOpen(true)}>
        <Plus className="h-4 w-4" />
        {label}
      </Button>
      <WalletForm open={open} onClose={() => setOpen(false)} defaultCurrency={defaultCurrency} />
    </>
  );
}
