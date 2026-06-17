"use client";

import * as React from "react";
import { Plus } from "lucide-react";
import type { Category } from "@prisma/client";
import { Button, type ButtonProps } from "@/components/ui/button";
import { BudgetForm } from "./budget-form";

export function AddBudgetButton({
  label = "Add Budget",
  variant = "primary",
  size = "md",
  month,
  year,
  availableCategories,
}: {
  label?: string;
  variant?: ButtonProps["variant"];
  size?: ButtonProps["size"];
  month: number;
  year: number;
  availableCategories: Category[];
}) {
  const [open, setOpen] = React.useState(false);

  return (
    <>
      <Button variant={variant} size={size} onClick={() => setOpen(true)}>
        <Plus className="h-4 w-4" />
        {label}
      </Button>
      <BudgetForm
        open={open}
        onClose={() => setOpen(false)}
        month={month}
        year={year}
        availableCategories={availableCategories}
      />
    </>
  );
}
