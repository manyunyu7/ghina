"use client";

import type * as React from "react";
import { useLinkStatus } from "next/link";
import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Pending hint for any in-page <Link> (tabs, "Riwayat", back links…): the top progress bar
 * plus (unless `spinner={false}`) a small fixed-size spinner that fades in (no layout shift).
 * Must be rendered inside the <Link>.
 */
export function LinkPending({ spinner = true, className }: { spinner?: boolean; className?: string }) {
  const { pending } = useLinkStatus();
  return (
    <>
      {spinner && (
        <Loader2
          aria-hidden
          className={cn(
            "h-3.5 w-3.5 shrink-0 animate-spin transition-opacity",
            pending ? "opacity-100" : "opacity-0",
            className,
          )}
        />
      )}
      {pending && <span role="progressbar" aria-label="Memuat halaman" className="nav-progress" />}
    </>
  );
}

/**
 * For a <Link> styled as a button: renders `children` (its icon) normally and swaps it for
 * the spinner while the link is navigating, plus the top progress bar. Same footprint.
 */
export function LinkPendingIcon({ children, className }: { children?: React.ReactNode; className?: string }) {
  const { pending } = useLinkStatus();
  return (
    <>
      {pending ? <Loader2 aria-hidden className={cn("h-4 w-4 shrink-0 animate-spin", className)} /> : children}
      {pending && <span role="progressbar" aria-label="Memuat halaman" className="nav-progress" />}
    </>
  );
}
