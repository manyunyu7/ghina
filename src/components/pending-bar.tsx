"use client";

/**
 * The shared top-of-viewport progress bar (see `.nav-progress` in globals.css), shown while
 * `pending` is true. Use it for in-page navigations (filters, month pickers, tabs) and
 * background requests that have no button of their own to spin.
 */
export function PendingBar({ pending, label = "Memuat…" }: { pending: boolean; label?: string }) {
  if (!pending) return null;
  return <span role="progressbar" aria-label={label} className="nav-progress" />;
}
