"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { MessageCircle } from "lucide-react";

/**
 * Floating shortcut to the Killa chat, bottom-right on every dashboard page except the
 * /killa pages. The layout renders it only for allowlisted users (isKillaAllowed).
 */
export function KillaFab() {
  const pathname = usePathname();
  if (pathname === "/killa" || pathname.startsWith("/killa/")) return null;
  return (
    <Link
      href="/killa"
      aria-label="Buka chat Killa"
      title="Killa"
      className="fixed right-[max(1rem,env(safe-area-inset-right))] bottom-[max(1rem,env(safe-area-inset-bottom))] z-30 inline-flex h-12 w-12 items-center justify-center rounded-full bg-primary text-white shadow-lg shadow-black/15 ring-1 ring-black/5 transition hover:scale-105 hover:bg-primary-hover focus-visible:ring-2 focus-visible:ring-primary/40 focus-visible:outline-none active:scale-95 sm:right-[max(1.5rem,env(safe-area-inset-right))] sm:bottom-[max(1.5rem,env(safe-area-inset-bottom))] print:hidden"
    >
      <MessageCircle className="h-5 w-5" />
    </Link>
  );
}
