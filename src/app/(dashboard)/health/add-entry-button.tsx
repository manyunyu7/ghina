"use client";

import * as React from "react";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { HealthForm } from "./health-form";

export function AddEntryButton({ label = "Add Measurement" }: { label?: string }) {
  const [open, setOpen] = React.useState(false);
  return (
    <>
      <Button onClick={() => setOpen(true)}>
        <Plus className="h-4 w-4" />
        {label}
      </Button>
      <HealthForm open={open} onClose={() => setOpen(false)} />
    </>
  );
}
