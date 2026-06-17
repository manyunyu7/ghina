"use client";

import * as React from "react";
import { Sparkles } from "lucide-react";
import { Button, type ButtonProps } from "@/components/ui/button";
import { seedDefaultCategories, type CategoryActionResult } from "./actions";

export function SeedButton({
  label = "Add default categories",
  variant = "primary",
  size = "md",
}: {
  label?: string;
  variant?: ButtonProps["variant"];
  size?: ButtonProps["size"];
}) {
  const [pending, setPending] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  async function handleSeed() {
    setPending(true);
    setError(null);
    let result: CategoryActionResult;
    try {
      result = await seedDefaultCategories();
    } catch {
      result = { ok: false, error: "Something went wrong" };
    }
    setPending(false);
    if (!result.ok) {
      setError(result.error ?? "Failed to add default categories");
    }
  }

  return (
    <div className="flex flex-col items-center gap-2">
      <Button variant={variant} size={size} onClick={handleSeed} disabled={pending}>
        <Sparkles className="h-4 w-4" />
        {pending ? "Adding…" : label}
      </Button>
      {error && <p className="text-sm text-expense">{error}</p>}
    </div>
  );
}
