"use client";

import * as React from "react";
import { Scale, HeartPulse } from "lucide-react";
import { Button } from "@/components/ui/button";
import { HealthForm, type HealthMode } from "./health-form";

export function AddEntryButton({
  mode,
  label,
  variant = "primary",
}: {
  mode: HealthMode;
  label?: string;
  variant?: "primary" | "outline";
}) {
  const [open, setOpen] = React.useState(false);
  const Icon = mode === "weight" ? Scale : HeartPulse;
  return (
    <>
      <Button variant={variant} onClick={() => setOpen(true)}>
        <Icon className="h-4 w-4" />
        {label ?? (mode === "weight" ? "Log Weight" : "Log Blood Pressure")}
      </Button>
      <HealthForm open={open} onClose={() => setOpen(false)} mode={mode} />
    </>
  );
}
