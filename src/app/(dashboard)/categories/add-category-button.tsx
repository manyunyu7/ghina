"use client";

import * as React from "react";
import { Plus } from "lucide-react";
import { Button, type ButtonProps } from "@/components/ui/button";
import { CategoryForm } from "./category-form";

export function AddCategoryButton({
  label = "Add Category",
  variant = "primary",
  size = "md",
  defaultType = "expense",
}: {
  label?: string;
  variant?: ButtonProps["variant"];
  size?: ButtonProps["size"];
  defaultType?: "expense" | "income";
}) {
  const [open, setOpen] = React.useState(false);

  return (
    <>
      <Button variant={variant} size={size} onClick={() => setOpen(true)}>
        <Plus className="h-4 w-4" />
        {label}
      </Button>
      <CategoryForm open={open} onClose={() => setOpen(false)} defaultType={defaultType} />
    </>
  );
}
