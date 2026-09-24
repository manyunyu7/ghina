"use client";

import { useLinkStatus } from "next/link";
import { Loader2 } from "lucide-react";

/**
 * Pending feedback for a nav <Link>: a spinner in the item (fixed size, no layout shift)
 * plus a progress bar across the top of the viewport while the page loads.
 * Must be rendered inside the <Link>.
 */
export function NavPending() {
  const { pending } = useLinkStatus();
  return (
    <>
      <Loader2
        aria-hidden
        className={`ml-auto h-4 w-4 shrink-0 animate-spin transition-opacity ${pending ? "opacity-100" : "opacity-0"}`}
      />
      {pending && (
        <span role="progressbar" aria-label="Memuat halaman" className="nav-progress" />
      )}
    </>
  );
}
