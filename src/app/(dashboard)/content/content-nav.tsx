"use client";

import Link from "next/link";
import { Settings2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { CONTENT_TABS, type ContentTab } from "./types";
import { LinkPending, LinkPendingIcon } from "@/components/link-pending";

/**
 * Tabs of the Content planner. On /content they switch client-side (`onSelect`); on
 * /content/accounts they are links back.
 */
export function ContentNav({
  active,
  onSelect,
  inboxCount,
}: {
  active: ContentTab | "pengaturan";
  onSelect?: (t: ContentTab) => void;
  inboxCount?: number;
}) {
  const item = (on: boolean) =>
    cn(
      "inline-flex shrink-0 items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition whitespace-nowrap",
      on ? "bg-card text-foreground shadow-sm" : "text-muted hover:text-foreground",
    );
  return (
    <div className="-mx-4 mb-5 overflow-x-auto px-4 sm:mx-0 sm:px-0">
      <nav aria-label="Bagian konten" className="inline-flex gap-0.5 rounded-lg bg-accent p-0.5">
        {CONTENT_TABS.map((t) => {
          const on = active === t.id;
          const badge =
            t.id === "ide" && inboxCount ? (
              <span className="rounded-full bg-primary px-1.5 text-[10px] font-bold leading-4 text-white">{inboxCount}</span>
            ) : null;
          return onSelect ? (
            <button key={t.id} type="button" aria-current={on ? "page" : undefined} onClick={() => onSelect(t.id)} className={item(on)}>
              {t.label}
              {badge}
            </button>
          ) : (
            <Link key={t.id} href={t.id === "papan" ? "/content" : `/content?tab=${t.id}`} className={item(on)}>
              {t.label}
              {badge}
              <LinkPending spinner={false} />
            </Link>
          );
        })}
        <Link href="/content/accounts" aria-current={active === "pengaturan" ? "page" : undefined} className={item(active === "pengaturan")}>
          <LinkPendingIcon>
            <Settings2 className="h-4 w-4" aria-hidden />
          </LinkPendingIcon>
          Pengaturan
        </Link>
      </nav>
    </div>
  );
}
