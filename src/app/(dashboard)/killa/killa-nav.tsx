"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LinkPending } from "@/components/link-pending";
import { cn } from "@/lib/utils";

const TABS = [
  { href: "/killa", label: "Chat" },
  { href: "/killa/files", label: "Berkas" },
  { href: "/killa/commits", label: "Commit" },
] as const;

/** Tabs of the Killa pages (same look as the Content planner tabs). */
export function KillaNav() {
  const pathname = usePathname();
  const item = (on: boolean) =>
    cn(
      "inline-flex shrink-0 items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition whitespace-nowrap",
      on ? "bg-card text-foreground shadow-sm" : "text-muted hover:text-foreground",
    );
  return (
    <div className="-mx-4 mb-5 overflow-x-auto px-4 sm:mx-0 sm:px-0">
      <nav aria-label="Bagian Killa" className="inline-flex gap-0.5 rounded-lg bg-accent p-0.5">
        {TABS.map((t) => {
          const on = t.href === "/killa" ? pathname === "/killa" : pathname.startsWith(t.href);
          return (
            <Link key={t.href} href={t.href} aria-current={on ? "page" : undefined} className={item(on)}>
              {t.label}
              <LinkPending spinner={false} />
            </Link>
          );
        })}
      </nav>
    </div>
  );
}
