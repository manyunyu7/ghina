"use client";

import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Subtle pending hint for optimistic UIs and in-page navigations: always rendered at full
 * size (no layout shift) and faded in while a request is in flight. Screen readers get the
 * label through a polite live region only while pending. Pass `label={null}` for spinner only.
 */
export function SavingHint({
  pending,
  label = "Menyimpan…",
  className,
}: {
  pending: boolean;
  label?: string | null;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex shrink-0 items-center gap-1.5 text-xs font-medium text-muted transition-opacity",
        pending ? "opacity-100" : "opacity-0",
        className,
      )}
    >
      <Loader2 aria-hidden className="h-4 w-4 animate-spin" />
      {label && <span aria-hidden>{label}</span>}
      <span role="status" aria-live="polite" className="sr-only">
        {pending ? (label ?? "Memuat…") : ""}
      </span>
    </span>
  );
}
