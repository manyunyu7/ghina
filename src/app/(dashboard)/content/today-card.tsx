"use client";

import Link from "next/link";
import { ArrowRight, Check } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { localDateKey } from "@/lib/content";
import { AccountCode, formatTime, useHydrated, useTimeZone } from "./ui";
import type { TodayPost } from "./data";
import { LinkPending, LinkPendingIcon } from "@/components/link-pending";

const MAX = 5;

/** Dashboard card "Tayang hari ini": posts placed on the browser's local today (hidden when none). */
export function ContentTodayCard({ posts }: { posts: TodayPost[] }) {
  const tz = useTimeZone();
  const hydrated = useHydrated();
  if (!hydrated) return null;
  const today = localDateKey(new Date(), tz);
  const list = posts.filter((p) => localDateKey(p.at, tz) === today).sort((a, b) => a.at.localeCompare(b.at));
  if (!list.length) return null;
  const done = list.filter((p) => p.status === "posted").length;
  return (
    <Card>
      <CardHeader>
        <CardTitle>🎬 Tayang hari ini</CardTitle>
        <Link href="/content?tab=kalender" className="inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline">
          Buka Konten{" "}
          <LinkPendingIcon className="h-3.5 w-3.5">
            <ArrowRight className="h-3.5 w-3.5" />
          </LinkPendingIcon>
        </Link>
      </CardHeader>
      <CardContent>
        <p className="-mt-2 mb-3 text-xs text-muted">
          {done}/{list.length} sudah tayang
        </p>
        <ul className="space-y-2">
          {list.slice(0, MAX).map((p) => (
            <li key={p.id}>
              <Link href={`/content?item=${encodeURIComponent(p.contentId)}`} className="flex items-center gap-2 rounded-md text-sm hover:bg-accent">
                <span className="w-11 shrink-0 tabular-nums text-muted">{formatTime(p.at, tz)}</span>
                <AccountCode account={p.account} />
                <span className="min-w-0 flex-1 truncate text-foreground">{p.title}</span>
                <LinkPending />
                {p.status === "posted" && <Check className="h-4 w-4 shrink-0 text-income" aria-label="Sudah tayang" />}
              </Link>
            </li>
          ))}
          {list.length > MAX && <li className="pt-1 text-xs text-muted">+{list.length - MAX} lainnya</li>}
        </ul>
      </CardContent>
    </Card>
  );
}
