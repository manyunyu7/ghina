"use client";

import * as React from "react";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { FoodForm } from "./food-form";

export function AddFoodButton({ label = "Log Meal" }: { label?: string }) {
  const [open, setOpen] = React.useState(false);
  return (
    <>
      <Button onClick={() => setOpen(true)}>
        <Plus className="h-4 w-4" />
        {label}
      </Button>
      <FoodForm open={open} onClose={() => setOpen(false)} />
    </>
  );
}
